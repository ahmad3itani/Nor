"""Cell-edge clip check shared by the rigs and build_chars.py.

A frame 'clips' when any opaque pixel sits in row 0, column 0 or the last column
of its cell (the sprite would be cut off in game). Bottom row is allowed (feet).
Usage: python3 cellcheck.py <sheet.png>...   (reads the .tres next to each png)
"""
from __future__ import annotations
import re, sys, os
import numpy as np
from PIL import Image

def parse_tres(tres):
    t = open(tres).read()
    cw, ch = map(int, re.search(r"cell_size = Vector2i\((\d+), (\d+)\)", t).groups())
    anims = [(n, int(r), int(c)) for n, r, c in re.findall(r'name = &"(\w+)"\nrow = (\d+)\nfirst_frame = 0\nframe_count = (\d+)', t)]
    return (cw, ch), anims

def frame_edges(cell_alpha):
    e = []
    if cell_alpha[0].any(): e.append("T")
    if cell_alpha[:, 0].any(): e.append("L")
    if cell_alpha[:, -1].any(): e.append("R")
    return e

def clips(png, tres=None, exempt=()):
    tres = tres or png[:-4] + ".tres"
    (cw, ch), anims = parse_tres(tres)
    a = np.asarray(Image.open(png).convert("RGBA"))[..., 3] > 0
    out = []
    for n, r, c in anims:
        if n in exempt:
            continue
        for k in range(c):
            e = frame_edges(a[r * ch:(r + 1) * ch, k * cw:(k + 1) * cw])
            if e:
                out.append(f"{n}[{k}]:{''.join(e)}")
    return out

if __name__ == "__main__":
    bad = 0
    for p in sys.argv[1:]:
        c = clips(p)
        print(os.path.basename(p), "OK" if not c else " ".join(c))
        bad += bool(c)
    sys.exit(1 if bad else 0)
