# Ghost Pepper ESP32 Keyboard Bridge — Agent Handoff

This folder is the handoff packet for finishing the Ghost Pepper “speech-to-text keyboard” setup on a MacBook with an ESP32/LILYGO board connected.

## Goal

Chris wants a spare MacBook to run Ghost Pepper locally, transcribe speech, and send the resulting text to a locked-down/company laptop **without installing any software on the company laptop**.

The target architecture is:

```text
User speaks
  ↓
Spare MacBook runs Ghost Pepper
  ↓ local speech-to-text + cleanup
Ghost Pepper sends final text as newline-delimited JSON over USB serial
  ↓
ESP32/LILYGO board receives text over USB serial
  ↓
ESP32 acts as a Bluetooth LE HID keyboard
  ↓
Company laptop receives normal Bluetooth keyboard keystrokes
```

The company laptop should only see a Bluetooth keyboard named `GhostPepper-Keyboard`.

## Important constraints / why this exists

- A normal macOS app cannot make a MacBook appear as a USB HID keyboard to another laptop.
- macOS Bluetooth HID keyboard emulation from an app is unsupported/fragile.
- The reliable bridge is a small device that is allowed to be a HID peripheral.
- Chris has LILYGO ESP32 LoRa/Meshtastic boards. Those are fine for this use case as long as they are ESP32-based and expose USB serial.
- Flashing this firmware **replaces Meshtastic firmware** on the board. Meshtastic can be restored later using the official Meshtastic flasher.

## What has already been implemented in this repo

### Ghost Pepper app

Files of interest:

- `GhostPepper/Output/TranscriptionOutput.swift`
  - Output modes:
    - `localPaste`
    - `usbSerialKeyboardBridge`
    - `networkKeyboardBridge`
  - Encodes bridge commands as newline-delimited JSON:
    - `{"type":"text","text":"hello"}\n`
  - USB serial transport uses POSIX `open`, `termios`, `write`, `tcdrain`, `close` at 115200 baud.

- `GhostPepper/AppState.swift`
  - Persists output settings:
    - `transcriptionOutputMode`
    - `externalKeyboardBridgeSerialPath`
    - `externalKeyboardBridgeHost`
    - `externalKeyboardBridgePort`
  - Routes final cleaned transcription through `TranscriptionOutputRouter`.

- `GhostPepper/UI/SettingsWindow.swift`
  - Settings → General → Output.
  - User can choose:
    - Local paste
    - USB serial keyboard bridge
    - Network keyboard bridge
  - USB serial mode asks for a serial device path like `/dev/cu.usbserial-0001`.

- `GhostPepperTests/TranscriptionOutputTests.swift`
  - Tests JSON command encoding and routing validation.

### ESP32 firmware and scripts

Files of interest:

- `hardware/esp32-ble-keyboard-bridge/platformio.ini`
  - PlatformIO project for ESP32.

- `hardware/esp32-ble-keyboard-bridge/src/main.cpp`
  - BLE keyboard firmware.
  - Advertises as `GhostPepper-Keyboard`.
  - Reads USB serial at 115200 baud.
  - Parses newline-delimited JSON commands.
  - Types received text via BLE HID.

- `hardware/esp32-ble-keyboard-bridge/README.md`
  - Firmware-specific setup notes.

- `scripts/flash-esp32-ble-keyboard-bridge.sh`
  - macOS helper to flash the ESP32 with PlatformIO.

- `scripts/test-esp32-ble-keyboard-bridge.py`
  - macOS helper to send a test JSON text command over USB serial.

## Expected agent workflow on the MacBook with the ESP32 attached

### 1. Clone the repo

```bash
git clone https://github.com/clawdbot-glitch003/ghost-pepper.git
cd ghost-pepper
```

### 2. Identify the ESP32 serial port

Plug the LILYGO/ESP32 into the MacBook, then run:

```bash
ls /dev/cu.*
```

Likely names include:

- `/dev/cu.usbserial-0001`
- `/dev/cu.SLAB_USBtoUART`
- `/dev/cu.wchusbserial*`
- `/dev/cu.usbmodem*`

If nothing obvious appears:

- Try another USB cable. Many USB-C cables are charge-only.
- Try another USB port/hub.
- Install the board’s USB serial driver if macOS does not expose a port.
- Check System Information → USB.

### 3. Install PlatformIO

Recommended:

```bash
python3 -m pip install --user platformio
```

If that fails on the MacBook, use one of:

```bash
brew install platformio
```

or:

```bash
python3 -m venv .venv-platformio
source .venv-platformio/bin/activate
pip install platformio
```

Confirm:

```bash
pio --version
```

### 4. Flash the ESP32 bridge firmware

Try auto-detect:

```bash
./scripts/flash-esp32-ble-keyboard-bridge.sh
```

If auto-detect finds the wrong port or fails:

```bash
./scripts/flash-esp32-ble-keyboard-bridge.sh --port /dev/cu.usbserial-0001
```

If upload fails with connection/bootloader errors, put the ESP32 into bootloader mode:

1. Hold `BOOT`.
2. Tap `RESET` / `RST`.
3. Release `BOOT` when upload starts or after reset.
4. Rerun the flash command.

Some boards need this every upload; some auto-reset correctly.

### 5. Pair the ESP32 as a Bluetooth keyboard to the company laptop

After flashing, the ESP32 should advertise as:

```text
GhostPepper-Keyboard
```

On the company laptop:

1. Open Bluetooth settings.
2. Pair with `GhostPepper-Keyboard`.
3. Open a text field on the company laptop.

