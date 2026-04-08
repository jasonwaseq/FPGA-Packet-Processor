from __future__ import annotations

from dataclasses import dataclass


MATCH_SRC_ADDR = 0x01
MATCH_DST_ADDR = 0x02
MATCH_SRC_PORT = 0x04
MATCH_DST_PORT = 0x08
MATCH_PROTOCOL = 0x10

REWRITE_DEC_TTL = 0x01
REWRITE_FLAGS = 0x02
REWRITE_DST_PORT = 0x04
REWRITE_DST_ADDR = 0x08


@dataclass(frozen=True)
class Rule:
    valid: int = 1
    match_en: int = 0
    action: int = 0
    rewrite_en: int = 0
    src_addr_value: int = 0
    src_addr_mask: int = 0
    dst_addr_value: int = 0
    dst_addr_mask: int = 0
    src_port_value: int = 0
    dst_port_value: int = 0
    protocol_value: int = 0
    rewrite_flags_value: int = 0
    rewrite_dst_addr: int = 0
    rewrite_dst_port: int = 0
    reserved: int = 0

    def encode(self) -> bytes:
        data = bytearray(24)
        data[0] = self.valid & 0xFF
        data[1] = self.match_en & 0x1F
        data[2] = self.action & 0xFF
        data[3] = self.rewrite_en & 0x0F
        data[4:6] = self.src_addr_value.to_bytes(2, "big")
        data[6:8] = self.src_addr_mask.to_bytes(2, "big")
        data[8:10] = self.dst_addr_value.to_bytes(2, "big")
        data[10:12] = self.dst_addr_mask.to_bytes(2, "big")
        data[12:14] = self.src_port_value.to_bytes(2, "big")
        data[14:16] = self.dst_port_value.to_bytes(2, "big")
        data[16] = self.protocol_value & 0xFF
        data[17] = self.rewrite_flags_value & 0xFF
        data[18:20] = self.rewrite_dst_addr.to_bytes(2, "big")
        data[20:22] = self.rewrite_dst_port.to_bytes(2, "big")
        data[22:24] = self.reserved.to_bytes(2, "big")
        return bytes(data)

    @staticmethod
    def decode(data: bytes) -> "Rule":
        if len(data) != 24:
            raise ValueError("rule image must be 24 bytes")
        return Rule(
            valid=data[0],
            match_en=data[1],
            action=data[2],
            rewrite_en=data[3],
            src_addr_value=int.from_bytes(data[4:6], "big"),
            src_addr_mask=int.from_bytes(data[6:8], "big"),
            dst_addr_value=int.from_bytes(data[8:10], "big"),
            dst_addr_mask=int.from_bytes(data[10:12], "big"),
            src_port_value=int.from_bytes(data[12:14], "big"),
            dst_port_value=int.from_bytes(data[14:16], "big"),
            protocol_value=data[16],
            rewrite_flags_value=data[17],
            rewrite_dst_addr=int.from_bytes(data[18:20], "big"),
            rewrite_dst_port=int.from_bytes(data[20:22], "big"),
            reserved=int.from_bytes(data[22:24], "big"),
        )

