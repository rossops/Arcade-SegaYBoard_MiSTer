#!/usr/bin/env python3
"""Render the full Y Board frame from a MAME capture directory with the
Python models (Y sprites, rotation, 16B sprites, mixer, palette) and compare
it with MAME's own screenshot of that frame.

    frame_check.py verif/golden/gforce2/f1000 [--diff out.png]

Exact agreement means the model chain reproduces MAME's video; the same
chain then judges the RTL (tools/board_check.py).
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from models import ysprite5305 as ys, rotate5306 as rt, bsprite5196 as bs, mixer5312 as mx, palette5242 as pal
from romsets import ROMSETS
ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"
_roms = {}


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def roms(setname):
    if setname not in _roms:
        rs = ROMSETS[setname]
        zf = zipfile.ZipFile(os.path.join(ZIPDIR, rs["zipfile"] + ".zip"))
        _roms[setname] = (ys.load_rom_qwords(zf, [f[0] for f in rs["regions"]["ysprite"][1]]),
                          bs.load_rom_words(zf, [f[0] for f in rs["regions"]["bsprite"][1]]))
    return _roms[setname]


def render_frame(splist, rotbuf, blist, palram, setname="gforce2"):
    rs = ROMSETS[setname]
    yrom, brom = roms(setname)
    fb = ys.render(splist, rotbuf, yrom, rs["yspr_banks"])
    yidx, ypri = rt.scanout(fb, rotbuf, 320, 224)
    bfb = bs.render(blist, brom, rs["bspr_banks"])
    idx, eff = mx.mix(yidx, ypri, bfb)
    im = Image.new("RGB", (320, 224))
    px = im.load()
    for y in range(224):
        for x in range(320):
            px[x, y] = pal.entry_rgb(palram[idx[y][x]], eff[y][x])
    return im


def main(dumpdir, diff=None, setname="gforce2"):
    # the rotation buffer MAME drew with is the RAM as the 198000 read tap sees
    # it (before the swap); rotateram.bin at frame end may hold the next frame's
    rotf = "rotateram_swap.bin" if os.path.exists(os.path.join(dumpdir, "rotateram_swap.bin")) else "rotateram.bin"
    im = render_frame(words(os.path.join(dumpdir, "yspriteram.bin")), words(os.path.join(dumpdir, rotf)),
                      words(os.path.join(dumpdir, "bspriteram.bin")), words(os.path.join(dumpdir, "paletteram.bin")), setname)
    mame = Image.open(os.path.join(dumpdir, "frame.png")).convert("RGB")
    if mame.size != (320, 224):
        print(f"{dumpdir}: MAME screenshot is {mame.size}, expected 320x224"); return 1
    ok = 0; first = None; bad = []
    for y in range(224):
        for x in range(320):
            if im.getpixel((x, y)) == mame.getpixel((x, y)): ok += 1
            else:
                bad.append((x, y))
                if first is None: first = (x, y, im.getpixel((x, y)), mame.getpixel((x, y)))
    print(f"{dumpdir}: {ok}/{320*224} pixels equal to MAME's screenshot; first difference {first}")
    if diff:
        d = Image.new("RGB", (320, 224)); bs_ = set(bad)
        for y in range(224):
            for x in range(320):
                d.putpixel((x, y), (255, 0, 0) if (x, y) in bs_ else tuple(c // 3 for c in mame.getpixel((x, y))))
        d.save(diff)
    return 0 if ok == 320 * 224 else 1


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    diff = sys.argv[sys.argv.index("--diff") + 1] if "--diff" in sys.argv else None
    rc = 0
    for d in args:
        rc |= main(d, diff)
    raise SystemExit(rc)
