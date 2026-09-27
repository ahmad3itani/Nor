"""pixrig: tiny code-driven pixel-art rig renderer for REDLINE character sheets.

Parts are drawn as vector shapes at SS x supersampling into per-part masks,
downsampled to 1 px by coverage, shaded with a per-part ramp (top-left key
light: lit rim, mid, shadow rim), composited back to front, optionally
separated from what is behind by a 1 px dark line, and finally outlined.
Everything is hard alpha and uses only the colours given (palette-safe).

Used by tools/rig_*.py. Output: horizontal strips, one animation per row,
plus a SpriteSheetSpec .tres (vfx/SpriteSheetSpec.gd).
"""
from __future__ import annotations

import math
import os
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw

SS = 4  # supersampling


def hex2rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- geometry
def rot(v, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, k):
    return (a[0] * k, a[1] * k)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp2(a, b, t):
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t))


def dirv(deg, length=1.0):
    """Limb direction: 0 deg = straight down, +90 = forward (+x), 180 = up."""
    a = math.radians(deg)
    return (math.sin(a) * length, math.cos(a) * length)


def tup(deg, length=1.0):
    """Body 'up' axis for a forward tilt of deg (0 = straight up, + = leaning forward/+x)."""
    a = math.radians(deg)
    return (math.sin(a) * length, -math.cos(a) * length)


def tfwd(deg, length=1.0):
    """Body 'forward' axis for a forward tilt of deg (0 = +x, + = rotates toward down)."""
    a = math.radians(deg)
    return (math.cos(a) * length, math.sin(a) * length)


def tdn(deg, length=1.0):
    a = math.radians(deg)
    return (-math.sin(a) * length, math.cos(a) * length)


