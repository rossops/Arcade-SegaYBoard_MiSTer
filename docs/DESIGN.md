# Sega Y Board core: design notes and plan

Written 2026-08-27 from MAME (`src/mame/sega/segaybd.cpp`, `segaybd_v.cpp`,
`sega16sp.cpp`, `segaic16.cpp`, `315_5296.cpp`, `src/devices/machine/msm6253.cpp`)
before any Y Board RTL exists. Where MAME guesses, the guess is marked as an
open question at the end. The X Board core's `docs/DESIGN.md` is the worked
example for everything that is shared; this document only says what is
different and what the plan is.

## 1. What came over from the X Board and what is new

Same hardware, carried over as `yb_*` (see `references.md`): the 68000
wrapper and ROM cache, 315-5248 multiplier and 315-5249 divider (three of
each here), the Z80 sound board with YM2151 and 315-5218 PCM, the 315-5242
palette, the SDRAM controller and loader, the DDR3 framebuffer interface,
video timing, the analog response shaper.

Not on this board: the 315-5250 (the Y Board's sound latch is a plain latch
and the timer interrupt comes from the 315-5306; `yb_cmptimer_5250.sv` was
deleted in M0), the tilemap, the road, the CXD1095 and the FD1094, none of
which came over from the X Board.

New for the Y Board:

| Piece | Chip | Notes |
| --- | --- | --- |
| Third 68000 | | main, sub X, sub Y, all 12.5 MHz, all share one 64 KB RAM |
| I/O chip | 315-5296 | 8 ports A-H with a direction register, replaces the CXD1095 pair |
| ADC | OKI MSM6253 | 4 channels, serial read one bit per access, channel 3 muxed 4 ways |
| Back sprite layer | 315-5305 | linked-list sprites with palette indirection into a 512x512 framebuffer, "huge fill rate" |
| Rotation and sync | 315-5306 x2 | affine scan-out of that framebuffer, per-line clip extents, the IRQ2 source |
| Front sprite layer | 315-5196 | System 16B sprites (line based, 16-bit ROM words), same chip as System 16B |
| Mixer | 315-5312 | Y layer under 16B layer with per-pixel priority compare and pen-14 shadow |

Games (MAME 0.289 sets, parents): Galaxy Force II `gforce2` (1988), Power
Drift `pdrift` (1988), G-LOC Air Battle `gloc` (1990), Rail Chase `rchase`
(1991), Strike Fighter `strkfgtr` (1991). Clones add `gforce2sd`, `gforce2j`,
`gforce2ja`, `glocj`, `glocu`, `glocr360`, `glocr360j`, `pdrifta`, `pdrifte`,
`pdriftj`, `pdriftjb`, `pdriftl` (link board), `rchasej`, `rchasejb`,
`strkfgtrj`. None use an FD1094. The deluxe motor boards and the Power Drift
link board are separate Z80 systems: stub them the way the X Board stubbed the
After Burner motor board. MAME only maps the motor board's Z80 (16 MHz / 2,
ROM 0000-7FFF, RAM 8000-FFFF, no port map, `segaybd.cpp:877-882`) and never
runs its protocol, so the stub is what the main CPU sees: port C limit
switches inactive and the pitch/roll ADC inputs centred at 0x80, MAME's
`read_safe` default. Open question 9.

## 2. Hardware reference

### Clocks
50 MHz master: 68000 x3 at 12.5 MHz (/4), 315-5296 at 6.25 MHz (/8). MAME
runs the sound board from a 32.2159 MHz crystal (/8 = 4.027 MHz for the Z80,
YM2151 and 315-5218); the Power Drift PCB notes on the same file say 16 MHz /
4 = 4.000 MHz. Open question 3. Either way it is the same modulo-25 enable
scheme as the X Board, one clock domain.

MAME's screen is `set_size(342, 262)` at `set_refresh_hz(60)` with a "to be
verified" comment and 320x224 visible (`segaybd.cpp:1474-1478`). There is no
`set_raw`, so the 342 is a placeholder rather than a measured horizontal
total. The X Board's encoder at 6.25 MHz gives 400x262 at 59.64 Hz; assume
the same here (open question 1) and keep `yb_video_timing` as it is.

### Memory maps (MAME; each CPU masks to 24 bits)

Main 68000:

| Range | What |
| --- | --- |
| 000000-07FFFF | program ROM (512 KB slot, gforce2 uses 256 KB) |
| 080000-080007 (mirror 1FF8) | 315-5248 multiplier (main) |
| 082001 (mirror 1FFE) | sound latch, byte, raises Z80 NMI |
| 084000-08401F (mirror 1FE0) | 315-5249 divider (main) |
| 0C0000-0CFFFF | shared RAM, 64 KB, all three CPUs |
| 100000-10001F | 315-5296, low byte of each word |
| 100040-100047 | MSM6253: write selects channel (A1:A0), read shifts one bit out on D7 |
| 1F0000-1FFFFF | local RAM 64 KB |
| 190000-190FFF | link board (pdriftl only): MB8421 dual-port RAM, left bank |
| 191000 / 192000 | link board: `link_r` status, `link2_r/w` control (`segaybd.cpp:843-874`) |

Sub X:

| Range | What |
| --- | --- |
| 000000-03FFFF | program ROM (256 KB) |
| 080000 / 084000 | its own 5248 / 5249 |
| 0C0000-0CFFFF | shared RAM |
| 180000-18FFFF | Y sprite RAM, 64 KB (4096 entries of 8 words, plus indirection tables in the same space) |
| 1F8000-1FBFFF | local RAM 16 KB |
| 1FC000-1FFFFF | backup RAM 16 KB (battery, NVRAM index 3 as on the X Board) |

Sub Y:

| Range | What |
| --- | --- |
| 000000-03FFFF | program ROM (256 KB) |
| 080000 / 084000 | its own 5248 / 5249 |
| 0C0000-0CFFFF | shared RAM |
| 180000-1807FF (mirror 7800) | rotation RAM, 2 KB |
| 188000-188FFF (mirror 7000) | 16B sprite RAM, 4 KB (256 entries of 8 words) |
| 190000-193FFF (mirror 4000) | palette RAM, 8192 x 16 |
| 198000-19FFFF | rotation control: a read swaps the two halves of rotation RAM, returns FFFF |
| 1F0000-1FFFFF | local RAM 64 KB |

