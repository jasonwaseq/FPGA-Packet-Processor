from __future__ import annotations

import argparse
import time

from .client import PacketProcessorClient
from .packet import Packet
from .protocol import Mode, TransportFrame


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark UART packet bursts")
    parser.add_argument("--port", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--payload-bytes", type=int, default=64)
    args = parser.parse_args()

    client = PacketProcessorClient(args.port)
    try:
        client.set_mode(int(Mode.BENCHMARK))
        client.clear_counters()
        payload = bytes((idx & 0xFF) for idx in range(args.payload_bytes))
        start = time.perf_counter()
        for idx in range(args.count):
            client.link.send_frame(
                TransportFrame(
                    msg_type=0x10,
                    seq=idx & 0xFF,
                    payload=Packet(
                        protocol=0x11,
                        flags=0,
                        ttl=16,
                        src_addr=0x1001,
                        dst_addr=0x2001,
                        src_port=1234,
                        dst_port=5678,
                        packet_id=idx & 0xFFFF,
                        payload=payload,
                    ).encode(),
                )
            )
        elapsed = time.perf_counter() - start
        print(f"sent {args.count} packets in {elapsed:.3f}s")
        print(client.read_counters())
    finally:
        client.close()


if __name__ == "__main__":
    main()
