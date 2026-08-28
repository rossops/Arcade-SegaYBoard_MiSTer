#!/bin/sh
# M2 gate: (1) the standalone 315-5305 renderer is pixel-exact against the
# Python model (a port of MAME sega16sp.cpp) on every captured sprite list;
# (2) the whole board's frame 101 is pixel-exact against the model rendered
# from the RTL's own RAM dumps at frame 100 (renderer + framebuffer +
# translation scan-out + palette + pipeline).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/gforce2.zip"
[ -f verif/golden/gforce2/ysprite.hex ] || $PY tools/pack_roms.py gforce2 --zip "$ZIP" --out /dev/null --hexdir verif/golden/gforce2
n=0; for d in verif/golden/gforce2/f*/; do [ -f "$d/yspriteram.bin" ] && n=$((n+1)); done
[ "$n" -ge 20 ] || { echo "need 20 captured lists in verif/golden/gforce2/f*/ (tools/mame_capture.py), have $n"; exit 1; }
(cd verif/unit/ysprite && ../../.venv/bin/python run_ysprite.py $(ls -d ../../golden/gforce2/f*/) | grep -v "^render done")
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=102 DUMPFRAME=100 >/dev/null 2>&1
$PY tools/board_check.py verif/board/out 100
echo "M2 gate passed"
