from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable, Iterator, Optional


FRAME_FLAG = 0x7E
FRAME_ESCAPE = 0x7D
PROTOCOL_VERSION = 0x01
MAX_FRAME_PAYLOAD = 252
MAX_PACKET_BYTES = 240
RESULT_BYTES = 20


class MessageType(IntEnum):
    CMD_REQ = 0x01
    CMD_RESP = 0x02
    DATA_PACKET = 0x10
    PKT_RESULT = 0x11
    PKT_FORWARD = 0x12
    EVENT = 0x13


class Mode(IntEnum):
    INSPECT = 0
    INLINE = 1
    BENCHMARK = 2


class Action(IntEnum):
    DROP = 0
    ACCEPT = 1
    COUNT_ONLY = 2
    REWRITE = 3


class Status(IntEnum):
    OK = 0
    ERR_BAD_OPCODE = 1
    ERR_BAD_LEN = 2
    ERR_BAD_PARAM = 3
    ERR_BUSY = 4
    ERR_RULE_INDEX = 5
    ERR_MODE = 6
    ERR_INTERNAL = 7


class Command(IntEnum):
    PING = 0x00
    GET_INFO = 0x01
    SOFT_RESET = 0x02
    CLEAR_COUNTERS = 0x03
    SET_MODE = 0x04
    GET_MODE = 0x05
    WRITE_RULE = 0x10
    CLEAR_RULE = 0x11
    CLEAR_ALL_RULES = 0x12
    READ_RULE = 0x13
    SET_DEFAULT_ACTION = 0x14
    SET_VERBOSE = 0x15
    READ_COUNTERS = 0x20
    READ_LAST_RESULT = 0x21
    READ_STATUS = 0x22


class ResultFlag(IntEnum):
    PARSE_OK = 0x01
    MATCHED = 0x02
    DROPPED = 0x04
    REWRITTEN = 0x08
    CHECKSUM_OK = 0x10
    DEFAULT_ACTION = 0x20
    VERBOSE = 0x40


COUNTER_NAMES = [
    "rx_frames_ok",
    "data_packets_ok",
    "packets_accepted",
    "packets_dropped",
    "packets_count_only",
    "parse_errors",
    "header_checksum_errors",
    "transport_crc_errors",
    "transport_length_errors",
    "ingress_overflow_frames",
    "bytes_processed",
    "transformed_packets",
    "last_latency_cycles",
    "max_latency_cycles",
    "busy_cycles",
    "rule_hit_0",
    "rule_hit_1",
    "rule_hit_2",
    "rule_hit_3",
    "rule_hit_4",
    "rule_hit_5",
    "rule_hit_6",
    "rule_hit_7",
]


def crc16_ccitt(data: bytes, init: int = 0xFFFF) -> int:
    crc = init & 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def escape_bytes(data: bytes) -> bytes:
    out = bytearray()
    for byte in data:
        if byte in (FRAME_FLAG, FRAME_ESCAPE):
            out.append(FRAME_ESCAPE)
            out.append(byte ^ 0x20)
        else:
            out.append(byte)
    return bytes(out)


def unescape_bytes(data: bytes) -> bytes:
    out = bytearray()
    escape = False
    for byte in data:
        if escape:
            out.append(byte ^ 0x20)
            escape = False
        elif byte == FRAME_ESCAPE:
            escape = True
        else:
            out.append(byte)
    if escape:
        raise ValueError("dangling escape byte")
    return bytes(out)


@dataclass(frozen=True)
class TransportFrame:
    msg_type: int
    seq: int
    payload: bytes
    flags: int = 0
    version: int = PROTOCOL_VERSION

    def encode(self) -> bytes:
        if len(self.payload) > MAX_FRAME_PAYLOAD:
            raise ValueError(f"payload too large: {len(self.payload)} > {MAX_FRAME_PAYLOAD}")
        body = bytes(
            [
                self.version & 0xFF,
                self.msg_type & 0xFF,
                self.flags & 0xFF,
                self.seq & 0xFF,
                (len(self.payload) >> 8) & 0xFF,
                len(self.payload) & 0xFF,
            ]
        ) + self.payload
        crc = crc16_ccitt(body)
        framed = bytes([FRAME_FLAG]) + escape_bytes(body + crc.to_bytes(2, "big")) + bytes([FRAME_FLAG])
        return framed

    @staticmethod
    def decode(frame_bytes: bytes) -> "TransportFrame":
        if len(frame_bytes) < 2 or frame_bytes[0] != FRAME_FLAG or frame_bytes[-1] != FRAME_FLAG:
            raise ValueError("missing frame delimiters")
        raw = unescape_bytes(frame_bytes[1:-1])
        if len(raw) < 8:
            raise ValueError("frame too short")
        body = raw[:-2]
        rx_crc = int.from_bytes(raw[-2:], "big")
        calc_crc = crc16_ccitt(body)
        if calc_crc != rx_crc:
            raise ValueError(f"CRC mismatch: got 0x{rx_crc:04X}, expected 0x{calc_crc:04X}")
        version, msg_type, flags, seq = body[0], body[1], body[2], body[3]
        length = int.from_bytes(body[4:6], "big")
        payload = body[6:]
        if length != len(payload):
            raise ValueError("length field mismatch")
        return TransportFrame(version=version, msg_type=msg_type, flags=flags, seq=seq, payload=payload)


class FrameStreamDecoder:
    def __init__(self) -> None:
        self._buf = bytearray()
        self._in_frame = False

    def feed(self, data: bytes) -> Iterator[TransportFrame]:
        for byte in data:
            if byte == FRAME_FLAG:
                if self._in_frame and self._buf:
                    try:
                        yield TransportFrame.decode(bytes([FRAME_FLAG]) + bytes(self._buf) + bytes([FRAME_FLAG]))
                    finally:
                        self._buf.clear()
                else:
                    self._buf.clear()
                self._in_frame = True
                continue
            if self._in_frame:
                self._buf.append(byte)


@dataclass(frozen=True)
class PacketResult:
    result_flags: int
    mode: int
    rule_id: int
    action: int
    error_code: int
    protocol: int
    packet_id: int
    src_addr: int
    dst_addr_final: int
    src_port: int
    dst_port_final: int
    total_length_final: int
    payload_length_final: int

    @staticmethod
    def decode(payload: bytes) -> "PacketResult":
        if len(payload) != RESULT_BYTES:
            raise ValueError(f"expected {RESULT_BYTES} result bytes, got {len(payload)}")
        return PacketResult(
            result_flags=payload[0],
            mode=payload[1],
            rule_id=payload[2],
            action=payload[3],
            error_code=payload[4],
            protocol=payload[5],
            packet_id=int.from_bytes(payload[6:8], "big"),
            src_addr=int.from_bytes(payload[8:10], "big"),
            dst_addr_final=int.from_bytes(payload[10:12], "big"),
            src_port=int.from_bytes(payload[12:14], "big"),
            dst_port_final=int.from_bytes(payload[14:16], "big"),
            total_length_final=int.from_bytes(payload[16:18], "big"),
            payload_length_final=int.from_bytes(payload[18:20], "big"),
        )


def parse_counter_block(payload: bytes) -> dict[str, int]:
    if (len(payload) % 4) != 0:
        raise ValueError(f"counter payload length must be multiple of 4, got {len(payload)}")
    values = {}
    count = len(payload) // 4
    for idx in range(count):
        name = COUNTER_NAMES[idx] if idx < len(COUNTER_NAMES) else f"counter_{idx}"
        base = idx * 4
        values[name] = int.from_bytes(payload[base : base + 4], "big")
    return values

