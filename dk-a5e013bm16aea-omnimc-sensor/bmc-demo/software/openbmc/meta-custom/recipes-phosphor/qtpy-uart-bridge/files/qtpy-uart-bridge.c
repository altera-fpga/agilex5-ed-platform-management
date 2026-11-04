// SPDX-License-Identifier: MIT
//
// qtpy-uart-bridge — read line-based telemetry from the Altera sensor board's
// QT Py MCU over the Pi-header UART (/dev/ttyS1 = HPS UART1, FPGA-muxed) and
// mirror the values onto dbus-sensors ExternalSensors (so they appear on the
// Redfish dashboard) plus a /run JSON debug dump.
//
// This is bring-up/demo scaffolding. The QT Py firmware streams ASCII lines of
// whitespace-separated KEY:VALUE tokens, e.g.:
//
//     Sliders: 32000
//
// The token->sensor mapping is DATA, not code: it is loaded at startup from a
// config file (default /etc/qtpy-uart-bridge.conf, override with QTPY_CONF or a
// 3rd CLI arg). Each line maps one UART token to one ExternalSensor object path
// and a linear transform:
//
//     TOKEN   sensor_object_path   [scale]   [offset]   [min]   [max]
//
// The published value is clamp(num*scale + offset, min, max). scale defaults to
// 1, offset to 0, and min/max to unbounded when omitted. Lines beginning with
// '#' and blank lines are ignored; unknown UART tokens are ignored. This means a
// customer can surface a NEW QT Py value by adding one config line plus one
// ExternalSensor entry in entity-manager — no recompile, and the dashboard
// auto-discovers the sensor. See qtpy-uart-protocol.md.
//
// If the config file is missing or has no valid entries, a compiled-in default
// table is used so the daemon still works out of the box (it maps the
// potentiometer knob — SLIDERS (current) and HEATER (post-rename), both a raw
// 16-bit ADC count — onto the "Heater_PWM" humidity-namespace sensor).
// PercentRH (the "humidity" namespace) is used because
// bmcweb surfaces it as a "%" reading under Chassis/Sensors, whereas the
// "percent" namespace that Units=Percent would use is not surfaced.
//
// The parser is deliberately tolerant: it scans each line for known keys and
// ignores anything else, so the exact QT Py format can change without breaking
// it. A "KEY: value" form with a space after the colon is accepted too.
//
// Output:
//   1. Each mapped token's value is set on its ExternalSensor Value property via
//      sd-bus (no bmcweb change; history/tiles come for free).
//   2. /run/qtpy/heater.json, refreshed on every parsed line, as a debug aid.
//   3. A throttled journal line.
//
// The only build dependency beyond libc + termios is libsystemd (sd-bus), used
// to set the ExternalSensor Value property.
//
// Usage: qtpy-uart-bridge [device] [baud] [config]
//        (defaults: /dev/ttyS1 115200 /etc/qtpy-uart-bridge.conf)

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <float.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include <systemd/sd-bus.h>

#include <sys/stat.h>

static const char *default_dev = "/dev/ttyS1";
static const char *json_path = "/run/qtpy/heater.json"; /* override: QTPY_JSON */
static const char *default_conf = "/etc/qtpy-uart-bridge.conf"; /* QTPY_CONF */

/* dbus-sensors ExternalSensor service/interface. Each mapped token's value is
 * written to Value on the object path from the config; that path must match the
 * object dbus-sensors creates from the entity-manager Exposes entry. */
#define SENSOR_SERVICE "xyz.openbmc_project.ExternalSensor"
#define SENSOR_IFACE "xyz.openbmc_project.Sensor.Value"

static sd_bus *bus = NULL;

static volatile sig_atomic_t running = 1;

static void on_signal(int sig)
{
    (void)sig;
    running = 0;
}

/* ------------------------------------------------------------------------- */
/* Token -> sensor mapping table (loaded from config, or compiled-in default). */
/* ------------------------------------------------------------------------- */

#define MAX_MAPPINGS 32
#define TOKEN_LEN 32
#define PATH_LEN 192

