# Customizing the OpenBMC Sensor Dashboard

A practical guide for front-end developers who want to change how the sensor
dashboard looks and behaves. No FPGA, Yocto, or embedded knowledge required for
most tasks - the dashboard is plain static HTML/CSS/JS.

---

## 1. What you can and cannot customize

| Surface | URL | Customizable? | How |
|---------|-----|---------------|-----|
| **This custom dashboard** | `https://<bmc>/dashboard/` | **Yes - your playground** | Edit the static files (below). No build step. |
| Stock OpenBMC web UI (`webui-vue`) | `https://<bmc>/` | Not in scope | Requires forking `webui-vue`, a full Vue/Node build, and rebuilding the BMC image. Heavy; avoid for demo work. |

Both pages coexist: the stock UI stays at `/`, this dashboard lives at
`/dashboard/`. Everything in this guide is about the dashboard only.

---

## 2. The files

All sources live in this recipe's `files/` directory and are installed to
`/usr/share/www/dashboard/` on the BMC:

| File | Purpose |
|------|---------|
| `index.html` | Markup + the inlined Altera wordmark `<svg>`. Board-specific text lives here. |
| `dashboard.css` | Theme (navy/Altera-blue) and layout. |
| `dashboard.js` | Redfish polling, card/sparkline rendering, topology dots, event log. **Most config lives here.** |
| `chart.umd.min.js` | Vendored Chart.js for sparklines. |
| `CUSTOMIZE.md` | This guide (installed at `/usr/share/dashboard/CUSTOMIZE.md`). |
| `deploy-dashboard.sh` | On-board deploy helper (installed as `/usr/bin/deploy-dashboard`). |

bmcweb recursively scans `/usr/share/www` at startup and registers one route per
file, so an `index.html` in the `dashboard/` subdir is served at
`/dashboard/`.

---

## 3. Hard rules (Content-Security-Policy)

bmcweb serves every page under a strict CSP:

```
default-src 'none'; img-src 'self' data:; style-src 'self'; script-src 'self'
```

This means:

- **No inline JavaScript.** No `<script>...</script>` with code, no `onclick=""`
  handlers. All JS must be in a separate `.js` file loaded with
  `<script src="...">`.
- **No inline CSS.** No `<style>...</style>` blocks, no `style="..."` attributes.
  All styling must be in `dashboard.css`. (To set a style from JS, use the CSSOM,
  e.g. `el.style.order = "3"` - that is allowed; it is the `style=""` *attribute
  in markup* that is blocked.)
- **No CDNs / external URLs.** Everything must be same-origin. Third-party
  libraries must be **vendored** (downloaded into `files/` and shipped), like
  `chart.umd.min.js`.
- **Images** must be same-origin files or `data:` URIs. The logo is an inline
  `<svg>` element (part of the document, not a fetch), which is allowed.

If you add a **new file** (e.g. `extra.js` or `theme2.css`), you must also add it
to the recipe (`dashboard_1.0.bb` - `SRC_URI` and `do_install`) so bmcweb
registers a route for it. Editing the *contents* of an existing file needs no
recipe change.

---

## 4. Reaching the dashboard while developing

The page authenticates with the bmcweb **session cookie**, so it must be loaded
from the BMC's own origin. Two ways:

**Directly**, if you can reach the BMC IP:

```
https://<bmc-ip>/dashboard/      (note the trailing slash)
```

**Via SSH tunnel**, if the BMC is behind a jump host:

```bash
ssh -L 127.0.0.1:8443:<bmc>:443 <jumphost>
# then browse:
https://localhost:8443/dashboard/
```

Log in to the stock web UI or Redfish first so the browser holds a valid session
cookie. Leave the dashboard's **BMC** header field blank so fetches use the same
origin (cross-origin would require CORS, which bmcweb does not enable).

---

## 5. The config API (edit `dashboard.js`, top of file)

Most look-and-feel changes need no new code - just edit these objects.

### 5.1 `CONFIG` - global behavior

```js
const CONFIG = {
  bmcBase: localStorage.getItem("bmcBase") ?? "",  // "" = same origin
  pollMs:  +(localStorage.getItem("pollMs") ?? 2000), // refresh interval (ms)
  history: 60,     // points kept per sparkline
  logMax:  12,     // event-log rows shown
  logPaths: [ ... ],  // Redfish event-log collections, tried in order
  oem: {           // optional custom endpoints (drive topology dots)
    heater: "/redfish/v1/Chassis/Agilex5E013B/Oem/Altera/Heater",
    accel:  "/redfish/v1/Chassis/Agilex5E013B/Oem/Altera/Accelerometer",
    fanPwm: "/redfish/v1/Chassis/Agilex5E013B/Oem/Altera/FanPwm",
  },
};
```

