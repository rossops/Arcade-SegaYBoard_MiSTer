#!/bin/sh
# M6 gate, the simulation half: the controls and the test switch reach the
# game the way MAME's do. (1) The test switch pressed at frame 200 brings
# up the test menu, pixel-exact against MAME's frame 300 with the same
# press; (2) a coin at frame 30 and Start at 120 put the game on the Scene
# Select: the board's frame 394 is exact against the model rendered from
# its own dumps (taken as its render starts) and against MAME's frame 400,
# carousel included, which needs the lever to read centred through the
# MSM6253 (the M6 strobe-timing bug moved it). The hardware half (the DIP switches
# on the test menu, NVRAM surviving a power cycle, 30 minutes of attract
# without a watchdog reset, HDMI against the sim) is the user's.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PY=verif/.venv/bin/python
G=verif/golden/gforce2
[ -f $G/play400/frame.png ] || $PY tools/mame_capture.py gforce2 --frame 400 --coin 30 --start 120 --out $G/play400
[ -f $G/test300/frame.png ] || $PY tools/mame_capture.py gforce2 --frame 300 --test --test-frame 200 --out $G/test300
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=305 PLUSARGS="+test_from=200" >/dev/null 2>&1
$PY tools/frame_diff.py verif/board/out $G/test300 --window 8
make -C verif/board run FRAMES=420 COIN=30 PLUSARGS="+start=120" DUMPFRAME=394 >/dev/null 2>&1
$PY tools/board_check.py verif/board/out 394
$PY tools/frame_diff.py verif/board/out $G/play400 --window 16
echo "M6 gate (simulation) passed"
