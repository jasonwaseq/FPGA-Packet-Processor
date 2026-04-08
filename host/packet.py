from __future__ import annotations

from dataclasses import dataclass


PACKET_HEADER_BYTES = 20


def ones_add16(a: int, b: int) -> int:
    total = a + b
    return (total & 0xFFFF) + (total >> 16)


def compute_header_checksum(header_without_checksum: bytes) -> int:
    if len(header_without_checksum) != PACKET_HEADER_BYTES:
        raise ValueError("header must be 20 bytes")
    checksum_header = bytearray(header_without_checksum)
    checksum_header[18:20] = b"\x00\x00"
    total = 0
    for idx in range(0, PACKET_HEADER_BYTES, 2):
        total = ones_add16(total, int.from_bytes(checksum_header[idx : idx + 2], "big"))
    return (~total) & 0xFFFF


@dataclass(frozen=True)
class Packet:
    protocol: int
    flags: int
    ttl: int
    src_addr: int
    dst_addr: int
    src_port: int
    dst_port: int
    packet_id: int
    payload: bytes
    version: int = 1
    hdr_len_words: int = 5

    def encode(self) -> bytes:
        payload_len = len(self.payload)
        total_len = PACKET_HEADER_BYTES + payload_len
        header = bytearray(PACKET_HEADER_BYTES)
        header[0] = ((self.version & 0xF) << 4) | (self.hdr_len_words & 0xF)
        header[1] = self.protocol & 0xFF
        header[2] = self.flags & 0xFF
        header[3] = self.ttl & 0xFF
        header[4:6] = total_len.to_bytes(2, "big")
        header[6:8] = payload_len.to_bytes(2, "big")
        header[8:10] = self.src_addr.to_bytes(2, "big")
        header[10:12] = self.dst_addr.to_bytes(2, "big")
        header[12:14] = self.src_port.to_bytes(2, "big")
        header[14:16] = self.dst_port.to_bytes(2, "big")
        header[16:18] = self.packet_id.to_bytes(2, "big")
        header[18:20] = compute_header_checksum(bytes(header)).to_bytes(2, "big")
        return bytes(header) + self.payload

    @staticmethod
    def decode(data: bytes) -> "Packet":
        if len(data) < PACKET_HEADER_BYTES:
            raise ValueError("packet too short")
        header = data[:PACKET_HEADER_BYTES]
        total_length = int.from_bytes(header[4:6], "big")
        payload_length = int.from_bytes(header[6:8], "big")
        if total_length != len(data):
            raise ValueError("total_length mismatch")
        if payload_length != len(data) - PACKET_HEADER_BYTES:
            raise ValueError("payload_length mismatch")
        checksum = compute_header_checksum(header)
        if checksum != int.from_bytes(header[18:20], "big"):
            raise ValueError("bad header checksum")
        return Packet(
            version=(header[0] >> 4) & 0xF,
            hdr_len_words=header[0] & 0xF,
            protocol=header[1],
            flags=header[2],
            ttl=header[3],
            src_addr=int.from_bytes(header[8:10], "big"),
            dst_addr=int.from_bytes(header[10:12], "big"),
            src_port=int.from_bytes(header[12:14], "big"),
            dst_port=int.from_bytes(header[14:16], "big"),
            packet_id=int.from_bytes(header[16:18], "big"),
            payload=data[PACKET_HEADER_BYTES:],
        )

