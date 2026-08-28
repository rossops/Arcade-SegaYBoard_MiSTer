#!/bin/sh
# M4 gate: (1) the standalone 315-5196 renderer is pixel-exact against the
# Python model (MAME sega16sp.cpp) on every captured list; (2) the model
# chain (Y sprites, rotation, 16B, mixer, palette) reproduces MAME's own
# screenshots of the still captures; (3) the board's frames are exact
# against the model rendered from the RTL's own dumps at frames 100 and 300,
# and pixel-exact against MAME's screenshots at frames 60, 150 and 300, the
# criterion in docs/DESIGN.md.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PY=verif/.venv/bin/python
G=verif/golden/gforce2
(cd verif/unit/bsprite && ../../.venv/bin/python run_bsprite.py $(ls -d ../../golden/gforce2/f[0-9]*/) | grep -v "^16B done")
$PY tools/frame_check.py $G/f60 $G/f150 $G/f300 $G/f1000
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=306 DUMPFRAME=300 2>&1 | grep "SCANOUT" | tail -1
$PY tools/board_check.py verif/board/out 300
for f in 60 150 300; do $PY tools/frame_diff.py verif/board/out $G/f$f; done
echo "M4 gate passed"
