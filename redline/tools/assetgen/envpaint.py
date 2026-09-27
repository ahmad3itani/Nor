"""envpaint: a small deterministic pixel painter for code-drawn environment planes (T02).

Everything is painted on an index canvas whose colours come from one named palette in
palettes.json, so a plane can never hold a colour outside its palette (and palettes.py
already keeps every decorative colour >= 48 away from the reserved gameplay colours).

Rules the helpers follow (ART_DIRECTION.md sections 0 and 4, Art Bible section 4):
- hard alpha: a pixel is a palette index or transparent (-1), nothing in between;
- no outlines on environment: shapes read by value, with 3 values per material and
  one top-edge highlight (rim);
- ordered Bayer dither only through `dither_vgrad`, used for skies and fog gradients;
- canvases wrap in x (and in y for tall planes), so a plane tiles by construction.

Randomness is always a seeded numpy Generator handed in by the caller (never global),
so every rebuild is byte-identical.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assetgen_paths import DATA  # noqa: E402

PAL = json.load(open(os.path.join(DATA, "palettes.json")))

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
BAYER8 = np.array([[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
                   [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
                   [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
                   [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]) / 64.0


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def srgb_to_L(rgb):
    """CIE L* of sRGB values (array [..., 3], 0-255)."""
    c = np.asarray(rgb, float) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    y = c @ np.array([0.2126, 0.7152, 0.0722])
    f = np.where(y > 0.008856, np.cbrt(y), 7.787 * y + 16 / 116)
    return 116 * f - 16


class Canvas:
    """An index canvas: idx[y, x] is a palette index, -1 is transparent."""

    def __init__(self, w, h, pal, wrap_x=True, wrap_y=False, fill=None):
        self.w, self.h, self.pal = w, h, pal
        cols = PAL["palettes"][pal]["colors"]
        self.names = list(cols)
        self.rgb = np.array([hex2rgb(cols[n]) for n in self.names], np.uint8)
        self.wrap_x, self.wrap_y = wrap_x, wrap_y
        self.idx = np.full((h, w), -1 if fill is None else self.ci(fill), np.int16)

    # ------------------------------------------------------------ basics
    def ci(self, name):
        if name is None:
            return -1
        try:
            return self.names.index(name)
        except ValueError:
            raise KeyError(f"colour '{name}' is not in palette {self.pal}")

    def L(self, name):
        return float(srgb_to_L(self.rgb[self.ci(name)]))

    @property
    def opaque(self):
        return self.idx >= 0

    def blank(self):
        return np.zeros((self.h, self.w), bool)

    def _offsets(self):
        xs = (-self.w, 0, self.w) if self.wrap_x else (0,)
        ys = (-self.h, 0, self.h) if self.wrap_y else (0,)
        return [(ox, oy) for ox in xs for oy in ys]

    def mask_poly(self, pts):
        """Boolean mask of a filled polygon (wrapping)."""
        im = Image.new("1", (self.w, self.h), 0)
        d = ImageDraw.Draw(im)
        for ox, oy in self._offsets():
            d.polygon([(x + ox, y + oy) for x, y in pts], fill=1, outline=1)
        return np.asarray(im, bool).copy()

    def mask_rect(self, x, y, w, h):
        m = self.blank()
        if w <= 0 or h <= 0:
            return m
        xs = np.arange(int(x), int(x) + int(w))
        ys = np.arange(int(y), int(y) + int(h))
        if self.wrap_x:
            xs = xs % self.w
        else:
            xs = xs[(xs >= 0) & (xs < self.w)]
        if self.wrap_y:
            ys = ys % self.h
        else:
            ys = ys[(ys >= 0) & (ys < self.h)]
        if len(xs) and len(ys):
            m[np.ix_(ys, xs)] = True
        return m

    def mask_ellipse(self, cx, cy, rx, ry):
        im = Image.new("1", (self.w, self.h), 0)
        d = ImageDraw.Draw(im)
        for ox, oy in self._offsets():
            d.ellipse([cx - rx + ox, cy - ry + oy, cx + rx + ox, cy + ry + oy], fill=1, outline=1)
        return np.asarray(im, bool).copy()

    def mask_line(self, pts, width=1):
        im = Image.new("1", (self.w, self.h), 0)
        d = ImageDraw.Draw(im)
        for ox, oy in self._offsets():
            d.line([(x + ox, y + oy) for x, y in pts], fill=1, width=width)
        return np.asarray(im, bool).copy()

    def put(self, mask, name):
        self.idx[mask] = self.ci(name)

    def rect(self, x, y, w, h, name):
        self.put(self.mask_rect(x, y, w, h), name)

    def poly(self, pts, name):
        self.put(self.mask_poly(pts), name)

    def px(self, x, y, name):
        x, y = int(x), int(y)
        if self.wrap_x:
            x %= self.w
        if self.wrap_y:
            y %= self.h
        if 0 <= x < self.w and 0 <= y < self.h:
            self.idx[y, x] = self.ci(name)

    def line(self, pts, name, width=1):
        self.put(self.mask_line(pts, width), name)

    # ------------------------------------------------------------ output
    def rgba(self):
        a = np.zeros((self.h, self.w, 4), np.uint8)
        op = self.opaque
        a[op, :3] = self.rgb[self.idx[op]]
        a[op, 3] = 255
        return a

    def image(self, opaque=False):
        """Indexed PNG image (palette order = palettes.json order; index 255 = transparent)."""
        if opaque and not self.opaque.all():
            raise ValueError(f"opaque plane has {int((~self.opaque).sum())} transparent pixels")
        arr = np.where(self.opaque, self.idx, 255).astype(np.uint8)
        im = Image.fromarray(arr, "P")
        pal = np.zeros((256, 3), np.uint8)
        pal[:len(self.rgb)] = self.rgb
        im.putpalette(pal.ravel().tolist())
        if not opaque:
            im.info["transparency"] = 255
        return im


def save_png(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if im.mode == "P" and "transparency" in im.info:
        im.save(path, optimize=False, transparency=im.info["transparency"])
    else:
        im.save(path, optimize=False)


# ------------------------------------------------------------------ gradients

def dither_vgrad(cv, stops, mask=None, bayer=BAYER4, x_phase=0):
    """Ordered-dither vertical gradient. stops: [(y, name), ...] sorted by y.
    Between two stops the lower colour takes over along a Bayer threshold."""
    m = np.ones((cv.h, cv.w), bool) if mask is None else mask
    n = bayer.shape[0]
    X = (np.arange(cv.w) + x_phase) % n
    for (y0, a), (y1, b) in zip(stops, stops[1:]):
        for y in range(max(0, int(y0)), min(cv.h, int(y1))):
            t = (y - y0) / max(1, (y1 - y0))
            row = bayer[y % n][X] < t
            sel = m[y]
            cv.idx[y, sel & ~row] = cv.ci(a)
            cv.idx[y, sel & row] = cv.ci(b)
    ylast, last = stops[-1]
    if ylast < cv.h:
        sel = m[int(ylast):]
        cv.idx[int(ylast):][sel] = cv.ci(last)
    y0, first = stops[0]
    if y0 > 0:
        sel = m[:int(y0)]
        cv.idx[:int(y0)][sel] = cv.ci(first)


def dither_blend(cv, mask, a, b, t, bayer=BAYER4):
    """Inside mask, a Bayer mix of colour b over a with coverage t (0..1, scalar or array)."""
    n = bayer.shape[0]
    Y, X = np.mgrid[0:cv.h, 0:cv.w]
    th = bayer[Y % n, X % n]
    t = np.broadcast_to(np.asarray(t, float), (cv.h, cv.w))
    cv.idx[mask & (th >= t)] = cv.ci(a)
    cv.idx[mask & (th < t)] = cv.ci(b)


# ------------------------------------------------------------------ shading helpers

def top_edge(mask):
    """Pixels of mask whose upper neighbour is outside it."""
    up = np.vstack([np.zeros((1, mask.shape[1]), bool), mask[:-1]])
    return mask & ~up


def left_edge(mask, wrap=True):
    lf = np.roll(mask, 1, 1) if wrap else np.hstack([np.zeros((mask.shape[0], 1), bool), mask[:, :-1]])
    return mask & ~lf


def right_edge(mask, wrap=True):
    rt = np.roll(mask, -1, 1) if wrap else np.hstack([mask[:, 1:], np.zeros((mask.shape[0], 1), bool)])
    return mask & ~rt


def paint_mat(cv, mask, ramp, edge=None, shade="flat", x0=None, x1=None, rng=None, stain=0.0,
              stain_name=None, light_frac=0.22, dark_frac=0.28):
    """Fill `mask` with a material: ramp = (dark, mid, light).
    shade: 'flat' (mid body, light left column, dark right column),
           'cyl'  (cylinder: light band at 20-40 %, dark right third, x0..x1 = the body extent),
           'none' (mid only).
    edge: top-edge rim colour. stain: fraction of columns with a dark seepage streak."""
    dark, mid, light = ramp
    cv.put(mask, mid)
    if shade == "cyl" and x0 is not None:
        w = max(1, x1 - x0)
        xs = (np.arange(cv.w) - x0) % cv.w if cv.wrap_x else np.arange(cv.w) - x0
        u = xs / w
        lb = (u >= 0.18) & (u < 0.18 + light_frac)
        db = (u >= 1 - dark_frac) & (u <= 1.0)
        cv.idx[mask & lb[None, :]] = cv.ci(light)
        cv.idx[mask & db[None, :]] = cv.ci(dark)
    elif shade == "flat":
        cv.put(left_edge(mask, cv.wrap_x), light)
        cv.put(right_edge(mask, cv.wrap_x), dark)
    if stain and rng is not None:
        ys, xs = np.nonzero(top_edge(mask))
        for y, x in zip(ys, xs):
            if rng.random() < stain:
                ln = int(rng.integers(3, 14))
                for k in range(1, ln):
                    yy = y + k
                    if yy >= cv.h or not mask[yy, x]:
                        break
                    cv.idx[yy, x] = cv.ci(stain_name or dark)
    if edge:
        cv.put(top_edge(mask), edge)


def speckle(cv, mask, name, density, rng, cluster=1):
    ys, xs = np.nonzero(mask)
    if not len(ys):
        return
    k = int(len(ys) * density)
    pick = rng.choice(len(ys), size=k, replace=False) if k < len(ys) else np.arange(len(ys))
    for i in pick:
        for c in range(cluster):
            yy, xx = ys[i], (xs[i] + c) % cv.w
            if mask[yy, xx]:
                cv.idx[yy, xx] = cv.ci(name)


# ------------------------------------------------------------------ shapes

def catenary(x0, y0, x1, y1, sag, steps=None):
    steps = steps or max(2, int(abs(x1 - x0)))
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t + sag * 4 * t * (1 - t)
        pts.append((x, y))
    return pts


def cable(cv, x0, y0, x1, y1, sag, name):
    cv.line(catenary(x0, y0, x1, y1, sag), name)


def chain(cv, x, y0, length, a, b):
    """A hanging chain: 1 px links alternating two values, 2 px wide every other link."""
    for k in range(length):
        y = y0 + k
        cv.px(x, y, a if k % 3 else b)
        if k % 3 == 1:
            cv.px(x + 1, y, b)


def windows_grid(cv, mask, x0, y0, x1, y1, cw, ch, gx, gy, names, rng, density, lit_names=None, lit_p=0.0):
    """Punch dark window openings in a facade (inside mask) and light a few of them.
    Lit windows are >= 3 px (accent hygiene: islands >= 3 px)."""
    y = y0
    while y + ch <= y1:
        x = x0
        while x + cw <= x1:
            if rng.random() < density:
                m = cv.mask_rect(x, y, cw, ch) & mask
                if m.sum() == cw * ch:
                    if lit_names and rng.random() < lit_p and cw * ch >= 3:
                        cv.put(m, lit_names[int(rng.integers(len(lit_names)))])
                    else:
                        cv.put(m, names[int(rng.integers(len(names)))])
            x += cw + gx
        y += ch + gy


# ------------------------------------------------------------------ texture

def noise(h, w, cell, seed, octaves=2, sy=1):
    """Periodic value noise in [0, 1] (wraps in x, and in y when cell*sy divides h).
    sy > 1 stretches the blobs vertically (water stains, seepage)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = max(2, cell >> o)
        gh, gw = -(-h // (c * sy)), -(-w // c)
        g = rng.random((gh, gw))
        ys = np.arange(h) / (c * sy)
        xs = np.arange(w) / c
        y0 = np.floor(ys).astype(int)
        x0 = np.floor(xs).astype(int)
        fy = (ys - y0)[:, None]
        fx = (xs - x0)[None, :]
        fy = fy * fy * (3 - 2 * fy)
        fx = fx * fx * (3 - 2 * fx)
        a = g[y0 % gh][:, x0 % gw]
        b = g[y0 % gh][:, (x0 + 1) % gw]
        cc = g[(y0 + 1) % gh][:, x0 % gw]
        d = g[(y0 + 1) % gh][:, (x0 + 1) % gw]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy)
        tot += amp
        amp *= 0.5
    return out / tot


