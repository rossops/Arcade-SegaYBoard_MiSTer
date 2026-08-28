"""315-5312 mixer, from MAME segaybd_v.cpp screen_update (0.289): the
rotated Y layer is the base (palette index, priority); a 16B pixel wins
when its priority nibble, shifted, is below the Y priority's low five bits,
and then either shadows the Y pixel (pen 0xE: the palette's effects copy)
or replaces it with 0x800 | pixel[10:0]. Display off is black.

mix(yidx, ypri, bpix) -> (palette index, effects) per pixel."""


def mix_pixel(yidx, ypri, bpix):
    if bpix != 0xFFFF and ((bpix >> 11) & 0x1e) < (ypri & 0x1f):
        if (bpix & 0xf) == 0xe:
            return yidx, True
        return 0x800 | (bpix & 0x7ff), False
    return yidx, False


def mix(yidx, ypri, bfb, width=320, height=224):
    idx = [[0] * width for _ in range(height)]
    eff = [[False] * width for _ in range(height)]
    for y in range(height):
        yi, yp, bb, oi, oe = yidx[y], ypri[y], bfb[y], idx[y], eff[y]
        for x in range(width):
            oi[x], oe[x] = mix_pixel(yi[x], yp[x], bb[x])
    return idx, eff
