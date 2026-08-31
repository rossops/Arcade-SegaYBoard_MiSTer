# Sega Y Board for MiSTer FPGA

MiSTer core for Sega's Y Board arcade hardware, the three-68000 sprite
scaler behind Galaxy Force II, Power Drift, G-LOC, Rail Chase and Strike
Fighter. The aim is a simulation of the actual board, not a
re-implementation of the games: three 68000s on a shared RAM, a Z80, the
315-5305 Y sprite generator with its double framebuffer, the 315-5306
rotation scan-out, the 315-5196 16B sprite generator, the 315-5312 mixer,
the 315-5242 palette, three pairs of 315-5248/5249 math chips, the
315-5296 I/O chip with an MSM6253 ADC behind it, an MB3773 watchdog, a
YM2151 and a 315-5218 PCM chip.

## Status

| Milestone | What it proves | State |
| --- | --- | --- |
| M0 | Skeleton compiles, MRA/stream tools agree with MAME CRCs | done 2026-08-27, 69/553 M10K, gradient on hardware |
| M1 | Three 68000s boot, shared RAM, math/IO/ADC chips pass unit tests, PC traces track MAME | done 2026-08-27, 415/553 M10K, traces 99.7% vs MAME on all three CPUs, boots on hardware |
| M2 | 315-5305 Y sprites into DDR3, palette, indirection | done 2026-08-28, 423/553 M10K, model exact on 20 captured lists, Y layer on hardware |
| M3 | 315-5306 rotation scan-out with a DDR3 word cache | done 2026-08-28, 423/553 M10K, exact on 20 captured parameter sets, rotates on hardware |
| M4 | 315-5196 16B sprites and the 315-5312 mixer | done 2026-08-28, 429/553 M10K, frames pixel-exact vs MAME, attract complete on hardware |
| M5 | Sound (Z80, YM2151, 315-5218 with the Y Board banking) | done 2026-08-28, 441/553 M10K, audio envelope 0.969 vs MAME's recording, music and samples on hardware |
| M6 | Hardware bring-up: controls, NVRAM, DIPs, timing | done 2026-08-28, 441/553 M10K, test menu and Scene Select pixel-exact vs MAME, controls and 30 minutes of attract on hardware |
| M7 | Power Drift, G-LOC, G-LOC R360, Rail Chase, Strike Fighter | done 2026-08-29, 441/553 M10K, all five attract modes match MAME at frames 150 and 300 (Rail Chase and Strike Fighter exact); two shared-RAM arbiter fixes came out of the hardware round |
| after | Power Drift's gear indicator (MAME's shifter overlay), wheel travel, "Stick re-center" option | done 2026-08-30, 442/553 M10K, confirmed on hardware (v1.1.1) |
| open | `pdriftl` (the link board), the Power Drift golden-model mismatch (open question 12), Strike Fighter on hardware | see `docs/DESIGN.md` |

## Fully playable games

One MRA per game sits in `releases/` (installed as `_Arcade/<game>.mra`);
the other versions of each game are under `releases/_alternatives/_<game>/`,
the standard MiSTer layout, and show up in the Arcade menu's alternatives
folder.

