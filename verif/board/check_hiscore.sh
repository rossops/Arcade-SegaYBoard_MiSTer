#!/bin/sh
# Hiscore restore/save path on Power Drift: the saved table (the 512-byte
# window after the backup RAM in the index 3 NVRAM file) is streamed in
# through the 16-bit ioctl path, the game boots and refills its table from
# ROM, hiscore.v puts the saved one back, then an OSD open and an index 3
# upload of the window read the same bytes back. Both checks must print PASS.
# Both fixtures are written here (verif/golden/ is not in git):
#   hs_cfg.bin  = tools/gen_mra.py hiscore_config("pdrift")
#   hs_dump.bin = the game's own default table (sub Y RAM at frame 300 in
#                 MAME) with every letter shifted by three
set -e
cd "$(dirname "$0")/../.."
mkdir -p verif/golden/pdrift
python3 - <<'PYEOF'
import sys; sys.path.insert(0, "tools"); import gen_mra, romsets
open("verif/golden/pdrift/hs_cfg.bin", "wb").write(gen_mra.hiscore_config(romsets.ROMSETS["pdrift"]))
open("verif/golden/pdrift/hs_dump.bin", "wb").write(bytes.fromhex(
    "025300000110000042582e000004000000010100018000000110000056444700010400010203030001700000011000004e525000020400010204020001600000011000005257440003040001020503000153000001100000554848000404010203020400014000000110000050445700000401020402050001350000011000004f464200010401020502060001300000011000004b555200020401020602070001250000011000004a475100030401020702080001200000011000005057580004040102080209000115000001100000574e4a000004010209020a000110000001100000502e4e00010301030203080001050000011000004c575200020302040204080001000000011000004b5044000303020502050800009500000110000042444a00040302060206080000900000011000002e2e2e00000302070207080000850000011000002e2e2e00010302080208080000800000011000002e2e2e00020302090209080000750000011000002e2e2e00030203020308080000700000011000002e2e2e0004020402030808"))
PYEOF
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board run GAME=pdrift FRAMES=${FRAMES:-70} PLUSARGS="+hiscore=$PWD/verif/golden/pdrift +hs_check=${HS_CHECK:-60} $(grep -o 'pdrift) P="[^"]*"' verif/board/check_m7.sh | sed 's/.*P="//; s/"$//')" 2>&1 | tee verif/board/out/hiscore.log | grep -E "HISCORE|ABORT" || true
grep -q "restore check.*PASS" verif/board/out/hiscore.log && grep -q "upload check.*PASS" verif/board/out/hiscore.log && echo "hiscore: PASS" || { echo "hiscore: FAIL"; exit 1; }
