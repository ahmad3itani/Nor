#!/usr/bin/env python3
"""null_tiles (Deep Rig): procedural, no AI source. Grey slab #4c4f59, 1 px edge
#dbdee6, one-way #9ea1ad, faint dotted 16 px scribe in grid_1. Same 8x6 autotile
layout as the AI tilesets (env_process.build_atlas)."""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import env_process as ep

names, prgb = ep.palette("null_env")
C = {n: prgb[names.index(n)].astype(np.uint8) for n in names}
sw = np.zeros((128, 128, 3), np.uint8)
sw[:] = C["solid"]
for y in range(128):
    for x in range(128):
        on_line = (x % 16 == 7) or (y % 16 == 7)
        if on_line and (x + y) % 3 == 0:
            sw[y, x] = C["grid_1"]
# sparse panel rivets, deterministic
rng = np.random.default_rng(7)
for _ in range(24):
    y, x = rng.integers(0, 128, 2)
    sw[y, x] = C["grid_1"]
r = dict(pal="null_env", ramp=["grid_1", "solid", "oneway"], edge="edge", under="void",
         out="null/null_tiles.png")
print(ep.build_atlas(names, prgb, sw, r))
