"""Rebuild every 'char'-owned asset from the code rigs and check them (ArtValidator rules re-implemented).

Usage: python3 build_chars.py [--check]    (--check: only validate what is in assets/)
Previews (x3 nearest on grey) go to tools/assetgen/_preview/, never into the game folders.
"""
from __future__ import annotations

import glob
import json
import os
import re
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = REDLINE
OUT = ASSETS
RIGS = ["rig_rook.py", "rig_enemies.py", "rig_machines.py", "rig_krail.py", "rig_collector.py", "rig_npcs.py", "rig_sweeper.py", "rig_weapons.py", "rig_portraits.py"]
CHAR_DIRS = ["rook", "enemies", "bosses", "npcs", "undercity/collector_eye", "lowlight/sweeper", "portraits"]
NAME_RULE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)+\.png$")
VALIDATOR_RESERVED = ["ff3b4f", "7fd7ff", "7dff9a", "ffd36b", "9fd8ff"]
# AD redo clip rule: no opaque pixel in row 0 or in the first / last column of any cell (the sprite would be
# cut off in game). Only these edges are exempt, because the sprite is ATTACHED there by design:
ATTACHED_EDGES = {
    "sweeper_sheet.png": "TLR",        # the overhead rail beam runs through the whole cell and joins the next rail piece
    "watcher_sheet.png": "L",          # the wall bracket is bolted to the wall at the cell's left edge
    "collector_eye_sheet.png": "T",    # the rail trolley hangs from the ceiling rail at the cell's top edge
}


def build():
    for r in RIGS:
        subprocess.run([sys.executable, os.path.join(HERE, r)], check=True)
    prev = PREVIEW
    os.makedirs(prev, exist_ok=True)
    for p in glob.glob(os.path.join(OUT, "**", "*_x3.png"), recursive=True):
        if "_preview" not in p:
            shutil.move(p, os.path.join(prev, os.path.basename(p)))


def check():
    errs, rows = [], []
    pngs = [p for p in glob.glob(os.path.join(OUT, "**", "*.png"), recursive=True) if "_preview" not in p
            and any(("/" + d) in p for d in ["rook", "enemies", "bosses", "npcs", "undercity/collector_eye", "lowlight/sweeper", "portraits"])]
    for p in sorted(pngs):
        name = os.path.basename(p)
        a = np.asarray(Image.open(p).convert("RGBA"))
        soft = int(((a[..., 3] != 0) & (a[..., 3] != 255)).sum())
        cols = {tuple(c) for c in a[a[..., 3] == 255][:, :3].tolist()}
        res = [r for r in VALIDATOR_RESERVED if tuple(int(r[i:i + 2], 16) for i in (0, 2, 4)) in cols]
        if not NAME_RULE.match(name):
            errs.append(f"{name}: bad name")
        if soft:
            errs.append(f"{name}: {soft} soft alpha px")
        if len(cols) > 64:
            errs.append(f"{name}: {len(cols)} colours")
        if res:
            errs.append(f"{name}: reserved {res}")
        tres = p[:-4] + ".tres"
        spec = None
        if os.path.exists(tres):
            t = open(tres).read()
            cw, ch = map(int, re.search(r"cell_size = Vector2i\((\d+), (\d+)\)", t).groups())
            if a.shape[1] % cw or a.shape[0] % ch:
                errs.append(f"{name}: {a.shape[1]}x{a.shape[0]} not a multiple of {cw}x{ch}")
            anims = re.findall(r'name = &"(\w+)"\nrow = (\d+)\nfirst_frame = 0\nframe_count = (\d+)\nfps = ([\d.]+)', t)
            spec = dict(cell=[cw, ch], anims=len(anims), frames=sum(int(x[2]) for x in anims))
            for nm, row, n, fps in anims:
                if int(row) >= a.shape[0] // ch or int(n) > a.shape[1] // cw:
                    errs.append(f"{name}: anim {nm} outside sheet")
                # every frame must have content, and must not touch the cell edges (1 px margin)
                allowed_edges = ATTACHED_EDGES.get(name, "")
                for k in range(int(n)):
                    cell = a[int(row) * ch:(int(row) + 1) * ch, k * cw:(k + 1) * cw, 3]
                    if not cell.any() and nm not in ("gone", "dormant"):
                        errs.append(f"{name}: {nm}[{k}] empty")
                    edges = ("T" if cell[0].any() else "") + ("L" if cell[:, 0].any() else "") + ("R" if cell[:, -1].any() else "")
                    bad = "".join(e for e in edges if e not in allowed_edges)
                    if bad:
                        errs.append(f"{name}: {nm}[{k}] touches the cell edge {bad} (keep 1 px transparent margin)")
        rows.append(dict(file=os.path.relpath(p, OUT), size=f"{a.shape[1]}x{a.shape[0]}", colours=len(cols), bytes=os.path.getsize(p), spec=spec))
    return errs, rows


if __name__ == "__main__":
    if "--check" not in sys.argv:
        build()
    errs, rows = check()
    for r in rows:
        print(json.dumps(r))
    print("ERRORS:" if errs else "OK: 0 errors", *errs, sep="\n")
    sys.exit(1 if errs else 0)
