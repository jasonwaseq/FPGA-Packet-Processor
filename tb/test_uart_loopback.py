from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge

from tb.common import reset_dut, start_clock


@cocotb.test()
async def uart_loopback_round_trip(dut) -> None:
    await start_clock(dut)
    dut.tx_data_i.value = 0
    dut.tx_valid_i.value = 0
    await reset_dut(dut)

    while not int(dut.tx_ready_o.value):
        await RisingEdge(dut.clk)

    dut.tx_data_i.value = 0xA5
    dut.tx_valid_i.value = 1
    await RisingEdge(dut.clk)
    dut.tx_valid_i.value = 0

    for _ in range(256):
        await RisingEdge(dut.clk)
        if int(dut.rx_valid_o.value):
            break
    else:
        raise AssertionError("UART loopback timed out")

    assert int(dut.rx_data_o.value) == 0xA5
    assert int(dut.frame_error_o.value) == 0

