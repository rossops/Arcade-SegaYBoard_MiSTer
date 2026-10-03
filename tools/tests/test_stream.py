"""The MRA the host expands and the packer's stream must be byte-identical,
and every region must match MAME's ROM CRCs. Both feed the same descriptor and
SDRAM slots, so a drift here would silently misplace ROMs on hardware."""
import os, sys, zipfile, zlib
import pytest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, ".."))
import romsets, pack_roms, gen_mra

ZIPDIR = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"


def expand_mra(text, zf):
    """Minimal MRA expander for the subset gen_mra emits."""
    import re
    out = bytearray()
    # only <rom index="0"> is the stream; a hiscore <rom index="5"> is not
    lines = text.splitlines()
    end = next(i for i, l in enumerate(lines) if l.strip() == "</rom>")
    lines = lines[:end]
    i = 0
    def rom(name):
        c = [n for n in zf.namelist() if n.split("/")[-1] == name]
        return zf.read(c[0])
    while i < len(lines):
        s = lines[i].strip()
        m = re.match(r'<part repeat="(\d+)">([0-9A-Fa-f]{2})</part>', s)
        if m:
            out += bytes([int(m.group(2), 16)]) * int(m.group(1))
        elif s.startswith("<part>") and s.endswith("</part>"):
            out += bytes.fromhex(s[6:-7].replace(" ", ""))
        elif s.startswith('<part name="') and s.endswith('/>') and "map=" not in s:
            out += rom(re.search(r'name="([^"]+)"', s).group(1))
        elif s.startswith('<interleave output="'):
            width = int(re.search(r'output="(\d+)"', s).group(1)) // 8
            parts = []
            i += 1
            while "</interleave>" not in lines[i]:
                m = re.search(r'name="([^"]+)".* map="([01]+)"', lines[i])
                parts.append((rom(m.group(1)), m.group(2)))
                i += 1
            n = len(parts[0][0])
            for j in range(n):
                word = bytearray(width)
                for data, mp in parts:
                    # map is MSB-first over the output word; MiSTer emits LE
                    for k, ch in enumerate(reversed(mp)):
                        if ch == "1":
                            word[k] = data[j]
                out += word
        i += 1
    return bytes(out)


@pytest.mark.parametrize("key", list(romsets.ROMSETS))
def test_mra_matches_packer(key):
    rs = romsets.ROMSETS[key]
    zp = os.path.join(ZIPDIR, rs["zipfile"] + ".zip")
    if not os.path.exists(zp):
        pytest.skip("ROM zip not available")
    try:
        stream, regions = pack_roms.build_stream(key, zp)
    except SystemExit as e:
        # a clone whose files this ROM collection lacks: the MRA is still
        # generated from MAME's CRCs and CI's mra_rom_check covers it
        pytest.skip(f"{e} in the local {rs['zipfile']}.zip")
    last = pack_roms.last_region(rs)
    # every region padded to its slot except the last one
    expected = romsets.DESC_SIZE + sum(romsets.SLOT[r] for r in romsets.ORDER[:last]) + len(regions[romsets.ORDER[last]])
    assert len(stream) == expected
    with zipfile.ZipFile(zp) as zf:
        mra = expand_mra(gen_mra.make_mra(key, rs), zf)
    assert len(mra) == len(stream)
    assert mra == stream


@pytest.mark.parametrize("key", list(romsets.ROMSETS))
def test_region_crcs(key):
    rs = romsets.ROMSETS[key]
    zp = os.path.join(ZIPDIR, rs["zipfile"] + ".zip")
    if not os.path.exists(zp):
        pytest.skip("ROM zip not available")
    with zipfile.ZipFile(zp) as zf:
        for region, (loader, files) in rs["regions"].items():
            for f in files:
                n, s, c, _ = pack_roms.file_fields(f)
                try:
                    pack_roms.read_rom(zf, n, s, c)   # raises on mismatch
                except SystemExit as e:
                    if "missing ROM" in str(e):
                        pytest.skip(f"{e} in the local {rs['zipfile']}.zip")
                    raise


def test_w16_word_order():
    # even ROM byte goes to the high byte of the SDRAM word (68000 big-endian)
    out = pack_roms.build_region("w16", [bytes([0x12]), bytes([0x34])])
    assert out == bytes([0x34, 0x12])
    assert int.from_bytes(out, "little") == 0x1234


def test_x64_word_order():
    # MAME's 64-bit big-endian word (ROM 0 most significant, 16 pens MSB
    # first) becomes four SDRAM words read in order: word 0 = {ROM0, ROM1}.
    # The Y sprite renderer relies on that to walk the pens left to right.
    out = pack_roms.build_region("x64", [bytes([k + 1]) for k in range(8)])
    assert out == bytes([2, 1, 4, 3, 6, 5, 8, 7])
    words = [int.from_bytes(out[i:i + 2], "little") for i in range(0, 8, 2)]
    assert words == [0x0102, 0x0304, 0x0506, 0x0708]


def test_pcm_mirrors_reach_every_bank():
    # gforce2's two 128 KB PCM ROMs are ROM_RELOADed to fill their 512 KB
    # banks (region populated to 0x180000); the 315-5218 bank mask F8 lets
    # the sample table point into any mirror, so the stream must carry them.
    rs = romsets.ROMSETS["gforce2"]
    files = [pack_roms.file_fields(f) for f in rs["regions"]["pcm"][1]]
    assert sum(s * rep for _, s, _, rep in files) == 0x180000
    parts = gen_mra.region_parts("flat", rs["regions"]["pcm"][1], romsets.SLOT["pcm"], "FF")
    assert sum(1 for p in parts if "epr-11516.106" in p) == 4


@pytest.mark.parametrize("key", [k for k, rs in romsets.ROMSETS.items() if "hiscore" in rs])
def test_hiscore_config(key):
    """hiscore.v parses the header and lines back from the byte stream with
    two-byte lengths, the table must fit the NVRAM window, and the MRA's nvram
    size must be the backup RAM plus that window or the host truncates the
    file."""
    rs = romsets.ROMSETS[key]
    cfg = gen_mra.hiscore_config(rs)
    assert len(cfg) == 16 + 8 * len(rs["hiscore"])
    assert cfg[15] == 0                        # no change mask: lines start at byte 16
    for n, (addr, length, start, end) in enumerate(rs["hiscore"]):
        line = cfg[16 + 8 * n:24 + 8 * n]
        assert int.from_bytes(line[0:4], "big") == addr
        assert int.from_bytes(line[4:6], "big") == length
        assert line[6:8] == bytes([start, end])
        cpu, a = addr >> 21, addr & 0x1FFFFF
        assert (cpu == 0 and a >> 16 == 0x1F) or (cpu == 1 and a >> 14 == 0x7F), "not a RAM the core serves"
    assert sum(e[1] for e in rs["hiscore"]) <= gen_mra.HS_WINDOW
    mra = gen_mra.make_mra(key, rs)
    assert f'<nvram index="3" size="{gen_mra.NVRAM_SIZE + gen_mra.HS_WINDOW}"/>' in mra
