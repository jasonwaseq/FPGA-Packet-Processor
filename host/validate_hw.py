from __future__ import annotations

import argparse
import collections
import random
import sys
import time

from .client import PacketProcessorClient


def _import_serial():
    try:
        import serial  # type: ignore
    except ImportError:
        print("FAIL: pyserial is not installed.", file=sys.stderr)
        return None
    return serial


def _detect_serial_ports() -> list[dict[str, str]]:
    serial = _import_serial()
    if serial is None:
        return []

    try:
        from serial.tools import list_ports  # type: ignore
    except Exception:
        return []

    ports: list[dict[str, str]] = []
    for item in list_ports.comports():
        desc = item.description if item.description and item.description != "n/a" else ""
        ports.append(
            {
                "device": item.device or "",
                "description": desc,
                "hwid": getattr(item, "hwid", "") or "",
                "interface": getattr(item, "interface", "") or "",
                "location": getattr(item, "location", "") or "",
            }
        )
    return ports


def _score_port_for_uart(port: dict[str, str]) -> int:
    score = 0
    dev = port["device"].lower()
    desc = port["description"].lower()
    iface = port["interface"].lower()
    hwid = port["hwid"].lower()

    if "icebreaker" in desc:
        score += 10
    if "ftdi" in desc or "ftdi" in hwid:
        score += 6
    if "interface b" in iface or iface == "b":
        score += 8
    if dev.endswith("1"):
        score += 2
    if dev.endswith("0"):
        score += 1
    return score


def _select_auto_port() -> str | None:
    ports = _detect_serial_ports()
    if not ports:
        return None
    best = max(ports, key=_score_port_for_uart)
    return best["device"] if best["device"] else None


def _print_serial_ports() -> int:
    ports = _detect_serial_ports()
    if not ports:
        print("No serial ports detected.")
        return 1

    print("Detected serial ports:")
    for p in ports:
        parts = []
        if p["description"]:
            parts.append(p["description"])
        if p["interface"]:
            parts.append(f"if={p['interface']}")
        if p["location"]:
            parts.append(f"loc={p['location']}")
        if p["hwid"]:
            parts.append(p["hwid"])
        suffix = f" ({', '.join(parts)})" if parts else ""
        print(f"- {p['device']}{suffix}")
    return 0


def _print_port_open_help(port: str, exc: Exception) -> None:
    print(f"FAIL: could not open serial port {port!r}: {exc}")
    ports = _detect_serial_ports()
    if ports:
        print("Detected serial ports:")
        for p in ports:
            parts = []
            if p["description"]:
                parts.append(p["description"])
            if p["interface"]:
                parts.append(f"if={p['interface']}")
            if p["location"]:
                parts.append(f"loc={p['location']}")
            suffix = f" ({', '.join(parts)})" if parts else ""
            print(f"- {p['device']}{suffix}")
    else:
        print("No serial ports detected by pyserial.")
    print("Tip: run `python3 -m host.validate_hw --list-ports` and use one of the reported devices.")
    print("Tip: in WSL, the board is often `/dev/ttyACM0` or `/dev/ttyUSB0` (or `/dev/ttyS*` for Windows COM mapping).")


def _read_exact(ser: object, size: int, timeout_s: float) -> bytes:
    deadline = time.monotonic() + timeout_s
    out = bytearray()
    while len(out) < size:
        chunk = ser.read(size - len(out))
        if chunk:
            out.extend(chunk)
            continue
        if time.monotonic() >= deadline:
            break
    return bytes(out)


def _first_mismatch(expected: bytes, actual: bytes) -> tuple[int, int, int] | None:
    limit = min(len(expected), len(actual))
    for idx in range(limit):
        if expected[idx] != actual[idx]:
            return idx, expected[idx], actual[idx]
    if len(expected) != len(actual):
        return limit, -1 if limit >= len(expected) else expected[limit], -1 if limit >= len(actual) else actual[limit]
    return None


