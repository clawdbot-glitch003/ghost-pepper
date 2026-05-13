# ESP32 BLE Keyboard Bridge

Starter firmware for turning an original ESP32 board (including LILYGO TTGO LoRa / Meshtastic ESP32 boards) into a USB-serial-to-Bluetooth-HID keyboard bridge for Ghost Pepper.

The intended hardware path is:

1. Ghost Pepper/Mac sends newline-delimited JSON over USB serial to the ESP32.
2. The ESP32 pairs to the target computer as a Bluetooth keyboard.
3. The ESP32 types the received text via BLE HID.

This directory is the firmware + manual USB-serial test path. The current app scaffold in this PR still emits the same JSON-line command shape over TCP host/port settings; a future app-side serial transport can send those JSON lines directly to the ESP32 USB serial port without changing the firmware protocol.

> **Important:** Flashing this firmware replaces Meshtastic on the board. Meshtastic cannot stay installed at the same time as this bridge firmware. You can restore Meshtastic later with the official Meshtastic web flasher or CLI flasher.

## Protocol

Send one JSON object per line at `115200` baud:

```json
{"type":"text","text":"Hello from Ghost Pepper"}
```

Optional fields:

- `delay_ms`: per-character delay in milliseconds, clamped by firmware.

Example:

```json
{"type":"text","text":"Slow test","delay_ms":25}
```

The firmware currently targets a US keyboard layout through the ESP32 BLE Keyboard library. Printable ASCII, newline/return, and tab are sent directly. A small set of common smart punctuation characters is normalized to ASCII; unsupported non-ASCII characters are skipped and reported on serial.

## Install PlatformIO

On macOS, either install the VS Code PlatformIO extension or use the CLI:

```sh
python3 -m pip install --user platformio
```

If your shell cannot find `pio`, add Python's user scripts directory to `PATH`, or run commands as `python3 -m platformio ...`.

## Flash the ESP32

From the repo root:

```sh
cd hardware/esp32-ble-keyboard-bridge
pio run -t upload
```

If the upload cannot connect, put the board into the ROM bootloader and retry:

1. Hold `BOOT`.
2. Tap/release `RESET` (or plug USB in while holding `BOOT`).
3. Release `BOOT` when PlatformIO starts connecting.

You can also use the helper script from the repo root:

```sh
scripts/flash-esp32-ble-keyboard-bridge.sh
```

Specify a port if auto-detection finds the wrong device:

```sh
scripts/flash-esp32-ble-keyboard-bridge.sh --port /dev/cu.usbserial-0001
```

## Pair the BLE keyboard

After flashing, the board advertises as:

```text
GhostPepper-Keyboard
```

On the company laptop, open Bluetooth settings and pair/connect to `GhostPepper-Keyboard`. Keep the ESP32 plugged into the spare MacBook via USB serial.

Serial logs show `BLE keyboard connected.` when the target laptop connects.

## Send a test line over serial

From the repo root:

```sh
scripts/test-esp32-ble-keyboard-bridge.py --text "Hello from Ghost Pepper"
```

Or choose a port explicitly:

```sh
scripts/test-esp32-ble-keyboard-bridge.py --port /dev/cu.usbserial-0001 --text "Hello target laptop"
```

Focus a text field on the paired laptop before sending the test. The ESP32 will type into the focused field.

## Edit board settings

The default PlatformIO env uses:

```ini
board = esp32dev
```

That generic original-ESP32 target is usually enough for LILYGO TTGO LoRa / Meshtastic boards because this bridge only uses USB serial and BLE HID, not LoRa. If needed, edit `platformio.ini` and switch `board` to the exact TTGO LoRa32 board definition available in your PlatformIO installation.