struct mapping {
    char token[TOKEN_LEN]; /* UART key, matched case-insensitively */
    char path[PATH_LEN]; /* ExternalSensor object path */
    double scale; /* published = clamp(num*scale + offset, min, max) */
    double offset;
    double min;
    double max;
    double value; /* latest computed value */
    int dirty; /* set on update, cleared after publish */
    int seen; /* ever updated (drives the JSON dump) */
};

static struct mapping mappings[MAX_MAPPINGS];
static int mapping_count = 0;

/* ------------------------------------------------------------------------- */
/* Multi-line JSON packet mode (new QT Py firmware).                          */
/*                                                                           */
/* The QT Py mini-rack firmware streams a multi-line record every 100 ms,    */
/* e.g.:                                                                      */
/*                                                                           */
/*     { "profile": "BoardManagementController",                             */
/*       "heater": 32000,                                                    */
/*       "messages": [                                                       */
/*         "text": "Chassis Intrusion Detected",                            */
/*         "text": "Fan Failed",                                            */
/*     ] }                                                                    */
/*                                                                           */
/* This is NOT strict JSON (the "text" items are bare key:value pairs inside  */
/* the array and there are trailing commas), so we parse it tolerantly with  */
/* strstr/strtod rather than a JSON library. The "heater" value feeds the    */
/* same mapping table as the legacy "Heater:" token; each "text" string is a */
/* switch-triggered fault that we post to the OpenBMC event log (Redfish).   */
/*                                                                           */
/* Packet start  = a line whose first non-space char is '{'.                 */
/* Packet end    = a line whose first non-space char is ']'.                 */
/* The legacy single-line "KEY:VALUE" format still works unchanged.          */
/* ------------------------------------------------------------------------- */

#define MAX_MSGS 8
#define MSG_LEN 128
#define PROFILE_LEN 64

static int in_packet = 0; /* currently inside a { ... ] } record */
static char cur_profile[PROFILE_LEN] = ""; /* "profile" from the current packet */
static char active_msgs[MAX_MSGS][MSG_LEN]; /* "text" faults seen in this packet */
static int active_count = 0;
static char prev_msgs[MAX_MSGS][MSG_LEN]; /* faults active in the previous packet */
static int prev_count = 0;

/* Raw CircuitPython 16-bit ADC count -> percent (0-65535 -> 0-100). */
#define ADC16_TO_PCT (100.0 / 65535.0)

/* Compiled-in fallback: knob -> Heater_PWM (humidity-namespace %). Used when no
 * config file is present or it has no valid entries. Kept in sync with the
 * shipped qtpy-uart-bridge.conf. */
static void load_default_mappings(void)
{
    static const struct {
        const char *token;
        const char *path;
        double scale;
    } defs[] = {
        { "SLIDERS", "/xyz/openbmc_project/sensors/humidity/Heater_PWM", ADC16_TO_PCT },
        { "HEATER", "/xyz/openbmc_project/sensors/humidity/Heater_PWM", ADC16_TO_PCT },
    };
    mapping_count = 0;
    for (size_t i = 0; i < sizeof(defs) / sizeof(defs[0]); i++) {
        struct mapping *m = &mappings[mapping_count++];
        snprintf(m->token, sizeof(m->token), "%s", defs[i].token);
        snprintf(m->path, sizeof(m->path), "%s", defs[i].path);
        m->scale = defs[i].scale;
        m->offset = 0.0;
        m->min = 0.0;
        m->max = 100.0;
        m->value = 0.0;
        m->dirty = 0;
        m->seen = 0;
    }
}

/* Parse the config file into the mapping table. Returns the number of entries
 * loaded (0 if the file is unreadable or has no valid lines). */
static int load_config(const char *conf_path)
{
    FILE *f = fopen(conf_path, "r");
    if (!f)
        return 0;
    mapping_count = 0;
    char line[320];
    while (fgets(line, sizeof(line), f) && mapping_count < MAX_MAPPINGS) {
        /* Skip leading whitespace; ignore blank lines and comments. */
        char *p = line;
        while (*p == ' ' || *p == '\t')
            p++;
        if (*p == '\0' || *p == '\n' || *p == '\r' || *p == '#')
            continue;

        char tok[TOKEN_LEN];
        char path[PATH_LEN];
        double scale = 1.0, offset = 0.0, mn = -DBL_MAX, mx = DBL_MAX;
        int nf = sscanf(p, "%31s %191s %lf %lf %lf %lf", tok, path, &scale, &offset, &mn, &mx);
        if (nf < 2)
            continue; /* need at least a token and a path */

        struct mapping *m = &mappings[mapping_count++];
        snprintf(m->token, sizeof(m->token), "%s", tok);
        snprintf(m->path, sizeof(m->path), "%s", path);
        m->scale = scale;
        m->offset = offset;
        m->min = mn;
        m->max = mx;
        m->value = 0.0;
        m->dirty = 0;
        m->seen = 0;
    }
    fclose(f);
    return mapping_count;
}

