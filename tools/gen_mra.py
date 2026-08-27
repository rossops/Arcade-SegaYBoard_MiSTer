#!/usr/bin/env python3
"""Generate MiSTer .mra files for every set in tools/romsets.py.

    gen_mra.py [--outdir releases]

The <rom index="0"> part must produce byte-for-byte the stream pack_roms.py
builds (tests/test_stream.py checks that).
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from romsets import ROMSETS, SLOT, ORDER, DESC_SIZE
from pack_roms import descriptor, last_region, file_fields

RBF = "Arcade-SegaYBoard"


def hexbytes(b):
    return " ".join(f"{x:02x}" for x in b)


def region_parts(loader, files, slot, fill="00", pad_to_slot=True):
    lines = []
    total = 0
    files = [file_fields(f) for f in files]
    if loader != "flat" and any(rep > 1 for _, _, _, rep in files):
        raise SystemExit("repeat is only supported in flat regions")
    if loader == "flat":
        for n, s, c, rep in files:
            # MAME ROM_RELOAD mirrors: the same file listed again
            for _ in range(rep):
                lines.append(f'      <part name="{n}" crc="{c}"/>')
            total += s * rep
    elif loader == "w16":
        for i in range(0, len(files), 2):
            (e, s, ec, _), (o, _, oc, _) = files[i], files[i + 1]
            lines.append('      <interleave output="16">')
            # map digits are byte positions, rightmost = byte 0. The stream word
            # is little-endian and must read back as {even, odd} (68000 order),
            # so the even ROM is byte 1 ("10") and the odd ROM byte 0 ("01").
            lines.append(f'        <part name="{e}" crc="{ec}" map="10"/>')
            lines.append(f'        <part name="{o}" crc="{oc}" map="01"/>')
            lines.append('      </interleave>')
            total += 2 * s
    elif loader == "x64":
        for i in range(0, len(files), 8):
            grp = files[i:i + 8]
            lines.append('      <interleave output="64">')
            # ROM k is byte k of MAME's big-endian 64-bit word; stored as four
            # little-endian 16-bit words with ROM 0 in the high byte of word 0,
            # so ROM k lands in output byte k ^ 1 (pack_roms.build_region).
            for k, (n, s, c, _) in enumerate(grp):
                m = ["0"] * 8
                m[7 - (k ^ 1)] = "1"
                lines.append(f'        <part name="{n}" crc="{c}" map="{"".join(m)}"/>')
            lines.append('      </interleave>')
            total += 8 * grp[0][1]
    else:
        raise ValueError(loader)
    pad = slot - total
    if pad < 0:
        raise SystemExit("region exceeds slot")
    if pad and pad_to_slot:
        lines.append(f'      <part repeat="{pad}">{fill}</part>')
    return lines


def make_mra(key, rs):
    L = []
    L.append('<misterromdescription>')
    L.append(f'  <name>{rs["name"]}</name>')
    L.append(f'  <setname>{key}</setname>')
    L.append(f'  <rbf>{RBF}</rbf>')
    L.append(f'  <mameversion>0289</mameversion>')
    L.append(f'  <year>{rs["year"]}</year>')
    L.append('  <manufacturer>Sega</manufacturer>')
    L.append(f'  <category>{rs.get("category", "Shooter / Flight")}</category>')
    zips = rs["zipfile"] + ".zip" if rs["zipfile"] == key else "|".join(
        f"{z}.zip" for z in [key] + rs.get("extra_zips", []) + [rs["zipfile"]])
    L.append(f'  <rom index="0" zip="{zips}" md5="None">')
    L.append(f'    <part>{hexbytes(descriptor(rs))}</part>')
    last = last_region(rs)
    for idx, region in enumerate(ORDER[:last + 1]):
        loader, files = rs["regions"].get(region, ("flat", []))
        L.append(f'    <!-- {region} -->')
        # the last region (the 16 MB Y sprite slot) ships unpadded
        L += region_parts(loader, files, SLOT[region], "FF" if region == "pcm" else "00", idx != last)
    L.append('  </rom>')
    # sub X backup RAM (16 KB) saved as NVRAM index 3
    L.append('  <nvram index="3" size="16384"/>')
    # DIP switches: raw port values (1 = off). Defaults are MAME's.
    L.append(f'  <switches default="{rs["dip_default"]}" base="0">')
    for lo, hi, name, ids in rs["dips"]:
        bits = f"{lo}" if lo == hi else f"{lo},{hi}"
        L.append(f'    <dip bits="{bits}" name="{name}" ids="{ids}"/>')
    L.append('  </switches>')
    names, default = rs["buttons"]
    L.append(f'  <buttons names="{names}" default="{default}"/>')
    L.append('</misterromdescription>')
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=os.path.join(os.path.dirname(__file__), "..", "releases"))
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    for key, rs in ROMSETS.items():
        # MiSTer layout: one primary MRA per game in releases/, the other
        # versions under releases/_alternatives/_<game>/
        sub = os.path.join("_alternatives", "_" + rs["alt"]) if "alt" in rs else ""
        os.makedirs(os.path.join(a.outdir, sub), exist_ok=True)
        path = os.path.join(a.outdir, sub, f'{rs["name"]}.mra')
        with open(path, "w") as f:
            f.write(make_mra(key, rs))
        print(path)


if __name__ == "__main__":
    main()