def validate_echo(
    port: str,
    baud: int,
    timeout: float,
    rounds: int,
    payload_bytes: int,
    seed: int,
    quiet: bool = False,
) -> bool:
    serial = _import_serial()
    if serial is None:
        return False

    rng = random.Random(seed)
    start = time.monotonic()
    total_bytes = 0

    try:
        with serial.Serial(port=port, baudrate=baud, timeout=timeout) as ser:
            ser.reset_input_buffer()
            ser.reset_output_buffer()

            for i in range(rounds):
                payload = bytes(rng.getrandbits(8) for _ in range(payload_bytes))
                ser.write(payload)
                ser.flush()

                # UART is 10 bits/byte; add safety margin for USB/host scheduling jitter.
                dynamic_timeout = timeout + (payload_bytes * 10.0 / max(baud, 1)) + 0.25
                echoed = _read_exact(ser, payload_bytes, dynamic_timeout)
                total_bytes += payload_bytes

                if echoed != payload:
                    mismatch = _first_mismatch(payload, echoed)
                    if mismatch is None:
                        if not quiet:
                            print(f"FAIL: echo length mismatch on round {i + 1}: expected {len(payload)}, got {len(echoed)}")
                    else:
                        idx, exp_b, got_b = mismatch
                        if exp_b < 0 or got_b < 0:
                            if not quiet:
                                print(
                                    f"FAIL: echo truncated/extended on round {i + 1} at byte {idx}: "
                                    f"expected_len={len(payload)} got_len={len(echoed)}"
                                )
                        else:
                            if not quiet:
                                print(
                                    f"FAIL: echo mismatch on round {i + 1} at byte {idx}: "
                                    f"expected=0x{exp_b:02X} got=0x{got_b:02X}"
                                )
                    if len(echoed) == 0:
                        if not quiet:
                            print("Hint: no UART response. Possible causes: FPGA not configured/running, wrong serial port, or wrong baud.")
                    return False
    except Exception as exc:  # pragma: no cover - hardware path
        if not quiet:
            _print_port_open_help(port, exc)
        return False

    elapsed = max(time.monotonic() - start, 1e-9)
    kbps = (total_bytes * 8.0 / elapsed) / 1000.0
    print(
        f"PASS: echo validation succeeded ({rounds} rounds x {payload_bytes} bytes, "
        f"{total_bytes} bytes total, {kbps:.1f} kbps effective)."
    )
    return True


def validate_echo_scan(baud: int, timeout: float, rounds: int, payload_bytes: int, seed: int) -> bool:
    ports = _detect_serial_ports()
    if not ports:
        print("FAIL: no serial ports detected.")
        return False

    ordered = sorted(ports, key=_score_port_for_uart, reverse=True)
    print(f"INFO: scanning {len(ordered)} serial port(s) for echo at {baud} baud...")
    for p in ordered:
        dev = p["device"]
        desc = p["description"]
        label = f"{dev} ({desc})" if desc else dev
        print(f"INFO: trying {label}")
        if validate_echo(
            port=dev,
            baud=baud,
            timeout=timeout,
            rounds=max(4, min(rounds, 8)),
            payload_bytes=payload_bytes,
            seed=seed,
            quiet=True,
        ):
            print(f"PASS: echo validated on {dev}")
            return True
    print("FAIL: no detected serial port responded to echo traffic.")
    return False