Z80: ROM 0000-EFFF, 315-5218 registers F000-F0FF (mirror 0700), RAM
F800-FFFF; ports 00-01 YM2151 (mirror 3E), 40 sound latch read (mirror 3F).
NMI from the latch write, INT from the YM2151. Identical to the X Board sound
board except the PCM banking. MAME configures `BANK_12M | BANK_MASKF8`
(`segaybd.cpp:1500`); `segapcm.h:25-33` makes that bank shift 13 and bank
mask 0xF8, and `segapcm.cpp:106` forms `offset = (reg86 & mask) << shift`.
So the bank field is register 0x86 bits 7:3 in 64 KB units and it reaches
the whole 2 MB region. The X Board was `BANK_512`: shift 12, mask 0x70, bits
6:4. The carried-over `yb_segapcm_5218` hard-codes the X Board case (a 7-bit
`bank` and `{bank, 12'd0}` in the address), so in M5 the shift and the bank
width become parameters (8-bit bank, `<< 13`) and the mask comes from the
descriptor as it does now.

### Interrupts
All three 68000s see the same three lines, no acknowledge on any of them:
IPL2 = "timer" from the 315-5306, one scanline wide; IPL4 = vblank, asserted
at line 223, cleared at 224; IPL6 when both are up. MAME fires IPL2 at
scanline 170, set in `machine_reset` (`segaybd.cpp:325`), and calls the value
a trial-and-error constant (open question 2). The same file keeps a debug
hotkey block (lines 408-416: Q, W, E, R move the line by 10 or 1 and pop the
new value), which is a cheap way to find each game's best line against
captures before hardware is involved. There is no 315-5250, so the interrupt
generator is a small block in `yb_core` driven by the video counter, and the
line number is descriptor byte 7.

The main CPU resets the others through 315-5296 port E: bit 3 XRES, bit 2
YRES (1 = held in reset), bit 4 /SRES for the Z80 (0 = reset). Also on port
E: bit 7 /KILL is the display enable, bit 6 CONT, bit 5 /WDCL kicks the MB3773
watchdog, bits 1:0 pick the ADC channel-3 mux. Port H: bit 7 /MUTE, bits 6:0
audio filter select (ignore). Port D is game outputs (lamps, motors). Inputs:
port A = P1, port B = general (service, test, start, buttons, coins), port C =
limit switches (deluxe cabinets; tie inactive), port F = DSW B, port G = DSW A
(coinage).

### 315-5296
64 byte-wide registers: 0-7 ports A-H, 8-B read 'S','E','G','A', C/E the CNT
register, D/F the direction register (bit n = port n is an output). A read of
an output port returns its latch; a write to an input port only updates the
latch. Reset: all inputs, latches 0. Unused registers read FF (on real
System 16 hardware, the prefetch value). Registers 10-1F do nothing;
registers 20-3F assert the chip's /FMCS peripheral select, and on this board
/FMCS and CKOT go to the MSM6253's CS and OSC IN (`segaybd.cpp:1458`), which
is why the ADC sits at 100040-100047: that is 5296 register 20-23. CKOT is
the 6.25 MHz clock divided by 2, 4, 8 or 16 from CNT bits 7:6 (MAME's CNT
emulation is a TODO, `315_5296.cpp:22`). CNT0-2 output pins unused here.

### MSM6253
Four 8-bit channels behind the 315-5296's /FMCS window. A write to 100040+2n
selects channel n from A2:A1 and loads its conversion into the shift
register (`msm6253.cpp:81-85`); each read of the odd byte returns the MSB on
D7 and shifts left with zero fill (`d7_r`, lines 128-132). MAME treats the
conversion as instant; the real chip converts at the CKOT rate, so the delay
between the write and the first valid read is open question 8. Games read
eight times per sample. Channel 3 goes through a
74HC4052 selected by port E bits 1:0, so `ADC.3`..`ADC.6` in MAME's port
names are the four mux inputs. Channel use per game (MAME):
gforce2 0 stick X, 1 stick Y (reversed), 2 throttle; gloc/strkfgtr 3 stick Y
(0x40-0xC0, reversed), 4 throttle, 5 stick X (0x20-0xE0), glocr360 also 0/2
motion pitch/roll; pdrift 3 brake, 4 gas, 5 steering (0x20-0xE0);
rchase 0/1 P1 gun X/Y, 2/3 P2 gun X/Y. The X Board's `ana_mode` descriptor
byte and `yb_ana_shape` cover the ranges; Line of Fire's gun modes cover
Rail Chase.

The two flight throttles run opposite ways, which the Speed Up and Slow Down
buttons have to follow. G-LOC and Strike Fighter clamp the reading to
0x30..0xC0 and scale it up, so high is fast, the same as the X Board's After
Burner. Galaxy Force II's sub Y low-passes the reading, takes the low byte of
`value - 0x80`, negates it and works out a target speed of
`0x2C0 + 4 * ((0x100 - value) & 0xFF)` (main CPU 001C88 fills shared RAM
C00CA..C00CD, sub Y 014B00 smooths into F02E.., 009394 turns F033 into the
speed at F100). So 0x01 is the fastest, 0xFF the slowest, and 0x00 wraps back
past the slowest. Speed Up must drive the channel low and Slow Down high, and
the axis has to stop short of 0x00.

Galaxy Force II's buttons drive a virtual lever rather than the ends of the
channel. The cabinet's throttle has travel and stays where it is left, so
holding an end and springing back to centre only gave three speeds with
nothing in between: Speed Up and Slow Down walk the lever four counts a frame,
about a second from end to end, and it keeps its place when they are released.
The analog axis overrides the lever whenever it is off centre, so a stick and
the buttons can share the channel. Same idea as the Power Drift wheel slew and
the flight games' hold-position stick.

### 315-5305 Y sprites (back layer)
Sprite RAM entry, 8 words (from `sega_yboard_sprite_device::draw`):

| Word | Bits | Field |
| --- | --- | --- |
| 0 | 15 | end of list |
| 0 | 14, 12 | hide |
| 0 | 10:0 | indirection table address (/16 words) inside sprite RAM |
| 1 | 15:12 | bank bits 7:4, 11:0 X (0x600 = screen 0) |
| 2 | 15:12 | bank bits 3:0, 11:0 Y (0x600 = screen 0) |
| 3 | 15:0 | ROM offset within bank (64-bit words) |
| 4 | 15:0 | height |
| 5 | 14 | draw top-to-bottom (else bottom-to-top), 13 flip (inverted sense), 12 left-to-right (else right-to-left), 10:0 zoom |
| 6 | 14:12 colour, 11:8 priority, 7:0 | signed pitch (words per row) |
| 7 | 11:0 | index of the next entry (linked list; a visited entry ends the walk) |

