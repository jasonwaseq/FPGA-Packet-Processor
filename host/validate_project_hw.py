from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass

from .packet import Packet
from .protocol import Action, MessageType, PacketResult, ResultFlag, TransportFrame
from .serial_link import SerialLink
from .validate_hw import _select_auto_port


@dataclass
class Check:
    name: str
    passed: bool
    details: str = ""


def _send_expect_result(link: SerialLink, packet: Packet, seq: int) -> PacketResult:
    link.send_frame(TransportFrame(msg_type=int(MessageType.DATA_PACKET), seq=seq & 0xFF, payload=packet.encode()))
    frame = link.recv_frame()
    if frame.msg_type != MessageType.PKT_RESULT:
        raise RuntimeError(f"expected PKT_RESULT, got 0x{frame.msg_type:02X}")
    if frame.seq != (seq & 0xFF):
        raise RuntimeError(f"unexpected seq: got {frame.seq}, expected {seq & 0xFF}")
    return PacketResult.decode(frame.payload)


def run_validation(port: str, baud: int, timeout: float, benchmark_count: int) -> tuple[bool, list[Check]]:
    _ = benchmark_count
    checks: list[Check] = []
    link = SerialLink(port=port, baudrate=baud, timeout=timeout)
    try:
        pkt_accept = Packet(
            protocol=0x11,
            flags=0x01,
            ttl=32,
            src_addr=0x1001,
            dst_addr=0x2001,
            src_port=0x1234,
            dst_port=0x2222,
            packet_id=0x1000,
            payload=b"",
        )
        result_accept = _send_expect_result(link, pkt_accept, seq=0x10)
        accept_ok = (
            result_accept.action == int(Action.ACCEPT)
            and bool(result_accept.result_flags & int(ResultFlag.PARSE_OK))
            and bool(result_accept.result_flags & int(ResultFlag.CHECKSUM_OK))
            and bool(result_accept.result_flags & int(ResultFlag.DEFAULT_ACTION))
            and result_accept.packet_id == pkt_accept.packet_id
        )
        checks.append(Check("Default accept path", accept_ok))
        if not accept_ok:
            return False, checks

        pkt_drop = Packet(
            protocol=0x11,
            flags=0x00,
            ttl=31,
            src_addr=0x1002,
            dst_addr=0x2002,
            src_port=0x1235,
            dst_port=0x9001,
            packet_id=0x1001,
            payload=b"",
        )
        result_drop = _send_expect_result(link, pkt_drop, seq=0x11)
        drop_ok = (
            result_drop.action == int(Action.DROP)
            and result_drop.rule_id == 0
            and bool(result_drop.result_flags & int(ResultFlag.MATCHED))
            and bool(result_drop.result_flags & int(ResultFlag.DROPPED))
        )
        checks.append(Check("Fixed drop rule", drop_ok))
        if not drop_ok:
            return False, checks

        pkt_count = Packet(
            protocol=0x22,
            flags=0x00,
            ttl=30,
            src_addr=0x3333,
            dst_addr=0x2003,
            src_port=0x1236,
            dst_port=0x2345,
            packet_id=0x1002,
            payload=b"",
        )
        result_count = _send_expect_result(link, pkt_count, seq=0x12)
        count_ok = (
            result_count.action == int(Action.COUNT_ONLY)
            and result_count.rule_id == 1
            and bool(result_count.result_flags & int(ResultFlag.MATCHED))
        )
        checks.append(Check("Fixed count-only rule", count_ok))
        if not count_ok:
            return False, checks

        pkt_rewrite = Packet(
            protocol=0x11,
            flags=0x00,
            ttl=15,
            src_addr=0x1111,
            dst_addr=0x2222,
            src_port=0x1237,
            dst_port=0x3456,
            packet_id=0x1003,
            payload=b"",
        )
        result_rewrite = _send_expect_result(link, pkt_rewrite, seq=0x13)
        rewrite_ok = (
            result_rewrite.action == int(Action.REWRITE)
            and result_rewrite.rule_id == 2
            and result_rewrite.error_code == 0
            and bool(result_rewrite.result_flags & int(ResultFlag.REWRITTEN))
            and result_rewrite.dst_addr_final == 0xCAFE
            and result_rewrite.dst_port_final == 0xBEEF
        )
        checks.append(Check("Fixed rewrite rule", rewrite_ok))
        return rewrite_ok, checks
    finally:
        link.close()


def _print_summary(checks: list[Check]) -> None:
    print("\nFull hardware validation summary:")
    for c in checks:
        state = "PASS" if c.passed else "FAIL"
        suffix = f" ({c.details})" if c.details else ""
        print(f"- {state}: {c.name}{suffix}")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "UP5K-lt hardware validation: framed data transport, parser/checksum, "
            "fixed classification actions, and rewrite-result metadata."
        )
    )
    parser.add_argument("--port", default="auto", help="Serial port (e.g. /dev/ttyUSB1 or COM7), or 'auto'.")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate (default: 115200).")
    parser.add_argument("--timeout", type=float, default=0.5, help="Serial timeout in seconds (default: 0.5).")
    parser.add_argument(
        "--benchmark-count",
        type=int,
        default=0,
        help="Reserved for compatibility with older flows; ignored by UP5K-lt validator.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    port = args.port
    if port == "auto":
        port = _select_auto_port()
        if port is None:
            print("FAIL: no serial ports found for --port auto.", file=sys.stderr)
            return 2
        print(f"INFO: auto-selected serial port {port}")
    try:
        ok, checks = run_validation(
            port=port,
            baud=args.baud,
            timeout=args.timeout,
            benchmark_count=args.benchmark_count,
        )
    except Exception as exc:
        print(f"FAIL: validation aborted: {exc}", file=sys.stderr)
        return 1

    _print_summary(checks)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
