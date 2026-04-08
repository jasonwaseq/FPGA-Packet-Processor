from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from .validate_hw import (
    _select_auto_port,
    validate_echo,
    validate_packet_processor,
    validate_rx_pattern,
)


ROOT = Path(__file__).resolve().parents[1]


@dataclass
class StepResult:
    name: str
    passed: bool
    details: str = ""


def _run_make(target: str) -> bool:
    cmd = ["make", target]
    print(f"INFO: running {' '.join(cmd)}")
    completed = subprocess.run(cmd, cwd=ROOT)
    return completed.returncode == 0


def _resolve_port(port_arg: str) -> str | None:
    if port_arg != "auto":
        return port_arg
    return _select_auto_port()


def _print_summary(results: list[StepResult]) -> None:
    print("\nValidation summary:")
    for result in results:
        status = "PASS" if result.passed else "FAIL"
        suffix = f" ({result.details})" if result.details else ""
        print(f"- {status}: {result.name}{suffix}")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="End-to-end FPGA hardware validation flow.")
    parser.add_argument("--port", default="auto", help="Serial port device, or 'auto' (default).")
    parser.add_argument("--bringup-baud", type=int, default=115200, help="Bring-up UART baud (default: 115200).")
    parser.add_argument("--packet-baud", type=int, default=1_500_000, help="Packet-processor UART baud (default: 1500000).")
    parser.add_argument("--timeout", type=float, default=0.5, help="Serial timeout in seconds (default: 0.5).")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail if TX pattern check fails (otherwise it is reported as warning and flow continues).",
    )
    parser.add_argument(
        "--require-packet",
        action="store_true",
        help="Fail if packet-processor protocol check fails (default: best-effort info only).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    results: list[StepResult] = []

    if not _run_make("flash_bringup"):
        results.append(StepResult("Program bring-up image", False))
        _print_summary(results)
        return 1
    results.append(StepResult("Program bring-up image", True))

    port = _resolve_port(args.port)
    if port is None:
        results.append(StepResult("Auto-select serial port", False, "no serial ports detected"))
        _print_summary(results)
        return 1
    results.append(StepResult("Serial port selection", True, port))

    echo_ok = validate_echo(
        port=port,
        baud=args.bringup_baud,
        timeout=args.timeout,
        rounds=8,
        payload_bytes=64,
        seed=12345,
    )
    results.append(StepResult("Bring-up echo", echo_ok, f"baud={args.bringup_baud}"))
    if not echo_ok:
        _print_summary(results)
        return 1

    tx_ok = False
    if _run_make("flash_tx_test"):
        tx_ok = validate_rx_pattern(
            port=port,
            baud=args.bringup_baud,
            timeout=args.timeout,
            pattern_byte=0x55,
            min_bytes=128,
            scan_seconds=1.0,
        )
    if not tx_ok and _run_make("flash_tx_test_alt"):
        tx_ok = validate_rx_pattern(
            port=port,
            baud=args.bringup_baud,
            timeout=args.timeout,
            pattern_byte=0x55,
            min_bytes=128,
            scan_seconds=1.0,
        )

    if tx_ok:
        results.append(StepResult("TX pattern stream", True))
    else:
        details = "not detected on default or alternate mapping"
        results.append(StepResult("TX pattern stream", False, details))
        if args.strict:
            _print_summary(results)
            return 1

    packet_ok = validate_packet_processor(
        port=port,
        baud=args.packet_baud,
        timeout=args.timeout,
    )
    results.append(StepResult("Packet-processor protocol", packet_ok, f"baud={args.packet_baud}"))
    if args.require_packet and not packet_ok:
        _print_summary(results)
        return 1

    _print_summary(results)
    required_ok = all(r.passed for r in results if r.name in {"Program bring-up image", "Serial port selection", "Bring-up echo"})
    if args.strict:
        required_ok = required_ok and any(r.name == "TX pattern stream" and r.passed for r in results)
    if args.require_packet:
        required_ok = required_ok and any(r.name == "Packet-processor protocol" and r.passed for r in results)
    return 0 if required_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