static speed_t baud_to_speed(long baud)
{
    switch (baud) {
    case 9600:
        return B9600;
    case 19200:
        return B19200;
    case 38400:
        return B38400;
    case 57600:
        return B57600;
    case 115200:
        return B115200;
    case 230400:
        return B230400;
    default:
        return B0;
    }
}

static int configure_tty(int fd, speed_t speed)
{
    struct termios tio;
    if (tcgetattr(fd, &tio) < 0)
        return -1;
    cfmakeraw(&tio);
    cfsetispeed(&tio, speed);
    cfsetospeed(&tio, speed);
    tio.c_cflag |= (CLOCAL | CREAD); /* ignore modem lines, enable receiver */
    tio.c_cflag &= ~CRTSCTS; /* no hardware flow control */
    /* VMIN=0/VTIME=10: read() returns as soon as bytes arrive, or after 1 s of
     * idle with 0 bytes. The periodic wake lets the main loop notice a stop
     * request even when no UART data is flowing. */
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 10;
    if (tcsetattr(fd, TCSANOW, &tio) < 0)
        return -1;
    tcflush(fd, TCIFLUSH);
    return 0;
}

/* Parse the numeric prefix of a value token (handles a leading sign and a
 * trailing unit letter like W / C / %). Returns 1 on success. */
static int parse_num(const char *s, double *out)
{
    char *end = NULL;
    double v = strtod(s, &end);
    if (end == s)
        return 0;
    *out = v;
    return 1;
}

/* Apply one recognised KEY/number pair: find every mapping whose token matches
 * (aliases with different scales may share a path) and update its value. */
static void apply_kv(const char *key, double num)
{
    for (int i = 0; i < mapping_count; i++) {
        struct mapping *m = &mappings[i];
        if (strcasecmp(key, m->token) != 0)
            continue;
        double v = num * m->scale + m->offset;
        if (v < m->min)
            v = m->min;
        else if (v > m->max)
            v = m->max;
        m->value = v;
        m->dirty = 1;
        m->seen = 1;
    }
}

static void parse_line(char *line)
{
    /* Tokens are whitespace-separated. A token is normally "KEY:VALUE", but when
     * the firmware prints a space after the colon (e.g. "Sliders: 32000") the
     * value arrives as the next token; pending_key carries the key across to it. */
    char pending_key[TOKEN_LEN] = "";
    for (char *tok = strtok(line, " \t\r\n"); tok != NULL; tok = strtok(NULL, " \t\r\n")) {
        char *colon = strchr(tok, ':');
        if (colon) {
            *colon = '\0';
            const char *key = tok;
            const char *val = colon + 1;
            double num;
            if (*val && parse_num(val, &num)) {
                apply_kv(key, num);
                pending_key[0] = '\0';
            } else {
                /* "KEY:" alone — the number is the following token. */
                snprintf(pending_key, sizeof(pending_key), "%s", key);
            }
        } else if (pending_key[0]) {
            double num;
            if (parse_num(tok, &num))
                apply_kv(pending_key, num);
            pending_key[0] = '\0';
        }
    }
}

