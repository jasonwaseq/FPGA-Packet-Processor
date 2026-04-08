from __future__ import annotations

from typing import Optional

from .protocol import FrameStreamDecoder, TransportFrame


class SerialLink:
    def __init__(self, port: str, baudrate: int = 1_500_000, timeout: float = 0.5) -> None:
        try:
            import serial  # type: ignore
        except ImportError as exc:
            raise RuntimeError("pyserial is required for hardware access") from exc

        self._serial = serial.Serial(port=port, baudrate=baudrate, timeout=timeout)
        self._decoder = FrameStreamDecoder()

    def close(self) -> None:
        self._serial.close()

    def send_frame(self, frame: TransportFrame) -> None:
        self._serial.write(frame.encode())
        self._serial.flush()

    def recv_frame(self) -> TransportFrame:
        while True:
            chunk = self._serial.read(256)
            if not chunk:
                raise TimeoutError("timed out waiting for UART frame")
            try:
                decoded = self._decoder.feed(chunk)
            except ValueError:
                # Ignore malformed/partial frame noise and keep scanning for the next valid frame.
                continue
            for frame in decoded:
                return frame