def validate_rx_pattern(
    port: str,
    baud: int,
    timeout: float,
    pattern_byte: int,
    min_bytes: int,
    scan_seconds: float,
) -> bool:
    serial = _import_serial()
    if serial is None:
        return False

    pattern = pattern_byte & 0xFF
    total_timeout = max(timeout, scan_seconds)
    payload = bytearray()

    try:
        with serial.Serial(port=port, baudrate=baud, timeout=timeout) as ser:
            ser.reset_input_buffer()
            ser.reset_output_buffer()

            deadline = time.monotonic() + total_timeout
            while time.monotonic() < deadline and len(payload) < min_bytes:
                chunk = ser.read(max(64, min_bytes - len(payload)))
                if chunk:
                    payload.extend(chunk)
    except Exception as exc:  # pragma: no cover - hardware path
        _print_port_open_help(port, exc)
        return False

    if len(payload) == 0:
        print("FAIL: no UART bytes received while waiting for RX pattern traffic.")
        print("Hint: FPGA TX may not be routed/configured, or selected baud is incorrect.")
        return False

    if len(payload) < min_bytes:
        print(f"FAIL: received only {len(payload)} byte(s), expected at least {min_bytes} for RX pattern validation.")
        print("Hint: increase --scan-seconds, reduce --min-bytes, or check UART baud/pin mapping.")
        return False

    mismatch = sum(1 for b in payload if b != pattern)
    allowed_mismatch = max(1, len(payload) // 20)  # allow up to 5% noise on startup.
    if mismatch > allowed_mismatch:
        sample = " ".join(f"{b:02X}" for b in payload[:16])
        top_values = collections.Counter(payload).most_common(4)
        top_values_str = ", ".join(f"0x{k:02X}:{v}" for k, v in top_values)
        print(
            f"FAIL: RX pattern mismatch. expected mostly 0x{pattern:02X}, "
            f"received {mismatch}/{len(payload)} mismatching bytes."
        )
        print(f"INFO: first 16 byte(s): {sample}")
        print(f"INFO: top byte histogram: {top_values_str}")
        print("Hint: this usually indicates wrong baud or the wrong UART pin mapping.")
        return False

    print(
        f"PASS: RX pattern validation succeeded "
        f"({len(payload)} byte(s) read, pattern=0x{pattern:02X}, mismatches={mismatch})."
    )
    return True


def validate_packet_processor(port: str, baud: int, timeout: float) -> bool:
    client = None
    try:
        client = PacketProcessorClient(port=port, baudrate=baud, timeout=timeout)
        ping = client.ping()
        info = client.get_info()
    except Exception as exc:  # pragma: no cover - hardware path
        _print_port_open_help(port, exc)
        print(f"FAIL: packet-processor protocol validation failed: {exc}")
        return False
    finally:
        if client is not None:
            client.close()

    print(
        "PASS: packet-processor protocol validation succeeded "
        f"(ping={ping!r}, proto={info.protocol_version}, rules={info.rule_count}, "
        f"max_packet={info.max_packet_bytes}, max_frame={info.max_frame_payload})."
    )
    return True


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Hardware validation for FPGA UART builds.")
    parser.add_argument("--port", help="Serial port (e.g. COM7 or /dev/ttyUSB1). Use 'auto' to auto-select.")
    parser.add_argument("--list-ports", action="store_true", help="List detected serial ports and exit.")
    parser.add_argument("--baud", type=int, default=1_500_000, help="UART baud rate (default: 1500000).")
    parser.add_argument("--timeout", type=float, default=0.5, help="Read timeout in seconds (default: 0.5).")
    parser.add_argument(
        "--mode",
        choices=("auto", "echo", "echo-scan", "packet", "rx-pattern"),
        default="auto",
        help=(
            "Validation mode: raw UART echo, scan all ports for echo, packet protocol, "
            "RX pattern stream check, or auto (echo then packet)."
        ),
    )
    parser.add_argument("--rounds", type=int, default=32, help="Echo rounds (default: 32).")
    parser.add_argument("--payload-bytes", type=int, default=64, help="Bytes per echo round (default: 64).")
    parser.add_argument("--seed", type=int, default=12345, help="RNG seed for echo payload generation.")
    parser.add_argument(
        "--pattern-byte",
        type=lambda x: int(x, 0),
        default=0x55,
        help="Expected RX pattern byte for rx-pattern mode (default: 0x55).",
    )
    parser.add_argument(
        "--min-bytes",
        type=int,
        default=128,
        help="Minimum bytes required for rx-pattern mode (default: 128).",
    )
    parser.add_argument(
        "--scan-seconds",
        type=float,
        default=1.0,
        help="Capture window for rx-pattern mode (default: 1.0s).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)

    if args.list_ports:
        return _print_serial_ports()

    if not args.port:
        print("FAIL: --port is required unless --list-ports is used.", file=sys.stderr)
        return 2

    if args.port == "auto":
        auto_port = _select_auto_port()
        if auto_port is None:
            print("FAIL: no serial ports found for --port auto.")
            return 2
        print(f"INFO: auto-selected serial port {auto_port}")
        args.port = auto_port

    if args.rounds <= 0 or args.payload_bytes <= 0 or args.min_bytes <= 0 or args.scan_seconds <= 0:
        print("FAIL: --rounds, --payload-bytes, --min-bytes, and --scan-seconds must be positive.", file=sys.stderr)
        return 2

    if args.pattern_byte < 0 or args.pattern_byte > 255:
        print("FAIL: --pattern-byte must be in [0, 255].", file=sys.stderr)
        return 2

    if args.mode == "echo":
        return 0 if validate_echo(args.port, args.baud, args.timeout, args.rounds, args.payload_bytes, args.seed) else 1

    if args.mode == "echo-scan":
        return 0 if validate_echo_scan(args.baud, args.timeout, args.rounds, args.payload_bytes, args.seed) else 1

    if args.mode == "rx-pattern":
        return (
            0
            if validate_rx_pattern(
                port=args.port,
                baud=args.baud,
                timeout=args.timeout,
                pattern_byte=args.pattern_byte,
                min_bytes=args.min_bytes,
                scan_seconds=args.scan_seconds,
            )
            else 1
        )

    if args.mode == "packet":
        return 0 if validate_packet_processor(args.port, args.baud, args.timeout) else 1

    # auto mode: prefer echo (bring-up bitstream), then packet protocol (full processor bitstream).
    if validate_echo(args.port, args.baud, args.timeout, max(4, min(args.rounds, 8)), args.payload_bytes, args.seed):
        return 0

    print("INFO: echo mode failed; trying packet-processor protocol validation.")
    return 0 if validate_packet_processor(args.port, args.baud, args.timeout) else 1


if __name__ == "__main__":
    raise SystemExit(main())
