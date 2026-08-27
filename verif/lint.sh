#!/bin/sh
# Verilator -Wall lint of every module we own (vendored code gets only the
# waivers it needs). Run from the repo root: sh verif/lint.sh
# Add yb_core.sv and the board-level pass (see the X Board's lint.sh) once
# the board top exists.
set -e
cd "$(dirname "$0")/.."
W="-Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT -Wno-IMPORTSTAR -Wno-PINCONNECTEMPTY -DYB_Z80_TV80"
OWN="rtl/video/yb_video_timing.sv rtl/mem/sdram.sv rtl/mem/yb_rom_loader.sv rtl/mem/yb_dpram.sv \
  rtl/cpu/yb_math_5248.sv rtl/cpu/yb_math_5249.sv rtl/cpu/yb_cmptimer_5250.sv rtl/io/yb_ana_shape.sv \
  rtl/cpu/yb_rom_cache.sv rtl/audio/yb_segapcm_5218.sv rtl/mem/yb_fb_if.sv rtl/video/yb_palette_5242.sv"
# yb_pkg.sv, yb_m68k_bus.sv and yb_soundsys.sv only lint inside a board top.
for f in $OWN; do
  verilator --lint-only $W -Irtl/video rtl/yb_pkg.sv $f --top-module $(basename ${f%.*}) >/dev/null
done
echo "lint clean"