Only 5 bank bits are used (`bank = ((w1 >> 8) & 0x10) | (w2 >> 12)`); a bank
is 0x10000 64-bit words = 512 KB. ROM words hold 16 4-bit pens, MSB first
(reversed when flipped); pen 0xF at the end of a word ends the row. Each pen
goes through the 16-entry indirection table: `ind = table[pen]`, written only
if `ind < 0x1FE` (0x1FE/0x1FF transparent). Zoom: `xacc += zoom` per output
pixel, a source pixel repeats while `xacc < 0x200` (so 0x200 = 1:1, smaller
magnifies, MAME clamps 0 to 1); vertically `yacc += zoom; addr += pitch *
(yacc >> 9); yacc &= 0x1FF`. Framebuffer pixel = `(w6 << 1) & 0xFE00 | ind`:
colour 15:13, priority 12:9, indirected colour 8:0. Rows are clipped to the
per-scanline-pair extents in rotation RAM: word `2n` = min X for lines 2n and
2n+1, word `2n+1` = max X; bit 15 of min = "above the top", bit 14 = "below
the bottom", either one skips the line and ends the sprite in that direction.
Framebuffer is 512x512; the PCB has 32 x 32 KB SRAM = 1 MB, i.e. two of
them, so it is double buffered like the X Board's (open question 4 for the
swap/erase cadence). MAME fills the whole buffer with FFFF before drawing.

### 315-5306 rotation scan-out
Rotation RAM (2 KB, double buffered by the read of 198000): words 0-0x3EF
are the clip extents above; words 0x3F0-0x3FB are six 32-bit big-endian
values: `currx`, `curry`, `dyy`, `dxx`, `dxy`, `dyx` in 18.14 fixed point.
Per frame `currx += dxx * (x0 + 27) + dxy * y0`, then per pixel `tx += dxx;
ty += dyx`, per line `currx += dxy; curry += dyy`; source pixel at
`((ty >> 14) & 0x1FF, (tx >> 14) & 0x1FF)`. A written pixel becomes palette
index `(pix & 0x1FF) | ((pix >> 6) & 0x200) | ((pix >> 3) & 0xC00) | 0x1000`
with priority byte `(pix >> 8) | 1`; an unwritten one (FFFF) becomes palette
index `sy` (the source row number: the "scanline colour", used for sky and
ground gradients) with priority FF. The 27 is MAME's; open question 5.

### 315-5196 16B sprites (front layer)
System 16B format, 8 words per entry, 256 entries in 4 KB:
w0 bottom-1 (15:8), top-1 (7:0); w1 X 8:0 (0xBD = screen 0; MAME's origin is
184 for this device), 12:9 sprite-vs-sprite priority (Y Board use); w2 bit 15
end, 14 hide, 8 flip, 7:0 signed pitch; w3 ROM offset (16-bit words); w4
11:8 bank, 7:6 priority, 5:0 colour; w5 vzoom 9:5, hzoom 4:0 (0 = full size,
0x10 = half); w7 is scratch the chip writes back. Four 4-bit pens per word,
pen 0 transparent, pen 0xF ends the row; horizontal zoom accumulator starts
at `4 * hzoom` and a pixel is drawn when `(xacc & 0x3F) + hzoom < 0x40`;
vertical: `w5 += vzoom << 10`, carry into bit 15 skips a source row. MAME
clamps both zooms to a minimum of 0x40 ("maximum of 8x, not 100% confirmed",
`sega16sp.cpp:1137` inside `sega_sys16b_sprite_device::draw`); this is the
same clamp the X Board has as a parameter, open question 7. Banks are
0x10000 words (128 KB), identity bank table (no 315-5195 mapper here).
Output pixel: bits 15:12 the 16B priority nibble, 11:10 priority, 9:4 colour,
3:0 pen. The real chip is line based (two line buffers); render per scanline
into a line buffer rather than a frame buffer. jotego's `jts16` (GPL-3) has a
315-5196 implementation that could be vendored instead of writing one.

### 315-5312 mixer (from `segaybd_state::screen_update`)
Base is the rotated Y layer. A 16B pixel (not FFFF) with
`((pix >> 11) & 0x1E) < (pri & 0x1F)` wins; if its pen is 0xE it shadows
(palette index + 8192, the 315-5242 shadow bank) otherwise it draws
`0x800 | (pix & 0x7FF)`. Display off (port E bit 7 low) = black.

### 315-5242 palette
8192 x 16, `sBGR BBBB GGGG RRRR` with the LSB of each component in bits
14:12, bit 15 selecting hilight vs shadow for the effects copy. Same as the
X Board: keep `yb_palette_5242` and its LUTs.

### ROM sets and sizes
| Region | gforce2 | pdrift | gloc | rchase | strkfgtr |
| --- | --- | --- | --- | --- | --- |
| main (LOAD16_BYTE pairs) | 256 KB | 256 KB | 256 KB | 256 KB | 256 KB |
| subx / suby | 128 / 128 KB | 128 / 128 | 256 / 256 | 256 / 256 | 256 / 256 |
| bsprites (LOAD16_BYTE, 16-bit words) | 512 KB | 512 KB | 2 MB | 512 KB | 2 MB |
| ysprites (LOAD64_BYTE, 8-way interleave) | 4 MB | 4 MB | 16 MB | 12 MB | 16 MB |
| Z80 | 64 KB | 64 KB | 64 KB | 64 KB | 64 KB |
| PCM (2 MB region, ERASEFF) | 768 KB, mirrored to 1.5 MB | 768 KB, same | 1.5 MB flat | 1.5 MB flat | 1.5 MB flat |

The PCM row: gforce2 and pdrift load one 512 KB ROM at 0 and two 128 KB
ROMs at 0x80000 and 0x100000, each of the small ones `ROM_RELOAD`ed three
more times so it fills a 512 KB bank and the region is populated up to
0x180000 (`segaybd.cpp:1620-1630`). With the
bank mask F8 the sample table can point into any of those mirrors, so the
stream carries them (a `repeat` count per file, section 3). The other three
games load three 512 KB ROMs back to back with no reloads.

The `ysprites` region is eight ROMs interleaved into 64-bit words
(`<interleave output="64">` in the MRA, eight `map` digits). `pack_roms.py`
needs a `x64` loader next to `w16`/`x32`. Power Drift's `user1` region and
the motor/link/driver-board ROMs are not loaded.

