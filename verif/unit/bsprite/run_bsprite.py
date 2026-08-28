#!/usr/bin/env python3
"""Standalone 315-5196 renderer against the Python model.
    run_bsprite.py <dumpdir>...   (uses dumpdir/bspriteram.bin)"""
import os, subprocess, sys, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "verif")); sys.path.insert(0, os.path.join(ROOT, "tools"))
from models import bsprite5196 as bs
from romsets import ROMSETS
BUDGET = 6400
_rom = None


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def build():
    srcs = [os.path.join(ROOT, s) for s in ("rtl/yb_pkg.sv", "rtl/video/yb_bsprite_5196.sv")]
    subprocess.check_call(["iverilog", "-g2012", "-DSIMULATION", "-o", "tb.vvp", "-s", "tb_bsprite"] + srcs + [os.path.join(HERE, "tb_bsprite.sv")], cwd=HERE)


def main(dumpdir, setname="gforce2"):
    global _rom
    rs = ROMSETS[setname]
    if _rom is None:
        zf = zipfile.ZipFile(os.path.join("/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)", rs["zipfile"] + ".zip"))
        _rom = bs.load_rom_words(zf, [f[0] for f in rs["regions"]["bsprite"][1]])
    lst = words(os.path.join(dumpdir, "bspriteram.bin"))
    with open(os.path.join(HERE, "bspriteram.hex"), "w") as f: f.write("\n".join(f"{w:04x}" for w in lst))
    dst = os.path.join(HERE, "bsprite.hex")
    if not os.path.exists(dst): os.symlink(os.path.join(ROOT, "verif", "golden", setname, "bsprite.hex"), dst)
    out = subprocess.run(["vvp", "-n", "tb.vvp"], cwd=HERE, capture_output=True, text=True).stdout
    last = [l for l in out.splitlines() if "16B done" in l or "TIMEOUT" in l]
    exp = bs.render(lst, _rom, rs["bspr_banks"])
    got = [int(l, 16) for l in open(os.path.join(HERE, "lines.txt"))]
    ok = tot = 0; first = None
    for y in range(224):
        for x in range(320):
            e, g = exp[y][x], got[y * 320 + x]
            if e != 0xFFFF or g != 0xFFFF:
                tot += 1
                if e == g: ok += 1
                elif first is None: first = (x, y, hex(e), hex(g))
    worst = max(int(l.split()[1]) for l in open(os.path.join(HERE, "stats.txt")))
    print(f"{dumpdir}: opaque pixels {tot}: match {ok}, first mismatch {first}; {last[0] if last else ''}")
    return 0 if ok == tot and worst <= BUDGET else 1


if __name__ == "__main__":
    build()
    rc = 0
    for d in [a for a in sys.argv[1:] if not a.startswith("--")]:
        rc |= main(d)
    raise SystemExit(rc)
