#!/bin/sh
# M7 gate, the simulation half: every other Y Board game boots on the core
# and its attract mode matches MAME at frames 150 and 300 (the descriptor,
# DIP defaults and ROM stream come from tools/romsets.py, so the same table
# that makes the MRAs drives the bench). Two things are tolerated, both
# timing MAME cannot share with a live scan-out: palette entries the game
# ramps during the frame (one 5-bit step in one channel; MAME draws from
# the frame-end palette) and the pixels of things the game animates on
# its own clock, which a one- or two-frame boot offset puts out of phase
# (Power Drift's kart markers on the track map, G-LOC's scrolling HUD tape
# and blinking LOCK ON), up to 200 per frame, about 0.3% of the screen.
# Everything else has to be exact. Power Drift,
# G-LOC, G-LOC R360, Rail Chase and Strike Fighter; the clones share their
# parents' code paths and are covered by tools/tests (CRCs, stream layout).
# The hardware half (each game plays on its controls) is the user's.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PY=verif/.venv/bin/python
ZIPDIR="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
for SET in ${SETS:-pdrift gloc glocr360 rchase strkfgtr}; do
    G=verif/golden/$SET
    ZIP=$($PY -c "import sys; sys.path.insert(0, 'tools'); import romsets; print(romsets.ROMSETS['$SET']['zipfile'])")
    [ -f $G/ysprite.hex ] || $PY tools/pack_roms.py $SET --zip "$ZIPDIR/$ZIP.zip" --out /dev/null --hexdir $G >/dev/null
    for F in 150 300; do
        [ -f $G/f$F/frame.png ] || $PY tools/mame_capture.py $SET --frame $F --out $G/f$F >/dev/null
    done
    # descriptor and DIP defaults as plusargs, straight from the table
    PL=$($PY -c "
import sys; sys.path.insert(0, 'tools'); import romsets
r = romsets.ROMSETS['$SET']; a, b = r['dip_default'].split(',')
print(f\"+game_id={r['game_id']} +deluxe={r['deluxe']} +r360={r['r360']} +yspr_banks={r['yspr_banks']} +bspr_banks={r['bspr_banks']} +adc_reverse={r['adc_reverse']:02x} +ana_mode={r['ana_mode']} +dswa={a} +dswb={b}\")")
    echo "== $SET ($PL)"
    make -C verif/board run GAME=$SET FRAMES=305 PLUSARGS="$PL" 2>&1 | grep "SCANOUT" | tail -1
    $PY tools/frame_diff.py verif/board/out $G/f150 --window 16 --step-ok --max-far 200
    $PY tools/frame_diff.py verif/board/out $G/f300 --window 16 --step-ok --max-far 200
done
echo "M7 gate (simulation) passed"