| Game | MAME set | ROM zips (MAME 0.289) | Controls |
|---|---|---|---|
| Galaxy Force II | `gforce2` | `gforce2.zip` | flight stick, throttle |
| Galaxy Force II (Super Deluxe unit) | `gforce2sd` | `gforce2.zip` + `gforce2sd.zip` | flight stick, throttle |
| Galaxy Force II (Japan, Rev A) | `gforce2ja` | `gforce2.zip` + `gforce2ja.zip` | flight stick, throttle |
| Galaxy Force II (Japan) | `gforce2j` | `gforce2.zip` + `gforce2j.zip` | flight stick, throttle |
| Power Drift | `pdrift` | `pdrift.zip` | wheel, pedals, gear shift |
| Power Drift (World) | `pdrifta` | `pdrift.zip` + `pdrifta.zip` | wheel, pedals, gear shift |
| Power Drift (World, Earlier) | `pdrifte` | `pdrift.zip` + `pdrifte.zip` | wheel, pedals, gear shift |
| Power Drift (Japan, Rev C) | `pdriftj` | `pdrift.zip` + `pdriftj.zip` | wheel, pedals, gear shift |
| Power Drift (Japan, Rev B) | `pdriftjb` | `pdrift.zip` + `pdriftjb.zip` | wheel, pedals, gear shift |
| G-LOC Air Battle | `gloc` | `gloc.zip` | flight stick, throttle |
| G-LOC Air Battle (Japan) | `glocj` | `gloc.zip` + `glocj.zip` | flight stick, throttle |
| G-LOC Air Battle (US) | `glocu` | `gloc.zip` + `glocu.zip` | flight stick, throttle |
| G-LOC R360 | `glocr360` | `gloc.zip` + `glocr360.zip` | flight stick, throttle |
| G-LOC R360 (Japan) | `glocr360j` | `gloc.zip` + `glocr360j.zip` | flight stick, throttle |
| Rail Chase | `rchase` | `rchase.zip` | two lightguns or gamepad cursors |
| Rail Chase (Japan) | `rchasej` | `rchase.zip` + `rchasej.zip` | two lightguns or gamepad cursors |
| Rail Chase (Japan, Rev B) | `rchasejb` | `rchase.zip` + `rchasejb.zip` | two lightguns or gamepad cursors |
| Strike Fighter | `strkfgtr` | `strkfgtr.zip` | flight stick, throttle |
| Strike Fighter (Japan) | `strkfgtrj` | `strkfgtr.zip` + `strkfgtrj.zip` | flight stick, throttle |

Every game has been played on a DE10-Nano except Strike Fighter, which so
far is verified pixel-exact against MAME in simulation only. `gforce2ja`
and `rchasej` are generated from MAME's ROM tables but could not be
checked against a local ROM set. The link version of Power Drift
(`pdriftl`) is not supported.

## Controls and options