- Faster/slower refresh: change `pollMs` (e.g. `1000` for 1 s).
- Longer sparkline memory: raise `history`.
- The BMC field and poll rate can also be overridden at runtime (persisted to
  `localStorage`), so you can tweak without redeploying.

### 5.2 `SECTIONS` - group and order the sensor cards

```js
const SECTIONS = [
  { id: "altera", title: "Altera Sensor Board",
    items: ["Fan_Ctrl_PWM", "Fan_Ctrl", "Board_Temp", "Heater_PWM", ...] },
  { id: "sdmxcvr", title: "SDM / XCVR Temperature",
    items: ["SDM_Temp", "XCVR_BotLeft_Temp", ...] },
];
const DEFAULT_SECTION = "altera";  // uncategorized sensors land here
```

- Each object is a titled group; `items` sets the **left-to-right order** within
  the group.
- Names are matched loosely: `Board_Temp`, `Board Temp`, and `board-temp` all
  match (normalized to lowercase alphanumerics).
- A sensor not listed in any section falls into `DEFAULT_SECTION`.
- To add a group, append a new `{ id, title, items }`. To reorder groups, reorder
  the array.

### 5.3 `DISPLAY_NAMES` - relabel a card

```js
const DISPLAY_NAMES = {
  "fanctrl": "Fan Ctrl Tach",
  "heatercurrent": "Heater Current",
};
```

Keys are the normalized sensor id/name; the value is the visible card title. This
changes only the label, not the underlying Redfish sensor.

---

## 6. Common tasks

**Change the refresh rate** -> `CONFIG.pollMs`.

**Rename a card** -> add an entry to `DISPLAY_NAMES`.

**Reorder / regroup cards** -> edit `SECTIONS`.

**Add a new sensor card** -> nothing to do in most cases. The dashboard
auto-discovers every sensor under `/redfish/v1/Chassis/Agilex5E013B/Sensors` and renders
a card for it. To place it, add its name to a section's `items`; otherwise it
lands in `DEFAULT_SECTION`. (A sensor only appears once the BMC actually exposes
it in Redfish - that is a firmware/entity-manager change, not a dashboard one.)

**Restyle** -> edit `dashboard.css`. Card markup is created in `upsertCard()` with
classes `.card`, `.name`, `.value .num`, `.unit`, `.sub`, plus state classes
`.pending`, `.warn`, `.bad`.

**Warn/critical colors** -> come automatically from each sensor's Redfish
`Thresholds` (see `sensorState()`); no config needed.

**Add a third-party JS/CSS library** -> vendor the file into `files/`, add it to
`SRC_URI` + `do_install` in `dashboard_1.0.bb`, and reference it same-origin.
Never link a CDN (CSP will block it).

---

## 7. Redfish data the dashboard consumes

All sensor values come from the standard Redfish sensor API. Getting them is a
three-step walk (the dashboard does exactly this):

```bash
# 1. Find the chassis (this board reports one: Agilex3E135B / Agilex5E013B)
curl -sk -u root:0penBmc https://<bmc>/redfish/v1/Chassis

# 2. List the sensor collection for that chassis -> array of @odata.id links
curl -sk -u root:0penBmc https://<bmc>/redfish/v1/Chassis/Agilex5E013B/Sensors

# 3. Read an individual sensor to get its live Reading
curl -sk -u root:0penBmc https://<bmc>/redfish/v1/Chassis/Agilex5E013B/Sensors/Board_Temp
```

Getting them all at once: Redfish defines `$expand` to inline every member in a
single request, e.g.:

```bash
curl -sk -u root:0penBmc \
  "https://<bmc>/redfish/v1/Chassis/Agilex5E013B/Sensors?\$expand=*(\$levels=1)"
```

but **not every bmcweb build enables `$expand`** (some reject it with
`QueryParameterValueFormatError`). If it is rejected, fall back to step 2 + a
per-sensor GET of each link. The dashboard tries `$expand` first and then
enumerates, fetching the members **concurrently** so it stays fast either way.

Reference implementation in `dashboard.js`:

- `discoverChassis()` - step 1 (finds the chassis with a `Sensors` collection).
- `fetchSensors()` - steps 2-3 (tries `$expand`, else parallel per-sensor GETs).
- `rf(path)` - the shared fetch helper (adds the session token, same origin).

