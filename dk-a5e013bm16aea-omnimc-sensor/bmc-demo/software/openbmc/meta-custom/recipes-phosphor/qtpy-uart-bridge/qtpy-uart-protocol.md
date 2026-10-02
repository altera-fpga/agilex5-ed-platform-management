# QT Py -> BMC UART Protocol

Contract between the Altera sensor board's QT Py MCU (sender) and the BMC's
`qtpy-uart-bridge` daemon (receiver). The QT Py firmware is owned separately;
this document is what that firmware should implement against.

## Physical link

| Property   | Value                                                      |
|------------|------------------------------------------------------------|
| Wire       | QT Py TX -> BMC RX on the HPS UART (`Host_TX`/`Host_RX`)    |
| BMC device | `/dev/ttyS1` (HPS UART1, FPGA pin-muxed)                    |
| Baud       | `115200`                                                   |
| Framing    | 8 data bits, no parity, 1 stop bit (8N1), no flow control   |

The bridge device/baud can be overridden via args or `QTPY_TTY` / `QTPY_BAUD`.

## Line format

- ASCII, one record per line, terminated by `\n` (a `\r` is also accepted).
- Each line is whitespace-separated `KEY:VALUE` tokens. A space after the colon
  is allowed too (e.g. `Sliders: 32000`), so the value may be the next token.
- `VALUE` is a number with an optional sign and an optional trailing unit letter
  (e.g. `%`, `W`, `C`); the unit letter is ignored by the parser.
- Keys are case-insensitive. Unknown tokens are ignored, so the format can be
  extended without breaking the receiver.
- Keep lines under ~250 bytes (longer lines are dropped and resynced).

## Token -> sensor mapping is configurable

The bridge does **not** hardcode token names. At startup it loads a mapping table
from `/etc/qtpy-uart-bridge.conf` (override with `QTPY_CONF` or a 3rd CLI arg).
Each non-comment line maps one UART token to one dbus-sensors `ExternalSensor`
object path plus a linear transform:

```
# TOKEN    sensor_object_path                                scale        offset  min  max
SLIDERS    /xyz/openbmc_project/sensors/humidity/Heater_PWM  0.00152590   0       0    100
```

- Published value = `clamp(num*scale + offset, min, max)`. `scale` defaults to 1,
  `offset` to 0, and `min`/`max` are unbounded when omitted.
- `0.00152590 = 100/65535` converts a raw 16-bit ADC count to percent.
- Lines starting with `#` and blank lines are ignored.
- If the config is missing or empty, a compiled-in default (identical to the
  shipped `qtpy-uart-bridge.conf`) is used, so the daemon works out of the box.

### Adding a new value (no recompile)

To surface a new QT Py value on Redfish:

1. Add a line to `/etc/qtpy-uart-bridge.conf` mapping the token to a new
   `ExternalSensor` object path.
2. Add a matching `ExternalSensor` entry to entity-manager's
   `entity-config.json` (this is what actually creates the Redfish sensor; the
   bridge only sets its `Value`). The object path is
   `/xyz/openbmc_project/sensors/<namespace>/<Name>`, where `<namespace>` comes
   from the `Units` (e.g. `PercentRH` -> `humidity`, `DegreesC` -> `temperature`).
3. Restart `qtpy-uart-bridge` (and `xyz.openbmc_project.EntityManager`). The
   custom dashboard auto-discovers any Redfish sensor, so no dashboard change is
   required unless you want custom placement or a display label.

## Default tokens

The shipped config maps the potentiometer knob to the `Heater_PWM` sensor:

| Token      | Meaning                              | Scaling            |
|------------|--------------------------------------|--------------------|
| `SLIDERS`  | Potentiometer / knob position        | raw 0-65535 -> %   |
| `HEATER`   | Same knob value (post-rename token)  | raw 0-65535 -> %   |

`SLIDERS`/`HEATER` are a **raw 16-bit ADC count** (0-65535) read by the QT Py
from the potentiometer. CircuitPython reports ADC values on a fixed 16-bit
scale, so the QT Py does no scaling; the BMC bridge scales it to 0-100% before
publishing. On the real sensor board the heater power and temperatures are
measured by BMC-side I3C sensors (driven from the FPGA), **not** the QT Py, so in
normal operation the QT Py only needs to send one knob token (`SLIDERS`, or
`HEATER` after the firmware rename). To accept a pre-scaled percent instead (e.g.
for loopback/dev), add a mapping line with `scale 1` for your token.

## Cadence and liveness

- Send `Sliders: <0-65535>` (or `Heater: <0-65535>`) **continuously at ~10 Hz**
  (every 100 ms), even when the knob is not moving.
- The BMC publishes each received value to Redfish immediately. The `Heater_PWM`
  ExternalSensor has a ~15 s `Timeout`, so if the QT Py stops sending, the
  dashboard tile goes "unavailable" rather than holding a stale value. Streaming
  continuously keeps it live and gives the dashboard a real trend.

### Example

```
Sliders: 32000
Sliders: 32768
Sliders: 49151
```

Combined lines are also valid (extra tokens are simply parsed too, and any token
without a mapping is ignored):

```
HEATER:32000 TEMP:31.4C VREF:1.8
```

Here `HEATER` is mapped and published; `TEMP`/`VREF` have no mapping and are
ignored entirely.

## Where the value lands

- D-Bus: `xyz.openbmc_project.ExternalSensor` ->
  `/xyz/openbmc_project/sensors/humidity/Heater_PWM` (`Sensor.Value`), in percent
  (0-100) after the bridge scales the raw 16-bit count.
  (Units=PercentRH lands in the "humidity" namespace; bmcweb does not surface
  the "percent" namespace that Units=Percent would use.)
- Redfish: `/redfish/v1/Chassis/<Chassis>/Sensors/humidity_Heater_PWM`
  (bmcweb reports `ReadingType: "Humidity"` with a `%` reading; the dashboard
  labels the tile "Heater").
- Debug JSON: `/run/qtpy/heater.json` (dumps every seen token's current value).

## Bring-up: loopback first

Before the QT Py exists, validate the path by feeding lines into the BMC UART
(or short TX<->RX and echo from another host):

```sh
# On the BMC, watch the bridge:
journalctl -fu qtpy-uart-bridge

# From a host wired to the UART (or a loopback jig):
while true; do printf 'Sliders: %d\n' $((RANDOM % 65536)); sleep 0.1; done > /dev/ttyUSBx
```

Confirm the value moves:

```sh
busctl get-property xyz.openbmc_project.ExternalSensor \
  /xyz/openbmc_project/sensors/humidity/Heater_PWM \
  xyz.openbmc_project.Sensor.Value Value
```

## Reserved for the future (not implemented yet)

A host->QT Py / fan PWM override command is reserved but **not** implemented in
the bridge today (the QT Py PWM nets are DNP on the current board; the HPS/FPGA
drives the fan/heater PWM directly). When added, the intended form is:

| Command        | Meaning                                      |
|----------------|----------------------------------------------|
| `PWM:<0-100>`  | Force fan PWM duty to N percent              |
| `PWM:AUTO`     | Return fan control to the PID loop (swampd)  |

This would be wired to the existing `fan-pwm-manual` utility. Do not rely on it
until it is implemented.
