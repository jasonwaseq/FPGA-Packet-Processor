from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from .packet import Packet
from .protocol import Command, MessageType, PacketResult, TransportFrame, parse_counter_block
from .rules import Rule
from .serial_link import SerialLink


@dataclass
class DeviceInfo:
    protocol_version: int
    rule_count: int
    max_packet_bytes: int
    max_frame_payload: int


class PacketProcessorClient:
    def __init__(self, port: str, baudrate: int = 1_500_000, timeout: float = 0.5) -> None:
        self.link = SerialLink(port=port, baudrate=baudrate, timeout=timeout)
        self._seq = 0

    def close(self) -> None:
        self.link.close()

    def _next_seq(self) -> int:
        seq = self._seq & 0xFF
        self._seq = (self._seq + 1) & 0xFF
        return seq

    def _send_cmd(self, cmd: Command, payload: bytes = b"") -> bytes:
        seq = self._next_seq()
        frame = TransportFrame(msg_type=MessageType.CMD_REQ, seq=seq, payload=bytes([cmd]) + payload)
        self.link.send_frame(frame)
        resp = self.link.recv_frame()
        if resp.msg_type != MessageType.CMD_RESP or resp.seq != seq:
            raise RuntimeError(f"unexpected response type/seq: {resp.msg_type:#x}/{resp.seq}")
        if not resp.payload or resp.payload[0] != cmd:
            raise RuntimeError("response opcode mismatch")
        if resp.payload[1] != 0:
            raise RuntimeError(f"device returned error status {resp.payload[1]}")
        return resp.payload[2:]

    def ping(self) -> str:
        return self._send_cmd(Command.PING).decode("ascii")

    def get_info(self) -> DeviceInfo:
        payload = self._send_cmd(Command.GET_INFO)
        return DeviceInfo(
            protocol_version=payload[0],
            rule_count=payload[1],
            max_packet_bytes=payload[2],
            max_frame_payload=payload[3],
        )

    def set_mode(self, mode: int) -> None:
        self._send_cmd(Command.SET_MODE, bytes([mode]))

    def get_mode(self) -> tuple[int, bool, int]:
        payload = self._send_cmd(Command.GET_MODE)
        return payload[0], bool(payload[1] & 0x1), payload[2]

    def set_verbose(self, enabled: bool) -> None:
        self._send_cmd(Command.SET_VERBOSE, bytes([1 if enabled else 0]))

    def set_default_action(self, action: int) -> None:
        self._send_cmd(Command.SET_DEFAULT_ACTION, bytes([action]))

    def write_rule(self, index: int, rule: Rule) -> None:
        self._send_cmd(Command.WRITE_RULE, bytes([index & 0xFF]) + rule.encode())

    def clear_rule(self, index: int) -> None:
        self._send_cmd(Command.CLEAR_RULE, bytes([index & 0xFF]))

    def clear_all_rules(self) -> None:
        self._send_cmd(Command.CLEAR_ALL_RULES)

    def read_rule(self, index: int) -> Rule:
        payload = self._send_cmd(Command.READ_RULE, bytes([index & 0xFF]))
        return Rule.decode(payload[1:25])

    def read_counters(self) -> dict[str, int]:
        payload = self._send_cmd(Command.READ_COUNTERS)
        return parse_counter_block(payload)

    def read_last_result(self) -> PacketResult:
        return PacketResult.decode(self._send_cmd(Command.READ_LAST_RESULT))

    def clear_counters(self) -> None:
        self._send_cmd(Command.CLEAR_COUNTERS)

    def soft_reset(self) -> None:
        self._send_cmd(Command.SOFT_RESET)

    def send_packet(self, packet: Packet) -> TransportFrame:
        seq = self._next_seq()
        self.link.send_frame(TransportFrame(msg_type=MessageType.DATA_PACKET, seq=seq, payload=packet.encode()))
        return self.link.recv_frame()

