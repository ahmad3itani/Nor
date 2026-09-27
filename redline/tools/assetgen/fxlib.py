"""fxlib: shared helpers for the fx_ui asset scripts (VFX strips, UI kit, title).

Frames are small numpy uint8 index maps: 0 = transparent, 1..3 = mask tones
(dark / mid / white). They become RGBA with hard alpha only at the end, using
either the grey mask ramp (tinted in-engine by Palette.color / UiTheme) or a
baked colour ramp from palettes.json.

Everything is deterministic (seeded RNG), so re-running a script reproduces
the same PNG bytes. `check_png` enforces the Art Bible rules we can test
offline: hard alpha, allowed colours only, no colour within 48 of a reserved
gameplay colour (unless the file is an explicit white/grey mask).
"""
from __future__ import annotations

import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = REDLINE
OUT = ASSETS
REVIEW = PREVIEW
SS = 4

PAL = json.load(open(os.path.join(DATA, "palettes.json")))
RESERVED = [tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) for h in PAL["reserved"].values()]
MIN_DIST = PAL.get("min_reserved_distance", 48)

# grey mask ramp (ui palette mask_dark / mask_mid / mask_white)
MASK = {1: (96, 96, 96), 2: (176, 176, 176), 3: (255, 255, 255)}


def hx(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def ui(key: str) -> tuple:
    return hx(PAL["palettes"]["ui"]["colors"][key])


# ------------------------------------------------------------------ canvas
def blank(w, h):
    return np.zeros((h, w), np.uint8)


def put(f, x, y, v):
    x, y = int(round(x)), int(round(y))
    if 0 <= y < f.shape[0] and 0 <= x < f.shape[1]:
        if v == 0:
            f[y, x] = 0
        else:
            f[y, x] = max(f[y, x], v) if v > 0 else f[y, x]


def put_over(f, x, y, v):
    x, y = int(round(x)), int(round(y))
    if 0 <= y < f.shape[0] and 0 <= x < f.shape[1]:
        f[y, x] = v


def merge(dst, src):
    """Max-combine src into dst (brighter tone wins)."""
    np.maximum(dst, src, out=dst)
    return dst


def over(dst, src):
    """Paint src over dst where src is non-zero."""
    dst[src > 0] = src[src > 0]
    return dst


def cov_poly(w, h, pts, thr=0.5):
    """Rasterise a polygon by coverage at SS supersampling -> bool mask."""
    im = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(im).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    a = np.asarray(im, np.float32).reshape(h, SS, w, SS).mean(axis=(1, 3)) / 255.0
    return a >= thr


def cov_ellipse(w, h, cx, cy, rx, ry, thr=0.5):
    im = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(im).ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255)
    a = np.asarray(im, np.float32).reshape(h, SS, w, SS).mean(axis=(1, 3)) / 255.0
    return a >= thr


def ring(w, h, cx, cy, rx, ry, width=1.0):
    """1-px (or wider) ellipse outline via Bresenham-like sampling."""
    m = np.zeros((h, w), bool)
    n = max(24, int((rx + ry) * 8))
    for k in range(n):
        a = 2 * math.pi * k / n
        for t in np.arange(0, width, 0.5):
            x = cx + (rx - t) * math.cos(a)
            y = cy + (ry - t) * math.sin(a)
            xi, yi = int(math.floor(x + 0.5)), int(math.floor(y + 0.5))
            if 0 <= xi < w and 0 <= yi < h:
                m[yi, xi] = True
    return m


def line(f, x0, y0, x1, y1, v):
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        put_over(f, x0, y0, v)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) / 16.0 + 1 / 32.0


def bayer(h, w, ox=0, oy=0):
    yy, xx = np.mgrid[0:h, 0:w]
    return BAYER4[(yy + oy) % 4, (xx + ox) % 4]


def dissolve(f, amount, ox=0, oy=0, where=None):
    """Ordered-dither dissolve: amount 0 = keep all, 1 = remove all."""
    b = bayer(*f.shape, ox, oy)
    kill = b < amount
    if where is not None:
        kill &= where
    f[kill] = 0
    return f


