"""ROM set table for the Sega Y Board core.

One entry per supported MAME set, copied from the ROM_START blocks in
src/mame/sega/segaybd.cpp. `regions` lists (region, loader, [files]) in
stream order; a file is (name, size, crc) or (name, size, crc, repeat) where
repeat > 1 reproduces MAME's ROM_RELOAD mirrors (flat regions only). The
loader tells pack_roms/gen_mra how the files interleave:

  'w16'  : pairs of ROMs, LOAD16_BYTE even/odd -> one 16-bit big-endian word
           (68000 program ROMs and the 16B sprite ROMs, REGION16_BE)
  'x64'  : groups of eight ROMs, LOAD64_BYTE -> one 64-bit big-endian word
           stored as four 16-bit words, ROM 0 in the high byte of word 0
           (Y sprite ROMs, REGION64_BE)
  'flat' : ROMs concatenated

Stream/SDRAM slot sizes must match rtl/yb_pkg.sv. Every region is padded to
its slot except the last populated one (always ysprite).

Per-set fields beyond the ROMs: `zipfile` (the MAME merged zip holding the
files, clones live in a subdirectory of the parent's zip), the descriptor
bytes (see yb_pkg.sv and docs/DESIGN.md), `dip_default` (SWA, SWB as MAME's
port values, 1 = off), `dips` [(bit_lo, bit_hi, name, ids ordered by value)]
with SWA in bits 0-7 and SWB in bits 8-15, and `buttons` (MRA names, MiSTer
defaults).
"""

SLOT = {
    "main":    0x080000,
    "subx":    0x040000,
    "suby":    0x040000,
    "z80":     0x010000,
    "pcm":     0x200000,
    "bsprite": 0x200000,
    "ysprite": 0x1000000,
}
ORDER = ["main", "subx", "suby", "z80", "pcm", "bsprite", "ysprite"]
DESC_SIZE = 64

# Sega's standard coinage table (SEGA_COINAGE_LOC), value order 0..15
COINAGE = ("Free Play (if both) or 1C/1C,1C/1C 2/3,1C/1C 4/5,1C/1C 5/6,2C/1C 4/3,"
           "2C/1C 3/2 5/3 6/4,2C/3C,4C/1C,3C/1C,2C/1C,7C/1C,6C/1C,5C/1C,1C/3C,1C/2C,1C/1C")

ROMSETS = {
    "gforce2": {
        "name": "Galaxy Force II",
        "year": "1988",
        "category": "Shooter / Flight",
        "zip": "gforce2",
        "zipfile": "gforce2",
        "game_id": 0,
        "deluxe": 0,
        "link": 0,
        "r360": 0,
        "yspr_banks": 8,
        "bspr_banks": 4,
        "adc_reverse": 0x02,      # stick Y (ADC 1) is PORT_REVERSE in MAME
        "pcm_bankmask": 0xF8,
        "ana_mode": 0,
        "irq2_line": 170,
        # SWA all off; SWB: Demo Sounds on, Energy Timer normal, Shield weak,
        # Difficulty normal, Cabinet upright (MAME defaults)
        "dip_default": "FF,7E",
        "dips": [
            (0, 3, "Coin A", COINAGE),
            (4, 7, "Coin B", COINAGE),
            (8, 8, "Demo Sounds", "On,Off"),
            (9, 10, "Energy Timer", "Hardest,Hard,Easy,Normal"),
            (11, 11, "Shield Strength", "Strong,Weak"),
            (12, 13, "Difficulty", "Hardest,Hard,Easy,Normal"),
            (14, 15, "Cabinet", "City,Upright,Deluxe,Super Deluxe"),
        ],
        "buttons": ("Shoot,Missile,Speed Up,Slow Down,Start,Coin,Pause,Test,Service", "A,B,R2,L2,Start,R,X,L,Select"),
        "regions": {
            "main": ("w16", [
                ("epr-11688.25", 0x20000, "c845f2df"),
                ("epr-11687.24", 0x20000, "1cbefbbf"),
            ]),
            "subx": ("w16", [
                ("epr-11875.81", 0x20000, "c81701c6"),
                ("epr-11874.80", 0x20000, "5301fd79"),
            ]),
            "suby": ("w16", [
                ("epr-11816b.54", 0x20000, "317dd0c2"),
                ("epr-11815b.53", 0x20000, "f1fb22f1"),
            ]),
            "z80": ("flat", [
                ("epr-11693.102", 0x10000, "0497785c"),
            ]),
            "pcm": ("flat", [
                ("mpr-11465.107", 0x80000, "e1436dab"),
                ("epr-11516.106", 0x20000, "19d0e17f", 4),
                ("epr-11814.105", 0x20000, "0b05d376", 4),
            ]),
            "bsprite": ("w16", [
                ("mpr-11467.16", 0x20000, "6e60e736"),
                ("mpr-11468.14", 0x20000, "74ca9ca5"),
                ("epr-11694.17", 0x20000, "7e297b84"),
                ("epr-11695.15", 0x20000, "38a864be"),
            ]),
            "ysprite": ("x64", [
                ("mpr-11469.67",  0x20000, "ed7a2299"),
                ("mpr-11470.75",  0x20000, "34dea550"),
                ("mpr-11477.63",  0x20000, "a2784653"),
                ("mpr-11478.71",  0x20000, "8b778993"),
                ("mpr-11471.86",  0x20000, "f1974069"),
                ("mpr-11472.114", 0x20000, "0d24409a"),
                ("mpr-11479.82",  0x20000, "ecd6138a"),
                ("mpr-11480.110", 0x20000, "64ad66c5"),
                ("mpr-11473.66",  0x20000, "0538c6ec"),
                ("mpr-11474.74",  0x20000, "eb923c50"),
                ("mpr-11481.62",  0x20000, "78e652b6"),
                ("mpr-11482.70",  0x20000, "2f879766"),
                ("mpr-11475.85",  0x20000, "69cfec89"),
                ("mpr-11476.113", 0x20000, "a60b9b79"),
                ("mpr-11483.81",  0x20000, "d5d3a505"),
                ("mpr-11484.109", 0x20000, "b8a56a50"),
                ("epr-11696.65",  0x20000, "99e8e49e"),
                ("epr-11697.73",  0x20000, "7545c52e"),
                ("epr-11700.61",  0x20000, "e13839c1"),
                ("epr-11701.69",  0x20000, "9fb3d365"),
                ("epr-11698.84",  0x20000, "cfeba3e2"),
                ("epr-11699.112", 0x20000, "4a00534a"),
                ("epr-11702.80",  0x20000, "2a09c627"),
                ("epr-11703.108", 0x20000, "43bb7d9f"),
                ("epr-11524.64",  0x20000, "5d35849f"),
                ("epr-11525.72",  0x20000, "9ae47552"),
                ("epr-11532.60",  0x20000, "b3565ddb"),
                ("epr-11533.68",  0x20000, "f5d16e8a"),
                ("epr-11526.83",  0x20000, "094cb3f0"),
                ("epr-11527.111", 0x20000, "e821a144"),
                ("epr-11534.79",  0x20000, "b7f0ad7c"),
                ("epr-11535.107", 0x20000, "95da7a46"),
            ]),
        },
    },
}
