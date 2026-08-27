# Hardware and IP references

## Behavioural references
- MAME (behavioural reference, GPL-2.0+/BSD-3): local checkout `/Users/rossesposito/Code/mame`
  (`f528cd62`, mame0284-123). Files to port from: `src/mame/sega/segaybd.cpp`, `segaybd.h`,
  `segaybd_v.cpp` (mixer), `sega16sp.cpp` (`sega_yboard_sprite_device`, `sega_sys16b_sprite_device`),
  `segaic16.cpp` (`rotate_draw`, `rotate_control_r`, palette), `segaic16_m.cpp` (5248/5249),
  `315_5296.cpp`, `src/devices/machine/msm6253.cpp`, `src/devices/sound/segapcm.cpp`.
  Installed binary for captures: `/opt/homebrew/bin/mame` (0.289).
- ROM sets: MAME 0.289 merged zips in `/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/`.

## Carried over from the X Board core
Copied from `rossops/Arcade-SegaXBoard_MiSTer` at commit `ee467b1` (2026-08-27) with the
`xb_` prefix renamed to `yb_`. Same licence (GPL-3). These are Y Board hardware as well and
were verified on that core against MAME and on a DE10-Nano:

| Path | What it is |
| --- | --- |
| `rtl/cpu/yb_m68k_bus.sv` | fx68k wrapper: unified bus, DTACK, IPL, VPA autovector |
| `rtl/cpu/yb_rom_cache.sv` | direct-mapped 68000/Z80 ROM cache over SDRAM (altsyncram, fill served from fill data) |
| `rtl/cpu/yb_math_5248.sv`, `yb_math_5249.sv` | 315-5248 multiplier, 315-5249 divider (the X Board's 315-5250 was dropped in M0: the Y Board has none) |
| `rtl/audio/yb_soundsys.sv`, `yb_segapcm_5218.sv` | Z80 sound board, YM2151 glue, 315-5218 PCM |
| `rtl/mem/sdram.sv`, `yb_rom_loader.sv`, `yb_dpram.sv` | SDRAM controller (ports p0..p7), ioctl stream loader, two-clock byte-enabled RAM |
| `rtl/mem/yb_fb_if.sv` | DDR3 framebuffer interface (run writes, line reads, erase) |
| `rtl/video/yb_video_timing.sv` | 400x262 @ 6.25 MHz timing with the 2x output grid |
| `rtl/video/yb_palette_5242.sv`, `yb_pal_lut.svh` | 315-5242 palette and resistor-ladder LUTs |
| `rtl/io/yb_ana_shape.sv` | analog response curves (OSD Linear/Soft/Softer) |
| `rtl/yb_pkg.sv` | shared package, rewritten in M0 for the Y Board map, stream and descriptor |
| `Arcade-SegaYBoard.sv`, `.qsf`, `.sdc`, `.qpf`, `.srf` | MiSTer emu wrapper and Quartus project (trimmed to the Y Board core's ports in M0) |
| `verif/` | lint scripts, board bench (trimmed to `yb_core` in M0), SDRAM/DDR3 models, golden models and cocotb tests for the chips above |
| `tools/` | MRA generator and packer, MiSTer Downloader db, MAME capture/trace/wav tools, MiSTer ssh helper, Quartus build-id and STA scripts |

## Vendored IP (pinned, unchanged)
| Path | Upstream | Commit | Licence |
| --- | --- | --- | --- |
| `sys/` | MiSTer-devel/Template_MiSTer (stock, never edited) | as in the X Board core | GPL-3 / mixed, see files |
| `rtl/cpu/fx68k/` | https://github.com/ijor/fx68k | `0602ee4627b10f301298f2673d826cdd6baa9327` | GPL-3 |
| `rtl/audio/jt51/` | https://github.com/jotego/jt51 (`hdl/`) | `985a573dcfc1ff135553a39f7eae21d18ba57cbe` | GPL-3 |
| `rtl/audio/T80/` | Wallner/MikeJ/Sorgelig, via Meathax's System 32 core | as vendored | BSD-style |
| `verif/board/tv80/` | tv80 (Guy Hutchison, opencores), simulation-only Z80 | as vendored | MIT-style |

`sdram.sv` and `yb_fb_if.sv` descend from Meathax's Sega System 32 core
(https://github.com/meathax/s32, GPL-3) by way of the X Board core.
