# Quick Start for the Handoff Agent

Use this when you are physically on the spare MacBook with the ESP32/LILYGO board connected.

## 0. What you are building

The ESP32 plugs into the Ghost Pepper MacBook over USB serial and pairs to the company laptop as a Bluetooth keyboard.

```text
Ghost Pepper MacBook --USB serial--> ESP32 --BLE keyboard--> company laptop
```

The ESP32 must be flashed with this repo’s bridge firmware. This replaces Meshtastic firmware.

## 1. Clone

```bash
git clone https://github.com/clawdbot-glitch003/ghost-pepper.git
cd ghost-pepper
```

## 2. Find ESP32 port

```bash
ls /dev/cu.*
```

Likely paths:

```text
/dev/cu.usbserial-0001
/dev/cu.SLAB_USBtoUART
/dev/cu.wchusbserial...
```

## 3. Install PlatformIO

```bash
python3 -m pip install --user platformio
```

If that fails:

```bash
brew install platformio
```

## 4. Flash ESP32

```bash
./scripts/flash-esp32-ble-keyboard-bridge.sh
```

Or explicit port:

```bash
./scripts/flash-esp32-ble-keyboard-bridge.sh --port /dev/cu.usbserial-0001
```

If upload fails: hold `BOOT`, tap `RESET`, release `BOOT`, rerun flash.

## 5. Pair company laptop

Pair Bluetooth device:

```text
GhostPepper-Keyboard
```

Open a text field on the company laptop.

## 6. Test typing through ESP32

```bash
./scripts/test-esp32-ble-keyboard-bridge.py --text "hello from ghost pepper"
```

If needed:

```bash
./scripts/test-esp32-ble-keyboard-bridge.py --port /dev/cu.usbserial-0001 --text "hello from ghost pepper"
```

Do not debug Ghost Pepper until this works.

## 7. Run Ghost Pepper

```bash
open GhostPepper.xcodeproj
```

Build/run in Xcode. Grant microphone/accessibility/input-monitoring permissions.

Settings → General → Output:

- Select `USB serial keyboard bridge`
- Serial path: your ESP32 `/dev/cu.*` path

Dictate. Text should appear on the company laptop.