## 3. Architecture

### Clocks
As the X Board: one PLL, `clk_sys` 50 MHz (= PCB master, so /4 and /8 are
exact), `clk_ram` 100 MHz, SDRAM clock at 180 degrees. Sound 4 MHz from the
modulo-25 enable.

### Memory placement
SDRAM (32 MB module; G-LOC and Strike Fighter need 21 MB of ROM):

| Offset | Slot | Contents |
| --- | --- | --- |
| 0x0000000 | 512 KB | main ROM |
| 0x0080000 | 256 KB | sub X ROM |
| 0x00C0000 | 256 KB | sub Y ROM |
| 0x0100000 | 64 KB | Z80 ROM |
| 0x0110000 | 2 MB | PCM |
| 0x0310000 | 2 MB | 16B sprite ROM |
| 0x0510000 | 16 MB | Y sprite ROM (64-bit words as four 16-bit halves), ends at 0x1510000 |

Ports: three 68000 ROM caches, Z80 cache, PCM, 16B line fetch, Y sprite
stream. Reuse `sdram.sv`'s p0..p7 and the X Board's priority scheme (CPUs
first, then sound, then video with deadline escalation).

BRAM: shared 64 KB, main local 64 KB, sub X local 16 KB + backup 16 KB, sub Y
local 64 KB, Y sprite RAM 64 KB, 16B sprite RAM 4 KB, rotation RAM 2 x 2 KB,
palette 16 KB, Z80 RAM 2 KB. About 320 KB = 2.6 Mbit, roughly 330 M10K
blocks before caches and line buffers; the framework takes about 40. Count
blocks from the first fit. If it does not close, the 64 KB local RAMs are the
candidates for SDRAM behind the ROM cache (they are not, on the X Board
evidence, the fast path).

Shared RAM: three masters on one 64 KB RAM. M1 built it as one BRAM at
`clk_sys` with a queue of one request per CPU: a CPU's bus-start pulse
queues its access, the arbiter serves one queued access per clock (main,
then sub X, then sub Y) and the requester gets its data and DTACK two clocks
later. A 68000 bus cycle is at least 16 `clk_sys` clocks, so three
contending CPUs cost each other at most two clocks and no wait state is ever
inserted. What the PALs 315-5314..5318 do on the real board is open
question 6; the X Board's bus-grant model does not apply because no CPU
owns another's space here.

