"""315-5296: port reads follow the direction register (latch for outputs,
pins for inputs), writes always land in the latch, the SEGA/CNT/DIR
registers read back, unused registers read FF, and /FMCS follows the
0x20-0x3F window. Every input the Y Board games see (buttons, coins, DIPs)
and every reset/display/watchdog output goes through this chip."""
import random, sys, os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from models.io5296 import Io5296

PORTS = "abcdefgh"


@cocotb.test()
async def random_ops(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    for s in ("cs", "we", "addr", "din"): getattr(dut, s).value = 0
    for p in PORTS: getattr(dut, "in_" + p).value = 0xff
    dut.reset.value = 1
    for _ in range(3): await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    m = Io5296()
    rng = random.Random(5296)
    for i in range(20000):
        r = rng.random()
        if r < 0.3:
            addr = rng.choice(list(range(8)) + [0xe, 0xf, 0xf, 0xf, 0x0c, 0x1a, 0x25])
            data = rng.randrange(256)
            m.write(addr, data)
            dut.cs.value = 1; dut.we.value = 1; dut.addr.value = addr; dut.din.value = data
            await RisingEdge(dut.clk)
            dut.cs.value = 0; dut.we.value = 0
            await RisingEdge(dut.clk)
        elif r < 0.5:
            p = rng.randrange(8)
            v = rng.randrange(256)
            m.inputs[p] = v
            getattr(dut, "in_" + PORTS[p]).value = v
            await RisingEdge(dut.clk)
        else:
            addr = rng.randrange(64)
            dut.cs.value = 1; dut.we.value = 0; dut.addr.value = addr
            await ReadOnly()
            got = int(dut.dout.value)
            exp = m.read(addr)
            assert got == exp, f"op {i}: read[{addr:02x}] = {got:02x} model {exp:02x} dir={m.dir:02x}"
            assert int(dut.fmcs.value) == int(m.fmcs(addr)), f"op {i}: fmcs at {addr:02x}"
            for p in range(8):
                got_o = int(getattr(dut, "out_" + PORTS[p]).value)
                assert got_o == m.output(p), f"op {i}: out {PORTS[p]} = {got_o:02x} model {m.output(p):02x}"
            await RisingEdge(dut.clk)
            dut.cs.value = 0


def test_io5296():
    from runner import run
    run("yb_315_5296", ["rtl/io/yb_315_5296.sv"], "test_io5296")
