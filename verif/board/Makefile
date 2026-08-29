# Verilator board simulation. From repo root: make -C verif/board run FRAMES=10
ROOT := $(abspath ../..)
SRCS := rtl/yb_pkg.sv rtl/video/yb_video_timing.sv rtl/mem/yb_dpram.sv \
  rtl/cpu/yb_math_5248.sv rtl/cpu/yb_math_5249.sv \
  rtl/io/yb_ana_shape.sv rtl/io/yb_315_5296.sv rtl/io/yb_msm6253.sv rtl/cpu/yb_rom_cache.sv rtl/cpu/yb_m68k_bus.sv \
  rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv \
  rtl/audio/yb_segapcm_5218.sv rtl/audio/yb_soundsys.sv rtl/mem/yb_fb_if.sv rtl/video/yb_palette_5242.sv rtl/video/yb_ysprite_5305.sv rtl/video/yb_rotate_5306.sv rtl/video/yb_bsprite_5196.sv \
  rtl/yb_core.sv verif/board/sdram_model.sv verif/board/ddram_model.sv verif/board/tb_board.sv
VFLAGS := -Wno-fatal -Wno-lint -Wno-style -Werror-PINMISSING -Wno-BLKANDNBLK -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
  -DSIMULATION -DYB_Z80_TV80 --timing -O2 --x-assign fast --x-initial fast \
  --no-assert-case --top-module tb_board -I$(ROOT)/rtl/cpu/fx68k -I$(ROOT)/rtl/video
FRAMES ?= 10
DUMPFRAME ?= -1
COIN ?= -1
PLUSARGS ?=
GAME ?= gforce2

EXTRA := $(wildcard $(ROOT)/rtl/audio/jt51/*.v) $(wildcard $(ROOT)/verif/board/tv80/*.v)

obj_dir/Vtb_board: $(addprefix $(ROOT)/,$(SRCS)) $(EXTRA) main.cpp
	verilator $(VFLAGS) --cc --exe --build -j 4 $(addprefix $(ROOT)/,$(SRCS)) $(EXTRA) main.cpp -o Vtb_board

build: obj_dir/Vtb_board

# the SDRAM model reads verif/golden/$(GAME)/<region>.hex (tools/pack_roms.py --hexdir)
# the share keep-alive (tools/keepalive.sh) runs for the duration of every run
run: obj_dir/Vtb_board
	mkdir -p out/verif && rm -f out/frame_*.ppm && ln -sfn $(ROOT)/verif/golden out/verif/golden; \
	ln -sf $(ROOT)/rtl/cpu/fx68k/microrom.mem out/microrom.mem; ln -sf $(ROOT)/rtl/cpu/fx68k/nanorom.mem out/nanorom.mem; \
	sh $(ROOT)/tools/keepalive.sh $(ROOT) & KA=$$!; \
	(cd out && ../obj_dir/Vtb_board +frames=$(FRAMES) +dumpframe=$(DUMPFRAME) +coin=$(COIN) +hexdir=verif/golden/$(GAME) $(PLUSARGS)); RC=$$?; \
	kill $$KA 2>/dev/null; wait $$KA 2>/dev/null; exit $$RC

clean:
	rm -rf obj_dir out
