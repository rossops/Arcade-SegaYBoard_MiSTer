#!/usr/bin/env python3
"""Board-level video self-consistency: render the Python model from the
RTL's own RAM dumps (tb +dumpframe=N: the Y list and the rotation buffer
as the render shown in frame N starts, in frame N-1; the 16B list as its
copy is taken at line 226 of frame N; the palette at the end of frame N)
and require the RTL's frame N to be pixel-exact.

    board_check.py verif/board/out 100 [gforce2]

The frame is the full chain: Y sprites, the affine scan-out, the 16B
sprites and the mixer.
"""
import os, sys, zipfile
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from models import ysprite5305 as ys, rotate5306 as rt, bsprite5196 as bs, mixer5312 as mx, palette5242 as pal
from romsets import ROMSETS
ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(outdir, frame, setname="gforce2"):
    rs = ROMSETS[setname]
    W, H = 320, 224
    splist = words(os.path.join(outdir, "rtl_yspriteram.bin"))
    rotbuf = words(os.path.join(outdir, "rtl_rotbuf.bin"))
    palram = words(os.path.join(outdir, "rtl_paletteram.bin"))
    zf = zipfile.ZipFile(os.path.join(ZIPDIR, rs["zipfile"] + ".zip"))
    rom = ys.load_rom_qwords(zf, [f[0] for f in rs["regions"]["ysprite"][1]])
    brom = bs.load_rom_words(zf, [f[0] for f in rs["regions"]["bsprite"][1]])
    blist = words(os.path.join(outdir, "rtl_bspriteram.bin"))
    fb = ys.render(splist, rotbuf, rom, rs["yspr_banks"])
    yidx, ypri = rt.scanout(fb, rotbuf, W, H)
    bfb = bs.render(blist, brom, rs["bspr_banks"])
    idx, eff = mx.mix(yidx, ypri, bfb)
    shown = frame
    rtl = Image.open(os.path.join(outdir, f"frame_{shown:04d}.ppm")).convert("RGB")
    ok = 0
    first = None
    mism = []
    for y in range(H):
        for x in range(W):
            exp = pal.entry_rgb(palram[idx[y][x]], eff[y][x])
            got = rtl.getpixel((x, y))
            if got == exp: ok += 1
            else:
                if first is None: first = (x, y, exp, got, hex(idx[y][x]))
                mism.append((x, y, exp, got))
    print(f"frame {shown} (rendered from its own dumps): {ok}/{W*H} pixels exact; first mismatch {first}")
    if os.environ.get("DIFF"):
        im = Image.new("RGB", (W, H))
        bad = set((m[0], m[1]) for m in mism)
        for y in range(H):
            for x in range(W):
                im.putpixel((x, y), (255, 0, 0) if (x, y) in bad else tuple(c // 3 for c in rtl.getpixel((x, y))))
        im.save(os.environ["DIFF"])
    if os.environ.get("LIST"):
        for m in mism[:60]: print("   ", m)
    return 0 if ok == W * H else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "gforce2"))
