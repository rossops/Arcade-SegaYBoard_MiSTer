# Sega Y Board core — working notes for Claude

This repo started on 2026-08-27 as a copy of the reusable half of the X Board
core, `/Volumes/roms/Arcade-SegaXBoard_MiSTer` (GitHub rossops/Arcade-SegaXBoard_MiSTer,
also MiSTer-devel/Arcade-SegaXBoard_MiSTer). Read that repo's `docs/DESIGN.md`
and `README.md` before designing anything: it is the worked example of every
convention below, and its git history shows what each decision cost.

## What is here and what is not
- `docs/references.md` lists every carried-over file. `yb_` used to be `xb_`.
- Not written yet: `rtl/yb_core.sv`, the 315-5305 sprite generator and the
  315-5306 rotation, the 16B sprite layer, the mixer, the 315-5296 I/O chip,
  the ADC, the three-CPU bus. `Arcade-SegaYBoard.sv`, `rtl/yb_pkg.sv` and
  `verif/board/tb_board.sv` are the X Board versions and need trimming.
  `tools/romsets.py` is empty; `tools/pack_roms.py`'s `descriptor()` still
  packs the X Board flags.
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
