from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


async def start_clock(dut, period_ns: int = 10) -> None:
    try:
        clock = Clock(dut.clk, period_ns, unit="ns")
    except ValueError:
        # Fall back to simulator time steps if the compiled design reports a coarse precision.
        clock = Clock(dut.clk, period_ns, unit="step")
    if hasattr(cocotb, "start_soon"):
        cocotb.start_soon(clock.start())
    else:
        cocotb.fork(clock.start())


async def reset_dut(dut, cycles: int = 4) -> None:
    dut.rst_n.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def pack_bytes(data: bytes, total_bytes: int) -> int:
    value = 0
    for idx, byte in enumerate(data):
        if idx >= total_bytes:
            raise ValueError("data longer than destination vector")
        value |= int(byte) << (idx * 8)
    return value
