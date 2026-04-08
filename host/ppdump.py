from __future__ import annotations

import argparse

from .protocol import FrameStreamDecoder, MessageType, PacketResult
from .serial_link import SerialLink


def main() -> None:
    parser = argparse.ArgumentParser(description="Live decode FPGA UART responses")
    parser.add_argument("--port", required=True)
    args = parser.parse_args()

    link = SerialLink(args.port)
    try:
        while True:
            frame = link.recv_frame()
            print(f"type=0x{frame.msg_type:02x} seq={frame.seq} len={len(frame.payload)}")
            if frame.msg_type == MessageType.PKT_RESULT:
                print(PacketResult.decode(frame.payload))
            else:
                print(frame.payload.hex())
    finally:
        link.close()


if __name__ == "__main__":
    main()