DDR3: two 512x512x16 Y framebuffers at 0x30000000 and 0x30080000. Rendering
writes runs (`yb_fb_if`'s run writer, 512-pixel rows). Scan-out is the new
part: the rotation reads one pixel per output pixel from an arbitrary
address. M3 built it (`yb_rotate_5306`) one line ahead into a double-banked
line buffer at `clk_ram`, through a direct-mapped cache of 128 64-bit words
(four pixels each) indexed by `sx[8:2] ^ sy[6:0]`: a whole source row stays
resident when consecutive lines read the same row, and vertical walks
spread over the entries. Misses are single-word DDR3 reads (`yb_fb_if`'s
`rq` port, served ahead of erases and run flushes). Measured on the
captures: 80 misses per line on the identity, 156 at the steepest attract
rotation (18 degrees), 2,550 clocks for the worst line against the 6,400
of a scanline with the bench's DDR3 model; in-game rolls will approach one
miss per pixel, which is where the tiled framebuffer layout (8x8 pixel
blocks per burst) or a prefetch of the next word comes in if hardware
shows late lines. The bench counts late lines.

### Modules
| File | Role |
| --- | --- |
| `rtl/yb_pkg.sv` | rewrite: constants, SDRAM/DDR3 map, stream layout, descriptor |
| `rtl/yb_core.sv` | board top: three `yb_m68k_bus` + caches, shared RAM arbiter, IRQ generator, resets from port E |
| `rtl/io/yb_315_5296.sv` | the I/O chip |
| `rtl/io/yb_msm6253.sv` | ADC with the serial read and the port-E mux |
| `rtl/video/yb_ysprite_5305.sv` | list walker (linked list, visited set), indirection, zoom, run writer to DDR3 |
| `rtl/video/yb_rotate_5306.sv` | rotation RAM (double buffer, swap on 198000 read), affine scan-out with cache, clip extents, IRQ2 line |
| `rtl/video/yb_bsprite_5196.sv` | 16B line renderer with two line buffers (or vendored `jts16` object unit) |
| `rtl/video/yb_mixer_5312.sv` | priority compare, shadow, display enable |
| `verif/models/ysprite5305.py`, `rotate5306.py`, `bsprite5196.py`, `mixer5312.py`, `io5296.py`, `msm6253.py` | golden models, ported line for line from MAME |

### ROM stream and descriptor
`tools/pack_roms.py` and `tools/gen_mra.py` share `tools/romsets.py`, as on
the X Board. The index-0 stream is the 64-byte descriptor followed by every
region padded to its slot, in the order the SDRAM table above uses:

| Region | Slot | Loader | Stream offset (after the descriptor) |
| --- | --- | --- | --- |
| `main` | 512 KB | `w16` | 0x000000 |
| `subx` | 256 KB | `w16` | 0x080000 |
| `suby` | 256 KB | `w16` | 0x0C0000 |
| `z80` | 64 KB | `flat` | 0x100000 |
| `pcm` | 2 MB | `flat`, FF fill | 0x110000 |
| `bsprite` | 2 MB | `w16` | 0x310000 |
| `ysprite` | 16 MB | `x64` | 0x510000 |

The offsets equal the SDRAM offsets and the slots are contiguous, so the
loader is a straight copy as on the X Board. `w16` and `flat` are the X
Board loaders. `x64` is new: groups of eight `LOAD64_BYTE` ROMs, MAME
`REGION64_BE`, one `<interleave output="64">` per group with eight `map`
digits, and the 64-bit word lands in SDRAM as four 16-bit halves in the
order `yb_ysprite_5305` reads them. Mirrored PCM ROMs get a fourth element
in the file tuple, a repeat count: `("epr-11516.106", 0x20000, "19d0e17f",
4)`. `build_region` repeats the bytes and `region_parts` emits the same
`<part>` that many times (the MRA format is happy with a file listed more
than once; `repeat=` on a literal part is already how the padding is
written). `ysprite` is always the last populated region, and today both
tools pad the last region to its slot, which would make every set a 21 MB
stream. M0 changes that rule: the trailing region ships unpadded, so
gforce2's stream is 9 MB and gloc's 21 MB. Either way the MRA load is
visibly longer than the X Board's 4.4 MB. Live with it.

The descriptor (`board_desc_t` in `yb_pkg.sv`, `descriptor()` in
`pack_roms.py`) replaces the X Board's byte layout entirely:

| Byte | Field | Values |
| --- | --- | --- |
| 0 | game id | 0 gforce2, 1 pdrift, 2 gloc, 3 rchase, 4 strkfgtr, 5 glocr360, 6 pdriftl |
| 1 | flags | bit 0 deluxe cabinet (motor board stub answers on port C and the ADC), bit 1 link board present (pdriftl), bit 2 R360 (pitch and roll on ADC 0 and 2); the rest reserved |
| 2 | Y sprite banks | 512 KB banks, for the `bank % numbanks` wrap: gforce2 8, pdrift 8, rchase 24, gloc and strkfgtr 32 |
| 3 | 16B sprite banks | 128 KB banks: gforce2, pdrift and rchase 4, gloc and strkfgtr 16 |
| 4 | ADC reverse mask | bit n = MAME channel n is `0x100 - value` (PORT_REVERSE on a 1..FF range): gforce2 0x02, gloc and strkfgtr 0x08 |
| 5 | PCM bank mask | 0xF8 for every set |
| 6 | analog mode | see Controls below |
| 7 | IRQ2 scanline | 170 unless a capture says otherwise (open question 2) |
| 8-63 | reserved | 0 |

### Controls
The 315-5296 ports are fixed by the board (section 2), so what changes per
game is the analog wiring and the button names. Analog mode, descriptor
byte 6, selects the channel map and the ranges that `yb_ana_shape` produces;
the seven MAME channels are ADC 0-2 direct and mux inputs 0-3 on channel 3,
selected by port E bits 1:0:

| Mode | Games | Channels |
| --- | --- | --- |
| 0 | gforce2 | stick X on 0, stick Y on 1 (reversed), throttle on 2 (low is fast, see below) |
| 1 | gloc, strkfgtr | stick Y on mux 0 (0x40-0xC0, reversed), throttle on mux 1, stick X on mux 2 (0x20-0xE0) |
| 2 | pdrift | brake on mux 0, gas on mux 1, steering on mux 2 (0x20-0xE0) |
| 3 | rchase | P1 gun X and Y on 0 and 1, P2 gun X and Y on 2 and mux 0; Line of Fire's gun shaping and crosshairs |
| 4 | glocr360 | mode 1 plus cabinet pitch on 0 and roll on 2, fed from the motor stub |

Unread channels return 0x80. What M7 made of each mode: the flight games
take the stick Y as half deflection (0x40..0xC0) and X as three quarters
(0x20..0xE0), the d-pad standing for full lock; Power Drift's wheel slews
toward the stick X or the d-pad at 6 counts a frame (about 0.4 s lock to
lock, close to MAME's keyboard ramp), scaled to three quarters, so it
steers like a wheel with travel rather than ice skates, its pedals the Gas
and Brake buttons or the throttle axis either side of centre; Rail Chase
is the X Board's Line of Fire arrangement, an absolute lightgun position
or a gamepad cursor at the OSD speed with crosshairs drawn by the core.
Power Drift draws MAME's gear indicator (the `pdrift.lay` shifter, 16x30
at 303, 193, blended at 5/8 as the layout's 0.6 alpha, the knob and label
following the gear toggle) from `rtl/video/yb_shifter.hex`, generated
from the layout's geometry; the OSD "Gear indicator" turns it off and is
hidden for the other games. The flight games (G-LOC, Strike Fighter,
R360) also have an OSD "Stick re-center"
choice, hidden for the others: "On" hands the game the pad's deflection
as the cabinet's self-centring stick would give it, "Off" keeps
a virtual stick that the pad moves at a rate (full deflection crosses the
range in about half a second) and that stays where it is left, for
players who would rather not hold the stick off centre through a turn.
Power Drift's gear shift is a toggle like MAME's PORT_TOGGLE, one press per
change, on the GENERAL port's bit 5 which that game reads active high;
G-LOC's After Burner is bit 0. Rail Chase wires the GENERAL port its own
way (P1 and P2 triggers, coins, starts, no test bit).

Button lists follow the order MiSTer-devel asked for on the X Board:
Start, Coin and Pause before Test and Service, driving sets with Gas and
Brake first, flight sets with the throttle buttons next to the stick. The
top level maps four MRA layouts (two-button flight for Galaxy Force II,
three-button flight, driving, guns) onto the core's fixed one, chosen by
the game id. DIP switches come straight from MAME's port definitions into
the `dips` and `dip_default` fields: port G is SW A (coinage) and port F is
SW B, both read active low with 1 = off. Port C (limit switches and
sensors) reads inactive: high, except for Power Drift, whose sensors MAME
declares active high, so it reads 0x00.

### Verification tooling
The X Board tools carry over as they are: `tools/mame_capture.py` and
`frame_diff.py` for frames, `trace_compare.py` for PC traces,
`wav_compare.py` for sound. `tools/mame_trace.py` has to grow from two CPUs
to three (`:maincpu`, `:subx`, `:suby`) and the bench writes three trace
files. Golden data lives in `verif/golden/<set>/`: MAME traces and captures
next to the `*.hex` files that `pack_roms.py --hexdir` writes for the
Verilator and Icarus benches. Each gate script `verif/board/check_mN.sh`
has the shape of the X Board's `check_m1.sh`: build the goldens if missing,
pack the ROMs, `make -C verif/board build` and `run FRAMES=N`, then the
comparison tools with explicit thresholds. Frame checks render the golden
model from the RTL's own RAM dump, not from MAME's frame of the same
number, because the two drift.

## 4. Milestones

Each row has a gate script `verif/board/check_mN.sh` that must pass before
the next starts. Sim on the Mac, Quartus on the Windows box, hardware test
by the user before any rbf is committed.

| M | Scope | Pass criterion |
| --- | --- | --- |
| M0 | Trim the scaffold: `yb_pkg`, `Arcade-SegaYBoard.sv` down to a `yb_core` stub, `romsets.py` with `gforce2`, `x64` loader, descriptor, MRA | `sh verif/lint.sh` and `lint_emu.sh` clean; `tools/tests` pass with the gforce2 zip; Quartus compile of the stub fits and STA is clean |
| M1 | Three 68000s with caches, shared and local RAMs, backup RAM, 5248/5249 x3, 315-5296, MSM6253, IRQ generator, watchdog, sound latch, Z80 stub | cocotb: 5296 and 6253 exact vs models; PC traces of all three CPUs match MAME (`tools/mame_trace.py`) for 500k instructions; IRQ2/4 entries on the same frame and line +-1 |
| M2 | Y sprites into DDR3 with identity scan-out, palette, indirection | `ysprite5305.py` exact on 20 dumped lists incl. zoom, flips, both draw directions, list loops; board frame exact in the Y layer vs the model rendered from the RTL's own RAM dump |
| M3 | Rotation scan-out, rotation RAM swap, scanline colour, cache | `rotate5306.py` exact on dumped rotation RAM for attract-mode frames; DDR3 miss count per line logged from the bench under the budget for the steepest attract rotation |
| M4 | 16B sprites and the mixer | `bsprite5196.py` exact on dumped lists; full frames pixel-exact vs MAME captures at f60/f150/f300 |
| M5 | Sound wired (PCM mask F8, latch NMI, port H mute) | PCM exact vs `segapcm.py`; attract-mode WAV envelope correlation > 0.95 as on the X Board |
| M6 | Hardware bring-up and timing closure, NVRAM, DIPs, controls, OSD | zero negative slack in the fit corner; 30 min attract without a watchdog reset; HDMI capture matches sim |
| M7 | Power Drift (gear shift, motor stub), G-LOC, Strike Fighter (16 MB ROM slot), Rail Chase (gun modes from Line of Fire), R360 | each boots, passes its memory test, plays; MRAs and alternatives regenerated, `db.json.zip`, release |

M1 findings (gforce2, 120 frames). All three CPUs track MAME's executed-PC
trace at 99.7% or better with the X Board thresholds; the resyncs left are
shared-RAM handshakes and polling loops. IRQ2 and IRQ4 are taken once per
frame on main and sub Y in both runs, and the first entries land within a
few dozen instructions of each other, which is the "same frame and line"
criterion. Sub X's IRQ4 handler is a `tas` guard that returns inside the
scanline while the level-4 line is still up, so the 68000 re-enters it six
or seven times per line, in MAME and in the RTL alike; the count differs
between the two (about 6.7 against 5.7 per frame) because the RTL's bus
cycles carry DTACK latency that MAME's do not. Harmless, the guard makes the
re-entries no-ops, but it is the first place the 342-versus-400 line length
(open question 1) would show. The boot sequence confirms the port E wiring:
the main CPU writes 0x4C to port E before making it an output, so both subs
sit in reset (XRES, YRES high) until the main releases them, and MAME's
trace shows the subs' first instructions only after that. On hardware the
M1 build shows the gradient with short blanks: the game drops /KILL for
about 12 frames at each attract-mode scene change (frames 269-281 in the
bench), and kicks /WDCL every other frame, so the MB3773 never fires.

M2 findings (gforce2). The renderer (`rtl/video/yb_ysprite_5305.sv`) is
pixel-exact against the model on all 20 captured lists (1,621 entries:
1,384 zoomed, 89 magnified, 779 flipped, 649 bottom-to-top, 921 right-to-
left) and on a synthetic list with a loop, hidden entries, zoom 0 and height
0, which the game never produces. The board frame is exact against the
model rendered from the RTL's own dumps once the scan-out read runs one
pixel ahead of the framework's sample point (the `-1` in `yb_core`'s
`fbr_xs`); `tools/board_check.py` found the picture one column early
without it. Whether that column belongs to the 315-5306 or to the video
pipeline is settled in M4 against MAME captures, together with the 16B
origin. The rotation parameters in the captures: the identity with a
translation for the first twenty seconds of the attract mode, then mild
rotations (`dyx` up to 0.325, about 18 degrees) from frame 1400 on. A
direct-mapped cache of 128 64-bit words needs 80 DDR3 reads per line on the
identity and 156 at the steepest attract angle; in-game rolls approach one
read per pixel. A full render of the busiest capture (348 entries) takes
well under a frame at one pixel per clock; the erase of 512 lines is 0.7 ms.