If the company laptop blocks Bluetooth keyboards by policy, this path will not work without IT policy changes. In that case, a USB HID firmware path may be needed on hardware that supports USB device mode.

### 6. Send a serial test from the MacBook

With a text field focused on the company laptop, run this on the Ghost Pepper MacBook:

```bash
./scripts/test-esp32-ble-keyboard-bridge.py --text "hello from ghost pepper"
```

If auto-detect fails:

```bash
./scripts/test-esp32-ble-keyboard-bridge.py --port /dev/cu.usbserial-0001 --text "hello from ghost pepper"
```

Expected result: the company laptop types the text into the focused field.

### 7. Build/run Ghost Pepper on the spare MacBook

Open the Xcode project:

```bash
open GhostPepper.xcodeproj
```

Build/run the `GhostPepper` app in Xcode.

Grant required permissions on the spare MacBook:

- Microphone
- Accessibility
- Input Monitoring if prompted by the hotkey monitor

### 8. Configure Ghost Pepper output

In Ghost Pepper Settings:

1. Go to General → Output.
2. Select `USB serial keyboard bridge`.
3. Enter the ESP32 serial path, e.g.:

```text
/dev/cu.usbserial-0001
```

Then use Ghost Pepper normally. Final cleaned dictation text should be sent to the ESP32 over USB serial, and the ESP32 should type it over BLE into the company laptop.

## Wire protocol

Ghost Pepper sends one UTF-8 JSON object per line over serial at 115200 baud.

Primary command:

```json
{"type":"text","text":"hello world"}
```

With optional per-character delay:

```json
{"type":"text","text":"hello world","delay_ms":10}
```

Ping command supported by firmware:

```json
{"type":"ping"}
```

The firmware replies/logs on serial for debugging, but Ghost Pepper currently treats serial as fire-and-forget.

## Known limitations

- The BLE firmware currently behaves like a US keyboard layout.
- Unsupported non-ASCII characters may be skipped or normalized.
- Smart punctuation is normalized where practical.
- Emoji are not expected to type correctly.
- The company laptop must allow Bluetooth keyboards.
- The target laptop must have a focused text field; the bridge cannot know target app/caret state.
- Some apps drop characters if typed too fast; adjust firmware delay if needed.
- Existing Meshtastic firmware is replaced by this bridge firmware.

## Troubleshooting checklist

### No serial port appears

- Use a known data-capable USB cable.
- Try another USB-C adapter/hub.
- Install CP210x/CH340 driver if the board needs it.
- Check `ls /dev/cu.*` before and after plugging in the board.

### Flash upload fails

- Put the ESP32 into bootloader mode with `BOOT` + `RESET`.
- Specify the port explicitly with `--port`.
- Close serial monitors or other apps using the port.
- Try lower upload speed by editing `upload_speed` in `hardware/esp32-ble-keyboard-bridge/platformio.ini`.

### BLE keyboard does not show up

- Reset the ESP32 after flashing.
- Remove old `GhostPepper-Keyboard` pairing from the company laptop and rescan.
- Check serial logs with PlatformIO monitor:

```bash
cd hardware/esp32-ble-keyboard-bridge
pio device monitor -b 115200 --port /dev/cu.usbserial-0001
```

### Test script sends but nothing types

- Confirm company laptop is paired to `GhostPepper-Keyboard`.
- Confirm a text field is focused.
- Check serial monitor logs.
- Send a simpler ASCII-only test.
- Increase typing delay in the JSON command or firmware.

### Ghost Pepper does not send text

- Verify Settings → Output is `USB serial keyboard bridge`.
- Verify serial path exactly matches `/dev/cu.*` path.
- Try the standalone test script first; fix firmware/serial/BLE before debugging the app.
- In Xcode console, watch for output delivery errors.

## Recommended next implementation tasks for the agent

1. **Get firmware flashed and BLE paired.**
   - Do not start by modifying app code.
   - First prove the ESP32 can type into the company laptop using the test script.

2. **Run Ghost Pepper from Xcode on the spare MacBook.**
   - Grant permissions.
   - Confirm local paste mode still works.

3. **Switch to USB serial keyboard bridge mode.**
   - Enter the serial path.
   - Dictate a short phrase.
   - Confirm text appears on the company laptop.

4. **If characters are missed, tune firmware typing delay.**
   - Start by increasing default delay in firmware.
   - Reflash and retest.

5. **If non-ASCII matters, improve keyboard mapping.**
   - Current firmware is intentionally a simple first pass.
   - Add better mappings only after the ASCII path is working.

6. **If Bluetooth is blocked by corporate policy, stop and report.**
   - Do not waste time debugging Ghost Pepper if the company laptop will not pair with the ESP32 keyboard.

## Success definition

The handoff is successful when:

1. ESP32 is flashed with bridge firmware.
2. Company laptop pairs with `GhostPepper-Keyboard`.
3. `scripts/test-esp32-ble-keyboard-bridge.py --text "hello"` causes text to appear on the company laptop.
4. Ghost Pepper running on the spare MacBook in USB serial keyboard bridge mode transcribes speech and types the final text into the company laptop.

## Commit/PR context

This work was merged into the fork:

- Repo: `https://github.com/clawdbot-glitch003/ghost-pepper`
- Merged PR: `https://github.com/clawdbot-glitch003/ghost-pepper/pull/1`
- Main branch includes:
  - Ghost Pepper output routing scaffold
  - ESP32 BLE keyboard bridge firmware
  - USB serial app transport
  - Flash/test scripts

