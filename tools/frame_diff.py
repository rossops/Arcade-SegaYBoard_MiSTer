#!/usr/bin/env python3
"""Compare the RTL's frames with a MAME screenshot.

    frame_diff.py verif/board/out verif/golden/gforce2/f300 [--window 4] [--diff out.png] [--layer16b] [--static DIR] [--min N] [--step-ok [--max-far N]]

MAME's frame N (the capture's frame.txt) and the RTL's frame N are not the
same frame: the two count from different resets and the RTL shows a render
one frame after MAME does. The RTL frames N-window..N+window are compared
and the best one reported; exact agreement on a still scene is the M4
criterion, and the offset that gives it is printed. --layer16b restricts
the comparison to the pixels the 16B layer owns in the capture (from its
dumps through the models): the text and frames of a menu, when the Y layer
behind it is an animation whose phase depends on the game's own state.
--static DIR restricts it further to the pixels that are identical between
the capture and a second capture one frame later (DIR): the parts of the
screen that do not animate at all. --min N passes when at least N of the
compared pixels are equal (a screen reached, when its animation is game
state the two runs do not share) instead of demanding all of them.
"""
import os, sys
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verif"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def layer16b_mask(capdir, setname="gforce2"):
    import zipfile
    from models import ysprite5305 as ys, rotate5306 as rt, bsprite5196 as bs, mixer5312 as mx
    from romsets import ROMSETS
    def words(p):
        b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]
    rs = ROMSETS[setname]
    zf = zipfile.ZipFile(os.path.join("/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)", rs["zipfile"] + ".zip"))
    rotf = "rotateram_swap.bin" if os.path.exists(os.path.join(capdir, "rotateram_swap.bin")) else "rotateram.bin"
    fb = ys.render(words(os.path.join(capdir, "yspriteram.bin")), words(os.path.join(capdir, rotf)),
                   ys.load_rom_qwords(zf, [f[0] for f in rs["regions"]["ysprite"][1]]), rs["yspr_banks"])
    yidx, ypri = rt.scanout(fb, words(os.path.join(capdir, rotf)), 320, 224)
    bfb = bs.render(words(os.path.join(capdir, "bspriteram.bin")), bs.load_rom_words(zf, [f[0] for f in rs["regions"]["bsprite"][1]]), rs["bspr_banks"])
    return [[bfb[y][x] != 0xFFFF and ((bfb[y][x] >> 11) & 0x1e) < (ypri[y][x] & 0x1f) for x in range(320)] for y in range(224)]


def near(a, b):
    # one 5-bit palette step in a single channel: a palette entry the game was
    # ramping while the frame was scanned (MAME draws from the frame-end palette)
    d = [abs(x - y) for x, y in zip(a, b)]
    return sum(1 for v in d if v) == 1 and max(d) <= 9


def main(outdir, capdir, window=4, diff=None, layer16b=False, static=None, minimum=None, step_ok=False, max_far=0):
    mame = Image.open(os.path.join(capdir, "frame.png")).convert("RGB")
    mask = layer16b_mask(capdir) if layer16b else [[True] * 320 for _ in range(224)]
    if static:
        other = Image.open(os.path.join(static, "frame.png")).convert("RGB")
        mask = [[mask[y][x] and mame.getpixel((x, y)) == other.getpixel((x, y)) for x in range(320)] for y in range(224)]
    total = sum(1 for y in range(224) for x in range(320) if mask[y][x])
    n = int(open(os.path.join(capdir, "frame.txt")).read().split()[0])
    best = None
    for f in range(max(0, n - window), n + window + 1):
        p = os.path.join(outdir, f"frame_{f:04d}.ppm")
        if not os.path.exists(p):
            continue
        rtl = Image.open(p).convert("RGB")
        ok = sum(1 for y in range(224) for x in range(320) if mask[y][x] and rtl.getpixel((x, y)) == mame.getpixel((x, y)))
        if best is None or ok > best[0]:
            best = (ok, f, rtl)
    if best is None:
        print(f"{capdir}: no RTL frames around {n} in {outdir}"); return 1
    ok, f, rtl = best
    what = ("static " if static else "") + ("16B-layer pixels" if layer16b else "pixels")
    if step_ok:
        # --step-ok: one-step differences are counted apart and tolerated; the
        # pass needs at most max_far pixels differing by more than that
        nnear = sum(1 for y in range(224) for x in range(320) if mask[y][x] and rtl.getpixel((x, y)) != mame.getpixel((x, y)) and near(rtl.getpixel((x, y)), mame.getpixel((x, y))))
        far = total - ok - nnear
        first = next(((x, y, rtl.getpixel((x, y)), mame.getpixel((x, y))) for y in range(224) for x in range(320)
                      if mask[y][x] and rtl.getpixel((x, y)) != mame.getpixel((x, y)) and not near(rtl.getpixel((x, y)), mame.getpixel((x, y)))), None)
        print(f"{capdir}: MAME frame {n} vs RTL frame {f} (offset {f - n:+d}): {ok}/{total} {what} equal, {nnear} one palette step off, {far} further (allowed {max_far}); first further difference {first}")
        return 0 if far <= max_far else 1
    first = next(((x, y, rtl.getpixel((x, y)), mame.getpixel((x, y))) for y in range(224) for x in range(320)
                  if mask[y][x] and rtl.getpixel((x, y)) != mame.getpixel((x, y))), None)
    print(f"{capdir}: MAME frame {n} vs RTL frame {f} (offset {f - n:+d}): {ok}/{total} {what} equal; first difference {first}")
    if diff:
        d = Image.new("RGB", (320, 224))
        for y in range(224):
            for x in range(320):
                d.putpixel((x, y), (255, 0, 0) if rtl.getpixel((x, y)) != mame.getpixel((x, y)) else tuple(c // 3 for c in mame.getpixel((x, y))))
        d.save(diff)
    return 0 if ok >= (total if minimum is None else minimum) else 1


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    window = int(sys.argv[sys.argv.index("--window") + 1]) if "--window" in sys.argv else 4
    diff = sys.argv[sys.argv.index("--diff") + 1] if "--diff" in sys.argv else None
    static = sys.argv[sys.argv.index("--static") + 1] if "--static" in sys.argv else None
    minimum = int(sys.argv[sys.argv.index("--min") + 1]) if "--min" in sys.argv else None
    max_far = int(sys.argv[sys.argv.index("--max-far") + 1]) if "--max-far" in sys.argv else 0
    args = [a for a in args if a != diff and a != str(window) and a != static and a != str(minimum) and a != str(max_far)]
    raise SystemExit(main(args[0], args[1], window, diff, "--layer16b" in sys.argv, static, minimum, "--step-ok" in sys.argv, max_far))