Player 1's left stick is the flight stick, wheel or gun; the right stick's
Y axis is the throttle or gas and brake, with Speed Up/Slow Down or
Gas/Brake buttons as the digital alternative. Power Drift's gear shift is
one button, a toggle like the cabinet's, and its wheel slews toward the
stick at about 0.4 seconds lock to lock rather than jumping. The button
list puts what you bind first at the front (Gas and Brake lead on Power
Drift, the throttle buttons follow the fire buttons on the flight games),
Test and Service last. OSD options: Stick (D-pad by default, analog, or
both), Analog response (Linear is the board's own mapping; Soft and
Softer flatten the centre for thumbsticks while keeping full lock),
Analog range (100/75/50%), Stick re-center for the flight games (On is
the cabinet's self-centring stick; Off holds the position the pad last
set), Gun control for Rail Chase (lightgun or gamepad cursor, with
per-player cursor speed and an optional crosshair), Power Drift's gear
indicator (MAME's shifter overlay in the lower right corner), and pause
while the OSD is open. Options that do not apply to the loaded game are
hidden (the MRA's board descriptor drives the framework's menu mask).

## Layout

```
Arcade-SegaYBoard.{sv,qsf,qpf,sdc}   MiSTer emu top and Quartus project
files.qip                            file list (edit this, never the IDE)
build.bat / clean.bat                Windows build with Quartus Prime 17.0 Lite
sys/                                 MiSTer framework (vendored)
rtl/                                 the board: yb_pkg, yb_core, cpu/ video/ audio/ io/ mem/ pll/
tools/                               ROM table, MRA generator, stream packer, MAME capture and trace
verif/                               golden models, cocotb unit tests, Verilator board sim
docs/                                design notes and hardware references
releases/                            .mra files and dated .rbf builds
```

## Building the .rbf (Windows)

Install Quartus Prime 17.0 Lite, clone the repo, then run `build.bat`. It
compiles `Arcade-SegaYBoard` and copies the result to
`releases\Arcade-SegaYBoard_YYYYMMDD.rbf`. `clean.bat` removes every
generated file. If Quartus lives somewhere other than
`C:\intelFPGA_lite\17.0\quartus`, set `QUARTUS_ROOTDIR` first.

The OSD's version line is `v<yymmdd>-<git sha>`, generated into
`build_id.v` at compile time by `tools/build_id.tcl` (a `*` after the SHA
means the tree had uncommitted changes; `git` on the build machine is
optional, the script falls back to reading `.git/HEAD`).

## Simulation and tests (macOS/Linux)

Needs Verilator, Icarus Verilog, Python 3.12 and MAME. cocotb does not
build on Python 3.14, so `verif/` keeps its own venv:

```
python3.12 -m venv verif/.venv && verif/.venv/bin/pip install cocotb pytest
sh verif/lint.sh                              # Verilator lint of the board
sh verif/lint_emu.sh                          # elaborate the MiSTer top against the framework
verif/.venv/bin/python -m pytest tools/tests  # MRA == packer stream, ROM CRCs
(cd verif/unit && ../.venv/bin/python -m pytest -q chips)   # cocotb chip tests vs MAME models
python3 tools/mame_trace.py gforce2 --seconds 2 --out verif/golden/gforce2
make -C verif/board run FRAMES=30             # Verilator board sim: traces + PPM frames
python3 tools/trace_compare.py verif/golden/gforce2/trace_main_mame.txt verif/board/out/trace_main_pc.txt --slack 1
python3 tools/mame_capture.py gforce2 --frame 60 --out verif/golden/gforce2/f60   # RAM dumps + PNG
sh verif/board/check_m1.sh                    # three-CPU trace gate
sh verif/board/check_m2.sh                    # Y sprite gate
sh verif/board/check_m3.sh                    # rotation gate
sh verif/board/check_m4.sh                    # 16B/mixer gate (full frames exact vs MAME)
sh verif/board/check_m5.sh                    # sound gate (PCM cocotb + audio envelope vs MAME)
sh verif/board/check_m6.sh                    # bring-up gate (test menu, Scene Select)
sh verif/board/check_m7.sh                    # the other five games vs MAME
python3 tools/gen_mra.py                      # writes releases/*.mra
python3 tools/pack_roms.py gforce2 --zip gforce2.zip --out stream.bin --hexdir verif/golden/gforce2
```

The ROM table in `tools/romsets.py` is copied from MAME's `segaybd.cpp`.
The MRA and the packer are checked against each other so the SDRAM layout
the RTL expects is the one the MiSTer host actually sends.

What the tests show: the custom chips are checked against Python ports of
MAME's C++ (the 315-5248/5249 over random operations, the 315-5296 and
MSM6253 against their models, the Y sprite, rotation and 16B generators
on lists and tables captured from MAME), the board simulation's three
68000 program-counter traces track MAME's, and the frames it renders
match MAME's screenshots pixel for pixel for Galaxy Force II, Rail Chase
and Strike Fighter, with Power Drift and G-LOC inside a small allowance
for animations a frame out of phase (`docs/DESIGN.md`, M7 findings). The
board simulation also checks itself: the model chain rendered from the
RTL's own RAM dumps must reproduce the RTL's frame exactly.
`docs/DESIGN.md` records the results per milestone, and where the RTL
deliberately differs from MAME.

## Installing

Copy `releases/Arcade-SegaYBoard_<date>.rbf` to `/media/fat/_Arcade/cores/`,
the `.mra` files to `/media/fat/_Arcade/` and the MAME 0.289 zips listed
in the games table to `/media/fat/games/mame/`, then launch a game from
the Arcade menu. Commercial ROMs are not included.

For automatic installation, add this to `/media/fat/downloader.ini` and
run Update All:

```
[rossops/Arcade-SegaYBoard_MiSTer]
db_url = https://raw.githubusercontent.com/rossops/Arcade-SegaYBoard_MiSTer/main/db.json.zip
```

The database (`db.json.zip`, built by `tools/make_db.py`) lists every MRA
and the current core with their MD5s, pointing at the files in this
repository; it is regenerated with each release.

