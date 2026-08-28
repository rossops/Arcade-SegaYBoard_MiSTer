"""315-5305 Y Board sprite generator and the 315-5306 scan-out, ported from
MAME sega16sp.cpp sega_yboard_sprite_device::draw and segaic16.cpp
rotate_draw (0.289).

render(spriteram, rotbuf, rom, numbanks) -> 512 x 512 framebuffer of
16-bit pixels, 0xFFFF = empty. Sprite X and Y are 0x600-based (0x600 =
framebuffer 0); the clip extents in the rotation buffer use the same space.
Pixel = colour[2:0] << 13 | priority[3:0] << 9 | indirected pen[8:0].

scanout(fb, rotbuf) -> (palette index grid, priority grid), 320 x 224,
following the affine parameters at rotbuf[0x3F0..0x3FB]; translate_only
replaces the matrix by the identity (M2's scan-out) and keeps the
translation, so the model and the RTL are compared like for like until M3.
"""
FB = 512
WIDTH, HEIGHT = 320, 224
XORIGIN = 0x600
YORIGIN = 0x600


def s8(v):
    v &= 0xff
    return v - 0x100 if v & 0x80 else v


def s32(v):
    v &= 0xffffffff
    return v - 0x100000000 if v & 0x80000000 else v


def load_rom_qwords(zf, names):
    """Eight ROMs per group, LOAD64_BYTE: ROM k is byte k of the big-endian
    64-bit word (ROM 0 most significant). Returns a list of 64-bit ints."""
    def read(n):
        c = [e for e in zf.namelist() if e.split("/")[-1] == n]
        return zf.read(c[0])
    out = []
    for g in range(0, len(names), 8):
        roms = [read(n) for n in names[g:g + 8]]
        for j in range(len(roms[0])):
            w = 0
            for k in range(8):
                w = (w << 8) | roms[k][j]
            out.append(w)
    return out


def render(spriteram, rotbuf, rom, numbanks, clip=(0, FB - 1, 0, FB - 1)):
    """spriteram: 32768 words (sub X's 64 KB); rotbuf: 1024 words, the
    rotation RAM bank the CPU is not writing; rom: 64-bit words, bank n at
    n * 0x10000; numbanks = ROM bytes / 0x80000 (0 = no wrap)."""
    min_x, max_x, min_y, max_y = clip
    fb = [[0xFFFF] * FB for _ in range(FB)]
    visited = bytearray(0x1000)
    nxt = 0
    while True:
        d = spriteram[nxt * 8:nxt * 8 + 8]
        if (d[0] & 0x8000) or visited[nxt]:
            break
        hide = d[0] & 0x5000
        indirect = spriteram[(d[0] & 0x7ff) << 4:((d[0] & 0x7ff) << 4) + 16]
        bank = ((d[1] >> 8) & 0x10) | ((d[2] >> 12) & 0x0f)
        xpos = d[1] & 0xfff
        top = d[2] & 0xfff
        addr = d[3]
        height = d[4]
        ydelta = 1 if (d[5] & 0x4000) else -1
        flip = (~d[5] >> 13) & 1
        xdelta = 1 if (d[5] & 0x1000) else -1
        zoom = d[5] & 0x7ff
        colpri = (d[6] << 1) & 0xfe00
        pitch = s8(d[6])
        visited[nxt] = 1
        nxt = d[7] & 0xfff
        if hide or height == 0:
            continue
        if numbanks:
            bank %= numbanks
        sbase = 0x10000 * bank
        if zoom == 0:
            zoom = 1
        ytarget = top + ydelta * height
        yacc = 0
        y = top
        while y != ytarget:
            fy = y - YORIGIN
            if min_y <= fy <= max_y:
                minx = rotbuf[fy & ~1]
                maxx = rotbuf[fy | 1]
                if (minx & 0x8000) and ydelta < 0:
                    break
                if (minx & 0x4000) and ydelta > 0:
                    break
                if not (minx & 0xc000):
                    if minx < XORIGIN + min_x: minx = XORIGIN + min_x
                    if maxx > XORIGIN + max_x: maxx = XORIGIN + max_x
                    row = fb[fy]
                    x = xpos
                    xacc = 0
                    offs = (addr - 1) & 0xffff if not flip else (addr + 1) & 0xffff
                    while (xdelta > 0 and x <= maxx) or (xdelta < 0 and x >= minx):
                        offs = (offs + 1) & 0xffff if not flip else (offs - 1) & 0xffff
                        pixels = rom[sbase + offs] if sbase + offs < len(rom) else 0
                        pix = 0
                        for sh in (range(60, -1, -4) if not flip else range(0, 64, 4)):
                            pix = (pixels >> sh) & 0xf
                            ind = indirect[pix]
                            while xacc < 0x200:
                                if minx <= x <= maxx and ind < 0x1fe:
                                    row[x - XORIGIN] = colpri | ind
                                x += xdelta
                                xacc += zoom
                            xacc -= 0x200
                        if pix == 0xf:
                            break
            yacc += zoom
            addr = (addr + pitch * (yacc >> 9)) & 0xffff
            yacc &= 0x1ff
            y += ydelta
    return fb


def rot_params(rotbuf):
    q = lambda i: s32((rotbuf[i] << 16) | rotbuf[i + 1])
    return q(0x3f0), q(0x3f2), q(0x3f4), q(0x3f6), q(0x3f8), q(0x3fa)   # currx, curry, dyy, dxx, dxy, dyx


def scanout(fb, rotbuf, width=WIDTH, height=HEIGHT, translate_only=False, colorbase=0):
    """MAME rotate_draw: (palette index, priority) per screen pixel. Written
    framebuffer pixels map to 0x1000 | colour/priority bits | pen, empty
    ones to the source row number (the scanline colour) with priority FF."""
    currx, curry, dyy, dxx, dxy, dyx = rot_params(rotbuf)
    if translate_only:
        dxx = dyy = 1 << 14
        dxy = dyx = 0
    currx += dxx * 27      # cliprect.min_x + 27, min_y = 0
    curry += dyx * 27
    idx = [[0] * width for _ in range(height)]
    pri = [[0] * width for _ in range(height)]
    for y in range(height):
        tx, ty = currx, curry
        di, dp = idx[y], pri[y]
        for x in range(width):
            sx = (tx >> 14) & 0x1ff
            sy = (ty >> 14) & 0x1ff
            pix = fb[sy][sx]
            if pix != 0xFFFF:
                di[x] = (pix & 0x1ff) | ((pix >> 6) & 0x200) | ((pix >> 3) & 0xc00) | 0x1000
                dp[x] = ((pix >> 8) | 1) & 0xff
            else:
                di[x] = colorbase + sy
                dp[x] = 0xff
            tx += dxx
            ty += dyx
        currx += dxy
        curry += dyy
    return idx, pri
