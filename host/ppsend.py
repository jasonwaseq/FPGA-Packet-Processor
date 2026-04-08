from __future__ import annotations

import argparse

from .client import PacketProcessorClient
from .packet import Packet
from .protocol import MessageType, PacketResult


def main() -> None:
    parser = argparse.ArgumentParser(description="Send one packet to the FPGA")
    parser.add_argument("--port", required=True)
    parser.add_argument("--protocol", type=lambda x: int(x, 0), default=0x11)
    parser.add_argument("--flags", type=lambda x: int(x, 0), default=0)
    parser.add_argument("--ttl", type=lambda x: int(x, 0), default=32)
    parser.add_argument("--src-addr", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--dst-addr", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--src-port", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--dst-port", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--packet-id", type=lambda x: int(x, 0), default=1)
    parser.add_argument("--payload-hex", default="")
    args = parser.parse_args()

    packet = Packet(
        protocol=args.protocol,
        flags=args.flags,
        ttl=args.ttl,
        src_addr=args.src_addr,
        dst_addr=args.dst_addr,
        src_port=args.src_port,
        dst_port=args.dst_port,
        packet_id=args.packet_id,
        payload=bytes.fromhex(args.payload_hex),
    )

    client = PacketProcessorClient(args.port)
    try:
        resp = client.send_packet(packet)
        print(f"RX frame type=0x{resp.msg_type:02x} seq={resp.seq} len={len(resp.payload)}")
        if resp.msg_type == MessageType.PKT_RESULT:
            print(PacketResult.decode(resp.payload))
        else:
            print(resp.payload.hex())
    finally:
        client.close()


if __name__ == "__main__":
    main()