static void write_json(const char *raw)
{
    /* Ensure the parent directory of json_path exists. */
    char dir[256];
    snprintf(dir, sizeof(dir), "%s", json_path);
    char *slash = strrchr(dir, '/');
    if (slash && slash != dir) {
        *slash = '\0';
        mkdir(dir, 0755);
    }
    char tmp[300];
    snprintf(tmp, sizeof(tmp), "%s.tmp", json_path);
    FILE *f = fopen(tmp, "w");
    if (!f)
        return;
    fprintf(f, "{\"source\":\"qtpy\"");
    if (cur_profile[0])
        fprintf(f, ",\"profile\":\"%s\"", cur_profile);
    for (int i = 0; i < mapping_count; i++) {
        if (mappings[i].seen)
            fprintf(f, ",\"%s\":%.3f", mappings[i].token, mappings[i].value);
    }
    /* Active fault strings from the current packet (empty array when none). */
    fprintf(f, ",\"messages\":[");
    for (int i = 0; i < active_count; i++)
        fprintf(f, "%s\"%s\"", i ? "," : "", active_msgs[i]);
    fprintf(f, "]");
    /* Echo the raw line (truncated, quotes stripped) for debugging. */
    char safe[160];
    size_t j = 0;
    for (size_t i = 0; raw[i] && j < sizeof(safe) - 1; i++) {
        char c = raw[i];
        if (c == '"' || c == '\\' || (unsigned char)c < 0x20)
            c = ' ';
        safe[j++] = c;
    }
    safe[j] = '\0';
    fprintf(f, ",\"raw\":\"%s\",\"timestamp\":%lld}\n", safe, (long long)time(NULL));
    fclose(f);
    rename(tmp, json_path);
}

/* (Re)open the system bus. Closes any stale handle first. */
static int connect_bus(void)
{
    if (bus) {
        sd_bus_flush_close_unref(bus);
        bus = NULL;
    }
    int r = sd_bus_open_system(&bus);
    if (r < 0) {
        bus = NULL;
        return r;
    }
    return 0;
}

/* Push a value onto an ExternalSensor's Value property. Failure is non-fatal.
 *
 * The bridge only publishes when a UART line arrives, so the bus connection can
 * sit idle for minutes (e.g. sparse loopback testing); an idle, never-serviced
 * sd-bus connection can be dropped by the broker, after which set_property
 * returns -ENOTCONN. Self-heal: (re)connect if the handle is gone/closed, and
 * on a failed write drop the (likely stale) connection and retry once. */
static void publish_value(const char *path, double v)
{
    for (int attempt = 0; attempt < 2; attempt++) {
        if (!bus || sd_bus_is_open(bus) <= 0) {
            if (connect_bus() < 0) {
                static time_t last_err = 0;
                time_t now = time(NULL);
                if (now != last_err) {
                    last_err = now;
                    fprintf(stderr, "qtpy: cannot open system bus\n");
                }
                return;
            }
        }
        sd_bus_error err = SD_BUS_ERROR_NULL;
        int r = sd_bus_set_property(bus, SENSOR_SERVICE, path, SENSOR_IFACE, "Value", &err, "d", v);
        sd_bus_error_free(&err);
        if (r >= 0)
            return;

        /* Drop the connection so the next iteration reconnects fresh. */
        sd_bus_flush_close_unref(bus);
        bus = NULL;
        if (attempt == 1) {
            static time_t last_err = 0;
            time_t now = time(NULL);
            if (now != last_err) {
                last_err = now;
                fprintf(stderr, "qtpy: set %s Value failed: %s\n", path, strerror(-r));
            }
        }
    }
}

/* Publish every mapping that changed since the last line, clearing dirty. */
static void publish_dirty(void)
{
    for (int i = 0; i < mapping_count; i++) {
        if (mappings[i].dirty) {
            publish_value(mappings[i].path, mappings[i].value);
            mappings[i].dirty = 0;
        }
    }
}

/* ------------------------------------------------------------------------- */
/* JSON packet parsing + fault-alert posting.                                 */
/* ------------------------------------------------------------------------- */

/* QTPY_DRYRUN=1 prints parsed alerts to stdout instead of calling sd-bus, for
 * host/loopback testing with no system bus. Cached on first use. */
static int alert_dryrun(void)
{
    static int v = -1;
    if (v < 0) {
        const char *e = getenv("QTPY_DRYRUN");
        v = (e && *e && strcmp(e, "0") != 0) ? 1 : 0;
    }
    return v;
}

/* Extract the number following "key": on a JSON line (e.g. "heater": 32000). */
static int json_number(const char *line, const char *key, double *out)
{
    const char *k = strstr(line, key);
    if (!k)
        return 0;
    const char *colon = strchr(k, ':');
    if (!colon)
        return 0;
    return parse_num(colon + 1, out);
}