So: point developers at **this section for the API**, and at those three
functions in `dashboard.js` for a working example.

Each sensor object looks like:

```json
{
  "Name": "Board_Temp",
  "ReadingType": "Temperature",
  "Reading": 41.2,
  "ReadingUnits": "Cel",
  "Thresholds": {
    "UpperCaution":  { "Reading": 70 },
    "UpperCritical": { "Reading": 85 }
  }
}
```

Key fields the dashboard uses: `Name`/`Id` (placement + label), `ReadingType`
(unit + which topology dot), `Reading` (value + sparkline), `Thresholds`
(warn/bad color).

Event log is read from the first of `CONFIG.logPaths` that answers:

1. `/redfish/v1/Systems/system/LogServices/EventLog/Entries`
2. `/redfish/v1/Managers/bmc/LogServices/EventLog/Entries`
3. `/redfish/v1/Managers/bmc/LogServices/Journal/Entries`

### A minimal standalone example

The smallest possible page that lists every sensor value, with no styling. It is
two files, because the CSP requires the JavaScript to be a separate same-origin
file (it cannot be inline).

`index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Sensors</title>
</head>
<body>
  <h1>Sensors</h1>
  <ul id="sensors"><li>loading...</li></ul>
  <script src="/dashboard/dashboard.js"></script>
</body>
</html>
```

`dashboard.js`:

```js
const CHASSIS = "Agilex5E013B";
const BASE = "/redfish/v1/Chassis/" + CHASSIS + "/Sensors";

async function load() {
  const list = document.getElementById("sensors");
  try {
    // 1. get the collection of sensor links
    const coll = await fetch(BASE, { credentials: "include" }).then(r => r.json());
    // 2. fetch each sensor (in parallel) to read its value
    const sensors = await Promise.all(
      coll.Members.map(m =>
        fetch(m["@odata.id"], { credentials: "include" }).then(r => r.json())
      )
    );
    // 3. render
    list.innerHTML = "";
    for (const s of sensors) {
      const li = document.createElement("li");
      li.textContent = `${s.Name}: ${s.Reading} ${s.ReadingUnits || ""}`;
      list.appendChild(li);
    }
  } catch (e) {
    list.innerHTML = "<li>error: " + e + "</li>";
  }
}

load();
setInterval(load, 500);   // refresh every 0.5 seconds
```

Deploy both files and hard-refresh:

```bash
deploy-dashboard /tmp/dash    # copies index.html + dashboard.js
```

Notes:

- Name the script `dashboard.js` so it reuses the existing bmcweb route and
  `deploy-dashboard` picks it up.
- It needs an active bmcweb session: log into the web UI first (the
  `credentials: "include"` sends the cookie), or add the SessionService login from
  section 9 to make it self-contained.
- This example refreshes every 500 ms for a snappy demo. Be aware that fast
  polling over Basic Auth re-hashes the password on every request and strains
  bmcweb; on a busy BMC use a larger interval or a session token (section 9).

---

## 8. Edit / deploy loop

1. Edit the files in `files/` on your workstation.
2. Copy them to the BMC and deploy with the helper:

```bash
# from your workstation
scp index.html dashboard.css dashboard.js chart.umd.min.js root@<bmc>:/tmp/dash/

# on the BMC
deploy-dashboard /tmp/dash
```

`deploy-dashboard` remounts the rootfs read-write, backs up the current dashboard
to `/var/lib/dashboard-backups/<timestamp>/`, installs the new files into
`/usr/share/www/dashboard/`, and restarts bmcweb. Run `deploy-dashboard --help`
for options.

3. Refresh `https://<bmc>/dashboard/`. Content edits appear on reload; a restart
   is only needed when you add brand-new files (new routes) - the helper does it
   for you.

For a permanent change, put the edited files back into this recipe's `files/`
directory and rebuild the image so the change ships by default.

---

## 9. Quick reference

| I want to... | Edit |
|--------------|------|
| Refresh faster/slower | `CONFIG.pollMs` in `dashboard.js` |
| Keep more history in sparklines | `CONFIG.history` |
| Rename a card | `DISPLAY_NAMES` |
| Group / order cards | `SECTIONS` |
| Change colors, spacing, fonts | `dashboard.css` |
| Add a vendored library | `files/` + `dashboard_1.0.bb` |
| Deploy to a running board | `deploy-dashboard` |
