from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge

from host.protocol import Action
from host.rules import MATCH_DST_PORT, MATCH_PROTOCOL, Rule
from tb.common import pack_bytes, reset_dut, start_clock


@cocotb.test()
async def classifier_hits_programmed_rule(dut) -> None:
    await start_clock(dut)
    dut.write_valid_i.value = 0
    dut.start_i.value = 0
    dut.default_action_i.value = int(Action.DROP)
    await reset_dut(dut)

    rule = Rule(
        valid=1,
        match_en=MATCH_DST_PORT | MATCH_PROTOCOL,
        action=int(Action.ACCEPT),
        dst_port_value=0x2222,
        protocol_value=0x11,
    ).encode()

    dut.write_index_i.value = 0
    dut.write_rule_i.value = pack_bytes(rule, 24)
    dut.write_valid_i.value = 1
    await RisingEdge(dut.clk)
    dut.write_valid_i.value = 0

    dut.protocol_i.value = 0x11
    dut.src_addr_i.value = 0x1001
    dut.dst_addr_i.value = 0x2001
    dut.src_port_i.value = 0x1111
    dut.dst_port_i.value = 0x2222
    dut.start_i.value = 1
    await RisingEdge(dut.clk)
    dut.start_i.value = 0

    for _ in range(32):
        await RisingEdge(dut.clk)
        if int(dut.done_o.value):
            break
    else:
        raise AssertionError("classifier timed out")

    assert int(dut.matched_o.value) == 1
    assert int(dut.matched_rule_o.value) == 0
    assert int(dut.action_o.value) == int(Action.ACCEPT)


@cocotb.test()
async def classifier_uses_default_action_on_miss(dut) -> None:
    await start_clock(dut)
    dut.write_valid_i.value = 0
    dut.start_i.value = 0
    dut.default_action_i.value = int(Action.COUNT_ONLY)
    await reset_dut(dut)

    dut.protocol_i.value = 0x99
    dut.src_addr_i.value = 0x1001
    dut.dst_addr_i.value = 0x2001
    dut.src_port_i.value = 0x1111
    dut.dst_port_i.value = 0x2222
    dut.start_i.value = 1
    await RisingEdge(dut.clk)
    dut.start_i.value = 0

    for _ in range(32):
        await RisingEdge(dut.clk)
        if int(dut.done_o.value):
            break
    else:
        raise AssertionError("classifier miss timed out")

    assert int(dut.matched_o.value) == 0
    assert int(dut.action_o.value) == int(Action.COUNT_ONLY)

