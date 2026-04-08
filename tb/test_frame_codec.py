from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge

from host.protocol import MessageType
from tb.common import pack_bytes, reset_dut, start_clock


@cocotb.test()
async def frame_encoder_decoder_round_trip(dut) -> None:
    await start_clock(dut)
    dut.start_i.value = 0
    dut.frame_ready_i.value = 0
    dut.payload_ready_i.value = 1
    dut.payload_i.value = pack_bytes(bytes([0xAA, 0x7E, 0x55]), 252)
    dut.msg_type_i.value = int(MessageType.CMD_RESP)
    dut.flags_i.value = 0
    dut.seq_i.value = 0x12
    dut.payload_len_i.value = 3
    await reset_dut(dut)

    dut.start_i.value = 1
    await RisingEdge(dut.clk)
    dut.start_i.value = 0

    for _ in range(512):
        await RisingEdge(dut.clk)
        if int(dut.frame_valid_o.value):
            break
    else:
        raise AssertionError("frame decoder never produced metadata")

    assert int(dut.frame_type_o.value) == int(MessageType.CMD_RESP)
    assert int(dut.frame_seq_o.value) == 0x12
    assert int(dut.frame_len_o.value) == 3

    dut.frame_ready_i.value = 1
    await RisingEdge(dut.clk)
    dut.frame_ready_i.value = 0

    payload = []
    for _ in range(64):
        await RisingEdge(dut.clk)
        if int(dut.payload_valid_o.value):
            payload.append(int(dut.payload_data_o.value))
            if int(dut.payload_eop_o.value):
                break
    assert payload == [0xAA, 0x7E, 0x55]