M3 findings (gforce2). The scan-out is pixel-exact against the model
(MAME's `rotate_draw`) on all 20 captured rotation parameter sets when fed
the framebuffer the model renders from the same capture, and the board
frame is exact through the whole chain. Two bugs found by the harness on the
way: the cache RAM was read with the registered index (one pixel stale, so
the first pixel of every fetched word came from the previous word), and a
fill and the next lookup hit the RAM in the same clock (every second pixel
of a word missed again). Two more at board level: the renderer's latch of
the twelve rotation words started one state late (every parameter shifted
by 16 bits, which showed up as a scan-out that never moved), and the line
buffer's display side must select its bank in `clk_sys` at every visible
line start, not through the synchronised `clk_ram` pulse, or the first
pixel of a line can come from the previous line. With the buffer read
straight at `hcnt` the blanking is no longer delayed a pixel: M2's `-1`
was the pipeline's, not the chip's. The DDR3 read budget is as predicted by
the Python cache simulation, so the layout question stays open until a
game rolls.

M4 findings (gforce2). Sub Y rewrites the whole 16B list every frame from
the IRQ2 handler, lines 170 to 182 (96 entries), so the snapshot the
renderer takes at line 226, the Y render's trigger, always sees a finished
list. The 315-5196 keeps its per-sprite state in the list (word 5 bits
15:10 accumulate the vertical zoom, word 7 is the row address), which is
why `yb_bsprite_5196` works on a private copy rather than the CPU's RAM:
the copy is stepped line by line exactly as MAME's frame loop steps it,
and the CPU never sees the chip's writes (whether the real chip writes
them back is open question 10). The model chain reproduces MAME's own
screenshots pixel for pixel on the 19 still captures; the three rotating
captures differ because a capture pairs RAMs dumped at frame end with a
picture drawn mid-frame (the Y list at frame end already belongs to the
next frame). The rotation buffer MAME draws with is the RAM as the 198000
read tap sees it, `rotateram_swap.bin`, which `tools/frame_check.py`
prefers.