## Releases and CI

Every push to `main` and every pull request runs `.github/workflows/ci.yml`:
it regenerates the MRAs and diffs them against `releases/` (so a hand edit
there fails the build), runs the same `mra_rom_check.sh` MiSTer-devel uses
on MRA-Alternatives, runs the tool tests, and refuses any tracked Quartus
output. Nothing gets built in CI. The `.rbf` still comes from `build.bat`
on a Windows box and a hardware test before it is committed.

Versions are semver tags, `v1.0.0` up. To cut one, run the "Release"
workflow from the Actions tab, pick patch, minor or major, and optionally
type a sentence for the top of the notes. It runs CI first, then tags the
current `main` and publishes a GitHub release whose notes list the rbf
(name, MD5, size), the game counts and the commits since the previous
tag. No files are attached to the release: the core and the MRAs live in
the tree and reach MiSTer through `db.json.zip`.

## Audio filter

The MiSTer framework applies a selectable low-pass filter to the core's
audio (OSD system page, "Audio filter", files under
`/media/fat/Filters_Audio/`). The Y Board's 315-5218 plays 8-bit samples
at 31.25 kHz without interpolation, so its output carries staircase
imaging above ~15 kHz that sounds gritty on a flat system, while the
YM2151 side is clean; the PCB itself has an analog low-pass before the
amplifier. Recommended: `General LPF/LPF 12khz 1st + AA.txt`, a gentle
first-order roll-off that tames the PCM grit without dulling the FM.
`Arcade LPF/Arcade LPF 8khz 2nd.txt` gives the warmer sound of a period
cabinet speaker. To make one the core's default add to `MiSTer.ini`:

```
[Arcade-SegaYBoard]
afilter_default=General LPF/LPF 12khz 1st + AA.txt
```

## Credits

The Sega custom chips, the board glue, the loader and the tooling in this
repository were written for this core from the references below. Several
pieces are other people's work, vendored under their own licences (pinned
commits in `docs/references.md`):

- **MAME** (mamedev.org) — the behavioural reference for the whole board:
  `segaybd.cpp` and the 16-bit Sega device family (`segaic16`,
  `sega16sp`), `segapcm.cpp`, `315_5296.cpp` and `msm6253.cpp`. Every
  custom chip model in `verif/models/` is a port of the MAME code, MAME
  0.289 produced the golden frames, traces and audio the RTL is checked
  against, and Power Drift's gear indicator is a redraw of the
  `pdrift.lay` layout (CC0). GPL-2.0+ / BSD-3.
- **Jose Tejada (jotego)** — the YM2151 (`jt51`), GPL-3.
- **Jorge Cwik (ijor)** — `fx68k`, the cycle-accurate 68000 used for all
  three CPUs, GPL-3.
- **Daniel Wallner, MikeJ, Sorgelig** — the T80 Z80 core, BSD-style.
- **Guy Hutchison** — `tv80`, the Verilog Z80 used by the Verilator
  simulations in place of the VHDL T80, MIT-style.
- **Alexey Melnikov (Sorgelig) and the MiSTer project** — the MiSTer
  framework (`sys/`), the MRA/ROM loading conventions, the audio filter
  and the DE10-Nano platform this runs on.
- **Meathax** — the Sega System 32 MiSTer core
  (https://github.com/meathax/s32), GPL-3: the repository layout follows
  it, and the SDRAM controller (`rtl/mem/sdram.sv`) and the DDR3 sprite
  framebuffer interface (`rtl/mem/yb_fb_if.sv`) are forks of its
  `sdram.sv` and `s32_fb_if.sv`; the `sys/` framework copy and the T80
  came from it as well.
- The X Board core (rossops/Arcade-SegaXBoard_MiSTer) is this
  repository's parent: the verification flow, the tooling and the reusable
  RTL started there.
- **Tools**: Verilator, Icarus Verilog, cocotb, numpy and Pillow for the
  verification flow; Quartus Prime 17.0 Lite for the FPGA build.

The core itself is GPL-3. Commercial ROMs are not included.
