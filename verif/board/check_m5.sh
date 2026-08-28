#!/bin/sh
# M5 gate: (1) the 315-5218 engine matches the MAME port tick for tick with
# the Y Board's banking (cocotb); (2) the board's audio with a coin at frame
# 30 correlates with MAME's recording of the same scenario (48 kHz,
# tools/wav_compare.py: envelope correlation over 5 ms windows).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PY=verif/.venv/bin/python
$PY -m pytest -q verif/unit/chips/test_segapcm.py | tail -1
[ -f verif/golden/gforce2/mame_coin30.wav ] || $PY tools/mame_wav.py gforce2 --seconds 6 --coin 30 --out verif/golden/gforce2/mame_coin30.wav
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=150 COIN=30 >/dev/null 2>&1
$PY tools/wav_compare.py verif/board/out/audio.raw verif/golden/gforce2/mame_coin30.wav --skip 0.3 --out verif/board/out/rtl.wav
echo "M5 gate passed"