M4 findings (gforce2). Sub Y rewrites the whole 16B list every frame from
the IRQ2 handler, lines 170 to 182 (96 entries), so the snapshot the
renderer takes at line 226, the Y render's trigger, always sees a finished
list. The 315-5196 keeps its per-sprite state in the list (word 5 bits
15:10 accumulate the vertical zoom, word 7 is the row address), which is
why `yb_bsprite_5196` works on a private copy rather than the CPU's RAM:
the copy is stepped line by line exactly as MAME's frame loop steps it,
and the CPU never sees the chip's writes (whether the real chip writes
them back is open question 10). The model chain reproduces MAME's own
screenshots pixel for pixel on the 19 still captures; the three rotating
captures differ because a capture pairs RAMs dumped at frame end with a
picture drawn mid-frame (the Y list at frame end already belongs to the
next frame). The rotation buffer MAME draws with is the RAM as the 198000
read tap sees it, `rotateram_swap.bin`, which `tools/frame_check.py`
prefers. The 16B renderer is exact against its model on all 22 captured
lists, worst line 2,164 clocks of 6,400. The board's own frames are
pixel-exact against MAME's screenshots at frames 60, 150 and 300 (RTL
frames 61, 151 and 296: the two count from different resets), which is
the first time the whole video path is compared with MAME rather than
with the models; MAME's `+27` and 184 origins and the pipeline's
alignment agree with it to the pixel.

M5 findings (gforce2). The X Board's sound section fits the Y Board with
two changes: the 315-5218 banking (shift 13, an 8-bit bank field under the
descriptor's F8 mask; the engine's model and cocotb test now run that
configuration, banks 0-7 of the 64 KB test ROM) and the mix. MAME routes
the Y Board's PCM at 0.70 and its YM2151 at 0.30 of full scale, exactly
twice the X Board's 0.35 and 0.15, which showed up as a bench recording at
half MAME's level before the gains became parameters of `yb_soundsys`.
With a coin at frame 30 the board's audio correlates with MAME's recording
at 0.969 on the 5 ms envelope (threshold 0.95), 5 ms of lag, RMS 535
against 514. The sound latch is MAME's generic latch: its data-pending
line is the Z80's NMI, raised by the main CPU's write to 082001 and
cleared by the Z80's read of port 40. The Z80 runs from the 4.000 MHz
enables of open question 3; a 0.7% pitch difference against MAME's 4.027
MHz is below what the envelope comparison can see.

