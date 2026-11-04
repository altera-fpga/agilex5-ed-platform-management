# Sensor-board QT Py MCU firmware (`code.py`)

The Altera sensor board carries an **Adafruit QT Py RP2040** running
[CircuitPython](https://circuitpython.org/). It reads the heater knob (or an I2C
switch panel), drives the heater PWM, and streams telemetry over the hardware
UART to the BMC, where `qtpy-uart-bridge` parses it (see
`../openbmc/meta-custom/recipes-phosphor/qtpy-uart-bridge/qtpy-uart-protocol.md`).

## Firmware versions

The firmware is versioned by its **UART wire format**, not by release date — it
only changes when the protocol between the QT Py and `qtpy-uart-bridge` changes.
Flash the version that matches the BMC image you are running:

| Firmware | UART format | Features | Use with |
|----------|-------------|----------|----------|
| [`v1-heater/code.py`](v1-heater/code.py) | `Heater: <n>` single line | Heater PWM only | **Any** release (older bridges included). |
| [`v2-rack/`](v2-rack) `bmc`/`cdu`/`psu` `/code.py` | JSON record + `messages[]` | Heater PWM **+ switch-triggered fault flagging**, BMC/CDU/PSU profiles | This release onward (bridge must understand the v2 format). |

The current `qtpy-uart-bridge` is **backward compatible** — it still parses the
legacy `v1` single-line format — so `v1-heater` keeps working on a new image. The
table therefore reads as *"minimum firmware for a given feature"*: a customer on
an older BMC image should flash `v1-heater`; the fault-flagging demo needs `v2`.

### v2 profiles (BMC / CDU / PSU)

| File | Profile |
|------|---------|
| `v2-rack/bmc/code.py` | Board Management Controller (**default** for a single board). |
| `v2-rack/cdu/code.py` | Cooling Distribution Unit. |
| `v2-rack/psu/code.py` | Power Shelf / Power Supply Unit. |

The three profiles are identical except for the `profile` string and the fault
message strings. They mirror the mini-rack demo (three of our boards emulating
BMC / CDU / PSU in a rack). For a single-board demo, use `v2-rack/bmc/code.py`.

## What v2 sends

Each profile streams a multi-line record over the UART every ~100 ms:

```
{ "profile": "BoardManagementController",
  "heater": 32000,
  "messages": [
    "text": "Chassis Intrusion Detected",
    "text": "Fan Failed",
] }
```

- `heater` is a raw 16-bit knob/ADC value (0..65535); the BMC scales it to 0-100%.
- Each `"text"` line is a fault triggered by a switch on the I2C panel. The BMC
  posts these to the OpenBMC event log, so they appear (in red) on both the stock
  bmcweb **Logs -> Event logs** page and the custom `/dashboard`.

| Switch | BMC fault | CDU fault | PSU fault |
|:------:|-----------|-----------|-----------|
| 1 | Chassis Intrusion Detected | Leak Detected | Power Supply A Failed |
| 2 | PFR Violation Detected | Pump Failed | Power Supply B Failed |
| 3 | Fan Failed | Fan Failed | Power Supply C Failed |

> **Note on the wire format.** The record above is *JSON-ish* but not strictly
> valid JSON (bare `"text":` items, trailing commas) — it matches the MCU
> firmware as shipped. The bridge parses it tolerantly (field scans, not a strict
> JSON parser). A future firmware revision may tighten this to be fully
> JSON-compliant; the tolerant bridge parser should continue to work, but
> re-verify against `qtpy-uart-protocol.md` when adopting a newer `code.py`.

### No panel? It still works

If the I2C switch panel is not connected, the firmware prints `No I2C` and
**reverts to the onboard potentiometer** for the heater value — so the heater
demo works with or without the front panel. Fault flagging requires the panel
(or the rev-2 user button; see below).

## Updating the firmware (drag-and-drop)

The QT Py mounts as a USB mass-storage drive named **`CIRCUITPY`**. Updating is
just copying `code.py` to the root of that drive; CircuitPython auto-reloads
within a few seconds.

> **Do this on a Linux host.** Corporate IT commonly blocks USB mass-storage on
> Windows, so the `CIRCUITPY` drive will not appear there. On a headless Linux
> host reached over SSH the desktop auto-mounter also does not fire, so you mount
> the drive yourself (see below).

### !! Required library for v2 — `adafruit_bus_device` (common gotcha) !!

The `v2-rack` code uses the I2C ADC + switch panel and therefore imports
`adafruit_bus_device`, which is **NOT built into CircuitPython**. A fresh QT Py
(or one that previously ran `v1-heater`) ships with an **empty `lib/`**, so the
v2 code fails at import and sends nothing over the UART — with no obvious error
unless you watch the USB REPL (`/dev/ttyACM0`), where you would see:

```
ImportError: no module named 'adafruit_bus_device'
```

**Fix:** copy the `adafruit_bus_device/` package into `CIRCUITPY/lib/`. Use the
pure-Python source (version-agnostic; avoids `.mpy` ABI mismatches across
CircuitPython major versions):

```bash
# on a host with internet (set the Altera proxy if needed):
export https_proxy=http://proxy-dmz.altera.com:912
curl -fsSL -o busdevice.zip \
  https://github.com/adafruit/Adafruit_CircuitPython_BusDevice/archive/refs/heads/main.zip
unzip -q busdevice.zip
# copy the package onto the CIRCUITPY drive:
cp -r Adafruit_CircuitPython_BusDevice-main/adafruit_bus_device <CIRCUITPY>/lib/
sync
```

`v1-heater` uses only built-in modules, so its `lib/` can be left empty — do not
assume an empty `lib/` is fine for the v2 firmware.

### Mounting CIRCUITPY on a headless Linux host

If the drive does not auto-mount (typical over SSH), mount it with your own
uid/gid so you can write to it without `sudo` per file:

```bash
DEV=$(lsblk -rno NAME,LABEL | awk '$2=="CIRCUITPY"{print "/dev/"$1}')   # e.g. /dev/sdb1
sudo mount -o uid=$(id -u),gid=$(id -g),umask=000 "$DEV" /tmp/circuitpy
cp v2-rack/bmc/code.py /tmp/circuitpy/code.py        # or v1-heater/code.py
sync
sudo umount /tmp/circuitpy
```

## Verifying it runs

The USB serial REPL (`/dev/ttyACM0`, often `root:dialout` -> needs `sudo`) shows
`print()` output only; the telemetry goes out the **hardware UART**, not USB.
A healthy v2 boot prints:

```
Starting!
Starting loop controlled by I2C ADC      # panel present
# or:
No I2C
Starting loop controlled by analog input # no panel -> potentiometer fallback
```

On the BMC side, watch the bridge:

```bash
journalctl -fu qtpy-uart-bridge
```

## Second-revision sensor board

Rev-2 boards add a user push-button that can also trigger a fault message (not
yet wired into these `code.py` files; reserved for a future update). This is the
intended way to demo fault flagging on a board that has no I2C front panel.