def mottle(cv, mask, name, field, lo, hi=1.01):
    """Paint `name` where lo <= field < hi inside mask (clustered stains, never dither)."""
    cv.idx[mask & (field >= lo) & (field < hi)] = cv.ci(name)


def jagged_top(cv, mask, rng, depth=3, p=0.3):
    """Break the top edge of a mask: randomly bite 1..depth px notches out of its columns."""
    ys, xs = np.nonzero(top_edge(mask))
    for y, x in zip(ys, xs):
        if rng.random() < p:
            d = int(rng.integers(1, depth + 1))
            for k in range(d):
                if y + k < cv.h and mask[y + k, x]:
                    cv.idx[y + k, x] = -1
                    mask[y + k, x] = False
    return mask


ACCENTS = ("rust_0", "rust_1", "rust_2", "rust_3", "sea_dim", "water_glint", "sodium_dim", "sodium", "sea_tube",
           "window_warm_far", "window_warm", "window_cold_far", "window_cold", "window_rose", "sodium_street", "wet_hi",
           "lamp_core", "lamp_warm")  # = env_process.ACCENT_NAMES (accent hygiene: islands >= 3 px, <= 2 %)


def accent_cleanup(cv, min_island=3):
    """Accent pixels (windows, lamps, rust, glints) left in islands smaller than min_island
    (8-connected) after later strokes crossed them take the most common non-accent
    neighbour colour, so every accent reads as a deliberate cluster."""
    acc = [cv.ci(n) for n in ACCENTS if n in cv.names]
    if not acc:
        return 0
    m = np.isin(cv.idx, acc)
    H, W = m.shape
    seen = np.zeros_like(m)
    fixed = 0
    for y, x in zip(*np.nonzero(m)):
        if seen[y, x]:
            continue
        comp, stack = [], [(y, x)]
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            comp.append((cy, cx))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = cy + dy, (cx + dx) % W if cv.wrap_x else cx + dx
                    if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        if len(comp) >= min_island:
            continue
        for cy, cx in comp:
            nb = [int(cv.idx[yy, xx]) for yy in (cy - 1, cy, cy + 1) for xx in (cx - 1, cx, cx + 1)
                  if 0 <= yy < H and 0 <= xx < W and not m[yy, xx]]
            opq = [n for n in nb if n >= 0]
            pool = opq if len(opq) * 2 >= len(nb) else nb
            cv.idx[cy, cx] = max(sorted(set(pool)), key=pool.count) if pool else -1
            fixed += 1
    return fixed
