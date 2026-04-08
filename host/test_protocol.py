from __future__ import annotations

import unittest

from host.packet import Packet
from host.protocol import MessageType, PacketResult, TransportFrame, crc16_ccitt
from host.rules import MATCH_DST_PORT, MATCH_PROTOCOL, REWRITE_DST_PORT, Rule


class ProtocolTests(unittest.TestCase):
    def test_transport_round_trip(self) -> None:
        frame = TransportFrame(msg_type=MessageType.CMD_REQ, seq=7, payload=b"\x00\x7e\x7d\x55")
        encoded = frame.encode()
        decoded = TransportFrame.decode(encoded)
        self.assertEqual(decoded.msg_type, MessageType.CMD_REQ)
        self.assertEqual(decoded.seq, 7)
        self.assertEqual(decoded.payload, b"\x00\x7e\x7d\x55")

    def test_packet_round_trip(self) -> None:
        packet = Packet(
            protocol=0x11,
            flags=0x22,
            ttl=0x33,
            src_addr=0x1111,
            dst_addr=0x2222,
            src_port=0x1234,
            dst_port=0x5678,
            packet_id=0x9ABC,
            payload=b"\xDE\xAD\xBE\xEF",
        )
        decoded = Packet.decode(packet.encode())
        self.assertEqual(decoded.protocol, 0x11)
        self.assertEqual(decoded.dst_port, 0x5678)
        self.assertEqual(decoded.payload, b"\xDE\xAD\xBE\xEF")

    def test_rule_round_trip(self) -> None:
        rule = Rule(
            valid=1,
            match_en=MATCH_DST_PORT | MATCH_PROTOCOL,
            action=3,
            rewrite_en=REWRITE_DST_PORT,
            dst_port_value=0x4000,
            protocol_value=0x11,
            rewrite_dst_port=0x5000,
        )
        self.assertEqual(Rule.decode(rule.encode()), rule)


if __name__ == "__main__":
    unittest.main()

