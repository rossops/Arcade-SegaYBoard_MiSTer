#!/bin/sh
# Elaborate the MiSTer emu top against the real framework modules with
# Verilator. Catches port-list mismatches and multiply-driven nets that only
# Quartus would otherwise report (unlike verif/lint.sh this is not -Wall).
# Fails until rtl/yb_core.sv exists and Arcade-SegaYBoard.sv is trimmed to it.
set -e
cd "$(dirname "$0")/.."
verilator --lint-only -DSIMULATION --top-module emu -DYB_Z80_TV80 -Isys -Irtl/video \
  -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT \
  -Wno-IMPORTSTAR -Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
  -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-UNOPTFLAT \
  -Wno-CASEOVERLAP -Wno-LATCH -Wno-SYNCASYNCNET -Wno-COMBDLY -Wno-INITIALDLY \
  -Wno-ASCRANGE -Wno-LITENDIAN -Wno-PROCASSWIRE -Wno-IMPLICIT -Wno-IMPLICITSTATIC -Wno-CASEX \
  verif/fx68k.vlt rtl/yb_pkg.sv rtl/video/yb_video_timing.sv rtl/mem/sdram.sv \
  rtl/mem/yb_rom_loader.sv rtl/mem/yb_dpram.sv rtl/cpu/yb_math_5248.sv rtl/cpu/yb_math_5249.sv \
  rtl/io/yb_ana_shape.sv rtl/io/yb_315_5296.sv rtl/io/yb_msm6253.sv rtl/cpu/yb_rom_cache.sv rtl/cpu/yb_m68k_bus.sv \
  rtl/audio/yb_segapcm_5218.sv rtl/audio/yb_soundsys.sv rtl/audio/jt51/*.v verif/board/tv80/*.v \
  rtl/mem/yb_fb_if.sv rtl/video/yb_palette_5242.sv \
  rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv rtl/yb_core.sv rtl/pll.v \
  sys/hps_io.sv sys/arcade_video.v sys/video_freak.sv sys/scandoubler.v \
  sys/scanlines.v sys/gamma_corr.sv sys/video_cleaner.sv sys/video_mixer.sv \
  sys/hq2x.sv sys/math.sv sys/sys_top.v \
  Arcade-SegaYBoard.sv
echo "emu elaborates"
