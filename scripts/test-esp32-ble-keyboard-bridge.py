#!/usr/bin/env python3
"""Send a Ghost Pepper BLE keyboard bridge test command over USB serial.

This script intentionally uses only the Python standard library so it can run on
macOS without installing pyserial.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import select
import sys
import termios
import time
import tty
from typing import Iterable

DEFAULT_BAUD = 115200
LIKELY_PORT_GLOBS = (
    "/dev/cu.usbserial*",
    "/dev/cu.SLAB_USBtoUART*",
    "/dev/cu.wchusbserial*",
    "/dev/cu.usbmodem*",
)

BAUD_RATES = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
}


def likely_ports() -> list[str]:
    ports: list[str] = []
    for pattern in LIKELY_PORT_GLOBS:
        ports.extend(glob.glob(pattern))
    return sorted(dict.fromkeys(ports))


def choose_port(explicit: str | None) -> str:
    if explicit:
        return explicit

    ports = likely_ports()
    if not ports:
        raise SystemExit(
            "No likely ESP32 serial port found under /dev/cu.*. "
            "Plug in the board or pass --port /dev/cu.<device>."
        )

    if len(ports) > 1:
        print("Multiple likely serial ports found:", file=sys.stderr)
        for port in ports:
            print(f"  {port}", file=sys.stderr)
        print(f"Using {ports[0]}; pass --port to choose another.", file=sys.stderr)

    return ports[0]


def configure_serial(fd: int, baud: int) -> list:
    if baud not in BAUD_RATES:
        raise SystemExit(f"Unsupported baud {baud}; supported: {sorted(BAUD_RATES)}")

    old_attrs = termios.tcgetattr(fd)
    attrs = termios.tcgetattr(fd)
    tty.setraw(fd)

    attrs[0] = attrs[0] & ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK | termios.ISTRIP | termios.INLCR | termios.IGNCR | termios.ICRNL | termios.IXON)
    attrs[1] = attrs[1] & ~termios.OPOST
    attrs[2] = attrs[2] & ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)
    attrs[2] = attrs[2] | termios.CS8 | termios.CLOCAL | termios.CREAD
    attrs[3] = attrs[3] & ~(termios.ECHO | termios.ECHONL | termios.ICANON | termios.ISIG | termios.IEXTEN)
    attrs[4] = BAUD_RATES[baud]
    attrs[5] = BAUD_RATES[baud]
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    return old_attrs


def read_available(fd: int, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    chunks: list[bytes] = []
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        readable, _, _ = select.select([fd], [], [], min(0.25, remaining))
        if not readable:
            continue
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if not chunk:
            continue
        chunks.append(chunk)
    return b"".join(chunks)


def build_payload(args: argparse.Namespace) -> dict[str, object]:
    if args.raw_json:
        try:
            payload = json.loads(args.raw_json)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid --raw-json: {exc}") from exc
        if not isinstance(payload, dict):
            raise SystemExit("--raw-json must decode to a JSON object")
        return payload

    payload: dict[str, object] = {"type": "text", "text": args.text}
    if args.delay_ms is not None:
        payload["delay_ms"] = args.delay_ms
    return payload


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Serial device, e.g. /dev/cu.usbserial-0001")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, help=f"Serial baud (default: {DEFAULT_BAUD})")
    parser.add_argument("--text", default="Hello from Ghost Pepper", help="Text to type via BLE keyboard")
    parser.add_argument("--delay-ms", type=int, help="Optional per-character delay sent to firmware")
    parser.add_argument("--raw-json", help='Send an explicit JSON object, e.g. {"type":"ping"}')
    parser.add_argument("--read-timeout", type=float, default=2.0, help="Seconds to read serial response after sending")
    return parser.parse_args(list(argv))


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    port = choose_port(args.port)
    payload = build_payload(args)
    line = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"

    if not os.path.exists(port):
        raise SystemExit(f"Serial port does not exist: {port}")

    print(f"Opening {port} at {args.baud} baud")
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    old_attrs = configure_serial(fd, args.baud)
    try:
        # Let macOS/USB serial settle, then clear any startup logs already queued.
        time.sleep(0.2)
        _ = read_available(fd, 0.1)
        print(f"Sending: {line.rstrip()}")
        os.write(fd, line.encode("utf-8"))
        response = read_available(fd, args.read_timeout)
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, old_attrs)
        os.close(fd)

    if response:
        print("Response:")
        print(response.decode("utf-8", errors="replace").rstrip())
    else:
        print("No serial response received. If BLE is not paired/connected, check the PlatformIO monitor logs.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
