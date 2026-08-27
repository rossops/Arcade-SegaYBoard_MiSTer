"""ROM set table for the Sega X Board core.

One entry per supported MAME set, copied from the ROM_START blocks in
src/mame/sega/segaybd.cpp. `regions` lists (region, loader, [(file, size, crc)])
in stream order; the loader tells pack_roms/gen_mra how the files interleave:

  'w16'  : pairs of ROMs, LOAD16_BYTE even/odd -> one 16-bit big-endian word
  'x32'  : groups of four ROMs, LOAD32_BYTE -> one 32-bit little-endian dword
  'flat' : ROMs concatenated

Stream/SDRAM slot sizes must match rtl/yb_pkg.sv.

Per-set fields beyond the ROMs (carried over from the X Board table; redo for
this board's descriptor): `zipfile` (the MAME merged zip holding the
files, clones live in a subdirectory of the parent's zip), the descriptor
flags (see yb_pkg.sv), `ana_mode` (0 = After Burner analog ranges, 1 = full
range with the throttle on ADC channel 1 and stick Y on channel 2 as Thunder
Blade wires them), `dip_default` (SWA, SWB as MAME's port values, 1 = off),
`dips` [(bit_lo, bit_hi, name, ids ordered by value)] and `buttons`.
"""

SLOT = {
    "main":   0x080000,
    "sub":    0x080000,
    "z80":    0x010000,
    "road":   0x010000,
    "pcm":    0x080000,
    "sprite": 0x400000,
    "tile":   0x040000,
    "key":    0x002000,   # FD1094 key RAM
    "z80b":   0x010000,   # SMGP second sound board Z80
    "pcm2":   0x080000,   # SMGP second 315-5218
}
ORDER = ["main", "sub", "z80", "road", "pcm", "sprite", "tile", "key", "z80b", "pcm2"]
# the stream ends after the last region a set populates (old sets stay short)
DESC_SIZE = 64

# Empty on purpose. For the shape of an entry (regions, zipfile, descriptor
# flags, dips, buttons, alt) see the X Board's tools/romsets.py; pack_roms.py's
# descriptor() must be rewritten for this board's flags at the same time.
ROMSETS = {}
