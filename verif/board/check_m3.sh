#!/bin/sh
# M3 gate: (1) the standalone 315-5306 scan-out is pixel-exact against the
# model (MAME's rotate_draw) on every captured rotation RAM, fed with the
# framebuffer the model renders from the same capture, and its worst DDR3
# misses per line stay under the budget in docs/DESIGN.md; (2) the board's
# frame 101 is pixel-exact against the model rendered from the RTL's own
# dumps through the full affine scan-out, with no line missing its deadline.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PY=verif/.venv/bin/python
(cd verif/unit/rotate && ../../.venv/bin/python run_rotate.py $(ls -d ../../golden/gforce2/f[0-9]*/))
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=102 DUMPFRAME=100 2>&1 | grep "SCANOUT" | tail -1 | tee verif/board/out/scanout.txt
grep -q "late lines so far=0" verif/board/out/scanout.txt
$PY tools/board_check.py verif/board/out 100
echo "M3 gate passed"
