#!/usr/bin/env python3
"""Standalone 315-5306 scan-out against the Python model.
    run_rotate.py <dumpdir>...   (uses yspriteram.bin + rotateram.bin of each)
The framebuffer the model renders from the capture is loaded into the DDRAM
model; the RTL must reproduce the model's scan-out of it pixel for pixel."""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "verif")); sys.path.insert(0, os.path.join(ROOT, "tools"))
from models import ysprite5305 as ys, rotate5306 as rt
from romsets import ROMSETS
BUDGET = 6400
_rom = None


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def build():
    srcs = [os.path.join(ROOT, s) for s in ("rtl/yb_pkg.sv", "rtl/mem/yb_fb_if.sv", "rtl/video/yb_rotate_5306.sv", "verif/board/ddram_model.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_rotate"] + srcs + [os.path.join(HERE, "tb_rotate.sv")], cwd=HERE)


def main(dumpdir, setname="gforce2"):
    global _rom
    rs = ROMSETS[setname]
    if _rom is None:
        zf = zipfile.ZipFile(os.path.join("/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)", rs["zipfile"] + ".zip"))
        _rom = ys.load_rom_qwords(zf, [f[0] for f in rs["regions"]["ysprite"][1]])
    sp = words(os.path.join(dumpdir, "yspriteram.bin")); rot = words(os.path.join(dumpdir, "rotateram.bin"))
    fb = ys.render(sp, rot, _rom, rs["yspr_banks"])
    with open(os.path.join(HERE, "fb.hex"), "w") as f:      # buffer 0 at the DDRAM model's base
        for y in range(512):
            row = fb[y]
            for w in range(128):
                v = row[w * 4] | (row[w * 4 + 1] << 16) | (row[w * 4 + 2] << 32) | (row[w * 4 + 3] << 48)
                f.write(f"{v:016x}\n")
    with open(os.path.join(HERE, "rot.hex"), "w") as f:
        f.write("\n".join(f"{rot[0x3f0 + k]:04x}" for k in range(12)))
    out = subprocess.run(["vvp", "-n", "tb.vvp"], cwd=HERE, capture_output=True, text=True).stdout
    last = [l for l in out.splitlines() if "scan-out done" in l or "TIMEOUT" in l]
    exp_idx, exp_pri = rt.scanout(fb, rot, 320, 224)
    got = [tuple(int(v) for v in l.split()) for l in open(os.path.join(HERE, "lines.txt"))]
    ok = 0; first = None
    for y in range(224):
        for x in range(320):
            g = got[y * 320 + x]
            if g == (exp_idx[y][x], exp_pri[y][x]): ok += 1
            elif first is None: first = (x, y, hex(exp_idx[y][x]), exp_pri[y][x], hex(g[0]), g[1])
    worst = max(int(l.split()[2]) for l in open(os.path.join(HERE, "stats.txt")))
    print(f"{dumpdir}: {ok}/{320*224} exact, first mismatch {first}; {last[0] if last else ''}")
    return 0 if ok == 320 * 224 and worst <= BUDGET else 1


if __name__ == "__main__":
    build()
    rc = 0
    for d in [a for a in sys.argv[1:] if not a.startswith("--")]:
        rc |= main(d)
    raise SystemExit(rc)
