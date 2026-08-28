#!/usr/bin/env python3
"""Record MAME's executed-PC trace for the Y Board 68000s.

    mame_trace.py gforce2 --seconds 2 --out verif/golden/gforce2

Runs MAME headless with a debugger script that traces the three CPUs from
reset, then keeps just the PC column so tools/trace_compare.py can check the
RTL's fetch stream against it.
"""
import argparse, os, subprocess, sys, tempfile

ROMPATH = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"
CPUS = (("main", "maincpu"), ("subx", "subx"), ("suby", "suby"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--seconds", type=float, default=2.0)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mame", default="mame")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    raws = {name: os.path.abspath(os.path.join(a.out, f"mame_trace_{name}.raw")) for name, _ in CPUS}
    script = os.path.join(a.out, "trace.dbg")
    with open(script, "w") as f:
        for name, tag in CPUS:
            f.write(f"trace {raws[name]},{tag},noloop\n")
        f.write("go\n")
    cmd = [a.mame, a.set, "-rompath", ROMPATH, "-debug", "-debugscript", script,
           "-window", "-sound", "none", "-nothrottle", "-seconds_to_run", str(int(a.seconds)),
           "-skip_gameinfo", "-nvram_directory", tempfile.mkdtemp(), "-cfg_directory", tempfile.mkdtemp(),
           "-debugger", "osx"]
    print(" ".join(cmd))
    subprocess.run(cmd, check=False)
    for name, _ in CPUS:
        n = 0
        with open(raws[name], errors="replace") as fi, open(os.path.join(a.out, f"trace_{name}_mame.txt"), "w") as fo:
            for line in fi:
                if len(line) > 7 and line[6] == ":":
                    fo.write(line[:6].lower() + "\n")
                    n += 1
        print(f"trace_{name}_mame.txt: {n} instructions")
    # keep the first 200k raw lines (with disassembly) for debugging
    for name, _ in CPUS:
        with open(raws[name], errors="replace") as fi, open(os.path.join(a.out, f"trace_{name}_mame_dis.txt"), "w") as fo:
            for i, line in enumerate(fi):
                if i >= 200000: break
                fo.write(line)
        os.remove(raws[name])


if __name__ == "__main__":
    main()
