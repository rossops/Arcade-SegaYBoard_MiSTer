# Sega Y Board core — working notes for Claude

This repo started on 2026-08-27 as a copy of the reusable half of the X Board
core, `/Volumes/roms/Arcade-SegaXBoard_MiSTer` (GitHub rossops/Arcade-SegaXBoard_MiSTer,
also MiSTer-devel/Arcade-SegaXBoard_MiSTer). Read that repo's `docs/DESIGN.md`
and `README.md` before designing anything: it is the worked example of every
convention below, and its git history shows what each decision cost.

## What is here and what is not
- `docs/references.md` lists every carried-over file. `yb_` used to be `xb_`.
- M0 (branch `m0-scaffold`) trimmed the scaffold: `rtl/yb_pkg.sv`,
  `Arcade-SegaYBoard.sv`, `verif/board/tb_board.sv`, the ROM loader and the
  tools carry the Y Board map, stream and descriptor; `rtl/yb_core.sv` is a
  stub with the final port list and a gradient on the real video timing;
  `tools/romsets.py` has `gforce2`. M1 (branch `m1-cpus`) filled `yb_core`
  with the three 68000s, every CPU-side RAM, the shared-RAM arbiter, the
  math chips, `rtl/io/yb_315_5296.sv` and `rtl/io/yb_msm6253.sv` (golden
  models in `verif/models/`), the scanline IRQs, watchdog and sound latch;
  `tools/mame_trace.py` traces three CPUs and `verif/board/check_m1.sh` is
  the gate. M2 (branch `m2-ysprites`) added `rtl/video/yb_ysprite_5305.sv`
  rendering into the DDR3 framebuffers (`yb_fb_if`, now 512-line buffers)
  with a translation-only scan-out through the palette; golden model
  `verif/models/ysprite5305.py` (render + full and translate-only scanout),
  standalone harness `verif/unit/ysprite/`, MAME dumps via
  `tools/mame_capture.py` into `verif/golden/gforce2/f<N>/`, board check
  `tools/board_check.py`, gate `verif/board/check_m2.sh`. M3 (branch
  `m3-rotation`) added `rtl/video/yb_rotate_5306.sv` (affine scan-out with
  a 128-word DDR3 cache, `verif/unit/rotate/` harness, `verif/models/
  rotate5306.py`, gate `verif/board/check_m3.sh`). M4 (branch `m4-bsprites`)
  added `rtl/video/yb_bsprite_5196.sv` (line-based, private list copy) and
  the 315-5312 mixer in `yb_core`; models `bsprite5196.py`, `mixer5312.py`;
  `tools/frame_check.py` (models vs MAME screenshots), `tools/frame_diff.py`
  (RTL vs MAME screenshots), harness `verif/unit/bsprite/`, gate
  `verif/board/check_m4.sh`. M5 (branch `m5-sound`) wired `yb_soundsys`
  (Z80, YM2151, 315-5218 with the Y Board banking: shift 13, mask F8) to
  the latch NMI, `/SRES` and `/MUTE`; gate `verif/board/check_m5.sh` (PCM
  vs `segapcm.py`, WAV envelope vs MAME's `mame_coin30.wav`). Not written yet: the sound board wiring (M5), the analog modes for
  the games other than Galaxy Force II (M7).
- `sys/` is MiSTer-devel's Template, byte for byte. Never edit it; update it by
  copying the template again. Keep `.qsf` deviations from Template.qsf to the
  handful that are listed in a comment at the top of the file.

## How the work goes
- The plan is `docs/DESIGN.md`: hardware reference from MAME, memory
  placement, module list, milestones M0..M7 with a pass criterion and a gate
  script each (`verif/board/check_mN.sh`), and the open questions. Start at
  M0. Update the README status table as milestones close.
- Every custom chip gets a Python golden model ported from MAME, a cocotb unit
  test, and a place in the Verilator board bench that dumps frames to diff
  against MAME captures (`tools/mame_capture.py`, `tools/frame_diff.py`).
  Unit benches are not enough for board-level sequencing: an X Board CDC bug
  only showed in the board check.
- Simulation runs on this Mac (Verilator 5, Icarus, cocotb in `verif/.venv`,
  Python 3.12; MAME 0.289 at `/opt/homebrew/bin/mame`; MAME source at
  `~/Code/mame`; merged ROM zips in `/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/`).
- Quartus 17.0.2 Lite runs on a Windows box the user drives: they run
  `build.bat` on this share, it compiles whatever is checked out here (the
  Windows box has no git), so check out the branch you want built. Watch
  `output_files/` with `find -newermt <start>` rather than trusting timestamps
  of old files. Read the M10K block row in `fit.rpt`, not the bit count; the
  X Board sat at 488/553.
- Upload with `tools/mister_ssh.sh put|run` (DE10-Nano at 192.168.1.63, root;
  password known to the user). MiSTer opens clone zips literally, so ship split
  clone zips (`tools/make_clone_zips.py`), not merged ones.
- The user tests every build on hardware before its `.rbf` is committed.
  Do not commit, merge or push unless told to. One branch per milestone,
  fast-forward merge into `main` on the user's word, then `tools/make_db.py`
  and push to every remote.

## Conventions
- `releases/` is generated: `tools/gen_mra.py` from `tools/romsets.py`, every
  `<part>` with its `crc`, alternatives under `releases/_alternatives/_<Game>/`.
  CI diffs the tree against the generator and runs MiSTer-devel's
  `mra_rom_check.sh`. Never hand-edit an MRA.
- Commit messages, docs and anything customer facing are written in plain
  conversational English (the user's Humanizer rules); no bullet-point
  cheerleading, no "delve".
- Verilator: `-Werror-PINMISSING` in the bench (a missing port is silent
  otherwise); `sh verif/lint.sh` before every commit.
- Quartus 17 quirks worth remembering: no untyped aggregate localparams (use
  case functions), no inference of two-clock byte-enabled RAMs (explicit
  altsyncram, `read_during_write_mode_port_a NEW_DATA_NO_NBE_READ`), MLAB
  placement can break hold on DDR3 read data (`ram_block_type = "M10K"`).
- fx68k: UDS/LDS come one state after AS on writes; the main CPU's RESET
  instruction resets the others (MAME's reset callback). Exact PC traces
  follow the prefetch queue, see the X Board `tools/mame_trace.py` notes.
- Meathax's System 32 core (`/Volumes/roms/s32`) is where `sdram.sv` and the
  framebuffer interface came from. Credit it; never describe the user as its
  author.
