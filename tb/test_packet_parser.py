from __future__ import annotations

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge

from host.packet import Packet
from tb.common import reset_dut, start_clock


async def drive_packet(dut, packet_bytes: bytes) -> None:
    for idx, byte in enumerate(packet_bytes):
        dut.data_i.value = byte
        dut.valid_i.value = 1
        dut.sop_i.value = 1 if idx == 0 else 0
        dut.eop_i.value = 1 if idx == len(packet_bytes) - 1 else 0
        await RisingEdge(dut.clk)
    dut.valid_i.value = 0
    dut.sop_i.value = 0
    dut.eop_i.value = 0


async def accept_header(dut) -> None:
    dut.hdr_ready_i.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.hdr_valid_o.value) == 0:
            break
    else:
        raise AssertionError("parser did not clear hdr_valid after header acceptance")
    await RisingEdge(dut.clk)
    dut.hdr_ready_i.value = 0


@cocotb.test()
async def parser_accepts_valid_packet(dut) -> None:
    await start_clock(dut)
    dut.valid_i.value = 0
    dut.sop_i.value = 0
    dut.eop_i.value = 0
    dut.hdr_ready_i.value = 0
    dut.payload_ready_i.value = 1
    await reset_dut(dut)

    packet = Packet(
        protocol=0x11,
        flags=0x00,
        ttl=0x20,
        src_addr=0x1001,
        dst_addr=0x2001,
        src_port=0x1111,
        dst_port=0x2222,
        packet_id=0x0001,
        payload=bytes.fromhex("deadbeef"),
    ).encode()

    dut.packet_len_i.value = len(packet)
    await drive_packet(dut, packet)

    for _ in range(64):
        await RisingEdge(dut.clk)
        if int(dut.hdr_valid_o.value):
            break
    else:
        raise AssertionError("parser never asserted hdr_valid")

    assert int(dut.parse_error_o.value) == 0
    assert int(dut.checksum_ok_o.value) == 1
    assert int(dut.protocol_o.value) == 0x11
    assert int(dut.dst_port_o.value) == 0x2222
    assert int(dut.payload_length_o.value) == 4
    await accept_header(dut)


@cocotb.test()
async def parser_detects_bad_checksum(dut) -> None:
    await start_clock(dut)
    dut.valid_i.value = 0
    dut.sop_i.value = 0
    dut.eop_i.value = 0
    dut.hdr_ready_i.value = 0
    dut.payload_ready_i.value = 1
    await reset_dut(dut)

    packet = bytearray(
        Packet(
            protocol=0x11,
            flags=0x00,
            ttl=0x20,
            src_addr=0x1001,
            dst_addr=0x2001,
            src_port=0x1111,
            dst_port=0x2222,
            packet_id=0x0002,
            payload=b"\x01\x02\x03\x04",
        ).encode()
    )
    packet[18] ^= 0xFF

    dut.packet_len_i.value = len(packet)
    await drive_packet(dut, bytes(packet))

    for _ in range(64):
        await RisingEdge(dut.clk)
        if int(dut.hdr_valid_o.value):
            break
    else:
        raise AssertionError("parser never asserted hdr_valid on bad packet")

    assert int(dut.checksum_ok_o.value) == 0
    assert int(dut.parse_error_o.value) != 0
    await accept_header(dut)


@cocotb.test()
async def parser_accepts_zero_payload_packet(dut) -> None:
    await start_clock(dut)
    dut.valid_i.value = 0
    dut.sop_i.value = 0
    dut.eop_i.value = 0
    dut.hdr_ready_i.value = 0
    dut.payload_ready_i.value = 1
    await reset_dut(dut)

    packet = Packet(
        protocol=0x11,
        flags=0x01,
        ttl=0x20,
        src_addr=0x1001,
        dst_addr=0x2001,
        src_port=0x1234,
        dst_port=0x2222,
        packet_id=0x1000,
        payload=b"",
    ).encode()

    dut.packet_len_i.value = len(packet)
    await drive_packet(dut, packet)

    for _ in range(64):
        await RisingEdge(dut.clk)
        if int(dut.hdr_valid_o.value):
            break
    else:
        raise AssertionError("parser never asserted hdr_valid for zero-payload packet")

    assert int(dut.parse_error_o.value) == 0
    assert int(dut.checksum_ok_o.value) == 1
    assert int(dut.protocol_o.value) == 0x11
    assert int(dut.total_length_o.value) == 20
    assert int(dut.payload_length_o.value) == 0
    await accept_header(dut)
