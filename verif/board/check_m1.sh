#!/bin/sh
# M1 gate: the three 68000s track MAME's executed-PC trace over 120 frames
# (2 s). Thresholds reflect what MAME can validate: the remaining resyncs are
# cross-CPU handshakes on the shared RAM and interrupt placement.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/gforce2.zip"
G=verif/golden/gforce2

$PY -m pytest -q verif/unit/chips/test_io5296.py verif/unit/chips/test_msm6253.py
[ -f $G/trace_main_mame.txt ] || $PY tools/mame_trace.py gforce2 --seconds 2 --out $G
[ -f $G/main.hex ] || $PY tools/pack_roms.py gforce2 --zip "$ZIP" --out /dev/null --hexdir $G
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=120 >/dev/null 2>&1
for cpu in main subx suby; do
  $PY tools/trace_compare.py $G/trace_${cpu}_mame.txt verif/board/out/trace_${cpu}_pc.txt --max 2500000 --slack 1 --min-match 97 --max-resync 1000 | grep -v "^  resync"
done
# interrupt placement: IRQ2 and IRQ4 handler entries per CPU over the same
# instruction span (vectors 26 and 28 of each ROM). Once per frame on main
# and sub Y; sub X's IRQ4 handler returns inside the scanline and re-enters,
# so only its IRQ2 count is compared.
irqcount() { $PY tools/irq_entries.py "$1" --irq2 $2 --irq4 $3 ${4:+--max $4} | awk '{print $3}' | tr '\n' ' '; }
for spec in "main 001c30 001d76 2" "subx 009e7a 009e8a 1" "suby 013e92 013f72 2"; do
  set -- $spec; cpu=$1; v2=$2; v4=$3; nchk=$4
  n=$(wc -l < verif/board/out/trace_${cpu}_pc.txt | tr -d ' ')
  rtl=$(irqcount verif/board/out/trace_${cpu}_pc.txt $v2 $v4); mame=$(irqcount $G/trace_${cpu}_mame.txt $v2 $v4 $n)
  $PY - "$cpu" "$nchk" $rtl $mame <<'PYEOF'
import sys
cpu, nchk, r2, r4, m2, m4 = sys.argv[1], int(sys.argv[2]), *map(int, sys.argv[3:7])
ok = abs(r2 - m2) <= 2 and (nchk < 2 or abs(r4 - m4) <= 2)
print(f"{cpu}: irq2 rtl {r2} mame {m2}, irq4 rtl {r4} mame {m4}", "OK" if ok else "MISMATCH")
sys.exit(0 if ok else 1)
PYEOF
done
echo "M1 gate passed"
