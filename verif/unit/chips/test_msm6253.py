"""MSM6253: a channel write loads the shift register (channel 3 through the
port E mux, reverse mask per MAME channel), each read shifts one bit out on
D7. The games read the stick eight times per sample through this path, so
a bit order or mux slip shows up as an unplayable stick."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.msm6253 import Msm6253

CH = ["ch0", "ch1", "ch2", "mux0", "mux1", "mux2", "mux3"]


@cocotb.test()
async def random_ops(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("cs", "we", "addr", "mux_sel", "adc_reverse"): getattr(dut, s).value = 0
    for n in CH: getattr(dut, n).value = 0x80
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    m = Msm6253()
    rng = random.Random(6253)
    for i in range(20000):
        r = rng.random()
        if r < 0.15:
            n = rng.randrange(4)
            m.write(n)
            dut.cs.value = 1; dut.we.value = 1; dut.addr.value = n
            await RisingEdge(dut.clk)
            dut.cs.value = 0; dut.we.value = 0
            await RisingEdge(dut.clk)
        elif r < 0.25:
            c = rng.randrange(7); v = rng.randrange(256)
            m.channels[c] = v; getattr(dut, CH[c]).value = v
            await RisingEdge(dut.clk)
        elif r < 0.30:
            m.mux = rng.randrange(4); dut.mux_sel.value = m.mux
            await RisingEdge(dut.clk)
        elif r < 0.33:
            m.reverse = rng.randrange(128); dut.adc_reverse.value = m.reverse
            await RisingEdge(dut.clk)
        else:
            dut.cs.value = 1; dut.we.value = 0; dut.addr.value = rng.randrange(4)
            await ReadOnly()
            got = int(dut.d7.value)
            exp = m.read()
            assert got == exp, f"op {i}: d7 = {got} model {exp}"
            await RisingEdge(dut.clk)
            dut.cs.value = 0


def test_msm6253():
    from runner import run
    run("yb_msm6253", ["rtl/io/yb_msm6253.sv"], "test_msm6253")
