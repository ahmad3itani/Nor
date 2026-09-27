"""Rook AD-redo review: composites over uc_far+fog at x3, x4 slide/dash, metrics."""
import re, sys, numpy as np
from PIL import Image
from review import comp, cells, changed, silhouette, REV, OUT
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402
P = OUT + "/rook/rook_sheet.png"
t = open(OUT + "/rook/rook_sheet.tres").read()
rows = {n: (int(r), int(c)) for n, r, c in re.findall(r'name = &"(\w+)"\nrow = (\d+)\nfirst_frame = 0\nframe_count = (\d+)', t)}
def an(n): r, c = rows[n]; return cells(P, 48, 48, r, c)
tag = sys.argv[1] if len(sys.argv) > 1 else "after"
comp([an("idle")[0], an("idle")[4], an("run")[1], an("run")[5], an("blade_heavy")[2], an("blade_light_1")[2]], f"{REV}/rook_{tag}_uc_x3.png")
comp(an("slide") + an("dash"), f"{REV}/rook_{tag}_slide_dash_x4.png", scale=4)
comp([an(f"katar_light_{i}")[2] for i in range(1, 5)] + [an("shoot_pistol")[1], an("shoot_scatter")[1], an("shoot_revolver")[2]], f"{REV}/rook_{tag}_katar_guns_x3.png")
for n in ("slide", "dash", "katar_light_1", "katar_light_2", "katar_light_3", "katar_light_4", "idle"):
    fr = an(n)
    d = [changed(a, b) for a, b in zip(fr, fr[1:])]
    boxes = [Image.Image.getbbox(f) for f in fr]
    hts = [b[3] - b[1] for b in boxes]
    print(n, "diffs", d, "bbox", boxes[len(boxes) // 2], "heights", hts)
# coat width at hem height (idle): widest run of coat colours in the lower 12 rows above the boots
a = np.asarray(an("idle")[0]); coat = {(0x6e,0x68,0x80),(0xa9,0xa3,0xb8),(0xd8,0xd4,0xe0),(0xf2,0xef,0xf7)}
w = []
for y in range(20, 44):
    xs = [x for x in range(48) if a[y, x, 3] and tuple(a[y, x, :3]) in coat]
    if xs: w.append((y, max(xs) - min(xs) + 1))
print("idle coat widths by row", w)
