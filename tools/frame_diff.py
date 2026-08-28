#!/usr/bin/env python3
"""Compare the RTL's frames with a MAME screenshot.

    frame_diff.py verif/board/out verif/golden/gforce2/f300 [--window 4] [--diff out.png]

MAME's frame N (the capture's frame.txt) and the RTL's frame N are not the
same frame: the two count from different resets and the RTL shows a render
one frame after MAME does. The RTL frames N-window..N+window are compared
and the best one reported; exact agreement on a still scene is the M4
criterion, and the offset that gives it is printed.
"""
import os, sys
from PIL import Image


def main(outdir, capdir, window=4, diff=None):
    mame = Image.open(os.path.join(capdir, "frame.png")).convert("RGB")
    n = int(open(os.path.join(capdir, "frame.txt")).read().split()[0])
    best = None
    for f in range(max(0, n - window), n + window + 1):
        p = os.path.join(outdir, f"frame_{f:04d}.ppm")
        if not os.path.exists(p):
            continue
        rtl = Image.open(p).convert("RGB")
        ok = sum(1 for y in range(224) for x in range(320) if rtl.getpixel((x, y)) == mame.getpixel((x, y)))
        if best is None or ok > best[0]:
            best = (ok, f, rtl)
    if best is None:
        print(f"{capdir}: no RTL frames around {n} in {outdir}"); return 1
    ok, f, rtl = best
    first = next(((x, y, rtl.getpixel((x, y)), mame.getpixel((x, y))) for y in range(224) for x in range(320)
                  if rtl.getpixel((x, y)) != mame.getpixel((x, y))), None)
    print(f"{capdir}: MAME frame {n} vs RTL frame {f} (offset {f - n:+d}): {ok}/{320*224} pixels equal; first difference {first}")
    if diff:
        d = Image.new("RGB", (320, 224))
        for y in range(224):
            for x in range(320):
                d.putpixel((x, y), (255, 0, 0) if rtl.getpixel((x, y)) != mame.getpixel((x, y)) else tuple(c // 3 for c in mame.getpixel((x, y))))
        d.save(diff)
    return 0 if ok == 320 * 224 else 1


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    window = int(sys.argv[sys.argv.index("--window") + 1]) if "--window" in sys.argv else 4
    diff = sys.argv[sys.argv.index("--diff") + 1] if "--diff" in sys.argv else None
    raise SystemExit(main(args[0], args[1], window, diff))
