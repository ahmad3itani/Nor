"""review.py: readability composites for the AD redo pass (review copies only, never game files).

comp(frames, out, bg='uc', scale=3): frames laid out left to right on the Undercity
far plane (graded #dfeee8) + fog band A (#2b3d38, texture alpha), as they sit in game.
silhouette(frames, out): pure-black silhouettes at 1x (plus a x4 copy).
metrics helpers: median L (CIE L*) of a colour set, changed-pixel counts between frames.
"""
from __future__ import annotations
import os
import numpy as np
from PIL import Image
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = REDLINE
OUT = ASSETS
REV = PREVIEW


def _hex(h):
    h = h.lstrip("#"); return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def lstar(rgb):
    c = np.asarray(rgb, np.float32) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    y = c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722
    return np.where(y > 216 / 24389, 116 * np.cbrt(y) - 16, y * 24389 / 27)


def median_l(img, mask=None):
    a = np.asarray(img.convert("RGBA"))
    m = a[..., 3] > 0 if mask is None else mask
    return float(np.median(lstar(a[..., :3][m]))) if m.any() else 0.0


def changed(a, b):
    a = np.asarray(a.convert("RGBA")).astype(int); b = np.asarray(b.convert("RGBA")).astype(int)
    return int((np.abs(a - b).sum(-1) > 0).sum())


BGS = {
    "uc": dict(void="#0f1a17", layer="undercity/uc_far.png", grade="#dfeee8", fog="#2b3d38", crop_y=90),
    "relay": dict(void="#1f1412", layer=None, grade="#fff0e0", fog="#4a3326", crop_y=0, wall="#332926"),
}


def background(w, h, bg="uc", x0=40):
    B = BGS[bg]
    base = np.zeros((h, w, 4), np.float32); base[..., :3] = _hex(B["void"]); base[..., 3] = 255
    if B.get("wall"):
        base[..., :3] = _hex(B["wall"])
    if B["layer"]:
        L = np.asarray(Image.open(os.path.join(OUT, B["layer"])).convert("RGBA")).astype(np.float32)
        Lw = L.shape[1]
        ys = B["crop_y"]
        for x in range(w):
            col = L[ys:ys + h, (x0 + x) % Lw]
            hh = col.shape[0]
            m = col[:, 3] > 0
            c = col[:, :3] * _hex(B["grade"]) / 255.0
            base[:hh, x, :3][m] = c[m]
    fog = np.asarray(Image.open(os.path.join(OUT, "vfx/atmos/fog_band_a.png")).convert("RGBA")).astype(np.float32)
    fy = h - fog.shape[0] - 8
    for x in range(w):
        col = fog[:, (x0 + x) % fog.shape[1]]
        a = col[:, 3:4] / 255.0
        seg = slice(max(0, fy), fy + fog.shape[0])
        n = base[seg, x, :3].shape[0]
        base[seg, x, :3] = base[seg, x, :3] * (1 - a[:n]) + _hex(B["fog"]) * a[:n]
    return Image.fromarray(base.astype(np.uint8), "RGBA")


def comp(frames, out, bg="uc", scale=3, gap=4, ground=None):
    cw, ch = frames[0].size
    w = len(frames) * (cw + gap) + gap
    h = ch + 16
    img = background(w, h, bg)
    for i, f in enumerate(frames):
        img.alpha_composite(f.convert("RGBA"), (gap + i * (cw + gap), 8))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.resize((w * scale, h * scale), Image.NEAREST).save(out)
    return out


def silhouette(frames, out, scale=4, gap=4):
    cw = sum(f.width for f in frames) + gap * (len(frames) + 1)
    ch = max(f.height for f in frames) + 2 * gap
    img = Image.new("RGBA", (cw, ch), (236, 232, 222, 255))
    x = gap
    for f in frames:
        a = np.asarray(f.convert("RGBA"))[..., 3] > 0
        s = np.zeros(a.shape + (4,), np.uint8); s[a] = (0, 0, 0, 255)
        img.alpha_composite(Image.fromarray(s, "RGBA"), (x, ch - gap - f.height))
        x += f.width + gap
    img.save(out.replace(".png", "_1x.png"))
    img.resize((cw * scale, ch * scale), Image.NEAREST).save(out)
    return out


def cells(png, cw, ch, row, n=None):
    im = Image.open(png).convert("RGBA")
    n = n or im.width // cw
    return [im.crop((k * cw, row * ch, (k + 1) * cw, (row + 1) * ch)) for k in range(n)]


def grid(frames, out, per_row=12, bg="uc", scale=2):
    """Frames wrapped into rows on the background (for whole-sheet review)."""
    cw, ch = frames[0].size
    rows = [frames[i:i + per_row] for i in range(0, len(frames), per_row)]
    w, h = per_row * cw, len(rows) * (ch + 4)
    img = Image.new("RGBA", (w, h))
    for k, r in enumerate(rows):
        b = background(w, ch + 4, bg)
        for i, f in enumerate(r):
            b.alpha_composite(f.convert("RGBA"), (i * cw, 2))
        img.paste(b, (0, k * (ch + 4)))
    img.resize((w * scale, h * scale), Image.NEAREST).save(out)
    return out


def sheet_frames(png, only=None):
    import re
    t = open(png[:-4] + ".tres").read()
    cw, ch = map(int, re.search(r"cell_size = Vector2i\((\d+), (\d+)\)", t).groups())
    rows = [(n, int(r), int(c)) for n, r, c in re.findall(r'name = &"(\w+)"\nrow = (\d+)\nfirst_frame = 0\nframe_count = (\d+)', t)]
    fr = []
    for n, r, c in rows:
        if only and n not in only:
            continue
        fr += cells(png, cw, ch, r, c)
    return fr
