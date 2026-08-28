#!/usr/bin/env python3
"""Derive a synthetic Y sprite list from a captured one, for the cases the
games never produce: a list loop (the last entry links back into the list),
hidden entries, zoom 0 (drawn at 1) and a zero-height entry. The renderer and
the model must agree on all of them.

    synth_ylist.py verif/golden/gforce2/f1000 verif/golden/gforce2/fsynth
"""
import os, shutil, sys


def words(p):
    b = open(p, "rb").read(); return [b[i] | (b[i + 1] << 8) for i in range(0, len(b), 2)]


def main(src, dst):
    os.makedirs(dst, exist_ok=True)
    s = words(os.path.join(src, "yspriteram.bin"))
    shutil.copy(os.path.join(src, "rotateram.bin"), os.path.join(dst, "rotateram.bin"))
    chain = []
    nxt = 0
    seen = bytearray(4096)
    while not (s[nxt * 8] & 0x8000) and not seen[nxt]:
        seen[nxt] = 1; chain.append(nxt); nxt = s[nxt * 8 + 7] & 0xfff
    assert len(chain) >= 8, "need a longer list"
    # hidden entries (both hide bits), a zoom-0 entry, a height-0 entry
    s[chain[2] * 8 + 0] |= 0x4000
    s[chain[3] * 8 + 0] |= 0x1000
    s[chain[4] * 8 + 5] = (s[chain[4] * 8 + 5] & ~0x7ff)
    s[chain[5] * 8 + 4] = 0
    # a bank beyond the ROM (wraps modulo the bank count): bank bits 3:0 + 8 on entry 6
    s[chain[6] * 8 + 2] = (s[chain[6] * 8 + 2] + 0x8000) & 0xffff
    # loop: the last entry links back to the third instead of the terminator
    s[chain[-1] * 8 + 7] = (s[chain[-1] * 8 + 7] & ~0xfff) | chain[2]
    with open(os.path.join(dst, "yspriteram.bin"), "wb") as f:
        f.write(bytes(b for w in s for b in (w & 0xff, w >> 8)))
    print(f"{dst}: {len(chain)} entries, loop {chain[-1]} -> {chain[2]}, hidden {chain[2]} {chain[3]}, zoom0 {chain[4]}, height0 {chain[5]}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
