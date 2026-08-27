#!/usr/bin/env python3
"""Build the ioctl index-0 byte stream for a ROM set from a MAME zip.

    pack_roms.py gforce2 --zip path/to/gforce2.zip --out stream.bin [--hexdir DIR]

The stream is exactly what the MRA makes the MiSTer host send (little-endian
16-bit words, WIDE=1): 64-byte descriptor, then each region in yb_pkg order,
padded to its slot except the last one. --hexdir also writes one $readmemh
file per region (16-bit words, SDRAM word order) for the simulators.
"""
import argparse, os, sys, zipfile, zlib

sys.path.insert(0, os.path.dirname(__file__))
from romsets import ROMSETS, SLOT, ORDER, DESC_SIZE


def descriptor(rs):
    d = bytearray(DESC_SIZE)
    d[0] = rs["game_id"]
    d[1] = (rs.get("deluxe", 0) & 1) | ((rs.get("link", 0) & 1) << 1) | ((rs.get("r360", 0) & 1) << 2)
    d[2] = rs["yspr_banks"]
    d[3] = rs["bspr_banks"]
    d[4] = rs["adc_reverse"]
    d[5] = rs["pcm_bankmask"]
    d[6] = rs["ana_mode"] & 7
    d[7] = rs.get("irq2_line", 170)
    return bytes(d)


def file_fields(f):
    """(name, size, crc, repeat) from a 3- or 4-tuple."""
    return f[0], f[1], f[2], (f[3] if len(f) > 3 else 1)


def read_rom(zf, name, size, crc):
    try:
        data = zf.read(name)
    except KeyError:
        # merged sets may keep the parent files at top level and clones in dirs
        cands = [n for n in zf.namelist() if n.split("/")[-1] == name]
        if not cands:
            raise SystemExit(f"missing ROM {name}")
        data = zf.read(cands[0])
    if len(data) != size:
        raise SystemExit(f"{name}: size {len(data):#x} != {size:#x}")
    got = f"{zlib.crc32(data) & 0xffffffff:08x}"
    if got != crc:
        raise SystemExit(f"{name}: crc {got} != {crc}")
    return data


def build_region(loader, roms):
    """Return the region bytes in the order the 16-bit SDRAM words are read."""
    if loader == "flat":
        return b"".join(roms)
    if loader == "w16":
        out = bytearray()
        for i in range(0, len(roms), 2):
            even, odd = roms[i], roms[i + 1]
            assert len(even) == len(odd)
            # 68000 big-endian word = (even byte << 8) | odd byte. The stream is
            # little-endian words, so emit (odd, even) byte pairs: the word the
            # loader writes to SDRAM then reads back as {even, odd}.
            for j in range(len(even)):
                out += bytes((odd[j], even[j]))
        return bytes(out)
    if loader == "x64":
        out = bytearray()
        for i in range(0, len(roms), 8):
            g = roms[i:i + 8]
            assert len(g) == 8 and all(len(x) == len(g[0]) for x in g)
            # MAME REGION64_BE: ROM k is byte k of the big-endian 64-bit word,
            # ROM 0 most significant. Stored as four 16-bit words, word 0 =
            # {ROM0, ROM1}, so the pens read out in order; each word is emitted
            # low byte first like the w16 case.
            for j in range(len(g[0])):
                out += bytes((g[1][j], g[0][j], g[3][j], g[2][j], g[5][j], g[4][j], g[7][j], g[6][j]))
        return bytes(out)
    raise ValueError(loader)


def last_region(rs):
    """Index in ORDER of the last region the set populates; the stream ends there."""
    return max(i for i, r in enumerate(ORDER) if rs["regions"].get(r, ("flat", []))[1])


def build_stream(setname, zippath):
    rs = ROMSETS[setname]
    regions = {}
    last = last_region(rs)
    with zipfile.ZipFile(zippath) as zf:
        for idx, region in enumerate(ORDER[:last + 1]):
            loader, files = rs["regions"].get(region, ("flat", []))
            roms = []
            for f in files:
                n, s, c, rep = file_fields(f)
                if rep > 1 and loader != "flat":
                    raise SystemExit(f"{n}: repeat is only supported in flat regions")
                roms.append(read_rom(zf, n, s, c) * rep)
            data = build_region(loader, roms)
            if len(data) > SLOT[region]:
                raise SystemExit(f"{region}: {len(data):#x} exceeds slot {SLOT[region]:#x}")
            # MAME's PCM region is ROMREGION_ERASEFF: unpopulated ROM reads 0xFF.
            # The last region is not padded (it is the 16 MB Y sprite slot).
            fill = b"\xff" if region == "pcm" else b"\x00"
            pad = 0 if idx == last else SLOT[region] - len(data)
            regions[region] = data + fill * pad
    stream = descriptor(rs) + b"".join(regions[r] for r in ORDER[:last + 1])
    return stream, regions


def write_hex(path, data):
    with open(path, "w") as f:
        for i in range(0, len(data), 2):
            f.write(f"{data[i] | (data[i+1] << 8):04x}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--zip", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--hexdir")
    a = ap.parse_args()
    stream, regions = build_stream(a.set, a.zip)

    with open(a.out, "wb") as f:
        f.write(stream)
    if a.hexdir:
        os.makedirs(a.hexdir, exist_ok=True)
        for r, d in regions.items():
            write_hex(os.path.join(a.hexdir, f"{r}.hex"), d)
    print(f"{a.out}: {len(stream)} bytes ({len(stream)/1048576:.2f} MB)")


if __name__ == "__main__":
    main()