M6 findings (gforce2). The test switch pressed at frame 200 brings up the
game's TEST MODE menu, pixel-exact against MAME's frame 300 with the same
press (the game wants an edge during the attract; a level held from reset
does nothing in either MAME or the core, which is what the X Board notes
had recorded as MAME's Lua not working). The coin and Start reach the game
through port B and it goes to the Scene Select. Along the way the MSM6253's
reverse arithmetic was off by one: MAME's `PORT_REVERSE` on a 1..FF range
is `0x100 - value`, so a centred stick stays 0x80, where `255 - value` had
left every reversed channel one count deflected. The RTL's and MAME's
frame counts drift by a frame or two over a few hundred frames (59.64
against 60 Hz), so a press in the bench has to be placed on the game's
frame, not MAME's, for animated screens to line up. The Scene Select
itself does not line up for another reason: MAME enters it with Scene A
in the centre of the carousel, the core with Scene E, from the first frame
of the screen and regardless of a one-frame shift of the presses, while
the text and frames (16B) agree and the model chain reproduces both
MAME's screenshot from MAME's dumps and the core's frame from the core's.
It is game state the two runs do not share (open question 11); the lever
reading is the suspect, since the game says "select by control lever". The
board check on that screen also taught the bench something. "Select by
control lever" is 16B text the game blinks, and it rewrites the whole 16B
list every frame at lines 170-182. The 315-5196 copy is taken at line 226
and drives that frame's own lines, whereas the Y buffer a frame shows was
rendered during the previous frame (kicked at 226, walked from about 234
after sub X's list writes at 227, swapped at 223). The bench had dumped
everything at line 226 of frame N and compared frame N+1, which is right
for the Y layer and one frame stale for the 16B one; only static screens
forgave it. `+dumpframe=N` now dumps the Y list and the rotation buffer as
the render for frame N starts (in N-1), the 16B list at line 226 of N and
the palette when N's last visible line has been scanned, and `board_check`
compares frame N.

The first hardware session found the stick: the ship drifted up and left
with the stick centred. The MSM6253 shifted its register on the bus
strobe, which is one clock at the start of the cycle, while the 68000
latches the data after DTACK several clocks later, so every read handed
the CPU the next bit and the game assembled `(value << 1) & 0xFF`: 0x80
became 0x00 on both axes. The unit test had sampled D7 before the strobe
and passed. The chip now latches the outgoing bit on the strobe before it
shifts, and the test samples the way the CPU does. With that the Scene
Select is pixel-exact against MAME's frame 400, carousel included, which
closes open question 11. Any register that changes state on a read has to
be checked this way, at the CPU's latch point, not the strobe's.

M0 in full, since it is next. Rewrite `rtl/yb_pkg.sv` from the tables in
section 3 (clocks, SDRAM and DDR3 map, stream offsets, `board_desc_t`). Trim
`Arcade-SegaYBoard.sv` to a `yb_core` stub whose port list is the Y Board's
(three CPU resets, the 5296 ports, the ADC channels, two framebuffers, no
road or tile ports) and trim `verif/board/tb_board.sv` to match. Fill
`tools/romsets.py` with `SLOT`, `ORDER` and the `gforce2` entry; give
`tools/pack_roms.py` the `x64` loader, the `repeat` count and the new
`descriptor()`; teach `tools/gen_mra.py` `x64` and `repeat`; update
`tools/tests/test_stream.py` and regenerate `releases/`. Delete
`yb_cmptimer_5250.sv` and the other files section 1 lists as not on this
board, and take them out of `references.md`, the `.qsf` and `lint.sh`. Write
`verif/board/check_m0.sh` as the lint plus tool-test gate. Then a Quartus
compile of the stub for the M10K baseline and a clean STA.

M7 findings. The other games needed three things the first one had not.
Power Drift froze on its first screen with no 16B layer: all three CPUs
sat in `tas; bne` loops on shared-RAM flags, and the shared-RAM watch in
the bench (`+watch_a`, `+watch_b`) with the same taps in MAME Lua showed
the lock byte at 0CEB43 set with no owner. Our arbiter served the other
CPUs between the read and write halves of a read-modify-write cycle, so
sub Y's `tas` wrote a stale "held" value back over main's release. A CPU
now keeps the RAM from a read until its next bus cycle (open question 6),
and Galaxy Force II, which never tripped over it, is unchanged by it. The
first hardware session found the same class one level up: with the gas
down, Power Drift froze entering Stage 1, main polling `bclr #2,0CFF12`
for sub Y's acknowledge, and the byte watch showed sub Y's `0404` landing
between the read and the write of main's `bclr` and being overwritten
with the `00` main had read. `bclr` on memory is two plain bus cycles a
few clocks apart, so a hold that ended when AS negated did not cover it;
the hold now lasts until the holder's next bus cycle, with the RMW write
served first and an instruction fetch releasing it. With that Power Drift
enters Stage 1 and races in the bench, on the same frames as MAME.

G-LOC R360's reset on the way into a fight was a different thing. The
three-CPU trace comparison (`mame_trace.py` can now press Coin and Start
and use a saved cfg for the DIPs) put main at 006C16, `move.l d0,(a0)+`
into 040000, which is ROM space: the game clears 64 KB there before the
fight. MAME drops writes to ROM; the core's ROM decode only acknowledged
reads, so main sat on that write with no DTACK, the subs idled on the
"FIGHTING COURSE" card, and 300 frames later the watchdog reset the
board, the 000400 fetch the trace showed. Writes into ROM space are now
acknowledged and dropped on all three CPUs, and the bench logs them
(`ROMWR`); with that R360's Fighting Only course takes off in the bench
25 frames after MAME's, no reset. Second,
MAME composes layout artwork into its screenshots for GAMEL sets; Power
Drift's gear-shifter overlay sat in the lower right corner of every
capture until `mame_capture.py` passed `-snapview native`. Third, a game
that boots one or two frames later than MAME's shows its self-timed
animations out of phase: Power Drift's kart markers on the track map,
G-LOC's scrolling HUD tape and blinking LOCK ON, and Power Drift's sky
gradient, which the game ramps from a counter that does not follow the
same offset as its sprites (the palette at the end of the RTL's frame has
the same two colours as MAME's in the gradient entries, a few entries
apart). `frame_diff --step-ok --max-far N` counts single-step palette
differences apart and allows N pixels of anything else; the gate uses
200. With that Power Drift, G-LOC and G-LOC R360 are within a few pixels
of MAME at frames 150 and 300, R360 at 4 and 1. Power Drift's LIMITSW port
reads 0xE4, MAME's value for its four active-high sensor bits. The Python
model chain, run on MAME's own Power Drift dumps, does not reproduce
MAME's frame (41,597 of 71,680 at frame 150) while the RTL does, so the
models or the capture's rotation-buffer choice have a Power Drift problem
the core does not (open question 12).

## 5. Open questions (MAME is the default answer until hardware says otherwise)
1. Horizontal total and pixel clock: MAME's 342 columns come from `set_size`, not a measured `set_raw`, so they carry no weight against the X Board's 400 at 6.25 MHz. Assume 400; a scope on a real board or a known refresh rate would settle it.
2. IRQ2 scanline: MAME's 170 is a tuned constant; the real source is the 315-5306. Descriptor byte 7, so it can be tuned per game without a rebuild, and MAME's Q/W/E/R hotkeys give a reference value per game from captures.
3. Sound crystal: 32.2159 MHz / 8 (MAME) or 16 MHz / 4 (PCB notes). Pitch differs by 0.7%; go with the PCB notes' 4.000 MHz unless a recording says otherwise.
4. Y framebuffer cadence. What Galaxy Force II does (bench `+trace_vid`): sub Y reads 198000 (the rotation swap) at line 223 every other frame, from the IRQ4 handler; sub X writes word 7 of sprite entry 0 at line 223 of every frame, cycling the list head through four lists at entries 0x600, 0x880, 0xB00 and 0xD80, and fills the lists that are not linked in during the following frame (from line 233). So the list the renderer walks is never being written. M2 therefore renders every frame from the live sprite RAM starting at line 226, erases the whole back buffer first (MAME's full FFFF fill), and swaps at the next vblank; the scan-out translation is latched with the render. What the real chips do between the swap read and the vblank is still unknown, and so is whether they render continuously; the visible result would be the same for this game.
5. The `+27` X offset in the rotation and the 16B origin of 184: MAME calibrations. M4's full frames match MAME's screenshots to the pixel with both, so the core is faithful to MAME; whether MAME is faithful to the board is a question for a real PCB.
6. Shared RAM arbitration between three CPUs (PALs 315-5314..5318): wait-state behaviour unknown; one access per clock in priority order is the model, and since M7 a CPU keeps the RAM from a read until its next bus cycle begins, which makes a `tas` and the two-cycle `bclr`/`bset`/`addq` on memory atomic across CPUs (M7 findings). Whether the PALs stall the others for exactly that long is not known; what is known is that Power Drift's lock and request/acknowledge protocols need it and that MAME, whose instructions are atomic, never sees the race.
7. 16B sprite zoom clamp: MAME clamps hzoom and vzoom to a minimum of 0x40 ("maximum of 8x, not 100% confirmed"); MacDonald's System 16 notes give the valid range as 0..0x3FF with odd behaviour above. Same parameter as the X Board, MAME's value by default. The Y sprite generator only has the zoom 0 to 1 clamp, which is MAME's guard and not a hardware claim.
8. MSM6253 timing: the conversion clock is the 315-5296's CKOT output, whose divider is in the CNT register MAME does not emulate, so the delay from the channel write to a valid first read is unknown; MAME makes it instant. Also whether the shift register reloads only on the write. Log the CNT writes in M1 and pick the divider from them.
9. Deluxe cabinets: what the motor board answers on port C and the ADC once a game starts driving it. MAME never runs the motor Z80, so the stub returns inactive limit switches and centred pitch and roll; if a deluxe set refuses to start on that, the answer is in its motor ROM.
10. 315-5196 write-back: MAME writes the zoom accumulator and row address into sprite RAM words 5 and 7 as it draws. The core keeps them in a private copy, so a game that reads them back would see the CPU's values; no known game does.
11. Resolved. Galaxy Force II's Scene Select centred on Scene E in the core and Scene A in MAME because the MSM6253 read path handed the CPU the bit after the shift (M6 findings), so the lever read 0x00 at rest and the carousel scrolled. With the bit latched on the strobe the frame after Start is pixel-exact against MAME's (`check_m6.sh`, frame 400).
12. The golden models on Power Drift: `frame_check` from MAME's frame-150 dumps gives 41,597 of 71,680 pixels, the whole Y layer wrong, while the RTL matches MAME to within the animation phase. Galaxy Force II's dumps reproduce exactly. Suspects are the capture's choice of rotation buffer (`rotateram_swap.bin` is the RAM as the 198000 read tap sees it, and Power Drift's swap cadence differs) or a list-timing assumption in `ysprite5305.py`. Worth settling before the models are used to argue with the RTL on that game.
