#!/bin/sh
# M0 gate: the trimmed scaffold lints and elaborates against the framework,
# the gforce2 MRA reproduces the packer's stream byte for byte, releases/ is
# what the generator emits, and the stub board bench runs a few frames.
# The Quartus fit and STA half of the gate is checked on the Windows box.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/gforce2.zip"

sh verif/lint.sh
sh verif/lint_emu.sh
$PY -m pytest -q tools/tests

TMP=$(mktemp -d)
$PY tools/gen_mra.py --outdir "$TMP" >/dev/null
diff -r -x .gitkeep "$TMP" releases
rm -rf "$TMP"

[ -f verif/golden/gforce2/main.hex ] || $PY tools/pack_roms.py gforce2 --zip "$ZIP" --out /dev/null --hexdir verif/golden/gforce2
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=3 >/dev/null 2>&1
[ -f verif/board/out/frame_0002.ppm ] || { echo "bench produced no frame"; exit 1; }
echo "M0 gate passed"
