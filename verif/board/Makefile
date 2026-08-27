# Verilator board simulation. From repo root: make -C verif/board run FRAMES=10
ROOT := $(abspath ../..)
SRCS := rtl/yb_pkg.sv rtl/video/yb_video_timing.sv rtl/mem/yb_dpram.sv \
  rtl/cpu/yb_math_5248.sv rtl/cpu/yb_math_5249.sv rtl/cpu/yb_cmptimer_5250.sv \
  rtl/io/yb_ana_shape.sv rtl/cpu/yb_rom_cache.sv rtl/cpu/yb_m68k_bus.sv \
  rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv \
  rtl/audio/yb_segapcm_5218.sv rtl/audio/yb_soundsys.sv rtl/mem/yb_fb_if.sv rtl/video/yb_palette_5242.sv \
  rtl/yb_core.sv verif/board/sdram_model.sv verif/board/ddram_model.sv verif/board/tb_board.sv
# tb_board.sv is the X Board bench (plusargs, frame dumps, RENDER prints): rewrite
# it against yb_core; the golden hex links in `run` follow the Y Board ROM regions.
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

run: obj_dir/Vtb_board
	mkdir -p out/verif && rm -f out/frame_*.ppm && ln -sfn $(ROOT)/verif/golden out/verif/golden; \
	ln -sf $(ROOT)/verif/golden/$(GAME)/roadrom.hex out/roadrom.hex; ln -sf $(ROOT)/verif/golden/$(GAME)/keyrom.hex out/keyrom.hex; ln -sf $(ROOT)/rtl/cpu/fx68k/microrom.mem out/microrom.mem; ln -sf $(ROOT)/rtl/cpu/fx68k/nanorom.mem out/nanorom.mem; \
	for p in 0 1 2; do ln -sf $(ROOT)/verif/golden/$(GAME)/tilerom$$p.hex out/tilerom$$p.hex; done; \
	cd out && ../obj_dir/Vtb_board +frames=$(FRAMES) +tilerom +roadrom +dumpframe=$(DUMPFRAME) +coin=$(COIN) +hexdir=verif/golden/$(GAME) $(PLUSARGS)

clean:
	rm -rf obj_dir out
