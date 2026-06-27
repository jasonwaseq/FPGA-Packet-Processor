from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge

from host.packet import Packet
from host.protocol import Action, MessageType, PacketResult, ResultFlag, TransportFrame
from tb.common import reset_dut, start_clock


UART_CLKS_PER_BIT = 104
POR_WAIT_CLKS = 600
RX_TIMEOUT_CLKS = 400_000


def start_background(coro):
    if hasattr(cocotb, "start_soon"):
        return cocotb.start_soon(coro)
    return cocotb.fork(coro)


async def wait_clks(dut, cycles: int) -> None:
    for _ in range(cycles):
        await RisingEdge(dut.clk)


async def send_uart_byte(dut, byte: int) -> None:
    dut.uart_rx_i.value = 0
    await wait_clks(dut, UART_CLKS_PER_BIT)
    for bit_idx in range(8):
        dut.uart_rx_i.value = (byte >> bit_idx) & 1
        await wait_clks(dut, UART_CLKS_PER_BIT)
    dut.uart_rx_i.value = 1
    await wait_clks(dut, UART_CLKS_PER_BIT)


async def send_transport_frame(dut, frame: TransportFrame) -> None:
    for byte in frame.encode():
        await send_uart_byte(dut, byte)


async def recv_transport_frame_bytes(dut, timeout_clks: int = RX_TIMEOUT_CLKS) -> bytes:
    # Decode the *actual* serialized uart_tx_o line via the dut's UART monitor
    # (dut.tx_valid_o / dut.tx_data_o). Tapping the pre-serialization encoder
    # bytes would hide bugs in uart_tx and the encoder<->uart_tx handshake.
    frame = bytearray()
    in_frame = False

    for _ in range(timeout_clks):
        await RisingEdge(dut.clk)
        if not int(dut.tx_valid_o.value):
            continue

        byte = int(dut.tx_data_o.value)
        frame.append(byte)
        if byte == 0x7E:
            if in_frame:
                return bytes(frame)
            in_frame = True

    raise AssertionError("timed out waiting for framed UART response")


def build_data_packet_frame(
    *,
    seq: int,
    protocol: int,
    flags: int,
    ttl: int,
    src_addr: int,
    dst_addr: int,
    src_port: int,
    dst_port: int,
    packet_id: int,
    payload: bytes = b"",
) -> TransportFrame:
    packet = Packet(
        protocol=protocol,
        flags=flags,
        ttl=ttl,
        src_addr=src_addr,
        dst_addr=dst_addr,
        src_port=src_port,
        dst_port=dst_port,
        packet_id=packet_id,
        payload=payload,
    )
    return TransportFrame(msg_type=int(MessageType.DATA_PACKET), seq=seq, payload=packet.encode())


@cocotb.test()
async def up5k_top_returns_expected_result_frames(dut) -> None:
    await start_clock(dut)
    dut.uart_rx_i.value = 1
    dut.rst_n.value = 1
    await reset_dut(dut)
    await wait_clks(dut, POR_WAIT_CLKS)

    default_accept = build_data_packet_frame(
        seq=0x10,
        protocol=0x11,
        flags=0x01,
        ttl=0x20,
        src_addr=0x1001,
        dst_addr=0x2001,
        src_port=0x1234,
        dst_port=0x2222,
        packet_id=0x1000,
        payload=b"",
    )
    default_capture = start_background(recv_transport_frame_bytes(dut))
    await send_transport_frame(dut, default_accept)
    raw_default = await default_capture
    decoded_default = TransportFrame.decode(raw_default)
    result_default = PacketResult.decode(decoded_default.payload)

    assert len(raw_default) == 30
    assert decoded_default.version == 0x01
    assert decoded_default.msg_type == int(MessageType.PKT_RESULT)
    assert decoded_default.seq == 0x10
    assert len(decoded_default.payload) == 20
    assert result_default.action == int(Action.ACCEPT)
    assert result_default.error_code == 0
    assert result_default.result_flags & int(ResultFlag.PARSE_OK)
    assert result_default.result_flags & int(ResultFlag.CHECKSUM_OK)
    assert result_default.result_flags & int(ResultFlag.DEFAULT_ACTION)
    assert result_default.packet_id == 0x1000
    assert result_default.payload_length_final == 0

    await wait_clks(dut, 64)

    drop = build_data_packet_frame(
        seq=0x11,
        protocol=0x11,
        flags=0x00,
        ttl=0x1F,
        src_addr=0x1002,
        dst_addr=0x2002,
        src_port=0x1235,
        dst_port=0x9001,
        packet_id=0x1001,
        payload=b"",
    )
    drop_capture = start_background(recv_transport_frame_bytes(dut))
    await send_transport_frame(dut, drop)
    raw_drop = await drop_capture
    decoded_drop = TransportFrame.decode(raw_drop)
    result_drop = PacketResult.decode(decoded_drop.payload)

    assert decoded_drop.seq == 0x11
    assert result_drop.action == int(Action.DROP)
    assert result_drop.rule_id == 0
    assert result_drop.error_code == 0
    assert result_drop.result_flags & int(ResultFlag.MATCHED)
    assert result_drop.result_flags & int(ResultFlag.DROPPED)

    await wait_clks(dut, 64)

    count = build_data_packet_frame(
        seq=0x12,
        protocol=0x22,
        flags=0x00,
        ttl=0x1E,
        src_addr=0x3333,
        dst_addr=0x2003,
        src_port=0x1236,
        dst_port=0x2345,
        packet_id=0x1002,
        payload=b"",
    )
    count_capture = start_background(recv_transport_frame_bytes(dut))
    await send_transport_frame(dut, count)
    raw_count = await count_capture
    decoded_count = TransportFrame.decode(raw_count)
    result_count = PacketResult.decode(decoded_count.payload)

    assert decoded_count.seq == 0x12
    assert result_count.action == int(Action.COUNT_ONLY)
    assert result_count.rule_id == 1
    assert result_count.error_code == 0
    assert result_count.result_flags & int(ResultFlag.MATCHED)
    assert not (result_count.result_flags & int(ResultFlag.DROPPED))

    await wait_clks(dut, 64)

    rewrite = build_data_packet_frame(
        seq=0x13,
        protocol=0x11,
        flags=0x00,
        ttl=0x0F,
        src_addr=0x1111,
        dst_addr=0x2222,
        src_port=0x1237,
        dst_port=0x3456,
        packet_id=0x1003,
        payload=b"",
    )
    rewrite_capture = start_background(recv_transport_frame_bytes(dut))
    await send_transport_frame(dut, rewrite)
    raw_rewrite = await rewrite_capture
    decoded_rewrite = TransportFrame.decode(raw_rewrite)
    result_rewrite = PacketResult.decode(decoded_rewrite.payload)

    assert decoded_rewrite.version == 0x01
    assert decoded_rewrite.msg_type == int(MessageType.PKT_RESULT)
    assert decoded_rewrite.seq == 0x13
    assert len(decoded_rewrite.payload) == 20
    assert result_rewrite.action == int(Action.REWRITE)
    assert result_rewrite.rule_id == 2
    assert result_rewrite.error_code == 0
    assert result_rewrite.result_flags & int(ResultFlag.MATCHED)
    assert result_rewrite.result_flags & int(ResultFlag.REWRITTEN)
    assert result_rewrite.dst_addr_final == 0xCAFE
    assert result_rewrite.dst_port_final == 0xBEEF
