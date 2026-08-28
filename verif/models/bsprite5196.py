"""315-5196 System 16B sprites as the Y Board uses them, ported from MAME
sega16sp.cpp sega_sys16b_sprite_device::draw (0.289) with the Y Board's
origin (184, 0), no screen flip and the identity bank table.

render(spriteram, rom, numbanks) -> 224 x 320 grid of 16-bit pixels in
screen coordinates, 0xFFFF = empty. Pixel = {ybd priority[3:0], priority
[1:0], colour[5:0], pen[3:0]} (colpri | pen). The chip writes its vertical
zoom accumulator back into word 5 and the row address into word 7 of each
entry; the caller's list is left alone, a copy is modified."""
WIDTH, HEIGHT = 320, 224
XORIGIN = 184


def s8(v):
    v &= 0xff
    return v - 0x100 if v & 0x80 else v


def load_rom_words(zf, names):
    """LOAD16_BYTE pairs (REGION16_BE): even ROM in the high byte."""
    def read(n):
        c = [e for e in zf.namelist() if e.split("/")[-1] == n]
        return zf.read(c[0])
    out = []
    for i in range(0, len(names), 2):
        ev, od = read(names[i]), read(names[i + 1])
        out.extend((ev[j] << 8) | od[j] for j in range(len(ev)))
    return out


def render(spriteram, rom, numbanks, width=WIDTH, height=HEIGHT):
    ram = list(spriteram[:2048])
    fb = [[0xFFFF] * width for _ in range(height)]
    min_x, max_x = XORIGIN, XORIGIN + width - 1
    for base in range(0, 2048, 8):
        d = ram[base:base + 8]
        if d[2] & 0x8000:
            break
        bottom = d[0] >> 8
        top = d[0] & 0xff
        xpos = d[1] & 0x1ff
        hide = d[2] & 0x4000
        flip = d[2] & 0x100
        pitch = s8(d[2])
        addr = d[3]
        bank = (d[4] >> 8) & 0xf
        colpri = ((d[4] & 0xff) << 4) | (((d[1] >> 9) & 0xf) << 12)
        vzoom = (d[5] >> 5) & 0x1f
        hzoom = d[5] & 0x1f
        ram[base + 7] = addr
        if hide or top >= bottom:
            continue
        if numbanks:
            bank %= numbanks
        sbase = 0x10000 * bank
        ram[base + 5] &= 0x03ff
        for y in range(top, bottom):
            addr = (addr + pitch) & 0xffff
            ram[base + 5] = (ram[base + 5] + (vzoom << 10)) & 0xffff
            if ram[base + 5] & 0x8000:
                addr = (addr + pitch) & 0xffff
                ram[base + 5] &= ~0x8000
            if 0 <= y < height:
                row = fb[y]
                xacc = 4 * hzoom
                x = xpos
                offs = (addr - 1) & 0xffff if not flip else (addr + 1) & 0xffff
                while ((xpos - x) & 0x1ff) != 1:
                    offs = (offs + 1) & 0xffff if not flip else (offs - 1) & 0xffff
                    pixels = rom[sbase + offs] if sbase + offs < len(rom) else 0
                    pix = 0
                    for sh in ((12, 8, 4, 0) if not flip else (0, 4, 8, 12)):
                        pix = (pixels >> sh) & 0xf
                        xacc = (xacc & 0x3f) + hzoom
                        if xacc < 0x40:
                            if min_x <= x <= max_x and pix != 0 and pix != 15:
                                row[x - XORIGIN] = colpri | pix
                            x += 1
                    if pix == 15:
                        break
    return fb