/* Extract the quoted string value following "key": on a JSON line
 * (e.g. "text": "Fan Failed" -> Fan Failed). Returns 1 on success. */
static int json_string(const char *line, const char *key, char *out, size_t outsz)
{
    const char *k = strstr(line, key);
    if (!k)
        return 0;
    const char *colon = strchr(k, ':');
    if (!colon)
        return 0;
    const char *q1 = strchr(colon, '"');
    if (!q1)
        return 0;
    const char *q2 = strchr(q1 + 1, '"');
    if (!q2)
        return 0;
    size_t n = (size_t)(q2 - (q1 + 1));
    if (n >= outsz)
        n = outsz - 1;
    memcpy(out, q1 + 1, n);
    out[n] = '\0';
    return 1;
}

/* Post one fault to the OpenBMC logging service -> Redfish EventLog (surfaced by
 * both the stock bmcweb WebUI and the custom dashboard). assert=1 logs the fault
 * at Error severity; assert=0 logs an Informational "cleared" note. Best-effort:
 * failures are non-fatal (the bus may be absent during host/loopback testing). */
static void post_alert(const char *msg, int assert)
{
    char full[256];
    const char *src = cur_profile[0] ? cur_profile : "SensorBoard";
    if (assert)
        snprintf(full, sizeof(full), "%s: %s", src, msg);
    else
        snprintf(full, sizeof(full), "%s: %s (cleared)", src, msg);

    if (alert_dryrun()) {
        printf("qtpy: ALERT[%s] %s\n", assert ? "SET" : "CLR", full);
        return;
    }

    if (!bus || sd_bus_is_open(bus) <= 0) {
        if (connect_bus() < 0)
            return;
    }
    const char *level = assert ? "xyz.openbmc_project.Logging.Entry.Level.Error" :
                                 "xyz.openbmc_project.Logging.Entry.Level.Informational";
    sd_bus_error err = SD_BUS_ERROR_NULL;
    int r = sd_bus_call_method(bus, "xyz.openbmc_project.Logging", "/xyz/openbmc_project/logging",
                               "xyz.openbmc_project.Logging.Create", "Create", &err, NULL, "ssa{ss}", full, level, 0);
    if (r < 0) {
        static time_t last_err = 0;
        time_t now = time(NULL);
        if (now != last_err) {
            last_err = now;
            fprintf(stderr, "qtpy: log Create failed: %s\n", err.message ? err.message : strerror(-r));
        }
        /* Drop a likely-stale bus so the next publish/alert reconnects fresh. */
        sd_bus_flush_close_unref(bus);
        bus = NULL;
    }
    sd_bus_error_free(&err);
}

/* Diff the current packet's faults against the previous packet and emit exactly
 * one event per edge: a held switch logs once (not at 10 Hz), and releasing it
 * logs a single "cleared". */
static void finalize_packet(void)
{
    for (int i = 0; i < active_count; i++) {
        int found = 0;
        for (int j = 0; j < prev_count; j++)
            if (strcmp(active_msgs[i], prev_msgs[j]) == 0) {
                found = 1;
                break;
            }
        if (!found)
            post_alert(active_msgs[i], 1);
    }
    for (int j = 0; j < prev_count; j++) {
        int found = 0;
        for (int i = 0; i < active_count; i++)
            if (strcmp(prev_msgs[j], active_msgs[i]) == 0) {
                found = 1;
                break;
            }
        if (!found)
            post_alert(prev_msgs[j], 0);
    }
    memcpy(prev_msgs, active_msgs, sizeof(prev_msgs));
    prev_count = active_count;
}

/* Dispatch one received line: JSON packet mode (new firmware) or legacy
 * single-line KEY:VALUE (old firmware / loopback). `line` is mutated by the
 * legacy tokenizer; `raw` is the untouched copy used for JSON scans + logging. */
