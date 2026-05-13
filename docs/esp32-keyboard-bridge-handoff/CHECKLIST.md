# Agent Task Checklist

Use this checklist to drive the rest of the work. Mark each item complete in your own notes as you go.

## Hardware / firmware

- [ ] Confirm ESP32 board appears in `ls /dev/cu.*`.
- [ ] Install PlatformIO (`pio --version`).
- [ ] Flash firmware with `scripts/flash-esp32-ble-keyboard-bridge.sh`.
- [ ] If flashing fails, retry with explicit `--port` and ESP32 bootloader mode.
- [ ] Pair company laptop to `GhostPepper-Keyboard`.
- [ ] Run serial test script and confirm text types into company laptop.

## Ghost Pepper app

- [ ] Open `GhostPepper.xcodeproj` in Xcode.
- [ ] Build app.
- [ ] Fix any compile issues from the new output/serial code if Xcode reports them.
- [ ] Run app on spare MacBook.
- [ ] Grant required macOS permissions.
- [ ] Verify local paste mode still works.
- [ ] Switch Settings → General → Output to `USB serial keyboard bridge`.
- [ ] Enter ESP32 serial path.
- [ ] Dictate and confirm text appears on company laptop.

## If things fail

- [ ] If no serial port: cable/driver/adapter issue.
- [ ] If no BLE pairing: reset ESP32 and remove stale pairings.
- [ ] If serial test works but Ghost Pepper does not: inspect Ghost Pepper output mode/path and Xcode logs.
- [ ] If Ghost Pepper works but drops chars: increase firmware typing delay.
- [ ] If company laptop blocks pairing: report that Bluetooth HID is blocked by policy.

## Done criteria

- [ ] Spoken phrase on spare MacBook appears as typed text on company laptop.
- [ ] Handoff notes updated with any board-specific port/driver/flashing quirks discovered.