# ---------------------------------------------------------------- part layer
class Layer:
    """One part's supersampled mask."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("L", (w * SS, h * SS), 0)
        self.d = ImageDraw.Draw(self.img)

    def _p(self, p):
        return (p[0] * SS, p[1] * SS)

    def poly(self, pts, fill=255):
        if len(pts) >= 3:
            self.d.polygon([self._p(p) for p in pts], fill=fill)
        return self

    def circle(self, c, r, fill=255):
        x, y = self._p(c)
        rr = r * SS
        self.d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=fill)
        return self

    def ellipse(self, c, rx, ry, fill=255):
        x, y = self._p(c)
        self.d.ellipse([x - rx * SS, y - ry * SS, x + rx * SS, y + ry * SS], fill=fill)
        return self

    def capsule(self, a, b, r0, r1=None, fill=255):
        r1 = r0 if r1 is None else r1
        ax, ay = a
        bx, by = b
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy) or 1e-6
        nx, ny = -dy / L, dx / L
        pts = [(ax + nx * r0, ay + ny * r0), (bx + nx * r1, by + ny * r1),
               (bx - nx * r1, by - ny * r1), (ax - nx * r0, ay - ny * r0)]
        self.poly(pts, fill)
        self.circle(a, r0, fill)
        self.circle(b, r1, fill)
        return self

    def rect(self, x0, y0, x1, y1, fill=255):
        self.d.rectangle([x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1], fill=fill)
        return self

    def mask(self, thr=0.5):
        a = np.asarray(self.img, dtype=np.float32) / 255.0
        a = a.reshape(self.h, SS, self.w, SS).mean(axis=(1, 3))
        return a >= thr


def shift(m, dx, dy):
    """out[y,x] = m[y-dy, x-dx] (False outside)."""
    h, w = m.shape
    o = np.zeros_like(m)
    ys = slice(max(0, dy), min(h, h + dy))
    xs = slice(max(0, dx), min(w, w + dx))
    yd = slice(max(0, -dy), min(h, h - dy))
    xd = slice(max(0, -dx), min(w, w - dx))
    o[ys, xs] = m[yd, xd]
    return o


def dilate(m):
    return m | shift(m, 1, 0) | shift(m, -1, 0) | shift(m, 0, 1) | shift(m, 0, -1)


# ---------------------------------------------------------------- frame composer
@dataclass
class Frame:
    w: int
    h: int
    rgb: np.ndarray = None
    alpha: np.ndarray = None
    owner: np.ndarray = None  # part index, -1 empty

    def __post_init__(self):
        self.rgb = np.zeros((self.h, self.w, 3), np.uint8)
        self.alpha = np.zeros((self.h, self.w), bool)
        self.owner = np.full((self.h, self.w), -1, np.int32)
        self._n = 0

    def part(self, layer_or_mask, ramp, light=1, shade=1, sep=None, thr=0.5, clip=None):
        """ramp: list of hex colours dark..light (1-4 entries).
        light/shade: rim widths in px for lit (top-left) and shadow (bottom-right) edges.
        sep: hex colour for a 1 px separation line drawn over what is behind.
        clip: only draw where this mask is True (e.g. inside the coat)."""
        m = layer_or_mask.mask(thr) if isinstance(layer_or_mask, Layer) else layer_or_mask
        if clip is not None:
            m = m & clip
        if not m.any():
            self._n += 1
            return m
        cols = [np.array(hex2rgb(c), np.uint8) for c in ramp]
        if len(cols) == 1:
            dark = mid = lit = cols[0]
        elif len(cols) == 2:
            dark, mid, lit = cols[0], cols[1], cols[1]
        elif len(cols) == 3:
            dark, mid, lit = cols
        else:
            dark, mid, lit = cols[0], cols[1], cols[2]
        if sep:
            ring = dilate(m) & ~m & self.alpha
            self.rgb[ring] = hex2rgb(sep)
        self.rgb[m] = mid
        if shade:
            edge = np.zeros_like(m)
            for d in range(1, shade + 1):
                edge |= ~shift(m, -d, -d) & m   # (x+d, y+d) outside
                edge |= ~shift(m, 0, -d) & m    # (x, y+d) outside
            self.rgb[edge] = dark
        if light:
            le = np.zeros_like(m)
            for d in range(1, light + 1):
                le |= ~shift(m, d, d) & m
                if d == 1:
                    le |= ~shift(m, 0, 1) & m
            self.rgb[le] = lit
            if len(cols) >= 4:
                hi = ~shift(m, 0, 1) & ~shift(m, 1, 0) & m
                self.rgb[hi] = cols[3]
        self.alpha |= m
        self.owner[m] = self._n
        self._n += 1
        return m

    def flat(self, layer_or_mask, colour, thr=0.5):
        return self.part(layer_or_mask, [colour], light=0, shade=0, thr=thr)

    def px(self, p, colour):
        x, y = int(math.floor(p[0])), int(math.floor(p[1]))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.rgb[y, x] = hex2rgb(colour)
            self.alpha[y, x] = True

    def outline(self, colour, inner=None):
        ring = dilate(self.alpha) & ~self.alpha
        self.rgb[ring] = hex2rgb(colour)
        self.alpha |= ring

    def rim(self, colour, only=None, top=True, back=True, back_dir=-1, rows=None, skip=None):
        """1 px rim light on figure pixels whose top and/or back neighbour is background.
        only: hex colours that may be recoloured (e.g. the coat/helm ramps); skip: hex colours kept.
        back_dir -1 = the back is -x (figure faces +x). rows: (y0, y1) inclusive limit."""
        a = self.alpha
        r = np.zeros_like(a)
        if top:
            r |= a & ~shift(a, 0, 1)
        if back:
            r |= a & ~shift(a, -back_dir, 0)
        if rows is not None:
            yy = np.arange(self.h)[:, None]
            r &= (yy >= rows[0]) & (yy <= rows[1])
        if only is not None:
            ok = np.zeros_like(a)
            for c in only:
                ok |= (self.rgb == np.array(hex2rgb(c), np.uint8)).all(-1)
            r &= ok
        if skip is not None:
            for c in skip:
                r &= ~(self.rgb == np.array(hex2rgb(c), np.uint8)).all(-1)
        self.rgb[r] = hex2rgb(colour)
        return r

    def mask_rim(self, m, colour, top=True, back=True, back_dir=-1):
        """Rim just the given part mask where its top / back neighbour is background right now."""
        a = self.alpha
        r = np.zeros_like(m)
        if top:
            r |= m & ~shift(a, 0, 1)
        if back:
            r |= m & ~shift(a, -back_dir, 0)
        self.rgb[r] = hex2rgb(colour)
        return r

    def edges(self):
        a = self.alpha
        return ("T" if a[0].any() else "") + ("L" if a[:, 0].any() else "") + ("R" if a[:, -1].any() else "")

    def despeckle(self):
        """Remove single opaque pixels with no 4-neighbours."""
        a = self.alpha
        n = shift(a, 1, 0).astype(int) + shift(a, -1, 0) + shift(a, 0, 1) + shift(a, 0, -1)
        lone = a & (n == 0)
        self.alpha[lone] = False

    def image(self):
        out = np.zeros((self.h, self.w, 4), np.uint8)
        out[..., :3] = self.rgb
        out[..., 3] = np.where(self.alpha, 255, 0)
        return Image.fromarray(out, "RGBA")


# ---------------------------------------------------------------- animation helpers
def ease(t):
    return t * t * (3 - 2 * t)


def interp_pose(keys, t):
    """keys: list of (time 0..1, dict). Linear/eased interpolation of numeric values."""
    if t <= keys[0][0]:
        return dict(keys[0][1])
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            u = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            u = ease(u)
            out = dict(a)
            for k in set(a) - set(b):
                if u >= 0.5:
                    out.pop(k)
            for k, v in b.items():
                if k in a and isinstance(v, (int, float)) and isinstance(a[k], (int, float)):
                    out[k] = a[k] + (v - a[k]) * u
                else:
                    out[k] = v if u >= 0.5 else a.get(k, v)
            return out
    return dict(keys[-1][1])


def merge(base, *over):
    d = dict(base)
    for o in over:
        if "wpn" in o and "wabs" not in o:
            d.pop("wabs", None)
        d.update(o)
    return d


# ---------------------------------------------------------------- sheet output
@dataclass
class Anim:
    name: str
    frames: list  # list of PIL RGBA images (cell size)
    fps: float
    loop: bool


def write_sheet(anims: list[Anim], cell, origin, png_path, res_path, tres_path, meta=None):
    cw, ch = cell
    cols = max(len(a.frames) for a in anims)
    sheet = Image.new("RGBA", (cols * cw, len(anims) * ch), (0, 0, 0, 0))
    for r, a in enumerate(anims):
        for i, f in enumerate(a.frames):
            sheet.paste(f, (i * cw, r * ch))
    os.makedirs(os.path.dirname(png_path), exist_ok=True)
    sheet.save(png_path, optimize=True)
    lines = [f'[gd_resource type="Resource" script_class="SpriteSheetSpec" load_steps={len(anims) + 3} format=3]', "",
             '[ext_resource type="Script" path="res://vfx/SpriteSheetSpec.gd" id="1_spec"]',
             '[ext_resource type="Script" path="res://vfx/SpriteAnim.gd" id="2_anim"]', ""]
    for r, a in enumerate(anims):
        lines += [f'[sub_resource type="Resource" id="a{r}"]', 'script = ExtResource("2_anim")',
                  f'name = &"{a.name}"', f"row = {r}", "first_frame = 0", f"frame_count = {len(a.frames)}",
                  f"fps = {float(a.fps)}", f"loop = {'true' if a.loop else 'false'}", ""]
    subs = ", ".join(f'SubResource("a{r}")' for r in range(len(anims)))
    lines += ["[resource]", 'script = ExtResource("1_spec")', f'texture_path = "{res_path}"',
              f"cell_size = Vector2i({cw}, {ch})", f"origin = Vector2i({origin[0]}, {origin[1]})",
              f'animations = Array[ExtResource("2_anim")]([{subs}])']
    for k, v in (meta or {}).items():
        lines.append(f'metadata/{k} = "{v}"')
    lines.append("")
    open(tres_path, "w").write("\n".join(lines))
    return sheet


def preview(sheet: Image.Image, path, scale=3, bg=(40, 44, 52)):
    # review copies never land next to game files (Godot would import them)
    from assetgen_paths import PREVIEW
    os.makedirs(PREVIEW, exist_ok=True)
    path = os.path.join(PREVIEW, os.path.basename(path))
    base = Image.new("RGBA", sheet.size, bg + (255,))
    base.alpha_composite(sheet)
    base = base.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    base.save(path)


def check_sheet(sheet: Image.Image, reserved_hex: list[str], allowed_reserved=()):
    a = np.asarray(sheet)
    alpha = a[..., 3]
    soft = int(((alpha != 0) & (alpha != 255)).sum())
    opaque = a[alpha == 255][:, :3]
    cols = {tuple(c) for c in opaque.tolist()}
    hits = []
    for r in reserved_hex:
        if r.lower() in allowed_reserved:
            continue
        if hex2rgb(r) in cols:
            hits.append(r)
    return {"soft_alpha": soft, "colours": len(cols), "reserved_hits": hits}


def red_mask(sheet: Image.Image, reds=("#e8283c", "#ff8a96")) -> Image.Image:
    """White mask of the sanctioned red pixels (visor, Core seam), everything else transparent.
    Lets colour-blind / high-contrast modes retint them (ART_DIRECTION 3, hook 6)."""
    a = np.asarray(sheet.convert("RGBA"))
    m = np.zeros(a.shape[:2], bool)
    for r in reds:
        m |= (a[..., :3] == np.array(hex2rgb(r), np.uint8)).all(-1) & (a[..., 3] == 255)
    out = np.zeros(a.shape, np.uint8)
    out[m] = (255, 255, 255, 255)
    return Image.fromarray(out, "RGBA")
