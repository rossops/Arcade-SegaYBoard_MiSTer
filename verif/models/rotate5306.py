"""315-5306 scan-out, ported from MAME segaic16.cpp rotate_draw (0.289).

scanout(fb, rotbuf) -> (palette index grid, priority grid), 320 x 224. The
affine walk starts at (currx + 27 dxx, curry + 27 dyx) and steps (dxx, dyx)
per pixel and (dxy, dyy) per line; a written framebuffer pixel maps to
0x1000 | colour/priority bits | pen, an empty one to its source line number
(the scanline colour) with priority FF. translate_only replaces the matrix
by the identity (M2's scan-out). The implementation lives in ysprite5305.py
next to the renderer it reads from; this module is the name the design
notes use for the chip."""
from .ysprite5305 import scanout, rot_params  # noqa: F401
