#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/hardware/esp32-ble-keyboard-bridge"
PORT="${ESP32_PORT:-}"
PIO_BIN="${PIO_BIN:-pio}"

usage() {
  cat <<'USAGE'
Usage: scripts/flash-esp32-ble-keyboard-bridge.sh [--port /dev/cu.usbserial-XXXX] [--pio pio]

Flashes the Ghost Pepper ESP32 BLE keyboard bridge PlatformIO project.

Options:
  --port PORT     Serial device to upload to. If omitted, tries likely /dev/cu.* devices.
  --pio COMMAND   PlatformIO command to run (default: pio). Use "python3 -m platformio" if needed.
  -h, --help      Show this help.

Note: flashing this firmware replaces Meshtastic on the board. Restore Meshtastic later with the official Meshtastic flasher if desired.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --pio)
      PIO_BIN="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "PlatformIO project not found: $PROJECT_DIR" >&2
  exit 1
fi

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if [[ "$PIO_BIN" == *" "* ]]; then
  : # multi-word command, checked by shell below
elif ! command_exists "$PIO_BIN"; then
  echo "PlatformIO command '$PIO_BIN' not found." >&2
  echo "Install with: python3 -m pip install --user platformio" >&2
  echo "Or pass: --pio 'python3 -m platformio'" >&2
  exit 1
fi

choose_port() {
  local candidates=()
  local pattern
  shopt -s nullglob
  for pattern in \
    /dev/cu.usbserial* \
    /dev/cu.SLAB_USBtoUART* \
    /dev/cu.wchusbserial* \
    /dev/cu.usbmodem*; do
    for device in $pattern; do
      candidates+=("$device")
    done
  done
  shopt -u nullglob

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "" && return 1
  fi

  if [[ ${#candidates[@]} -gt 1 ]]; then
    echo "Multiple likely serial ports found:" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    echo "Using ${candidates[0]}. Pass --port to choose another." >&2
  fi

  echo "${candidates[0]}"
}

if [[ -z "$PORT" ]]; then
  if ! PORT="$(choose_port)" || [[ -z "$PORT" ]]; then
    echo "No likely ESP32 serial port found under /dev/cu.*" >&2
    echo "Plug in the board, install the USB serial driver if needed, or pass --port." >&2
    exit 1
  fi
fi

if [[ ! -e "$PORT" ]]; then
  echo "Serial port does not exist: $PORT" >&2
  exit 1
fi

echo "About to flash Ghost Pepper BLE keyboard bridge to $PORT"
echo "WARNING: this replaces Meshtastic firmware on the ESP32."
echo "If upload hangs, hold BOOT, tap RESET, then release BOOT when connecting."

cd "$PROJECT_DIR"
# shellcheck disable=SC2086
$PIO_BIN run -t upload --upload-port "$PORT"