def remove_islands(f, min_px=1):
    """Drop isolated single pixels (no 8-neighbour) when min_px>=1."""
    if min_px < 1:
        return f
    nz = f > 0
    p = np.pad(nz, 1)
    nb = sum(np.roll(np.roll(p, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)[1:-1, 1:-1]
    f[nz & (nb == 0)] = 0
    return f


# ------------------------------------------------------------------ output
def to_rgba(f, ramp=None, alpha=None):
    ramp = ramp or MASK
    h, w = f.shape
    out = np.zeros((h, w, 4), np.uint8)
    for k, c in ramp.items():
        sel = f == k
        out[sel, :3] = c[:3]
        out[sel, 3] = 255 if alpha is None else alpha
    return out


def sheet(rows, cw, ch, ramp=None):
    """rows: list of (name, [frames]) -> RGBA sheet, one animation per row."""
    cols = max(len(fr) for _, fr in rows)
    img = np.zeros((ch * len(rows), cw * cols, 4), np.uint8)
    for r, (_, frames) in enumerate(rows):
        for c, fr in enumerate(frames):
            assert fr.shape == (ch, cw), (fr.shape, cw, ch)
            img[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = to_rgba(fr, ramp)
    return img


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(img, "RGBA").save(path, optimize=True)
    return path


def preview(path, scale=3, bg=(38, 34, 48), tag=None):
    """x`scale` nearest copy on a dark checker for review with the Read tool."""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    yy, xx = np.mgrid[0:h, 0:w]
    chk = ((xx // 8 + yy // 8) % 2).astype(np.uint8)
    base = np.zeros((h, w, 4), np.uint8)
    base[..., :3] = np.where(chk[..., None] == 0, np.array(bg), np.array(bg) + 10)
    base[..., 3] = 255
    b = Image.fromarray(base, "RGBA")
    b.alpha_composite(im)
    os.makedirs(REVIEW, exist_ok=True)
    name = tag or os.path.basename(path)
    p = os.path.join(REVIEW, "fxui__" + name)
    b.resize((w * scale, h * scale), Image.NEAREST).save(p)
    return p


def write_tres(path, png_res_path, cw, ch, origin, anims, row_origins=None):
    """anims: list of (name, row, count, fps, loop). SpriteSheetSpec format.
    row_origins: anim name -> [x, y], written as the SpriteAnim.origin override
    (the json sidecar keeps the same numbers for tools)."""
    row_origins = row_origins or {}
    lines = [f'[gd_resource type="Resource" script_class="SpriteSheetSpec" load_steps={len(anims) + 3} format=3]', "",
             '[ext_resource type="Script" path="res://vfx/SpriteSheetSpec.gd" id="1_spec"]',
             '[ext_resource type="Script" path="res://vfx/SpriteAnim.gd" id="2_anim"]', ""]
    for i, (name, row, count, fps, loop) in enumerate(anims):
        lines += [f'[sub_resource type="Resource" id="a{i}"]', 'script = ExtResource("2_anim")', f'name = &"{name}"',
                  f"row = {row}", "first_frame = 0", f"frame_count = {count}", f"fps = {float(fps)}",
                  f"loop = {'true' if loop else 'false'}"]
        if name in row_origins:
            ox, oy = row_origins[name]
            lines += [f"origin = Vector2i({ox}, {oy})"]
        lines += [""]
    refs = ", ".join(f'SubResource("a{i}")' for i in range(len(anims)))
    lines += ["[resource]", 'script = ExtResource("1_spec")', f'texture_path = "{png_res_path}"',
              f"cell_size = Vector2i({cw}, {ch})", f"origin = Vector2i({origin[0]}, {origin[1]})",
              f'animations = Array[Resource("res://vfx/SpriteAnim.gd")]([{refs}])', ""]
    with open(path, "w") as fh:
        fh.write("\n".join(lines))


def write_json(path, data):
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1)


# ------------------------------------------------------------------ checks
def check_png(path, allowed=None, soft_alpha_steps=None, mask=False):
    """Return a list of problems (empty = pass)."""
    errs = []
    a = np.asarray(Image.open(path).convert("RGBA"))
    al = a[..., 3]
    vals = set(np.unique(al).tolist())
    if soft_alpha_steps is None:
        if not vals <= {0, 255}:
            errs.append(f"{os.path.basename(path)}: soft alpha {sorted(vals)[:6]}")
    elif len(vals) > soft_alpha_steps + 1:
        errs.append(f"{os.path.basename(path)}: {len(vals) - 1} alpha steps > {soft_alpha_steps}")
    cols = {tuple(c) for c in a[al > 0][:, :3].tolist()}
    if allowed is not None:
        bad = cols - {tuple(c) for c in allowed}
        if bad:
            errs.append(f"{os.path.basename(path)}: {len(bad)} colours outside palette e.g. {list(bad)[:3]}")
    if not mask:
        for c in cols:
            for r in RESERVED:
                if math.dist(c, r) < MIN_DIST:
                    errs.append(f"{os.path.basename(path)}: colour {c} within {MIN_DIST} of reserved {r}")
    if al.max() == 0:
        errs.append(f"{os.path.basename(path)}: empty")
    return errs


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)
