#!/usr/bin/env python3
"""Capture MAME Y Board video RAM dumps and a screenshot at a given frame.

    mame_capture.py gforce2 --frame 300 --out verif/golden/gforce2/f300 [--test]

--test starts the game in service/test mode (DIP). The snapshot is written by
MAME into the output directory as <setname>/0000.png and moved to frame.png.
"""
import argparse, glob, os, shutil, subprocess, tempfile

ROMPATH = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--frame", type=int, default=300)
    ap.add_argument("--out", required=True)
    ap.add_argument("--test", action="store_true", help="service mode on (test switch held)")
    ap.add_argument("--coin", type=int, help="press Coin 1 for four frames from this frame")
    ap.add_argument("--test-frame", type=int, default=1, help="with --test: hold the test switch from this frame")
    ap.add_argument("--start", type=int, help="press 1 Player Start for four frames from this frame")
    ap.add_argument("--mame", default="mame")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    env = dict(os.environ, YB_FRAME=str(a.frame), YB_OUT=out)
    cfg = tempfile.mkdtemp()
    cmd = [a.mame, a.set, "-rompath", ROMPATH, "-window", "-sound", "none", "-nothrottle",
           "-skip_gameinfo", "-snapshot_directory", out, "-nvram_directory", tempfile.mkdtemp(),
           "-cfg_directory", cfg, "-autoboot_script", os.path.join(HERE, "mame_capture.lua"),
           "-seconds_to_run", str(a.frame // 60 + 5)]
    if a.coin is not None: env["YB_COIN"] = str(a.coin)
    if a.start is not None: env["YB_START"] = str(a.start)
    env["YB_TEST_FRAME"] = str(a.test_frame)
    if a.test:
        # MAME's generic "Service Mode" toggle is the F2 key; simplest is a
        # cfg file that maps the test switch... use the built-in dip override:
        cmd += ["-noautosave"]
        env["YB_TEST"] = "1"
    subprocess.run(cmd, env=env, check=False)
    pngs = sorted(glob.glob(os.path.join(out, a.set, "*.png")))
    if pngs:
        shutil.move(pngs[-1], os.path.join(out, "frame.png"))
        shutil.rmtree(os.path.join(out, a.set), ignore_errors=True)
    print(out, os.listdir(out))


if __name__ == "__main__":
    main()
