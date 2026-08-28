#!/usr/bin/env python3
"""Standalone 315-5305 renderer against the Python model.
    run_ysprite.py <dumpdir> [--keep]   (uses dumpdir/yspriteram.bin and rotateram.bin)
The rotation buffer for the render is rotateram.bin as dumped; the model and
the RTL see the same words, which is what this test checks."""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "verif")); sys.path.insert(0, os.path.join(ROOT, "tools"))
from models import ysprite5305 as ys
from romsets import ROMSETS

_rom_cache = {}


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def rom_for(setname):
    if setname not in _rom_cache:
        rs = ROMSETS[setname]
        zf = zipfile.ZipFile(os.path.join("/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)", rs["zipfile"] + ".zip"))
        _rom_cache[setname] = ys.load_rom_qwords(zf, [f[0] for f in rs["regions"]["ysprite"][1]])
    return _rom_cache[setname]


def build():
    srcs = [os.path.join(ROOT, s) for s in ("rtl/yb_pkg.sv", "rtl/mem/yb_fb_if.sv", "rtl/video/yb_ysprite_5305.sv", "verif/board/ddram_model.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_ysprite"] + srcs + [os.path.join(HERE, "tb_ysprite.sv")], cwd=HERE)


def main(dumpdir, setname="gforce2", built=False):
    splist = words(os.path.join(dumpdir, "yspriteram.bin"))
    rot = words(os.path.join(dumpdir, "rotateram.bin"))
    with open(os.path.join(HERE, "yspriteram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in splist))
    with open(os.path.join(HERE, "rotateram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in rot))
    dst = os.path.join(HERE, "ysprite.hex")
    if not os.path.exists(dst): os.symlink(os.path.join(ROOT, "verif", "golden", setname, "ysprite.hex"), dst)
    if not built: build()
    out = subprocess.run(["vvp", "-n", "tb.vvp"], cwd=HERE, capture_output=True, text=True).stdout
    print(out.strip().splitlines()[-1])
    rom = rom_for(setname)
    exp = ys.render(splist, rot, rom, ROMSETS[setname]["yspr_banks"])
    got = [[0xFFFF] * 512 for _ in range(512)]
    vals = open(os.path.join(HERE, "fb.txt")).read().split()
    i = 0
    for y in range(512):
        for xw in range(128):
            for k in range(4):
                got[y][xw * 4 + k] = int(vals[i], 16); i += 1
    ok = tot = 0
    first = None
    for y in range(512):
        er, gr = exp[y], got[y]
        for x in range(512):
            e, g = er[x], gr[x]
            if e != 0xFFFF or g != 0xFFFF:
                tot += 1
                if e == g: ok += 1
                elif first is None: first = (x, y, hex(e), hex(g))
    print(f"{dumpdir}: opaque pixels {tot}: match {ok} ({100.0*ok/max(1,tot):.2f}%) first mismatch {first}")
    return 0 if ok == tot else 1


if __name__ == "__main__":
    dirs = [a for a in sys.argv[1:] if not a.startswith("--")]
    build()
    rc = 0
    for d in dirs:
        rc |= main(d, built=True)
    raise SystemExit(rc)