static void process_record(char *line, const char *raw)
{
    const char *p = raw;
    while (*p == ' ' || *p == '\t')
        p++;

    if (*p == '{') {
        /* Start of a new packet: reset per-packet state, grab profile+heater. */
        in_packet = 1;
        active_count = 0;
        cur_profile[0] = '\0';
        json_string(raw, "\"profile\"", cur_profile, sizeof(cur_profile));
        double h;
        if (json_number(raw, "\"heater\"", &h))
            apply_kv("HEATER", h);
        return;
    }

    if (in_packet) {
        if (*p == ']') {
            /* End of packet: publish heater, dump JSON, edge-diff the faults. */
            write_json(raw);
            publish_dirty();
            finalize_packet();
            in_packet = 0;
            return;
        }
        double h;
        if (json_number(raw, "\"heater\"", &h))
            apply_kv("HEATER", h);
        char msg[MSG_LEN];
        if (json_string(raw, "\"text\"", msg, sizeof(msg)) && active_count < MAX_MSGS)
            snprintf(active_msgs[active_count++], MSG_LEN, "%s", msg);
        return;
    }

    /* Legacy single-line format. */
    parse_line(line);
    write_json(raw);
    publish_dirty();
}

int main(int argc, char **argv)
{
    const char *dev = (argc > 1) ? argv[1] : getenv("QTPY_TTY");
    if (!dev || !*dev)
        dev = default_dev;
    long baud = (argc > 2) ? strtol(argv[2], NULL, 10) : 0;
    if (baud == 0) {
        const char *b = getenv("QTPY_BAUD");
        baud = b ? strtol(b, NULL, 10) : 115200;
    }
    speed_t speed = baud_to_speed(baud);
    if (speed == B0) {
        fprintf(stderr, "qtpy: unsupported baud %ld\n", baud);
        return 1;
    }
    const char *jp = getenv("QTPY_JSON");
    if (jp && *jp)
        json_path = jp;

    /* Config path: 3rd arg, else QTPY_CONF, else the default /etc location. */
    const char *conf = (argc > 3) ? argv[3] : getenv("QTPY_CONF");
    if (!conf || !*conf)
        conf = default_conf;
    if (load_config(conf) > 0) {
        printf("qtpy: loaded %d mapping(s) from %s\n", mapping_count, conf);
    } else {
        load_default_mappings();
        printf("qtpy: no config at %s; using %d built-in default mapping(s)\n", conf, mapping_count);
    }

    /* sigaction without SA_RESTART so a blocking read() returns EINTR on stop
     * (glibc signal() defaults to SA_RESTART, which would mask SIGTERM here). */
    struct sigaction sa = { 0 };
    sa.sa_handler = on_signal;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    setvbuf(stdout, NULL, _IOLBF, 0);

    int fd = open(dev, O_RDWR | O_NOCTTY);
    if (fd < 0) {
        fprintf(stderr, "qtpy: cannot open %s: %s\n", dev, strerror(errno));
        return 1;
    }
    if (configure_tty(fd, speed) < 0) {
        fprintf(stderr, "qtpy: tty config failed on %s: %s\n", dev, strerror(errno));
        close(fd);
        return 1;
    }
    /* Open the system bus for ExternalSensor updates (non-fatal: publish_value
     * reconnects on demand, so a failure here just delays the first publish). */
    if (connect_bus() < 0) {
        fprintf(stderr, "qtpy: system bus not up yet; will retry on publish, "
                        "/run JSON still works\n");
    }

    printf("qtpy: reading %s @ %ld 8N1; waiting for QT Py lines...\n", dev, baud);

    char line[256];
    size_t len = 0;
    unsigned lines = 0;
    time_t last_log = 0;

    while (running) {
        char buf[128];
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n < 0) {
            if (errno == EINTR)
                continue;
            fprintf(stderr, "qtpy: read error: %s\n", strerror(errno));
            break;
        }
        if (n == 0)
            continue;
        for (ssize_t i = 0; i < n; i++) {
            char c = buf[i];
            if (c == '\n' || c == '\r') {
                if (len == 0)
                    continue;
                line[len] = '\0';
                char raw[256];
                memcpy(raw, line, len + 1);
                process_record(line, raw);
                lines++;
                time_t now = time(NULL);
                if (now != last_log) { /* throttle journal to ~1 Hz */
                    last_log = now;
                    printf("qtpy: %s\n", raw);
                }
                len = 0;
            } else if (len < sizeof(line) - 1) {
                line[len++] = c;
            } else {
                len = 0; /* overlong line; drop and resync */
            }
        }
    }

    printf("qtpy: exiting after %u lines\n", lines);
    if (bus)
        sd_bus_unref(bus);
    close(fd);
    return 0;
}
