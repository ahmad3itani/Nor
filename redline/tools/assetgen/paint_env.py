#!/usr/bin/env python3
"""paint_env: code-painted environment planes, tilesets, foreground sets and critters (T02).

    python3 -B tools/assetgen/paint_env.py                 # (re)paint every item into assets/
    python3 -B tools/assetgen/paint_env.py <id> [<id> ...]  # paint some items
    python3 -B tools/assetgen/paint_env.py --check          # verify (exit 1 on any problem)
    python3 -B tools/assetgen/paint_env.py --review <dir>   # x2/x3 review composites (not the repo)

Deterministic Pillow/numpy painters (envpaint.py) in the Hollow Knight mood of
ART_DIRECTION.md sections 0 and 4: layered silhouettes, 3 values per material plus one
top-edge rim, no outlines, hard alpha, ordered Bayer dither on skies only, sparse
window / lamp accents. Every item has a fixed seed; nothing reads global randomness.

AI swap path: every file name here is also the `out` of an env_process.py recipe and an
env_queue.json entry. When a raw download for the item's manifest id exists in
art/source/raw/, env_process.py makes the file and this painter leaves it alone
(PAINTED() skips it), so an AI layer replaces a painted one with no code change.

--check (all of it fails the task gate):
 1. deterministic: two rebuilds into temp dirs are byte-identical to each other and to
    the committed files; sizes match the file contract (SIZES);
 2. hard alpha (0/255), every colour from the item's palettes.json palette, no colour
    within 48 (RGB) of a reserved gameplay colour, opaque planes fully opaque;
 3. tileability: every plane tiled x3 (A, B, A|B and B|A for variants; y too for tall
    planes) has seam columns no harsher than the 99th percentile of its own interior
    column-to-column changes;
 4. value ladder: the CIE L* median of each plane's opaque pixels inside its kind's range
    +-3 (sky 2-10, far 6-12, mid 10-18, near 14-24, backwall 16-26, fg 2-6), with near
    and backwall medians capped at 16;
 5. playfield: the new tileset face median (fill + face tiles) is 24-30 and the edge
    highlight 45-55; each district plane's median stays >= 2 value steps (12 L*) below
    its district's face median;
 6. character contrast: idle frame 0 of Rook, every enemy, the Sweeper, the NPCs and the
    bosses composited over every plane at the anchor band (below) must differ by
    >= 12 L* from the local backdrop median;
 7. critters: no dark outline (edge pixels are not darker than the body) and a median at
    or below the lowest playfield face median, so they never read as small enemies.

Anchor band (check 6). The camera keeps the player's feet near screen y 153 (vertical
offset -18) with a +-36 px dead zone, so characters stand with their feet at screen y
130, 153 or 176. A bottom-anchored plane of height h sits with its bottom row on the
screen's bottom row, so the feet land on plane rows h-140, h-117 and h-94 (above the
plane top the backdrop is the district sky); y-tiled planes use every 16th row. The
sprite is stamped every 8 px across the plane; the local backdrop median is the median
L* of the plane-over-sky composite under the sprite's opaque pixels, pooled over those
stamps. Landmark / train sprites, foreground sets and tiles are not backdrops and are
not in check 6. Planes this script does not paint (uc_far.png and title_sky.png, AI) are
measured and reported as INFO lines, never failed here.
"""
from __future__ import annotations

import filecmp
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import envpaint as ep  # noqa: E402
from envpaint import Canvas, paint_mat, top_edge, dither_vgrad, cable, chain, speckle, windows_grid  # noqa: E402
from assetgen_paths import ASSETS, REDLINE, REPO_ASSETS, RAW  # noqa: E402

OUT = ASSETS

# --------------------------------------------------------------------------- registry
# id -> dict(out, kind, district, pal, size, variants, tile_x, tile_y, opaque, manifest, fn)
ITEMS: dict[str, dict] = {}


def item(iid, out, kind, district, pal, size, variants=("",), tile_x=True, tile_y=False, opaque=False,
         manifest=None, seed=None, extra=None):
    def deco(fn):
        ITEMS[iid] = dict(id=iid, out=out, kind=kind, district=district, pal=pal, size=size, variants=variants,
                          tile_x=tile_x, tile_y=tile_y, opaque=opaque, manifest=manifest or iid,
                          seed=seed if seed is not None else (sum(ord(c) * (i + 7) for i, c in enumerate(iid)) % 99991),
                          fn=fn, extra=extra or {})
        return fn
    return deco


def rngs(it, variant):
    base = it["seed"]
    return np.random.default_rng(base), np.random.default_rng(base * 31 + (1 + "ab".index(variant or "a")) * 7919)


def variant_path(it, v):
    return it["out"] if not v else it["out"].replace(".png", "_%s.png" % v)


SEAM = 40  # shared seam zone half-width: elements crossing x=0 are identical in A and B


def slots(rng, x0, x1, wmin, wmax, gmin, gmax):
    """(x, w) runs laid left to right inside [x0, x1)."""
    out, x = [], x0 + int(rng.integers(gmin, gmax + 1))
    while True:
        w = int(rng.integers(wmin, wmax + 1))
        if x + w > x1:
            break
        out.append((x, w))
        x += w + int(rng.integers(gmin, gmax + 1))
    return out


def seam_and_body(shared, var, wmin, wmax, gmin, gmax, W=480):
    """Element runs for an A/B plane: one run straddling the seam (shared rng, so A and B match
    at both edges) plus runs strictly inside the body (variant rng)."""
    w = int(shared.integers(wmin, wmax + 1))
    seam = [(-(w // 2) + int(shared.integers(-6, 7)), w)]
    lo = seam[0][0] + seam[0][1] + int(shared.integers(gmin, gmax + 1))
    hi = W + seam[0][0] - int(shared.integers(gmin, gmax + 1))
    return seam + slots(var, lo, hi, wmin, wmax, gmin, gmax)


# =========================================================================== shared shapes
def field(it_seed, tag, h, w, cell, octaves=2, sy=3):
    """Stain field: periodic value noise, stretched vertically (sy) so stains read as seepage."""
    return ep.noise(h, w, cell, (it_seed * 131 + sum(map(ord, tag))) % (2 ** 31), octaves, sy)


def mass(cv, mask, ramp, rim=None, fld=None, lo=0.27, hi=0.76, shade="flat", x0=None, x1=None):
    """A material mass: 3 values (dark / mid / light) + a top rim. With a noise field the
    dark and light values form clustered stains instead of flat bands."""
    paint_mat(cv, mask, ramp, shade=shade, x0=x0, x1=x1)
    if fld is not None:
        ep.mottle(cv, mask, ramp[0], fld, 0.0, lo)
        ep.mottle(cv, mask, ramp[2], fld, hi, 1.01)
    if rim:
        cv.put(top_edge(mask), rim)


def pipe_h(cv, x0, x1, y, d, ramp, edge=None, flange=None):
    """Horizontal pipe of diameter d: light upper quarter, dark lower third; flanges every `flange` px."""
    dark, mid, light = ramp
    cv.rect(x0, y, x1 - x0, d, mid)
    cv.rect(x0, y + max(1, d // 4), x1 - x0, max(1, d // 4), light)
    cv.rect(x0, y + d - max(1, d // 3), x1 - x0, max(1, d // 3), dark)
    if edge:
        cv.rect(x0, y, x1 - x0, 1, edge)
    if flange:
        for fx in range(x0 + flange // 2, x1 - 2, flange):
            cv.rect(fx, y - 1, 2, d + 2, light)
            cv.rect(fx + 2, y - 1, 1, d + 2, dark)


def pipe_v(cv, x, y0, y1, d, ramp, edge=None, flange=None):
    m = cv.mask_rect(x, y0, d, y1 - y0)
    paint_mat(cv, m, ramp, shade="cyl", x0=x, x1=x + d)
    if edge:
        cv.rect(x, y0, d, 1, edge)
    if flange:
        for fy in range(y0 + flange, y1 - 2, flange):
            cv.rect(x - 1, fy, d + 2, 2, ramp[2])
            cv.rect(x - 1, fy + 2, d + 2, 1, ramp[0])


def pipe_bend(cv, x0, y0, x1, top, d, ramp, edge=None):
    """A pipe rising at x0 from y0, crossing over at `top` and dropping at x1 (an inverted U)."""
    pipe_v(cv, x0, top, y0, d, ramp)
    pipe_v(cv, x1, top, y0, d, ramp)
    pipe_h(cv, x0, x1 + d, top, d, ramp, edge=edge)


def tank(cv, x, top, w, bottom, ramp, edge, fld=None):
    body = cv.mask_rect(x, top + w // 4, w, bottom - top - w // 4) | \
        (cv.mask_ellipse(x + w / 2 - 0.5, top + w // 4, w / 2 - 0.5, w // 4) & cv.mask_rect(x, top, w, w // 4 + 1))
    mass(cv, body, ramp, rim=edge, fld=fld, shade="cyl", x0=x, x1=x + w)
    for by in range(top + w // 4 + 8, bottom - 4, 10):  # riveted bands
        cv.rect(x, by, w, 1, ramp[0])
    cv.rect(x + w // 2, top - 3, 1, 3, ramp[0])


def trestle(cv, x, y, w, h, name, name2):
    """An open steel trestle: two legs and X bracing."""
    cv.rect(x, y, 2, h, name)
    cv.rect(x + w - 2, y, 2, h, name)
    cv.rect(x, y, w, 2, name2)
    cv.line([(x + 1, y + 2), (x + w - 2, y + h - 1)], name)
    cv.line([(x + w - 2, y + 2), (x + 1, y + h - 1)], name)


def lattice_mast(cv, x, top, bottom, w, name, rim=None):
    """A lattice tower (radio mast, lamp tower, crane): two chords and zig-zag web."""
    cv.rect(x, top, 1, bottom - top, name)
    cv.rect(x + w - 1, top, 1, bottom - top, name)
    y, left = top, True
    while y < bottom - 1:
        y2 = min(bottom - 1, y + w)
        cv.line([(x if left else x + w - 1, y), (x + w - 1 if left else x, y2)], name)
        cv.rect(x, y, w, 1, name)
        y, left = y2, not left
    if rim:
        cv.rect(x, top, w, 1, rim)


def roof_shape(x, top, w, kind, rng):
    """Polygon (list of points) for a building top; kind flat/slant/gable/step/saw."""
    if kind == "slant":
        d = int(rng.integers(4, 12))
        return [(x, top + d), (x + w - 1, top), (x + w - 1, top + 400), (x, top + 400)]
    if kind == "gable":
        d = max(3, w // 3)
        return [(x, top + d), (x + w // 2, top), (x + w - 1, top + d), (x + w - 1, top + 400), (x, top + 400)]
    if kind == "step":
        s = max(4, w // 3)
        return [(x, top + 10), (x + s, top + 10), (x + s, top), (x + w - 1 - s, top), (x + w - 1 - s, top + 6),
                (x + w - 1, top + 6), (x + w - 1, top + 400), (x, top + 400)]
    if kind == "saw":
        pts = [(x, top + 400), (x, top + 6)]
        t = x
        while t + 8 < x + w:
            pts += [(t + 8, top), (t + 8, top + 6)]
            t += 8
        pts += [(x + w - 1, top + 6), (x + w - 1, top + 400)]
        return pts
    return [(x, top), (x + w - 1, top), (x + w - 1, top + 400), (x, top + 400)]


def building(cv, x, top, w, bottom, ramp, rim, rng, fld=None, kind=None, win=None, lit=None, lit_p=0.0,
             win_density=0.55, cw=2, ch=3, gx=3, gy=4, antenna=0.3):
    """A block silhouette with a roofline, stains, dark window slots and a few lit ones."""
    kind = kind or ["flat", "slant", "gable", "step", "saw"][int(rng.integers(0, 5))]
    m = cv.mask_poly(roof_shape(x, top, w, kind, rng)) & cv.mask_rect(x, top, w, bottom - top)
    mass(cv, m, ramp, rim=rim, fld=fld)
    if win:
        windows_grid(cv, m & ~top_edge(m), x + 3, top + 8, x + w - 3, bottom - 4, cw, ch, gx, gy, win, rng,
                     win_density, lit_names=lit, lit_p=lit_p)
    if rng.random() < antenna:
        ax = x + int(rng.integers(2, max(3, w - 2)))
        at = top - int(rng.integers(6, 22))
        cv.rect(ax, at, 1, top - at + 1, ramp[0])
        cv.rect(ax - 1, at + 3, 3, 1, ramp[0])
    return m


# =========================================================================== UNDERCITY
UC_MID = ("mid", "concrete_0", "steel_0")           # L 9.0 / 12.9 / 14.4
UC_NEAR = ("mid", "concrete_0", "concrete_1")       # L 9.0 / 12.9 / 16.8
UC_WALL = ("concrete_0", "steel_0", "concrete_1")   # L 12.9 / 14.4 / 16.8
UC_FAR = ("far", "sky_bottom", "mid")               # L 5.4 / 8.1 / 9.0


@item("uc_sky_vault", "undercity/uc_sky_vault.png", "sky", "undercity", "uc_env", (480, 270), opaque=True)
def uc_sky_vault(cv, sh, var, v):
    """The cistern vault seen from below: an arcade of arches under a dripping ceiling. The
    openings fall away into the dark (seepage gradient), so the body band stays near-black."""
    s = ITEMS["uc_sky_vault"]["seed"]
    f = field(s, "ceil", 270, 480, 24)
    # openings: gradient from the lit crown down into the void, then the flood line
    dither_vgrad(cv, [(40, "far"), (84, "vault"), (150, "void"), (214, "vault"), (244, "far")])
    # a second, deeper arcade seen through the first (half scale): depth by value alone
    for k in range(8):
        cx = k * 60 + 30
        ring = cv.mask_ellipse(cx, 150, 24, 24) & ~cv.mask_ellipse(cx, 150, 21, 21) & cv.mask_rect(0, 0, 480, 150)
        cv.put(ring, "far")
        cv.rect(k * 60 - 2, 150, 4, 64, "far")
    # the near arcade: spandrels (ceiling masonry) around 4 arches of 104 px on 16 px piers
    open_m = cv.blank()
    for k in range(4):
        cx = k * 120 + 60
        open_m |= cv.mask_ellipse(cx, 100, 51, 51) & cv.mask_rect(0, 0, 480, 101)
        open_m |= cv.mask_rect(cx - 51, 100, 103, 170)
    ceil = ~open_m
    mass(cv, ceil & cv.mask_rect(0, 0, 480, 110), ("far", "sky_bottom", "mid"), fld=f, lo=0.33, hi=0.7, shade="none")
    for k in range(4):
        cx = k * 120 + 60
        # arch ring (voussoirs): a lighter band with joints, lit at the crown
        ring = cv.mask_ellipse(cx, 100, 55, 55) & ~cv.mask_ellipse(cx, 100, 51, 51) & cv.mask_rect(0, 0, 480, 101)
        cv.put(ring, "mid")
        for a in range(200, 341, 14):
            t = np.radians(a)
            cv.line([(cx + 51 * np.cos(t), 100 + 51 * np.sin(t)), (cx + 55 * np.cos(t), 100 + 55 * np.sin(t))], "sky_bottom")
        crown = ring & cv.mask_rect(cx - 16, 0, 32, 50)
        cv.put(top_edge(crown) | (crown & cv.mask_rect(0, 45, 480, 2)), "fog_dark")
        # grate slit above the crown: the only light up here
        cv.rect(cx - 7, 30, 14, 3, "void")
        for gx in range(cx - 6, cx + 7, 3):
            cv.rect(gx, 30, 1, 3, "mid")
        cv.rect(cx - 8, 29, 16, 1, "fog_dark")
        # piers below the springing, fading into the dark
        px0 = k * 120 - 8
        pier = cv.mask_rect(px0, 100, 16, 100)
        cv.put(pier, "far")
        cv.rect(px0 + 3, 100, 3, 100, "sky_bottom")
        ep.dither_blend(cv, pier, "far", "vault", np.clip((np.arange(270)[:, None] - 112) / 48, 0, 1))
        cv.rect(px0 - 3, 100, 22, 4, "mid")  # impost block
        cv.rect(px0 - 3, 100, 22, 1, "fog_dark")
    # ceiling top: the deck above the arches, with rib bands
    cv.rect(0, 0, 480, 6, "mid")
    cv.rect(0, 6, 480, 1, "fog_dark")
    for x in range(0, 480, 40):
        cv.rect(x, 7, 3, 12, "sky_bottom")
    # seepage: drip streaks down the spandrels and faces
    for k in range(34):
        x = int(sh.integers(0, 480))
        y0 = int(sh.integers(8, 40))
        ln = int(sh.integers(8, 50))
        for y in range(y0, min(269, y0 + ln)):
            if ceil[y, x] and y % 2 == 0:
                cv.px(x, y, "far" if y < 60 else "vault")
    # the flood far below: a dim surface line with broken glints
    cv.rect(0, 244, 480, 1, "water_0")
    for k in range(46):
        x = int(sh.integers(0, 480))
        cv.rect(x, 246 + int(sh.integers(0, 22)), int(sh.integers(3, 14)), 1, "sky_bottom" if k % 3 else "water_0")


@item("uc_mid_pipeworks", "undercity/uc_mid_pipeworks.png", "mid", "undercity", "uc_env", (480, 180), variants=("", "b"))
def uc_mid_pipeworks(cv, sh, var, v):
    """Pump halls, stacks, tanks and looping pipe bridges of the disposal works."""
    s = ITEMS["uc_mid_pipeworks"]["seed"]
    f = field(s, "m", 180, 480, 16)
    # the hall base: continuous, with culvert arches along its foot (same in A and B)
    base = cv.mask_rect(0, 124, 480, 56)
    mass(cv, base, UC_MID, rim="concrete_1", fld=f, lo=0.28, hi=0.74, shade="none")
    for k in range(8):
        cx = k * 60 + 30
        cul = (cv.mask_ellipse(cx, 164, 14, 14) & cv.mask_rect(0, 0, 480, 165)) | cv.mask_rect(cx - 14, 164, 29, 16)
        cv.put(cul, "mid")
        cv.put(top_edge(cul), "concrete_0")
        for gx in range(cx - 12, cx + 13, 4):
            cv.rect(gx, 152, 1, 28, "far")
    for y in range(132, 180, 10):
        cv.rect(0, y, 480, 1, "mid")
    pipe_h(cv, 0, 480, 110, 7, UC_MID, edge="concrete_1", flange=60)
    pipe_h(cv, 0, 480, 119, 4, UC_MID, flange=40)
    runs = seam_and_body(sh, var, 28, 64, 14, 40)
    for i, (x, w) in enumerate(runs):
        r = sh if i == 0 else var
        kind = int(r.integers(0, 5))
        if kind in (0, 4):   # pump house with a roofline, slot windows and a stack
            top = int(r.integers(70, 96))
            m = building(cv, x, top, w, 124, UC_MID, "concrete_1", r, fld=f, win=["mid"], win_density=0.5,
                         cw=2, ch=4, gx=4, gy=5, antenna=0.0)
            if kind == 0:
                sx = x + int(r.integers(3, max(4, w - 9)))
                st_top = int(r.integers(26, 56))
                pipe_v(cv, sx, st_top, top + 4, 6, UC_MID, edge="concrete_1", flange=12)
                cv.rect(sx - 1, st_top, 8, 2, "steel_0")
                cv.rect(sx - 1, st_top, 8, 1, "concrete_1")
        elif kind == 1:  # storage tank on a trestle
            tw = min(w, int(r.integers(22, 34)))
            ttop = int(r.integers(48, 72))
            tank(cv, x, ttop, tw, 102, UC_MID, "concrete_1", fld=f)
            trestle(cv, x + 2, 102, tw - 4, 22, "mid", "concrete_0")
        elif kind == 2:  # sluice gate frame with a winch house
            gtop = int(r.integers(66, 88))
            cv.rect(x, gtop, 5, 124 - gtop, "concrete_0")
            cv.rect(x + w - 5, gtop, 5, 124 - gtop, "concrete_0")
            cv.rect(x + 1, gtop, 1, 124 - gtop, "steel_0")
            cv.rect(x - 2, gtop, w + 4, 6, "concrete_0")
            cv.rect(x - 2, gtop, w + 4, 1, "concrete_1")
            cv.rect(x + 5, gtop + 6, w - 10, 124 - gtop - 6, "mid")
            for gy in range(gtop + 10, 122, 6):
                cv.rect(x + 5, gy, w - 10, 1, "concrete_0")
            wh = cv.mask_rect(x + w // 2 - 7, gtop - 10, 14, 10)
            mass(cv, wh, UC_MID, rim="concrete_1")
        else:  # a pipe bridge looping over, and a lattice gantry
            pipe_bend(cv, x, 118, x + w - 6, int(r.integers(54, 84)), 5, UC_MID, edge="concrete_1")
            lattice_mast(cv, x + w // 2 - 3, int(r.integers(40, 70)), 110, 6, "concrete_0", rim="concrete_1")
    # route lamp housings on the base (3 px, unlit-dim), rust blooms (3 px)
    for x in range(52, 480, 120):
        cv.rect(x, 122, 3, 1, "sodium_dim")
    for k in range(8):
        x, y = int(var.integers(0, 60)) * 8 + 2, int(var.integers(128, 150))
        cv.rect(x, y, 1, 3, "rust_0")


def column(cv, x, top, bottom, w, ramp, rim, fld=None, rng=None, capital=True):
    body = cv.mask_rect(x, top, w, bottom - top)
    mass(cv, body, ramp, fld=fld, lo=0.26, hi=0.8, shade="cyl", x0=x, x1=x + w)
    if rng is not None:  # cracks and seepage down the shaft
        for k in range(3):
            cx = x + int(rng.integers(3, w - 3))
            cy = top + int(rng.integers(20, max(21, bottom - top - 40)))
            for d in range(int(rng.integers(6, 20))):
                cv.px(cx + (d // 4) % 2, cy + d, ramp[0])
    if capital:
        cap = cv.mask_rect(x - 5, top, w + 10, 7) | cv.mask_rect(x - 3, top + 7, w + 6, 3)
        mass(cv, cap, ramp, rim=rim, shade="flat")
    cv.rect(x - 3, bottom - 12, w + 6, 12, ramp[0])
    cv.rect(x - 3, bottom - 12, w + 6, 1, ramp[1])


@item("uc_near_columns", "undercity/uc_near_columns.png", "near", "undercity", "uc_env", (480, 220), variants=("", "b"))
def uc_near_columns(cv, sh, var, v):
    """Drowned arcade columns carrying the vault, with algae drapes and hanging chains."""
    s = ITEMS["uc_near_columns"]["seed"]
    f = field(s, "c", 220, 480, 12)
    # flood water across the bottom, with broken reflection lines
    cv.rect(0, 202, 480, 18, "water_0")
    for y in (205, 210, 216):
        for x in range(0, 480, 13):
            cv.rect((x + y * 5) % 480, y, 4 + (x // 13) % 3, 1, "water_1")
    # the ward's parapet walkway behind the columns
    wall = cv.mask_rect(0, 180, 480, 22)
    mass(cv, wall, UC_NEAR, rim="concrete_1", fld=f, shade="none")
    for x in range(0, 480, 24):
        cv.rect(x, 186, 1, 16, "mid")
    cv.rect(0, 171, 480, 2, "concrete_0")
    for x in range(0, 480, 12):
        cv.rect(x, 173, 1, 7, "concrete_0")
    cols = [(-17 + int(sh.integers(-4, 5)), int(sh.integers(30, 38)))]
    xs = [150 + int(var.integers(-24, 25)), 310 + int(var.integers(-24, 25))]
    cols += [(x, int(var.integers(26, 34))) for x in xs]
    # the arch crowns between column heads: a heavy lintel band at the top edge
    for i in range(len(cols)):
        a = cols[i]
        b = cols[(i + 1) % len(cols)]
        bx = b[0] if b[0] > a[0] else b[0] + 480
        span = cv.mask_rect(a[0] + a[1], 0, bx - a[0] - a[1], 12)
        cx = (a[0] + a[1] + bx) / 2
        rad = (bx - a[0] - a[1]) / 2
        span &= ~(cv.mask_ellipse(cx, 12 + rad * 0.2, rad, rad * 0.55))
        mass(cv, span, UC_NEAR, fld=f, shade="none")
        cv.put(span & ~np.roll(span, -1, 0), "concrete_1")  # lit intrados edge
    for i, (x, w) in enumerate(cols):
        r = sh if i == 0 else var
        column(cv, x, 12, 202, w, UC_NEAR, "steel_1", fld=f, rng=r)
        for k in range(int(r.integers(2, 4))):  # algae drapes from the capital
            hx = x - 3 + int(r.integers(0, w + 6))
            ln = int(r.integers(6, 26))
            for y in range(22, 22 + ln):
                cv.px(hx, y, "algae_0" if (y + hx) % 4 else "mid")
    a, b = cols[1], cols[2]
    # a chain with a hook hanging from the lintel, a sagging cable and a pipe between the body columns
    hx = (a[0] + a[1] + b[0]) // 2 + int(var.integers(-20, 20))
    chain(cv, hx, 12, int(var.integers(40, 70)), "concrete_0", "mid")
    cable(cv, a[0] + a[1] + 2, 30, b[0] - 2, 34, 22, "concrete_0")
    pipe_h(cv, a[0] + a[1] + 3, b[0] - 3, 62, 5, UC_NEAR, flange=30)


@item("uc_backwall_ward", "undercity/uc_backwall_ward.png", "backwall", "undercity", "uc_env", (480, 270), opaque=True)
def uc_backwall_ward(cv, sh, var, v):
    """The intake ward wall: glazed tiles, a gurney rail, four dark intake bays at body height."""
    s = ITEMS["uc_backwall_ward"]["seed"]
    f = field(s, "w", 270, 480, 16)
    streak = field(s, "s", 270, 480, 4, octaves=1)
    cv.put(np.ones((270, 480), bool), "steel_0")
    for y in range(0, 270, 6):
        cv.rect(0, y, 480, 1, "concrete_1")
        off = 0 if (y // 6) % 2 else 4
        for x in range(off, 480, 8):
            cv.rect(x, y, 1, 6, "concrete_1")
    # water stains running down from the cornice: long vertical blotches
    Y = np.arange(270)[:, None]
    stain = (f < 0.36) & (streak[:1, :] < 0.5) & (Y < 200)
    cv.put(stain & (cv.idx == cv.ci("steel_0")), "concrete_0")
    for k in range(40):  # missing tiles
        x, y = int(sh.integers(0, 60)) * 8, int(sh.integers(3, 30)) * 6
        cv.rect(x + 1, y + 1, 7, 5, "concrete_0")
        cv.rect(x + 1, y + 1, 7, 1, "mid")
    # cornice with a service pipe run, and a dado rail
    cv.rect(0, 0, 480, 12, "concrete_0")
    cv.rect(0, 12, 480, 2, "concrete_1")
    cv.rect(0, 14, 480, 1, "steel_1")
    pipe_h(cv, 0, 480, 18, 6, UC_WALL, edge="steel_1", flange=80)
    cv.rect(0, 186, 480, 4, "concrete_0")
    cv.rect(0, 186, 480, 1, "steel_1")
    for x in range(0, 480, 40):  # lower wall panels (above: the rail passes behind the bays)
        cv.rect(x, 194, 38, 68, "concrete_1")
        cv.rect(x, 194, 38, 1, "steel_1")
        cv.rect(x + 37, 194, 1, 68, "concrete_0")
        cv.rect(x + 2, 250, 34, 12, "steel_0")
    cv.rect(0, 262, 480, 8, "concrete_0")
    # the gurney rail across the wall
    cv.rect(0, 80, 480, 2, "concrete_0")
    cv.rect(0, 80, 480, 1, "steel_1")
    for x in range(10, 480, 30):
        cv.rect(x, 76, 1, 4, "concrete_0")
    for k in range(4):
        x = k * 120 + 18
        w = 84
        # intake number plate (blank) above the bay
        cv.rect(x + w // 2 - 8, 26, 16, 7, "concrete_1")
        cv.rect(x + w // 2 - 7, 27, 14, 5, "steel_0")
        # frame and the tall dark bay (arched head)
        head = cv.mask_ellipse(x + w / 2 - 0.5, 60, w / 2 + 3, 20) & cv.mask_rect(0, 0, 480, 61)
        cv.put(head, "concrete_1")
        cv.put(top_edge(head), "steel_1")
        cv.rect(x - 4, 60, 4, 118, "concrete_0")
        cv.rect(x + w, 60, 4, 118, "concrete_0")
        bay = (cv.mask_ellipse(x + w / 2 - 0.5, 60, w / 2 - 1, 17) & cv.mask_rect(0, 0, 480, 61)) | cv.mask_rect(x, 60, w, 118)
        cv.put(bay, "vault")
        cv.put(bay & cv.mask_rect(0, 0, 480, 70), "void")
        ep.dither_blend(cv, cv.mask_rect(x, 150, w, 28), "vault", "far",
                        np.clip((np.arange(270)[:, None] - 150) / 28, 0, 1) * 0.5)
        cv.rect(x - 4, 178, w + 8, 4, "concrete_0")
        cv.rect(x - 4, 178, w + 8, 1, "concrete_1")
        # inside: a rail, a hook and a gurney silhouette
        cv.rect(x, 112, w, 1, "far")
        hx = x + 14 + int(sh.integers(0, 40))
        cv.rect(hx, 113, 1, 10, "far")
        cv.rect(hx - 1, 123, 3, 1, "far")
        gx = x + 8 + int(sh.integers(0, 30))
        cv.rect(gx, 160, 34, 3, "far")
        cv.rect(gx + 2, 163, 1, 12, "far")
        cv.rect(gx + 31, 163, 1, 12, "far")
        cv.rect(gx + 4, 157, 12, 3, "far")
        # conduit between bays
        pipe_v(cv, x + w + 18, 24, 186, 3, UC_WALL)
    for k in range(4):  # route lamp housings (unlit), 3 px
        cv.rect(k * 120 + 8, 92, 3, 2, "sodium_dim")


@item("uc_shaft_near", "undercity/uc_shaft_near.png", "near", "undercity", "uc_env", (480, 270), tile_y=True)
def uc_shaft_near(cv, sh, var, v):
    """The maintenance shaft: I-beam girders with X bracing, a ladder, a riser, a platform."""
    for gx in (40, 280):
        for dx in (0, 70):
            m = cv.mask_rect(gx + dx, 0, 10, 270)
            paint_mat(cv, m, UC_NEAR, shade="flat")
            cv.rect(gx + dx + 4, 0, 2, 270, "mid")
            for y in range(0, 270, 18):
                cv.rect(gx + dx, y, 10, 1, "concrete_1")
                cv.px(gx + dx + 2, y + 3, "steel_1")
                cv.px(gx + dx + 7, y + 3, "steel_1")
        for y in range(0, 270, 54):
            cv.line([(gx + 10, y), (gx + 70, y + 54)], "concrete_0", width=2)
            cv.line([(gx + 70, y), (gx + 10, y + 54)], "concrete_0", width=2)
            cv.rect(gx + 10, y, 60, 3, "concrete_0")
            cv.rect(gx + 10, y, 60, 1, "concrete_1")
    cv.rect(190, 0, 1, 270, "concrete_0")
    cv.rect(198, 0, 1, 270, "concrete_0")
    for y in range(0, 270, 6):
        if y not in (96, 102):  # two missing rungs
            cv.rect(190, y, 9, 1, "concrete_0")
    pipe_v(cv, 420, 0, 270, 8, UC_NEAR, flange=27)
    pipe_v(cv, 440, 0, 270, 4, UC_NEAR, flange=45)
    for y in (20, 110, 200):
        cable(cv, 120, y, 280, y + 6, 14, "mid")
    cv.rect(270, 150, 110, 4, "concrete_0")
    cv.rect(270, 150, 110, 1, "steel_1")
    for x in range(272, 380, 8):
        cv.rect(x, 142, 1, 8, "concrete_0")
    cv.rect(270, 142, 110, 1, "concrete_0")
    cv.rect(300, 154, 3, 2, "sodium_dim")
    for y in range(0, 270, 30):  # seepage stains down the riser side
        cv.rect(418, y + 4, 1, 6, "algae_0")


@item("uc_tunnel_mid", "undercity/uc_tunnel_mid.png", "mid", "undercity", "uc_env", (480, 160))
def uc_tunnel_mid(cv, sh, var, v):
    """The escape tunnel: ring ribs, the trackbed, a dead two-car tram, the catenary wire."""
    s = ITEMS["uc_tunnel_mid"]["seed"]
    f = field(s, "t", 160, 480, 12)
    for k in range(8):
        x = k * 60 + 30
        cv.rect(x, 58, 6, 102, "concrete_0")
        cv.rect(x, 58, 1, 102, "steel_0")
        cv.rect(x - 2, 56, 10, 3, "concrete_0")
        cv.rect(x - 2, 56, 10, 1, "concrete_1")
        cv.rect(x + 2, 70, 2, 3, "mid")  # cable cleat
    cv.rect(0, 74, 480, 2, "concrete_0")  # cable tray along the wall
    cv.rect(0, 140, 480, 20, "mid")
    cv.rect(0, 140, 480, 1, "concrete_0")
    cv.rect(0, 136, 480, 2, "steel_0")
    cv.rect(0, 136, 480, 1, "concrete_1")
    for x in range(0, 480, 10):
        cv.rect(x, 138, 6, 2, "concrete_0")
    x0 = 120
    for car in range(2):
        cx = x0 + car * 124
        body = cv.mask_rect(cx, 96, 118, 38) | cv.mask_rect(cx + 4, 92, 110, 4)
        mass(cv, body, UC_MID, rim="concrete_1", fld=f)
        for wx in range(cx + 8, cx + 110, 14):
            cv.rect(wx, 102, 10, 12, "far")
            cv.rect(wx, 102, 10, 1, "mid")
            if (wx // 14) % 3 == 0:  # a broken pane: jagged glass left in the frame
                cv.rect(wx + 1, 103, 3, 2, "mid")
        cv.rect(cx, 120, 118, 1, "steel_0")
        cv.rect(cx + 50, 100, 1, 34, "mid")  # door seam
        for wx in (cx + 12, cx + 96):
            cv.rect(wx, 134, 10, 3, "mid")
    cv.line([(190, 92), (200, 78), (212, 80)], "concrete_0")
    cv.line([(200, 78), (196, 70)], "concrete_0")
    cv.rect(0, 64, 480, 1, "concrete_0")
    for x in range(30, 480, 60):
        cv.rect(x, 59, 1, 5, "concrete_0")
    for x in (40, 330, 420):
        cv.rect(x, 146, 4, 1, "water_1")
    cv.rect(96, 150, 3, 1, "water_glint")


@item("uc_boss_bay", "undercity/uc_boss_bay.png", "sky", "undercity", "uc_env", (480, 270), opaque=True, tile_x=False)
def uc_boss_bay(cv, sh, var, v):
    """Collector Bay, the arena's only backdrop (screen-fixed, so it is measured as a sky): a dark
    riveted plate wall, cage bays, a crane rail with chains and the great unlit hatch ring (its
    red glow stays code). The ring is the brightest structure; everything else stays low."""
    s = ITEMS["uc_boss_bay"]["seed"]
    f = field(s, "b", 270, 480, 20)
    allm = np.ones((270, 480), bool)
    cv.put(allm, "sky_bottom")
    ep.mottle(cv, allm, "far", f, 0.0, 0.3)
    for y in range(0, 270, 30):
        cv.rect(0, y, 480, 1, "mid")
        cv.rect(0, y + 29, 480, 1, "far")
    for x in range(0, 480, 40):
        cv.rect(x, 0, 1, 270, "mid")
        for y in range(4, 270, 10):
            cv.px(x + 3, y, "vault")
    for x in range(0, 480, 96):
        m = cv.mask_rect(x, 0, 10, 270)
        paint_mat(cv, m, ("far", "mid", "concrete_0"), shade="flat")
    for (ax, ay) in ((0, 30), (480, 30), (0, 250), (480, 250)):  # struts from the ring to the frame
        cv.line([(240, 138), (ax, ay)], "far", width=5)
        cv.line([(240, 138), (ax, ay)], "mid", width=1)
    cv.rect(0, 18, 480, 6, "mid")
    cv.rect(0, 18, 480, 1, "concrete_0")
    for x in range(8, 480, 16):
        cv.rect(x, 24, 2, 2, "far")
    for bx in (16, 384):
        cv.rect(bx, 92, 80, 88, "vault")
        cv.rect(bx, 92, 80, 6, "void")
        cv.rect(bx - 3, 89, 86, 3, "mid")
        cv.rect(bx - 3, 89, 86, 1, "concrete_0")
        cv.rect(bx - 3, 180, 86, 3, "far")
        for k in range(2):
            cx = bx + 12 + k * 36
            cv.rect(cx + 8, 92, 1, 16, "far")
            cage = cv.mask_rect(cx, 108, 18, 26)
            cv.put(cage & ~cv.mask_rect(cx + 1, 109, 16, 24), "far")
            for gx in range(cx + 4, cx + 16, 4):
                cv.rect(gx, 109, 1, 24, "far")
    ring = cv.mask_ellipse(240, 138, 94, 94)
    inner = cv.mask_ellipse(240, 138, 80, 80)
    mass(cv, ring & ~inner, UC_WALL, fld=f, shade="none")
    rr = cv.mask_ellipse(240, 138, 88, 88) & ~cv.mask_ellipse(240, 138, 86, 86)
    cv.put(rr, "concrete_0")
    cv.put(top_edge(ring), "steel_1")
    cv.put(inner, "vault")
    cv.put(cv.mask_ellipse(240, 138, 66, 66), "void")
    for a in range(0, 360, 45):
        t = np.radians(a)
        cv.line([(240 + 66 * np.cos(t), 138 + 66 * np.sin(t)), (240 + 80 * np.cos(t), 138 + 80 * np.sin(t))], "far")
    for a in range(0, 360, 30):
        t = np.radians(a)
        cv.rect(240 + 91 * np.cos(t) - 1, 138 + 91 * np.sin(t) - 1, 2, 2, "steel_1")
    for hx, ln in ((150, 40), (330, 56)):  # chains with hooks from the crane rail
        chain(cv, hx, 24, ln, "mid", "concrete_0")
        cv.rect(hx - 1, 24 + ln, 3, 1, "mid")
        cv.rect(hx + 1, 24 + ln - 2, 1, 2, "mid")
    cv.rect(0, 250, 480, 20, "far")
    cv.rect(0, 250, 480, 1, "mid")


# --------------------------------------------------------------------------- foreground sets
def fg_pack(cv, pieces):
    """Shelf-pack piece canvases (index arrays, -1 transparent) into cv; returns region meta."""
    x = y = rowh = 0
    meta = []
    for name, piece, anchor in pieces:
        h, w = piece.shape
        if x + w > cv.w:
            x, y, rowh = 0, y + rowh + 2, 0
        cv.idx[y:y + h, x:x + w] = np.where(piece >= 0, piece, cv.idx[y:y + h, x:x + w])
        meta.append({"name": name, "rect": [x, y, w, h], "anchor": anchor,
                     "origin": [w // 2, h if anchor == "bottom" else 0]})
        x += w + 2
        rowh = max(rowh, h)
    return meta


def piece(pal, w, h):
    return Canvas(w, h, pal, wrap_x=False)


def fg_meta(meta, pal, note):
    return {"regions": meta, "palette": pal, "note": note,
            "anchor_rule": "bottom = origin at the bottom-centre (sits below the floor line); "
                           "top = origin at the top-centre (hangs into the top 40 px)"}


@item("uc_fg_set", "undercity/uc_fg_set.png", "fg", "undercity", "uc_env", (256, 160), tile_x=False,
      manifest="uc_fg_silhouettes")
def uc_fg_set(cv, sh, var, v):
    D, M, L, R = "void", "vault", "far", "concrete_0"   # 3 values + rim
    ps = []
    for name, ln in (("chain_long", 96), ("chain_short", 52)):
        p = piece("uc_env", 12, ln + 8)
        for x in (3, 8):
            chain(p, x, 0, ln - (x - 3) * 3, D, M)
        p.rect(7, ln - 12, 4, 2, M)
        p.rect(9, ln - 10, 2, 5, D)
        p.rect(2, 0, 9, 2, R)
        ps.append((name, p.idx, "top"))
    p = piece("uc_env", 72, 56)  # curtain rail with torn curtain strips
    p.rect(0, 0, 72, 3, M)
    p.rect(0, 0, 72, 1, R)
    for k, x in enumerate(range(2, 70, 6)):
        ln = int(sh.integers(14, 54))
        p.rect(x, 3, 5, ln, D if k % 2 else M)
        p.rect(x, 3, 1, ln, L)
        for t in range(0, ln, 7):
            p.px(x + 4, 3 + t, L)
        p.idx[3 + ln - 1, x + 1 + int(sh.integers(0, 3))] = -1  # torn hem
    ps.append(("curtain_rail", p.idx, "top"))
    p = piece("uc_env", 40, 64)  # pipe end: comes down from the top, elbow, broken flange
    p.rect(8, 0, 14, 40, M)
    p.rect(10, 0, 3, 40, L)
    p.rect(19, 0, 3, 40, D)
    p.rect(8, 36, 30, 14, M)
    p.rect(8, 38, 30, 3, L)
    p.rect(8, 47, 30, 3, D)
    p.rect(36, 34, 4, 18, L)
    p.rect(36, 34, 1, 18, R)
    p.rect(6, 12, 18, 3, L)
    p.rect(6, 12, 18, 1, R)
    for y in range(52, 64, 3):
        p.px(38, y, L)
    ps.append(("pipe_end", p.idx, "top"))
    for name, w, h in (("rubble_a", 64, 22), ("rubble_b", 40, 16)):
        p = piece("uc_env", w, h)
        for k in range(int(w / 5)):
            cw, ch = int(sh.integers(5, 14)), int(sh.integers(4, 10))
            cx = int(sh.integers(0, w - cw))
            cy = h - ch - int(sh.integers(0, max(1, h // 2 - ch // 2)))
            poly = [(cx, cy + ch), (cx + 2, cy), (cx + cw - 3, cy + 1), (cx + cw, cy + ch)]
            m = p.mask_poly(poly)
            p.put(m, [D, M, L][k % 3])
            p.put(top_edge(m) & (np.arange(w)[None, :] % 3 != 0), R)
        p.rect(0, h - 3, w, 3, D)
        p.line([(w // 2, h - 4), (w // 2 + 8, 0)], M)  # rebar
        ps.append((name, p.idx, "bottom"))
    p = piece("uc_env", 72, 24)  # bent railing
    p.rect(0, 20, 72, 4, D)
    p.line([(0, 6), (30, 6), (44, 12), (72, 14)], M, width=2)
    p.line([(0, 6), (30, 6)], R)
    for x in range(4, 72, 10):
        top = 6 if x < 30 else 6 + (x - 30) // 3
        p.rect(x, top, 1, 20 - top, M)
    ps.append(("railing_broken", p.idx, "bottom"))
    meta = fg_pack(cv, ps)
    return fg_meta(meta, "uc_env", "Undercity foreground silhouettes (hanging chains, curtain rail, pipe end, rubble, railing)")


# =========================================================================== LOWLIGHT
LL_FAR = ("sky_1", "far", "mid")                    # L 5.2 / 5.8 / 8.7
LL_MID = ("mid", "fog_dark", "brick_0")             # L 8.7 / 11.8 / 13.6
LL_NEAR = ("concrete_0", "brick_0", "brick_1")      # L 10.0 / 13.6 / 19.7
LL_WALL = ("brick_0", "concrete_1", "brick_1")      # L 13.6 / 15.0 / 19.7
LL_WIN_FAR = ["window_warm_far", "window_cold_far", "window_rose"]
LL_WIN = ["window_warm", "window_warm_far", "window_cold", "window_rose"]


def warden_tower(cv, cx, top, bottom, name, lit):
    """The Wardens' tower: a tapering shaft with a flared crown and a spire (always on the horizon)."""
    cv.poly([(cx - 14, bottom), (cx - 8, top + 30), (cx + 8, top + 30), (cx + 14, bottom)], name)
    cv.poly([(cx - 16, top + 30), (cx - 12, top + 16), (cx + 12, top + 16), (cx + 16, top + 30)], name)
    cv.poly([(cx - 22, bottom), (cx - 18, bottom - 60), (cx - 14, bottom - 60), (cx - 12, bottom)], name)
    cv.rect(cx - 7, top + 8, 14, 8, name)
    cv.rect(cx - 1, top, 2, 10, name)
    cv.rect(cx - 5, top + 22, 10, 1, lit)   # a slit of cold light in the crown (1 x 10 px)
    for y in range(top + 40, bottom - 6, 14):
        cv.rect(cx - 1, y, 1, 3, lit)


def sky_clouds(cv, it_seed, tag, y0, y1, names, cell=24, lo=(0.55, 0.68)):
    """Cloud banks as clustered value-noise bands (dithered only at their soft top edge)."""
    f = ep.noise(cv.h, cv.w, cell, it_seed * 7 + sum(map(ord, tag)), 3, 1)
    Y = np.arange(cv.h)[:, None]
    band = (Y >= y0) & (Y < y1)
    fall = np.clip(1 - np.abs((Y - (y0 + y1) / 2) / ((y1 - y0) / 2)), 0, 1)
    v = f * (0.6 + 0.4 * fall)
    cv.put(band & (v > lo[0]), names[0])
    cv.put(band & (v > lo[1]), names[1])


@item("ll_sky_night", "lowlight/ll_sky_night.png", "sky", "lowlight", "ll_env", (480, 270), opaque=True)
def ll_sky_night(cv, sh, var, v):
    """Night over Lowlight: a low cloud deck lit from below by the city, the dark middle
    where the characters play, and the Wardens' tower on the horizon."""
    s = ITEMS["ll_sky_night"]["seed"]
    dither_vgrad(cv, [(0, "sky_bottom"), (46, "far"), (86, "sky_1"), (120, "sky_top"), (196, "sky_top"),
                      (236, "sky_1"), (262, "far")])
    sky_clouds(cv, s, "deck", -30, 80, ["mid", "fog_dark"], cell=40, lo=(0.46, 0.62))
    sky_clouds(cv, s, "wisps", 56, 100, ["far", "sky_bottom"], cell=20, lo=(0.52, 0.66))
    warden_tower(cv, 344, 108, 270, "sky_top", "window_cold_far")
    # a distant low skyline haze band on the horizon (the city far below the tower)
    for x in range(0, 480, 6):
        hgt = 8 + int(sh.integers(0, 14))
        cv.rect(x, 262 - hgt, 6, hgt + 8, "sky_1")


@item("ll_sky_storm", "lowlight/ll_sky_storm.png", "sky", "lowlight", "ll_env", (480, 270), opaque=True)
def ll_sky_storm(cv, sh, var, v):
    """Storm over the roofs: heavy cloud rolls with a lit underside, the tower on the horizon."""
    s = ITEMS["ll_sky_storm"]["seed"]
    dither_vgrad(cv, [(0, "mid"), (40, "sky_bottom"), (80, "far"), (112, "sky_1"), (200, "sky_1"),
                      (246, "far")])
    sky_clouds(cv, s, "roll", 0, 84, ["fog_dark", "fog_light"], cell=36, lo=(0.52, 0.66))
    sky_clouds(cv, s, "under", 50, 100, ["sky_bottom", "mid"], cell=20, lo=(0.6, 0.72))
    # the storm glow: one torn break where the lightning lives (sparse)
    f = ep.noise(270, 480, 12, s + 5, 2, 1)
    Y = np.arange(270)[:, None]
    X = np.arange(480)[None, :]
    near = ((X - 120) ** 2 / 90 ** 2 + (Y - 30) ** 2 / 22 ** 2) < 1
    cv.put(near & (f > 0.62), "storm_glow")
    warden_tower(cv, 344, 108, 270, "sky_top", "window_cold_far")
    for x in range(0, 480, 6):
        hgt = 8 + int(sh.integers(0, 14))
        cv.rect(x, 262 - hgt, 6, hgt + 8, "sky_top")


def ll_skyline(cv, sh, var, H, ramp, rim, top_rng, win, lit, lit_p, wmin, wmax, gmin, gmax, spire_p=0.25,
               bridge=True, cw=1, ch=3, gx=3, gy=4, fld=None):
    runs = seam_and_body(sh, var, wmin, wmax, gmin, gmax)
    tops = []
    for i, (x, w) in enumerate(runs):
        r = sh if i == 0 else var
        top = int(r.integers(*top_rng))
        building(cv, x, top, w, H, ramp, rim, r, fld=fld, win=win, lit=lit, lit_p=lit_p, win_density=0.5,
                 cw=cw, ch=ch, gx=gx, gy=gy, antenna=0.5)
        if r.random() < spire_p:  # a stepped spire / setback crown
            sw = max(4, w // 3)
            sx = x + (w - sw) // 2
            st = top - int(r.integers(10, 30))
            m = cv.mask_rect(sx, st, sw, top - st + 1)
            mass(cv, m, ramp, rim=rim)
            cv.rect(sx + sw // 2, st - 8, 1, 8, ramp[0])
        tops.append((x, w, top))
    if bridge:  # thin sky-bridges and cables between neighbours
        for (x0, w0, t0), (x1, w1, t1) in zip(tops, tops[1:]):
            y = max(t0, t1) + 12
            if x1 - (x0 + w0) < 40:
                cv.rect(x0 + w0, y, x1 - x0 - w0, 2, ramp[0])
            cable(cv, x0 + w0 - 1, max(t0, t1) + 4, x1, max(t0, t1) + 6, 6, ramp[0])
    return tops


@item("ll_far_skyline", "lowlight/ll_far_skyline.png", "far", "lowlight", "ll_env", (480, 160), variants=("", "b"))
def ll_far_skyline(cv, sh, var, v):
    """Distant stacked blocks and spires, muted warm / cold / rose windows."""
    ll_skyline(cv, sh, var, 160, LL_FAR, "fog_dark", (14, 70), ["sky_1"], LL_WIN_FAR, 0.05, 18, 44, 0, 8)
    # a haze-dark base so the band dissolves into fog A
    for y in range(140, 160):
        cv.rect(0, y, 480, 1, "far" if y % 3 else "sky_1")


@item("ll_far_bell_tower", "lowlight/ll_far_bell_tower.png", "far", "lowlight", "ll_env", (48, 160), tile_x=False)
def ll_far_bell_tower(cv, sh, var, v):
    """Landmark: the bell tower on the far layer: a square shaft, an open belfry with the bell
    silhouette, a pointed roof and a finial."""
    c = 24
    cv.rect(c - 10, 60, 20, 100, "far")
    cv.rect(c - 10, 60, 2, 100, "mid")
    cv.rect(c + 8, 60, 2, 100, "sky_1")
    cv.rect(c - 12, 56, 24, 4, "mid")
    cv.rect(c - 12, 56, 24, 1, "fog_dark")
    # belfry: two arched openings with the bell hanging inside one
    cv.rect(c - 11, 30, 22, 26, "far")
    for ox in (-7, 3):
        op = cv.mask_rect(c + ox, 36, 5, 18) | cv.mask_ellipse(c + ox + 2, 36, 2, 3)
        cv.put(op, "sky_top")
    cv.poly([(c - 6, 48), (c - 5, 42), (c - 3, 42), (c - 2, 48)], "mid")  # bell
    cv.rect(c - 12, 28, 24, 2, "mid")
    cv.rect(c - 12, 28, 24, 1, "fog_dark")
    cv.poly([(c - 12, 28), (c, 4), (c + 11, 28)], "far")
    cv.line([(c - 12, 28), (c, 4)], "mid")
    cv.rect(c, 0, 1, 6, "mid")
    cv.rect(c - 2, 2, 5, 1, "mid")
    for y in range(70, 150, 16):  # stair slits, one lit (3 px)
        cv.rect(c - 1, y, 1, 3, "sky_1")
    cv.rect(c - 1, 102, 1, 3, "window_warm_far")
    cv.rect(c - 6, 150, 12, 10, "sky_1")  # the door


@item("ll_train_far", "lowlight/ll_train_far.png", "far", "lowlight", "ll_env", (144, 14), tile_x=False)
def ll_train_far(cv, sh, var, v):
    """A far train silhouette (loco + 2 cars) with window dots; crosses the far layer (code)."""
    for k in range(3):
        x = k * 48
        body = cv.mask_rect(x + 1, 3, 46, 9) | cv.mask_rect(x + 3, 2, 42, 1)
        if k == 0:
            body = cv.mask_poly([(1, 12), (1, 5), (6, 2), (47, 2), (47, 12)])
        cv.put(body, "far")
        cv.rect(x + 1, 3, 46, 1, "mid")
        for wx in range(x + 10 if k else x + 14, x + 44, 12):
            cv.rect(wx, 5, 3, 1, LL_WIN_FAR[(wx // 12) % 2])
        cv.rect(x + 4, 12, 3, 2, "sky_1")
        cv.rect(x + 40, 12, 3, 2, "sky_1")
    cv.rect(10, 0, 1, 2, "far")  # pantograph
    cv.rect(8, 0, 5, 1, "far")


@item("ll_mid_blocks", "lowlight/ll_mid_blocks.png", "mid", "lowlight", "ll_env", (480, 190), variants=("", "b"))
def ll_mid_blocks(cv, sh, var, v):
    """Apartment blocks: fire escapes, balconies, blank sign frames, warm people's windows."""
    s = ITEMS["ll_mid_blocks"]["seed"]
    f = field(s, "b", 190, 480, 12)
    tops = ll_skyline(cv, sh, var, 190, LL_MID, "concrete_2", (40, 104), ["mid", "puddle_0"], LL_WIN, 0.08,
                      34, 70, 4, 18, spire_p=0.0, bridge=False, cw=2, ch=3, gx=4, gy=5, fld=f)
    for i, (x, w, top) in enumerate(tops):
        r = sh if i == 0 else var
        if r.random() < 0.6:  # fire escape: landings and zig-zag stairs on one flank
            fx = x + (2 if r.random() < 0.5 else w - 14)
            for y in range(top + 16, 180, 16):
                cv.rect(fx, y, 12, 1, "concrete_2")
                cv.rect(fx, y - 4, 1, 4, "mid")
                cv.rect(fx + 11, y - 4, 1, 4, "mid")
                cv.line([(fx + 1, y + 1), (fx + 10, y + 15)], "mid")
        if r.random() < 0.5:  # a blank sign frame on brackets
            sx = x + int(r.integers(2, max(3, w - 18)))
            sy = top + int(r.integers(8, 30))
            cv.rect(sx, sy, 16, 7, "mid")
            cv.rect(sx, sy, 16, 1, "concrete_2")
            cv.rect(sx + 1, sy + 1, 14, 5, "puddle_0")
    for y in range(176, 190):  # street-level shadow
        cv.idx[y][cv.idx[y] >= 0] = cv.ci("mid")


@item("ll_mid_roofs", "lowlight/ll_mid_roofs.png", "mid", "lowlight", "ll_env", (480, 150), variants=("", "b"))
def ll_mid_roofs(cv, sh, var, v):
    """Roofscape: water tanks on stilts, antennas, chimneys, laundry lines (baked static)."""
    s = ITEMS["ll_mid_roofs"]["seed"]
    f = field(s, "r", 150, 480, 12)
    base = cv.mask_rect(0, 118, 480, 32)
    mass(cv, base, LL_MID, rim="concrete_2", fld=f, shade="none")
    runs = seam_and_body(sh, var, 30, 64, 6, 20)
    for i, (x, w) in enumerate(runs):
        r = sh if i == 0 else var
        top = int(r.integers(70, 108))
        building(cv, x, top, w, 120, LL_MID, "concrete_2", r, fld=f, win=["mid"], lit=LL_WIN, lit_p=0.06,
                 win_density=0.4, cw=2, ch=3, gx=5, gy=5, antenna=0.0)
        kind = int(r.integers(0, 3))
        if kind == 0:  # water tank on stilts
            tx = x + int(r.integers(0, max(1, w - 16)))
            tank(cv, tx, top - 34, 16, top - 12, LL_MID, "concrete_2")
            trestle(cv, tx + 1, top - 12, 14, 12, "mid", "fog_dark")
        elif kind == 1:  # antenna mast with guy wires
            ax = x + int(r.integers(4, max(5, w - 4)))
            at = int(r.integers(14, 50))
            lattice_mast(cv, ax, at, top, 3, "mid", rim="concrete_2")
            cable(cv, ax + 1, at + 6, x, top, 3, "fog_dark")
            cable(cv, ax + 1, at + 6, x + w - 1, top, 3, "fog_dark")
        else:  # chimney stacks
            for k in range(int(r.integers(1, 4))):
                cx = x + int(r.integers(2, max(3, w - 6)))
                ct = top - int(r.integers(6, 18))
                cv.rect(cx, ct, 4, top - ct, "fog_dark")
                cv.rect(cx - 1, ct, 6, 2, "brick_0")
                cv.rect(cx - 1, ct, 6, 1, "concrete_2")
    # laundry lines baked static between roofs: sagging lines with cloth squares
    tops_x = [x for x, w in runs]
    for a, b in zip(tops_x[1:], tops_x[2:]):
        y0 = 84 + int(var.integers(0, 20))
        pts = ep.catenary(a + 6, y0, b + 4, y0 + 2, 8)
        cv.line(pts, "fog_dark")
        for k in range(3, len(pts) - 3, 9):
            px, py = pts[k]
            cv.rect(px, py + 1, 4, int(var.integers(3, 7)), ["brick_1", "concrete_1", "violet_muted"][k % 3])


@item("ll_canal_mid", "lowlight/ll_canal_mid.png", "mid", "lowlight", "ll_env", (480, 150))
def ll_canal_mid(cv, sh, var, v):
    """The smugglers' canal: quay walls, a low arched bridge, moored boats, lamp posts."""
    s = ITEMS["ll_canal_mid"]["seed"]
    f = field(s, "c", 150, 480, 12)
    cv.rect(0, 132, 480, 18, "puddle_0")
    for y in (135, 140, 146):
        for x in range(0, 480, 17):
            cv.rect((x + y * 7) % 480, y, 5, 1, "fog_dark")
    quay = cv.mask_rect(0, 110, 480, 22)
    mass(cv, quay, LL_MID, rim="concrete_2", fld=f, shade="none")
    for x in range(0, 480, 16):
        cv.rect(x, 112, 1, 20, "mid")
    # the bridge: a deck across the frame with two arches over the water
    deck = cv.mask_rect(0, 76, 480, 10)
    mass(cv, deck, LL_MID, rim="concrete_2")
    for k in range(2):
        cx = k * 240 + 120
        pier = cv.mask_rect(cx - 130, 86, 20, 46)
        mass(cv, pier, LL_MID, fld=f)
        arch = cv.mask_rect(cx - 110, 86, 220, 24) & ~cv.mask_ellipse(cx, 112, 104, 24)
        mass(cv, arch, LL_MID, fld=f, shade="none")
    for x in range(0, 480, 8):  # parapet balusters
        cv.rect(x, 68, 2, 8, "mid")
    cv.rect(0, 67, 480, 2, "fog_dark")
    cv.rect(0, 67, 480, 1, "concrete_2")
    for x in (60, 300):  # lamp posts on the bridge, unlit sodium heads (3 px)
        cv.rect(x, 40, 1, 27, "mid")
        cv.rect(x - 2, 38, 5, 2, "mid")
        cv.rect(x - 1, 40, 3, 1, "sodium_street")
    for bx in (160, 390):  # moored boats
        hull = cv.mask_poly([(bx, 128), (bx + 4, 134), (bx + 40, 134), (bx + 46, 126), (bx + 40, 128)])
        cv.put(hull, "mid")
        cv.rect(bx + 14, 118, 16, 10, "fog_dark")
        cv.rect(bx + 14, 118, 16, 1, "concrete_2")
        cv.rect(bx + 20, 100, 1, 18, "mid")


def street_lamp(cv, x, top, base, name, head, lit):
    cv.rect(x, top, 2, base - top, name)
    cv.rect(x, top, 9, 2, name)
    cv.rect(x + 7, top + 2, 3, 2, head)
    cv.rect(x + 7, top + 4, 3, 1, lit)


@item("ll_near_street", "lowlight/ll_near_street.png", "near", "lowlight", "ll_env", (480, 200), variants=("", "b"))
def ll_near_street(cv, sh, var, v):
    """The street face: shopfronts with shutters and awnings, stairs, pipes, lamp posts."""
    s = ITEMS["ll_near_street"]["seed"]
    f = field(s, "n", 200, 480, 12)
    base = cv.mask_rect(0, 178, 480, 22)
    mass(cv, base, LL_NEAR, rim="concrete_2", fld=f, shade="none")
    runs = seam_and_body(sh, var, 52, 96, 18, 44)
    for i, (x, w) in enumerate(runs):
        r = sh if i == 0 else var
        top = int(r.integers(30, 80))
        m = building(cv, x, top, w, 178, LL_NEAR, "concrete_2", r, fld=f, kind="flat", antenna=0.0)
        # dark upper windows (deep openings), a few warm ones
        windows_grid(cv, m & cv.mask_rect(0, 0, 480, 130), x + 4, top + 8, x + w - 4, 128, 6, 9, 5, 6,
                     ["sky_top", "far"], r, 0.7, lit_names=["window_warm", "window_rose"], lit_p=0.05)
        # shopfront: a shutter bay at street level
        sx0, sx1 = x + 4, x + w - 4
        cv.rect(sx0, 136, sx1 - sx0, 42, "far")
        for y in range(138, 176, 3):
            cv.rect(sx0 + 1, y, sx1 - sx0 - 2, 1, "concrete_0")
        # awning over the bay
        aw = cv.mask_poly([(sx0 - 3, 130), (sx1 + 3, 130), (sx1 + 6, 137), (sx0 - 6, 137)])
        mass(cv, aw, ("concrete_0", "brick_1", "concrete_2"), rim="concrete_2")
        for ax in range(sx0 - 5, sx1 + 5, 4):
            cv.rect(ax, 137, 2, 2, "brick_1")
        # a drain pipe down one side
        pipe_v(cv, x + (1 if r.random() < 0.5 else w - 4), top + 2, 178, 3, LL_NEAR)
    for k, (x, w) in enumerate(runs):  # lamp posts in some gaps
        r = sh if k == 0 else var
        if r.random() < 0.6:
            lx = x + w + 6
            street_lamp(cv, lx, 108, 178, "concrete_0", "brick_0", "sodium_street")


@item("ll_tower_near", "lowlight/ll_tower_near.png", "near", "lowlight", "ll_env", (480, 270), tile_y=True)
def ll_tower_near(cv, sh, var, v):
    """Inside the tall towers: stone piers with lit slit windows, iron stair flights and
    landings, cables and a freight-lift cage rail. Open between, so the dark reads through."""
    s = ITEMS["ll_tower_near"]["seed"]
    f = field(s, "t", 270, 480, 10, sy=3)
    for px in (0, 160, 320):
        m = cv.mask_rect(px - 14, 0, 28, 270)
        mass(cv, m, LL_NEAR, fld=f, shade="cyl", x0=px - 14, x1=px + 14)
        for y in range(0, 270, 45):  # string courses
            cv.rect(px - 16, y, 32, 3, "brick_0")
            cv.rect(px - 16, y, 32, 1, "concrete_2")
        for y in range(18, 270, 45):  # slit windows, some lit (1 x 4 px)
            cv.rect(px - 1, y, 2, 6, "sky_top")
        cv.rect(px - 1, 18 + 45 * 2, 1, 4, "window_warm")
    # stair flights between the piers: stringers and landings, periodic every 135 px
    for k, x0 in enumerate((14, 174, 334)):
        for y in (0, 135):
            yy = y + (40 if k % 2 else 100)
            cv.rect(x0, yy, 34, 3, "concrete_0")
            cv.rect(x0, yy, 34, 1, "concrete_2")
            cv.line([(x0 + 34, yy + 1), (x0 + 112, yy + 68)], "concrete_0", width=2)
            cv.line([(x0 + 34, yy), (x0 + 112, yy + 67)], "brick_1")
            for t in range(0, 78, 8):
                cv.rect(x0 + 34 + t, yy - 6 + int(t * 67 / 78), 1, 6, "concrete_0")
            cv.rect(x0 + 110, yy + 68, 36, 3, "concrete_0")
            cv.rect(x0 + 110, yy + 68, 36, 1, "concrete_2")
    # the freight lift rail: two thin rails in one bay
    cv.rect(246, 0, 1, 270, "concrete_0")
    cv.rect(262, 0, 1, 270, "concrete_0")
    for y in range(0, 270, 30):
        cv.rect(246, y, 17, 1, "concrete_0")
    for y in (60, 195):  # cables looping between piers
        cable(cv, 14, y, 146, y + 4, 18, "concrete_0")
        cable(cv, 334, y + 20, 466, y + 24, 14, "concrete_0")


@item("ll_backwall_interior", "lowlight/ll_backwall_interior.png", "backwall", "lowlight", "ll_env", (480, 270), opaque=True)
def ll_backwall_interior(cv, sh, var, v):
    """Stack interiors: plaster and brick, dark stairwell openings and doorways at body height,
    pipe runs and caged ceiling lights (unlit)."""
    s = ITEMS["ll_backwall_interior"]["seed"]
    f = field(s, "i", 270, 480, 16)
    cv.put(np.ones((270, 480), bool), "concrete_1")
    ep.mottle(cv, np.ones((270, 480), bool), "brick_1", f, 0.74)
    # exposed brick patches where the plaster fell
    br = (f < 0.3)
    cv.put(br, "brick_0")
    for y in range(0, 270, 4):
        row = br[y]
        cv.idx[y][row] = cv.ci("brick_1")
        off = 0 if (y // 4) % 2 else 4
        for x in range(off, 480, 8):
            if br[min(269, y + 2), x]:
                cv.idx[y:y + 4, x][br[y:y + 4, x]] = cv.ci("brick_1")
    cv.rect(0, 0, 480, 14, "brick_0")  # ceiling slab
    cv.rect(0, 14, 480, 2, "concrete_0")
    pipe_h(cv, 0, 480, 20, 5, LL_WALL, edge="concrete_2", flange=64)
    pipe_h(cv, 0, 480, 28, 3, LL_WALL, flange=48)
    cv.rect(0, 190, 480, 4, "brick_0")  # skirting
    cv.rect(0, 190, 480, 1, "concrete_2")
    cv.rect(0, 250, 480, 20, "brick_0")
    cv.rect(0, 250, 480, 1, "concrete_2")
    for k in range(2):  # per 240: a stairwell opening and a doorway
        x = k * 240
        # stairwell: a wide dark shaft with a flight of stairs rising inside
        cv.rect(x + 14, 44, 130, 146, "sky_top")
        cv.rect(x + 10, 40, 138, 4, "concrete_0")
        cv.rect(x + 10, 40, 138, 1, "concrete_2")
        cv.rect(x + 10, 44, 4, 146, "concrete_0")
        cv.rect(x + 144, 44, 4, 146, "concrete_0")
        for t in range(0, 120, 6):  # the upper flight, going back the other way
            cv.rect(x + 132 - t, 118 - int(t * 0.6), 6, 1, "far")
        cv.rect(x + 14, 120, 130, 2, "far")  # landing
        for t in range(0, 110, 6):
            cv.rect(x + 20 + t, 180 - int(t * 0.8), 6, 1, "far")
            cv.rect(x + 20 + t, 181 - int(t * 0.8), 1, int(t * 0.8) + 3, "sky_1")
        cv.line([(x + 18, 172), (x + 132, 81 + 9)], "far")  # handrail
        # doorway
        cv.rect(x + 170, 60, 50, 130, "sky_top")
        cv.rect(x + 166, 56, 58, 4, "concrete_0")
        cv.rect(x + 166, 56, 58, 1, "concrete_2")
        cv.rect(x + 166, 60, 4, 130, "concrete_0")
        cv.rect(x + 220, 60, 4, 130, "concrete_0")
        cv.rect(x + 174, 60, 1, 130, "far")  # the door ajar
        cv.rect(x + 170, 88, 50, 1, "far")  # transom
        # caged ceiling light (unlit), 3 px bulb
        lx = x + 160
        cv.rect(lx, 16, 1, 10, "concrete_0")
        cv.rect(lx - 3, 26, 7, 6, "concrete_0")
        cv.rect(lx - 2, 27, 5, 4, "brick_0")
        cv.rect(lx - 1, 28, 3, 1, "window_warm_far")
        for gx in (lx - 2, lx + 2):
            cv.rect(gx, 27, 1, 4, "concrete_0")
        # conduit and a fuse box
        pipe_v(cv, x + 230, 32, 190, 3, LL_WALL)
        cv.rect(x + 226, 120, 12, 16, "concrete_0")
        cv.rect(x + 227, 121, 10, 14, "brick_0")
        cv.rect(x + 227, 121, 10, 1, "concrete_2")


@item("ll_fg_set", "lowlight/ll_fg_set.png", "fg", "lowlight", "ll_env", (256, 128), tile_x=False,
      manifest="ll_fg_silhouettes")
def ll_fg_set(cv, sh, var, v):
    D, M, L, R = "sky_top", "sky_1", "far", "fog_dark"
    ps = []
    for name, h in (("antenna_tall", 72), ("antenna_short", 44)):  # antenna tops rising from below
        p = piece("ll_env", 28, h)
        p.rect(13, 6, 2, h - 6, M)
        p.rect(13, 6, 1, h - 6, R)
        for y in range(10, h - 8, 10):
            w = 12 - (y // 10) % 3 * 3
            p.rect(14 - w, y, 2 * w, 1, M)
        p.rect(12, 0, 4, 6, L)
        p.rect(12, 0, 4, 1, R)
        p.line([(14, 12), (2, h - 1)], D)
        p.line([(14, 12), (26, h - 1)], D)
        ps.append((name, p.idx, "bottom"))
    for name, w, sag in (("cable_loop_wide", 120, 40), ("cable_loop_narrow", 64, 26)):
        p = piece("ll_env", w, sag + 6)
        p.line(ep.catenary(0, 1, w - 1, 3, sag), M, width=2)
        p.line(ep.catenary(4, 1, w - 5, 2, sag * 0.6), D)
        p.rect(0, 0, 3, 3, L)
        p.rect(w - 3, 0, 3, 3, L)
        ps.append((name, p.idx, "top"))
    p = piece("ll_env", 64, 20)  # awning edge dipping into the frame
    p.poly([(0, 0), (63, 0), (63, 10), (0, 14)], M)
    p.rect(0, 0, 64, 2, L)
    for x in range(0, 64, 5):
        p.rect(x, 13 - x // 10, 3, 4, D)
    p.line([(0, 14), (63, 10)], R)
    ps.append(("awning", p.idx, "top"))
    p = piece("ll_env", 40, 26)  # a railing top with a satellite dish, rising from below
    p.rect(0, 12, 40, 14, D)
    p.rect(0, 12, 40, 1, R)
    for x in range(0, 40, 6):
        p.rect(x, 6, 1, 6, M)
    p.rect(0, 6, 40, 1, M)
    p.poly([(20, 6), (26, 0), (32, 3), (28, 8)], L)
    ps.append(("dish_railing", p.idx, "bottom"))
    meta = fg_pack(cv, ps)
    return fg_meta(meta, "ll_env", "Lowlight foreground silhouettes (antenna tops, cable loops, awning, dish railing)")


# =========================================================================== THE RELAY
RL_MID = ("mid", "stone_0", "fog_warm")             # L 10.0 / 11.1 / 14.1
RL_WALL = ("stone_0", "fog_warm", "stone_1")        # L 11.1 / 14.1 / 17.6


@item("relay_backwall", "relay/relay_backwall.png", "backwall", "relay", "relay_env", (480, 270), opaque=True)
def relay_backwall(cv, sh, var, v):
    """The station's brick arcade: three arches per 480, a bunk train car in one, cloth
    partitions in another, bulb-string hooks along the frieze. The warm dark of the
    tunnels behind is where the characters stand out."""
    s = ITEMS["relay_backwall"]["seed"]
    f = field(s, "w", 270, 480, 16)
    cv.put(np.ones((270, 480), bool), "fog_warm")
    # brick courses: light lime mortar (stone_1) every 5 rows, staggered joints
    for y in range(0, 270, 5):
        cv.rect(0, y, 480, 1, "stone_1")
        off = 0 if (y // 5) % 2 else 6
        for x in range(off, 480, 12):
            cv.rect(x, y, 1, 5, "stone_1")
    ep.mottle(cv, np.ones((270, 480), bool), "haze", f, 0.8)
    for k in range(3):
        cx = k * 160 + 80
        op = (cv.mask_ellipse(cx, 100, 64, 64) & cv.mask_rect(0, 0, 480, 101)) | cv.mask_rect(cx - 64, 100, 129, 96)
        # voussoir ring and keystone
        ring = cv.mask_ellipse(cx, 100, 70, 70) & ~cv.mask_ellipse(cx, 100, 64, 64) & cv.mask_rect(0, 0, 480, 101)
        cv.put(ring, "stone_1")
        for a in range(185, 356, 10):
            t = np.radians(a)
            cv.line([(cx + 64 * np.cos(t), 100 + 64 * np.sin(t)), (cx + 70 * np.cos(t), 100 + 70 * np.sin(t))], "fog_warm")
        cv.rect(cx - 4, 28, 9, 9, "haze")
        cv.rect(cx - 4, 28, 9, 1, "lamp_spill")
        cv.put(op, "sky_top")
        # the tunnel beyond: a faint far ring and the rails' glint
        cv.put(cv.mask_ellipse(cx, 120, 34, 34) & ~cv.mask_ellipse(cx, 120, 32, 32) & cv.mask_rect(0, 0, 480, 121), "far")
        cv.rect(cx - 34, 120, 2, 76, "far")
        cv.rect(cx + 33, 120, 2, 76, "far")
        # impost blocks
        cv.rect(cx - 72, 98, 10, 5, "stone_1")
        cv.rect(cx + 63, 98, 10, 5, "stone_1")
        cv.rect(cx - 72, 98, 10, 1, "haze")
        cv.rect(cx + 63, 98, 10, 1, "haze")
    # arch 0: the bunk train car, windows warm (someone lives here)
    cx = 80
    car = cv.mask_rect(cx - 56, 128, 112, 56) | cv.mask_rect(cx - 52, 124, 104, 4)
    cv.put(car, "far")
    cv.rect(cx - 56, 128, 112, 1, "mid")
    for wx in range(cx - 48, cx + 44, 16):
        cv.rect(wx, 136, 10, 8, "sky_top")
    cv.rect(cx - 32, 138, 4, 3, "lamp_warm")
    cv.rect(cx + 16, 137, 3, 3, "lamp_core")
    cv.rect(cx - 56, 160, 112, 1, "mid")
    # arch 1: cloth partitions on a line
    cx = 240
    cv.rect(cx - 58, 112, 117, 1, "mid")
    for k, x in enumerate(range(cx - 54, cx + 50, 14)):
        ln = 16 + (k * 17) % 20
        col = ["cloth_plum", "cloth_teal", "stone_0", "cloth_plum"][k % 4]
        cv.rect(x, 113, 11, ln, col)
        cv.rect(x + 10, 113, 1, ln, "mid")
        cv.idx[113 + ln - 1, x + 3] = cv.ci("sky_top")
    # arch 2: dark, a ladder into the tunnel (left open: depth)
    cx = 400
    cv.rect(cx + 20, 130, 1, 66, "far")
    cv.rect(cx + 28, 130, 1, 66, "far")
    for y in range(132, 196, 6):
        cv.rect(cx + 20, y, 9, 1, "far")
    # frieze with bulb-string hooks
    cv.rect(0, 12, 480, 6, "stone_1")
    cv.rect(0, 12, 480, 1, "haze")
    cv.rect(0, 18, 480, 1, "stone_0")
    for x in range(8, 480, 32):
        cv.rect(x, 19, 1, 3, "stone_0")
        cv.rect(x - 1, 21, 2, 1, "stone_0")
    # platform wall below the arches and the platform lip
    cv.rect(0, 196, 480, 4, "stone_1")
    cv.rect(0, 196, 480, 1, "haze")
    cv.rect(0, 250, 480, 20, "stone_0")
    cv.rect(0, 250, 480, 1, "stone_1")
    for x in range(0, 480, 20):
        cv.rect(x, 251, 1, 19, "mid")


@item("relay_mid_concourse", "relay/relay_mid_concourse.png", "mid", "relay", "relay_env", (480, 180), variants=("", "b"))
def relay_mid_concourse(cv, sh, var, v):
    """The concourse: iron canopy columns with brackets, a canopy line, hanging blank signs,
    a clock, and market stalls with lamps under awnings."""
    s = ITEMS["relay_mid_concourse"]["seed"]
    f = field(s, "c", 180, 480, 12)
    # canopy: a thin roof line with a valance (continuous)
    cv.rect(0, 30, 480, 5, "stone_0")
    cv.rect(0, 30, 480, 1, "lamp_spill")
    for x in range(0, 480, 6):
        cv.rect(x, 35, 3, 3, "mid")
    # columns every 96 px with ornamental brackets
    for x in range(0, 480, 96):
        cv.rect(x - 2, 35, 5, 145, "stone_0")
        cv.rect(x - 2, 35, 1, 145, "fog_warm")
        cv.line([(x + 2, 52), (x + 18, 36)], "stone_0", width=2)
        cv.line([(x - 2, 52), (x - 18, 36)], "stone_0", width=2)
        cv.put(cv.mask_ellipse(x, 44, 5, 5) & ~cv.mask_ellipse(x, 44, 3, 3), "stone_0")
        cv.rect(x - 4, 172, 9, 8, "stone_0")
    # the platform edge and floor mass at the bottom (continuous)
    base = cv.mask_rect(0, 160, 480, 20)
    mass(cv, base, RL_MID, rim="lamp_spill", fld=f, shade="none")
    runs = seam_and_body(sh, var, 36, 70, 30, 60)
    for i, (x, w) in enumerate(runs):
        r = sh if i == 0 else var
        kind = int(r.integers(0, 3))
        if kind == 0:  # a stall: counter, awning, crates, a lamp
            body = cv.mask_rect(x, 132, w, 28)
            mass(cv, body, RL_MID, rim="fog_warm", fld=f)
            aw = cv.mask_poly([(x - 3, 116), (x + w + 3, 116), (x + w + 6, 124), (x - 6, 124)])
            mass(cv, aw, ("stone_0", "cloth_plum" if r.random() < 0.5 else "cloth_teal", "fog_warm"), rim="lamp_spill")
            cv.rect(x + 2, 124, 1, 8, "stone_0")
            cv.rect(x + w - 3, 124, 1, 8, "stone_0")
            lx = x + w // 2
            cv.rect(lx, 124, 1, 3, "stone_0")
            cv.rect(lx - 1, 127, 3, 2, "lamp_core")
            cv.rect(x + 4, 148, 10, 12, "stone_0")
            cv.rect(x + 4, 148, 10, 1, "fog_warm")
        elif kind == 1:  # a hanging blank sign on two rods
            sx = x + w // 2 - 14
            cv.rect(sx + 3, 38, 1, 22, "stone_0")
            cv.rect(sx + 24, 38, 1, 22, "stone_0")
            cv.rect(sx, 60, 28, 10, "stone_0")
            cv.rect(sx, 60, 28, 1, "lamp_spill")
            cv.rect(sx + 2, 62, 24, 6, "mid")
        else:  # the station clock on a bracket
            cx = x + w // 2
            cv.rect(cx, 38, 1, 12, "stone_0")
            clock = cv.mask_ellipse(cx, 58, 8, 8)
            cv.put(clock, "stone_0")
            cv.put(cv.mask_ellipse(cx, 58, 6, 6), "mid")
            cv.rect(cx, 53, 1, 5, "fog_warm")
            cv.rect(cx, 58, 4, 1, "fog_warm")
            cv.put(top_edge(clock), "lamp_spill")
    # a footbridge truss crossing high up (continuous)
    cv.rect(0, 12, 480, 2, "stone_0")
    cv.rect(0, 22, 480, 2, "stone_0")
    for x in range(0, 480, 12):
        cv.line([(x, 14), (x + 6, 21)], "mid")
        cv.line([(x + 6, 14), (x + 12, 21)], "mid")
    cv.rect(0, 12, 480, 1, "lamp_spill")


@item("relay_fg_set", "relay/relay_fg_set.png", "fg", "relay", "relay_env", (256, 128), tile_x=False,
      manifest="relay_fg")
def relay_fg_set(cv, sh, var, v):
    D, M, L, R = "sky_top", "far", "sky_bottom", "lamp_spill"
    ps = []
    for name, n, w in (("cloth_strips_wide", 6, 56), ("cloth_strips_narrow", 3, 28)):
        p = piece("relay_env", w, 64)
        p.rect(0, 0, w, 2, M)
        p.rect(0, 0, w, 1, R)
        for k in range(n):
            x = k * (w // n) + 1
            ln = 24 + (k * 13 + w) % 38
            p.rect(x, 2, w // n - 2, ln, [D, M, L][k % 3])
            p.rect(x, 2, 1, ln, R if k % 2 else L)
            p.idx[2 + ln - 1, x + 1] = -1
        ps.append((name, p.idx, "top"))
    for name, w, sag in (("bulb_string_wide", 128, 22), ("bulb_string_narrow", 72, 14)):
        p = piece("relay_env", w, sag + 8)
        pts = ep.catenary(0, 1, w - 1, 2, sag)
        p.line(pts, M)
        for k in range(6, len(pts) - 4, 12):
            x, y = pts[k]
            p.rect(x, y + 1, 1, 2, M)
            p.rect(x - 1, y + 3, 3, 2, "lamp_warm")
            p.px(x, y + 3, "lamp_core")
        ps.append((name, p.idx, "top"))
    p = piece("relay_env", 36, 28)  # crate stack below the floor line
    p.rect(0, 10, 20, 18, D)
    p.rect(18, 0, 18, 28, M)
    p.rect(0, 10, 20, 1, R)
    p.rect(18, 0, 18, 1, R)
    p.line([(19, 1), (35, 27)], D)
    p.line([(1, 11), (19, 27)], M)
    ps.append(("crates", p.idx, "bottom"))
    meta = fg_pack(cv, ps)
    return fg_meta(meta, "relay_env", "Relay foreground silhouettes (cloth strips, bulb strings, crates)")


# =========================================================================== DEEP RIG / PULSE PIT
@item("null_far_strata", "null/null_far_strata.png", "far", "null", "null_env", (480, 200))
def null_far_strata(cv, sh, var, v):
    """Deep Rig far layer: grey rock strata stepping down in faulted ledges. No warm light."""
    s = ITEMS["null_far_strata"]["seed"]
    f = ep.noise(200, 480, 20, s, 2, 1)
    # skyline profile: stepped ledges (periodic)
    prof = np.zeros(480, int)
    x = -20  # the first ledge straddles the seam, so the profile wraps without a step
    first = int(sh.integers(40, 110))
    while x < 460:
        w = int(sh.integers(24, 70))
        h = first if x < 0 else int(sh.integers(40, 110))
        for xx in range(x, min(x + w, 460)):
            prof[xx % 480] = h
        x += w
    prof[460:] = first
    prof = np.minimum(prof, 150)
    for x in range(480):
        cv.idx[200 - prof[x]:, x] = cv.ci("mid")
    Y = np.arange(200)[:, None]
    op = cv.opaque
    # strata: tilted bands of far / mid / sky_bottom
    tilt = np.round(6 * np.sin(np.arange(480) * 2 * np.pi / 240)).astype(int)[None, :]
    band = ((Y + tilt + (f * 10).astype(int)) // 9) % 4
    cv.idx[op & (band == 1)] = cv.ci("far")
    cv.idx[op & (band == 3)] = cv.ci("sky_bottom")
    # scribed grid lines, fault cracks and a lit top rim
    for y in range(0, 200, 16):
        row = op[y] & (np.arange(480) % 3 != 0)
        cv.idx[y][row] = cv.ci("grid_0")
    cv.put(top_edge(op), "grid_0")
    for k in range(10):
        x0 = int(sh.integers(0, 480))
        y0 = 200 - int(prof[x0]) + 2
        cv.line([(x0, y0), (x0 + int(sh.integers(-12, 12)), 199)], "void")
    cv.rect(0, 186, 480, 14, "sky_bottom")


@item("pit_rig_near", "challenge/pit_rig_near.png", "near", "lowlight", "ll_env", (480, 200))
def pit_rig_near(cv, sh, var, v):
    """Pulse Pit rig: two lattice lamp towers per 480 with unlit lamp racks, a scaffold deck,
    a barrier wall and sagging power cables."""
    for tx in (80, 320):
        lattice_mast(cv, tx - 6, 30, 180, 12, "metal_0", rim="metal_1")
        lattice_mast(cv, tx - 5, 30, 180, 10, "metal_0")
        # lamp rack: three housings, dark glass (unlit: code flicks them on in waves)
        cv.rect(tx - 20, 20, 40, 3, "metal_0")
        cv.rect(tx - 20, 20, 40, 1, "metal_1")
        for k in range(3):
            lx = tx - 18 + k * 13
            cv.rect(lx, 10, 10, 10, "metal_0")
            cv.rect(lx, 10, 10, 1, "metal_1")
            cv.rect(lx + 2, 12, 6, 6, "puddle_0")
            cv.rect(lx + 2, 12, 2, 1, "metal_1")
        cv.rect(tx - 1, 0, 2, 10, "metal_0")
        # the scaffold deck around the tower's waist
        cv.rect(tx - 34, 110, 68, 3, "metal_0")
        cv.rect(tx - 34, 110, 68, 1, "metal_1")
        for x in range(tx - 34, tx + 35, 8):
            cv.rect(x, 102, 1, 8, "metal_0")
        cv.rect(tx - 34, 102, 68, 1, "metal_0")
    for y0 in (40, 60):  # power cables between the towers (periodic)
        cable(cv, 86, y0, 314, y0 + 4, 26, "concrete_0")
        cable(cv, 326, y0 + 4, 554, y0, 26, "concrete_0")
    wall = cv.mask_rect(0, 170, 480, 30)  # barrier wall
    paint_mat(cv, wall, ("concrete_0", "metal_0", "metal_1"), shade="none")
    cv.rect(0, 170, 480, 1, "metal_1")
    for x in range(0, 480, 24):
        cv.rect(x, 171, 1, 29, "concrete_0")
        cv.rect(x + 10, 180, 4, 3, "concrete_0")


# =========================================================================== TITLE
TT_FAR = ("sky_1", "far", "mid")
TT_MID = ("near", "mid", "cloud_0")
TT_NEAR = ("mid", "cloud_0", "cloud_1")
TT_WIN = ["window_warm_far", "window_cold", "window_rose"]


@item("title_far_spires", "title/title_far_spires.png", "far", "title", "title", (480, 160))
def title_far_spires(cv, sh, var, v):
    """Veyra far away: impossibly tall stacked towers, sky-bridges and cables, sparse windows."""
    tops = ll_skyline(cv, sh, sh, 160, TT_FAR, "cloud_0", (8, 70), ["sky_1"], TT_WIN, 0.05, 14, 36, 0, 10,
                      spire_p=0.5, cw=1, ch=3, gx=3, gy=5)
    # the central spire, slightly off-centre, rising to the top edge
    cx = 210
    cv.poly([(cx - 8, 160), (cx - 5, 18), (cx, 0), (cx + 5, 18), (cx + 8, 160)], "far")
    cv.line([(cx - 5, 18), (cx, 0)], "mid")
    cv.rect(cx - 6, 40, 12, 2, "mid")
    cv.rect(cx - 7, 70, 14, 2, "mid")
    cv.rect(cx - 1, 90, 1, 3, "window_cold")
    for y in range(146, 160):
        cv.rect(0, y, 480, 1, "far" if y % 3 else "sky_1")


@item("title_mid_rooftops", "title/title_mid_rooftops.png", "mid", "title", "title", (480, 150))
def title_mid_rooftops(cv, sh, var, v):
    """Wet rooftops, tanks and antennas with a dead elevated rail crossing the frame."""
    s = ITEMS["title_mid_rooftops"]["seed"]
    f = field(s, "t", 150, 480, 12)
    runs = slots(sh, 0, 480, 34, 70, 4, 16)
    for x, w in runs:
        top = int(sh.integers(66, 110))
        building(cv, x, top, w, 150, TT_MID, "rim", sh, fld=f, win=["near"], lit=TT_WIN, lit_p=0.06,
                 win_density=0.45, cw=2, ch=3, gx=4, gy=5, antenna=0.4)
        if sh.random() < 0.4:
            tx = x + int(sh.integers(0, max(1, w - 14)))
            tank(cv, tx, top - 28, 14, top - 10, TT_MID, "rim")
            trestle(cv, tx + 1, top - 10, 12, 10, "near", "mid")
    # the elevated rail viaduct: a deck with a truss and piers every 120 px
    cv.rect(0, 56, 480, 5, "mid")
    cv.rect(0, 56, 480, 1, "rim")
    cv.rect(0, 61, 480, 1, "near")
    for x in range(0, 480, 10):
        cv.line([(x, 61), (x + 5, 68)], "near")
        cv.line([(x + 5, 68), (x + 10, 61)], "near")
    cv.rect(0, 68, 480, 1, "near")
    for x in range(40, 480, 120):
        cv.rect(x, 69, 6, 81, "mid")
        cv.rect(x, 69, 1, 81, "cloud_0")
        cv.rect(x - 3, 69, 12, 2, "mid")
    for y in range(136, 150):
        cv.idx[y][cv.idx[y] >= 0] = cv.ci("near" if y % 2 else "mid")


TITLE_STAND_Y = 44


@item("title_near_ledge", "title/title_near_ledge.png", "near", "title", "title", (200, 120), tile_x=False)
def title_near_ledge(cv, sh, var, v):
    """The ledge Rook stands on (right third of the title): a parapet corner with a broken
    railing, a vent box and an antenna, the building face falling away below."""
    s = ITEMS["title_near_ledge"]["seed"]
    f = field(s, "l", 120, 200, 10)
    y = TITLE_STAND_Y
    face = cv.mask_poly([(18, y), (199, y), (199, 119), (10, 119), (14, 80)])
    mass(cv, face, TT_NEAR, rim="rim", fld=f, lo=0.3, hi=0.82)
    cv.rect(16, y, 184, 4, "cloud_0")        # coping stone
    cv.rect(16, y, 184, 1, "rim")
    cv.rect(16, y + 4, 184, 1, "mid")
    windows_grid(cv, face & cv.mask_rect(0, y + 14, 200, 120), 30, y + 16, 196, 118, 6, 9, 8, 7,
                 ["near", "mid"], sh, 0.7, lit_names=["window_warm"], lit_p=0.08)
    # broken railing (behind the stand point, low) and a vent box, an antenna at the right
    for x in range(120, 200, 10):
        cv.rect(x, y - 9, 1, 9, "mid")
    cv.line([(120, y - 9), (170, y - 9), (184, y - 4)], "mid")
    cv.rect(150, y - 14, 18, 14, "mid")
    cv.rect(150, y - 14, 18, 1, "cloud_0")
    for gy in range(y - 11, y - 1, 3):
        cv.rect(152, gy, 14, 1, "near")
    lattice_mast(cv, 186, 0, y, 4, "mid", rim="cloud_0")
    cv.rect(186, 0, 4, 1, "rim")
    return {"stand_y": y, "stand_x": [24, 140], "note": "Rook's feet sit on row stand_y (the coping top) between stand_x"}


# =========================================================================== TILESETS
def _swatch(pal, seed, painter):
    cv = Canvas(128, 128, pal)
    rng = np.random.default_rng(seed)
    painter(cv, rng)
    return cv


def sw_uc(cv, rng):
    """Undercity concrete: running-bond slabs 32 x 16, lit upper-left chips, algae and rust."""
    cv.put(np.ones((128, 128), bool), "concrete_2")
    for y in range(0, 128, 16):
        cv.rect(0, y, 128, 1, "concrete_1")
        off = 0 if (y // 16) % 2 else 16
        for x in range(off, 128, 32):
            cv.rect(x, y, 1, 16, "concrete_1")
            cv.rect(x + 1, y + 1, 6, 1, "concrete_3")
            cv.rect(x + 1, y + 1, 1, 3, "concrete_3")
    f = ep.noise(128, 128, 16, 11, 2, 1)
    ep.mottle(cv, cv.opaque & (cv.idx == cv.ci("concrete_2")), "concrete_1", f, 0.0, 0.2)
    for k in range(10):
        x, y = int(rng.integers(0, 126)), int(rng.integers(0, 8)) * 16 + 12
        cv.rect(x, y, 3, 3, "algae_0")
    for k in range(4):
        x, y = int(rng.integers(0, 127)), int(rng.integers(0, 8)) * 16 + 2
        cv.rect(x, y, 1, 4, "rust_1")


def sw_ll(cv, rng):
    """Lowlight brick: 8 x 4 bricks in concrete mortar, a few dark and lit bricks."""
    cv.put(np.ones((128, 128), bool), "brick_2")
    for y in range(0, 128, 4):
        cv.rect(0, y, 128, 1, "concrete_2")
        off = 0 if (y // 4) % 2 else 4
        for x in range(off, 128, 8):
            cv.rect(x, y, 1, 4, "concrete_2")
            r = rng.random()
            if r < 0.1:
                cv.rect(x + 1, y + 1, 7, 3, "brick_1")
            elif r < 0.2:
                cv.rect(x + 1, y + 1, 3, 1, "concrete_3")


def sw_relay(cv, rng):
    """Relay platform boards: horizontal planks 5 px, end joints, nail heads and grain."""
    cv.put(np.ones((128, 128), bool), "wood_1")
    for y in range(0, 128, 5):
        cv.rect(0, y, 128, 1, "wood_0")
        off = int(rng.integers(0, 64))
        for x in (off, off + 64):
            cv.rect(x % 128, y, 1, 5, "wood_0")
            cv.px((x + 2) % 128, y + 2, "wood_2")
    for k in range(40):
        x, y = int(rng.integers(0, 120)), int(rng.integers(0, 128))
        if cv.idx[y, x] == cv.ci("wood_1"):
            cv.rect(x, y, int(rng.integers(3, 8)), 1, "wood_0" if k % 3 else "wood_2")


TILESETS = {
    "uc_tiles": dict(pal="uc_env", ramp=["concrete_1", "concrete_2", "concrete_3"], edge="edge", under="void",
                     out="undercity/uc_tiles.png", painter=sw_uc, district="undercity"),
    # edge: ll "oneway" (#577380, L* 46.8), the theme edge's blue-grey family; ll "edge" itself is L* 44.7
    "ll_tiles": dict(pal="ll_env", ramp=["concrete_2", "brick_2", "concrete_3"], edge="oneway", under="sky_top",
                     out="lowlight/ll_tiles.png", painter=sw_ll, district="lowlight"),
    "relay_tiles": dict(pal="relay_env", ramp=["wood_0", "wood_1", "wood_2"], edge="edge", under="sky_top",
                        out="relay/relay_tiles.png", painter=sw_relay, district="relay"),
}
for _tid, _t in TILESETS.items():
    item(_tid, _t["out"], "tiles", _t["district"], _t["pal"], (128, 96), tile_x=False)(_t["painter"])


def build_tiles(iid, out_root):
    """Paint the 128 px swatch and cut it with env_process.build_atlas (the tiles_null.py layout)."""
    t = TILESETS[iid]
    cv = _swatch(t["pal"], ITEMS[iid]["seed"], t["painter"])
    sw = cv.rgb[cv.idx]
    env = dict(os.environ)
    if os.path.abspath(out_root) != os.path.abspath(REPO_ASSETS):
        env["ASSETGEN_OUT"] = out_root
    else:
        env.pop("ASSETGEN_OUT", None)
    env.setdefault("ASSETGEN_PREVIEW", os.path.join(tempfile.gettempdir(), "paint_env_preview"))
    tmp = os.path.join(tempfile.mkdtemp(prefix="swatch_"), iid + ".npy")
    np.save(tmp, sw)
    code = ("import sys, json, numpy as np; sys.path.insert(0, %r); import env_process as e; "
            "n, p = e.palette(%r); sw = np.load(%r); "
            "print(e.build_atlas(n, p, sw, dict(pal=%r, ramp=%r, edge=%r, under=%r, out=%r)))"
            % (HERE, t["pal"], tmp, t["pal"], t["ramp"], t["edge"], t["under"], t["out"]))
    subprocess.run([sys.executable, "-B", "-c", code], env=env, check=True, capture_output=True, cwd=REDLINE)
    shutil.rmtree(os.path.dirname(tmp), ignore_errors=True)
    return [t["out"], t["out"][:-4] + ".json"]


# =========================================================================== CRITTERS
CRIT_CELL = 16
CRIT_ORIGIN = (8, 15)
CRIT_ROWS = [  # name, frames, fps, loop
    ("moth_flutter", 4, 12, True), ("rat_idle", 2, 6, True), ("rat_run", 4, 14, True),
    ("gull_idle", 2, 4, True), ("gull_peck", 3, 10, False), ("gull_fly", 4, 12, True),
    ("eel_ripple", 6, 10, False),
]
ITEMS_CRIT = "life_critters"


def _moth(c, f, ox, oy):
    body, wing, tip = "concrete_1", "concrete_2", "concrete_3"
    y = oy + 9 + (1 if f in (1, 3) else 0)
    c.rect(ox + 7, y, 2, 3, body)
    span = [(3, -2), (4, 0), (3, 2), (4, 0)][f]
    w, lift = span
    for s in (-1, 1):
        x0 = ox + (6 if s < 0 else 9)
        for k in range(w):
            xx = x0 + s * k
            yy = y + (lift * (k + 1)) // 3
            c.px(xx, yy, wing)
            c.px(xx, yy + 1, wing)
        c.px(x0 + s * (w - 1), y + (lift * w) // 3, tip)


def _rat(c, f, ox, oy, run=False):
    body, back, tail = "brick_0", "brick_1", "concrete_1"
    stretch = [0, 2, 0, -1][f] if run else 0
    y = oy + 12 - (1 if run and f == 1 else 0)
    x0 = ox + 3
    c.rect(x0, y, 8 + stretch, 3, body)
    c.rect(x0 + 1, y - 1, 6 + stretch, 1, back)
    c.rect(x0 + 8 + stretch, y, 3, 2, body)          # head
    c.px(x0 + 9 + stretch, y - 1, back)               # ear
    c.px(x0 + 11 + stretch, y + (1 if (not run and f == 1) else 0), body)  # snout (sniff on idle f1)
    c.rect(x0 - 3, y + 1, 3, 1, tail)                  # tail
    c.px(x0 - 4, y + (0 if f % 2 else 2), tail)
    legs = [(1, 6), (3, 5), (1, 6), (0, 7)][f] if run else (1, 6)
    for lx in legs:
        c.px(x0 + lx + (stretch if lx > 4 else 0), y + 3, body)


def _gull(c, f, ox, oy, mode):
    body, wing, head, beak, leg = "concrete_2", "metal_1", "concrete_3", "sodium_spill", "concrete_1"
    if mode == "fly":
        y = oy + 8
        c.rect(ox + 4, y, 8, 2, body)
        c.rect(ox + 11, y - 1, 2, 2, head)
        c.px(ox + 13, y - 1, beak)
        c.px(ox + 3, y, wing)
        lift = [-3, -1, 2, -1][f]
        for s in (0, 1):
            for k in range(5):
                xx = ox + 5 + k + s
                c.px(xx, y + (lift * (5 - k)) // 5 - (1 if s == 0 else 0), wing)
        return
    y = oy + 9
    c.rect(ox + 5, y, 6, 4, body)
    c.rect(ox + 4, y + 1, 5, 2, wing)
    c.px(ox + 3, y + 2, wing)
    hy = y - 2 if mode == "idle" else y + [0, 2, 3][f]
    hx = ox + 10 + (0 if mode == "idle" else 1)
    if mode == "idle" and f == 1:
        hy -= 1
    c.rect(hx, hy, 2, 2, head)
    c.px(hx + 2, hy + 1, beak)
    c.rect(ox + 7, y + 4, 1, 2, leg)
    c.rect(ox + 9, y + 4, 1, 2, leg)


def _eel(c, f, ox, oy):
    """A wake: a hump crossing the water surface, rings trailing (16 x 8 used area)."""
    y = oy + 12
    hx = ox + 2 + f * 2
    c.rect(ox, y + 1, 16, 1, "puddle_0")
    c.rect(hx, y, 3, 1, "puddle_1")
    c.px(hx + 1, y - 1, "puddle_1")
    for k in range(1, 4):
        tx = hx - 3 * k
        if tx >= ox:
            c.rect(tx, y + (k % 2), 2, 1, "puddle_1")
    if f in (2, 3):
        c.px(hx + 1, y - 1, "wet_hi")


def paint_critters():
    cols = max(r[1] for r in CRIT_ROWS)
    cv = Canvas(cols * CRIT_CELL, len(CRIT_ROWS) * CRIT_CELL, "ll_env", wrap_x=False)
    for ri, (name, n, fps, loop) in enumerate(CRIT_ROWS):
        for f in range(n):
            ox, oy = f * CRIT_CELL, ri * CRIT_CELL
            if name == "moth_flutter":
                _moth(cv, f, ox, oy)
            elif name == "rat_idle":
                _rat(cv, f, ox, oy)
            elif name == "rat_run":
                _rat(cv, f, ox, oy, run=True)
            elif name == "gull_idle":
                _gull(cv, f, ox, oy, "idle")
            elif name == "gull_peck":
                _gull(cv, f, ox, oy, "peck")
            elif name == "gull_fly":
                _gull(cv, f, ox, oy, "fly")
            else:
                _eel(cv, f, ox, oy)
    return cv


item("life_critters", "props/life_critters.png", "critters", "all", "ll_env", (96, 112), tile_x=False)(
    lambda cv, sh, var, v: None)


def critters_tres():
    subs, refs = [], []
    for i, (name, n, fps, loop) in enumerate(CRIT_ROWS):
        subs.append('[sub_resource type="Resource" id="a%d"]\nscript = ExtResource("2_anim")\nname = &"%s"\nrow = %d\n'
                    'first_frame = 0\nframe_count = %d\nfps = %.1f\nloop = %s\n' % (i, name, i, n, fps, "true" if loop else "false"))
        refs.append('SubResource("a%d")' % i)
    return ('[gd_resource type="Resource" script_class="SpriteSheetSpec" load_steps=%d format=3]\n\n'
            '[ext_resource type="Script" path="res://vfx/SpriteSheetSpec.gd" id="1_spec"]\n'
            '[ext_resource type="Script" path="res://vfx/SpriteAnim.gd" id="2_anim"]\n\n' % (len(CRIT_ROWS) + 3)
            + "\n".join(subs) +
            '\n[resource]\nscript = ExtResource("1_spec")\ntexture_path = "res://assets/props/life_critters.png"\n'
            'cell_size = Vector2i(%d, %d)\norigin = Vector2i(%d, %d)\nanimations = Array[ExtResource("2_anim")]([%s])\n'
            % (CRIT_CELL, CRIT_CELL, CRIT_ORIGIN[0], CRIT_ORIGIN[1], ", ".join(refs)))


def build_critters(iid, out_root):
    cv = paint_critters()
    p = os.path.join(out_root, ITEMS[iid]["out"])
    ep.save_png(cv.image(), p)
    with open(p[:-4] + ".tres", "w") as fh:
        fh.write(critters_tres())
    meta = {"id": "life_critters", "texture": "res://assets/props/life_critters.png", "cell": [CRIT_CELL, CRIT_CELL],
            "origin": list(CRIT_ORIGIN),
            "rows": [{"name": n, "row": i, "frames": k, "fps": fps, "loop": lp} for i, (n, k, fps, lp) in enumerate(CRIT_ROWS)],
            "palette": "ll_env", "facing": "+x (flip_h for facing -1)",
            "notes": "Ambient life, visual only. No dark outline and a value at or below the playfield face, "
                     "so critters never read as small enemies. eel_ripple uses the lower 16x8 of its cell."}
    with open(p[:-4] + ".json", "w") as fh:
        json.dump(meta, fh, indent=1, sort_keys=True)
        fh.write("\n")
    rel = ITEMS[iid]["out"]
    return [rel, rel[:-4] + ".tres", rel[:-4] + ".json"]
# =========================================================================== build
def painted(iid):
    """False when an AI raw exists for the item's manifest id (env_process owns the file then)."""
    it = ITEMS[iid]
    for ext in (".png", ".webp", ".jpg"):
        if os.path.exists(os.path.join(RAW, it["manifest"] + ext)):
            return False
    return True


def paint(iid, v=""):
    it = ITEMS[iid]
    w, h = it["size"]
    cv = Canvas(w, h, it["pal"], wrap_x=it["tile_x"], wrap_y=it["tile_y"])
    sh, var = rngs(it, v)
    meta = it["fn"](cv, sh, var, v)
    if it["kind"] in ("far", "mid", "near", "backwall"):
        ep.accent_cleanup(cv)
    return cv, meta


def outputs(iid):
    """Every file an item writes (relative to assets/)."""
    it = ITEMS[iid]
    if it["kind"] == "tiles":
        return [it["out"], it["out"][:-4] + ".json"]
    if it["kind"] == "critters":
        return [it["out"], it["out"][:-4] + ".tres", it["out"][:-4] + ".json"]
    outs = [variant_path(it, v) for v in it["variants"]]
    if it["kind"] == "fg" or iid == "title_near_ledge":
        outs.append(it["out"][:-4] + ".json")
    return outs


def pngs(iid):
    return [o for o in outputs(iid) if o.endswith(".png")]


def build_item(iid, out_root):
    it = ITEMS[iid]
    if it["kind"] == "tiles":
        return build_tiles(iid, out_root)
    if it["kind"] == "critters":
        return build_critters(iid, out_root)
    written = []
    for v in it["variants"]:
        cv, meta = paint(iid, v)
        rel = variant_path(it, v)
        p = os.path.join(out_root, rel)
        ep.save_png(cv.image(opaque=it["opaque"]), p)
        written.append(rel)
        if meta:
            with open(p[:-4] + ".json", "w") as f:
                json.dump(meta, f, indent=1, sort_keys=True)
                f.write("\n")
            written.append(rel[:-4] + ".json")
    return written


def build(ids, out_root):
    out = []
    for iid in ids:
        if painted(iid):
            out += build_item(iid, out_root)
    return out


# =========================================================================== check
# file contract (T03 codes against these names); sizes are maxima
CONTRACT = {
    "undercity/uc_sky_vault.png": (480, 270), "undercity/uc_mid_pipeworks.png": (480, 180),
    "undercity/uc_near_columns.png": (480, 220), "undercity/uc_backwall_ward.png": (480, 270),
    "undercity/uc_shaft_near.png": (480, 270), "undercity/uc_tunnel_mid.png": (480, 160),
    "undercity/uc_boss_bay.png": (480, 270), "lowlight/ll_sky_night.png": (480, 270),
    "lowlight/ll_sky_storm.png": (480, 270), "lowlight/ll_far_skyline.png": (480, 160),
    "lowlight/ll_far_bell_tower.png": (64, 160), "lowlight/ll_mid_blocks.png": (480, 190),
    "lowlight/ll_mid_roofs.png": (480, 150), "lowlight/ll_canal_mid.png": (480, 150),
    "lowlight/ll_near_street.png": (480, 200), "lowlight/ll_tower_near.png": (480, 270),
    "lowlight/ll_backwall_interior.png": (480, 270), "lowlight/ll_train_far.png": (160, 16),
    "relay/relay_backwall.png": (480, 270), "relay/relay_mid_concourse.png": (480, 180),
    "null/null_far_strata.png": (480, 200), "challenge/pit_rig_near.png": (480, 200),
    "title/title_far_spires.png": (480, 160), "title/title_mid_rooftops.png": (480, 150),
    "title/title_near_ledge.png": (200, 120), "undercity/uc_tiles.png": (128, 96),
    "lowlight/ll_tiles.png": (128, 96), "relay/relay_tiles.png": (128, 96),
    "props/life_critters.png": (96, 112),
}
LADDER = {"sky": (2, 10), "far": (6, 12), "mid": (10, 18), "near": (14, 24), "backwall": (16, 26), "fg": (2, 6)}
CAP = {"near": 16, "backwall": 16}
TOL = 3
STEP = 6            # one value step in L*
FACE = (24, 30)
EDGE = (45, 55)
CONTRAST = 12
FEET_Y = (130, 153, 176)
STAMP_DX = 8
PLANE_KINDS = ("sky", "far", "mid", "near", "backwall")
NOT_BACKDROPS = {"ll_far_bell_tower", "ll_train_far"}  # landmark / train sprites on the far layer
DISTRICT_SKY = {"undercity": "undercity/uc_sky_vault.png", "lowlight": "lowlight/ll_sky_night.png",
                "title": "title/title_sky.png"}
DISTRICT_GRAD = {"relay": ("relay_env", "sky_top", "sky_bottom"), "null": ("null_env", "void", "sky_bottom")}
DISTRICT_TILES = {"undercity": "undercity/uc_tiles.png", "lowlight": "lowlight/ll_tiles.png",
                  "relay": "relay/relay_tiles.png", "null": "null/null_tiles.png"}
# AI planes this script does not paint: measured, reported, never failed here
FOREIGN = {"undercity/uc_far.png": ("far", "undercity"), "title/title_sky.png": ("sky", "title")}
CHAR_GLOBS = ("rook/*_sheet.tres", "enemies/*_sheet.tres", "bosses/*_sheet.tres", "npcs/*_sheet.tres",
              "lowlight/sweeper_sheet.tres")


def load_rgba(p):
    return np.asarray(Image.open(p).convert("RGBA"))


def Lmap(a):
    return ep.srgb_to_L(a[..., :3].astype(float))


def pal_rgb(pal):
    return {ep.hex2rgb(h) for h in ep.PAL["palettes"][pal]["colors"].values()}


def characters():
    out = []
    for g in CHAR_GLOBS:
        for t in sorted(glob.glob(os.path.join(REPO_ASSETS, g))):
            s = open(t).read()
            tex = re.search(r'texture_path = "res://(.*?)"', s).group(1)
            cell = [int(v) for v in re.search(r"cell_size = Vector2i\((\d+), (\d+)\)", s).groups()]
            org = [int(v) for v in re.search(r"^origin = Vector2i\((\d+), (\d+)\)", s, re.M).groups()]
            anims = re.findall(r'name = &"(\w+)"\nrow = (\d+)\nfirst_frame = (\d+)', s)
            a = [x for x in anims if x[0] == "idle"] or anims[:1]
            row, ff = int(a[0][1]), int(a[0][2])
            img = load_rgba(os.path.join(REDLINE, tex))
            fr = img[row * cell[1]:(row + 1) * cell[1], ff * cell[0]:(ff + 1) * cell[0]]
            op = fr[..., 3] > 0
            dy, dx = np.nonzero(op)
            out.append(dict(name=os.path.basename(t)[:-11], anim=a[0][0], med=float(np.median(Lmap(fr)[op])),
                            dy=dy - org[1], dx=dx - org[0]))
    return out


def district_backdrop(district, w, root):
    """The 270-row district sky behind a plane (RGB), cropped / tiled to width w."""
    if district in DISTRICT_SKY:
        p = os.path.join(root if os.path.exists(os.path.join(root, DISTRICT_SKY[district])) else REPO_ASSETS,
                         DISTRICT_SKY[district])
        sky = load_rgba(p)[..., :3]
        reps = -(-w // sky.shape[1])
        return np.tile(sky, (1, reps, 1))[:, :w]
    pal, a, b = DISTRICT_GRAD[district]
    ca = np.array(ep.hex2rgb(ep.PAL["palettes"][pal]["colors"][a]), float)
    cb = np.array(ep.hex2rgb(ep.PAL["palettes"][pal]["colors"][b]), float)
    t = (np.arange(270) / 269.0)[:, None, None]
    return np.broadcast_to(ca * (1 - t) + cb * t, (270, w, 3)).astype(np.uint8)


def composite_L(plane, district, kind, root):
    """L* of the plane over its district sky on a 270-row screen (bottom-anchored)."""
    h, w = plane.shape[:2]
    if kind == "sky":
        return Lmap(plane)
    scr = district_backdrop(district, w, root).astype(float).copy()
    y0 = 270 - h
    op = plane[..., 3] > 0
    reg = scr[y0:y0 + h]
    reg[op] = plane[..., :3][op]
    scr[y0:y0 + h] = reg
    return Lmap(scr)


def band_median(Lc, ch, wrap_x, tile_y):
    H, W = Lc.shape
    feet = list(range(0, H, 16)) if tile_y else list(FEET_Y)
    xs = np.arange(0, W, STAMP_DX)
    sx = np.repeat(xs, len(feet))
    sy = np.tile(feet, len(xs))
    X = sx[:, None] + ch["dx"][None, :]
    Y = sy[:, None] + ch["dy"][None, :]
    if wrap_x:
        X %= W
    if tile_y:
        Y %= H
    ok = (X >= 0) & (X < W) & (Y >= 0) & (Y < H)
    return float(np.median(Lc[Y[ok], X[ok]]))


def seam_problems(name, imgs, axis):
    """imgs: list of RGBA variants. The step across every A|A, A|B, B|A, B|B seam must be no
    harsher than the 99th percentile of the interior column (row) steps."""
    def prof(a):
        L = Lmap(a)
        L[a[..., 3] == 0] = -20.0
        return L if axis == 1 else L.T
    Ls = [prof(a) for a in imgs]
    inner = np.concatenate([np.abs(np.diff(L, axis=1)).mean(0) for L in Ls])
    lim = max(float(np.percentile(inner, 99)), 1.0)
    out = []
    for i, A in enumerate(Ls):
        for j, B in enumerate(Ls):
            seam = float(np.abs(A[:, -1] - B[:, 0]).mean())
            if seam > lim + 1e-6:
                out.append("%s: %s seam %s|%s steps %.2f L* (interior p99 %.2f)" %
                           (name, "x" if axis == 1 else "y", "AB"[i], "AB"[j], seam, lim))
    return out


def face_stats(tiles_png):
    a = load_rgba(tiles_png)
    meta = json.load(open(tiles_png[:-4] + ".json"))
    T, cols = meta["tile"], meta["cols"]
    face, edge = [], []
    for k, n in enumerate(meta["names"]):
        y, x = (k // cols) * T, (k % cols) * T
        t = a[y:y + T, x:x + T]
        if n.startswith(("fill_", "face_")):
            face.append(Lmap(t)[t[..., 3] > 0])
        if n.startswith("top_"):
            edge.append(Lmap(t[:1])[t[:1, :, 3] > 0])
    return float(np.median(np.concatenate(face))), float(np.median(np.concatenate(edge)))


def critter_problems(png, face_min):
    out = []
    a = load_rgba(png)
    op = a[..., 3] > 0
    L = Lmap(a)
    med = float(np.median(L[op]))
    if med > face_min + 1e-6:
        out.append("critters: median L* %.1f is above the lowest playfield face %.1f" % (med, face_min))
    C = CRIT_CELL
    for ri, (name, n, fps, loop) in enumerate(CRIT_ROWS):
        for f in range(n):
            c = op[ri * C:(ri + 1) * C, f * C:(f + 1) * C]
            l = L[ri * C:(ri + 1) * C, f * C:(f + 1) * C]
            if not c.any():
                out.append("critters: %s frame %d is empty" % (name, f))
                continue
            p = np.pad(c, 1)
            inner = c & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
            edge = c & ~inner
            ref = float(np.median(l[inner])) if inner.sum() >= 3 else float(np.median(l[c]))
            dark = (l[edge] < ref - STEP).mean()
            if dark > 0.34:
                out.append("critters: %s frame %d has a dark outline (%.0f %% of its edge is > 1 step darker "
                           "than its body)" % (name, f, dark * 100))
    return out, med


def rebuild_into(tmp):
    env = dict(os.environ, ASSETGEN_OUT=tmp, ASSETGEN_PREVIEW=os.path.join(tmp, "_preview"))
    p = subprocess.run([sys.executable, "-B", os.path.join(HERE, "paint_env.py")], env=env, cwd=REDLINE,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def check(verbose=True):
    problems, info = [], []
    # 1. determinism: two rebuilds, identical to each other and to the repo
    with tempfile.TemporaryDirectory(prefix="paint_env_a_") as ta, tempfile.TemporaryDirectory(prefix="paint_env_b_") as tb:
        for t in (ta, tb):
            code, out = rebuild_into(t)
            if code:
                problems.append("rebuild failed:\n" + out[-2000:])
                return report(problems, info)
        n = 0
        for dp, dns, fs in os.walk(ta):
            dns[:] = [d for d in dns if d != "_preview"]
            for f in fs:
                rel = os.path.relpath(os.path.join(dp, f), ta)
                n += 1
                if not filecmp.cmp(os.path.join(ta, rel), os.path.join(tb, rel), shallow=False):
                    problems.append("not deterministic: %s differs between two rebuilds" % rel)
                repo = os.path.join(REDLINE, "art", "source", os.path.relpath(rel, "_source")) \
                    if rel.startswith("_source") else os.path.join(REPO_ASSETS, rel)
                if not os.path.exists(repo):
                    problems.append("missing: %s is built but not committed" % os.path.relpath(repo, REDLINE))
                elif not filecmp.cmp(os.path.join(ta, rel), repo, shallow=False):
                    problems.append("drift: %s differs from its rebuild" % os.path.relpath(repo, REDLINE))
        info.append("rebuilt %d files twice, byte-compared" % n)
    chars = characters()
    info.append("characters: " + ", ".join("%s %.1f" % (c["name"], c["med"]) for c in chars))
    faces = {}
    for d, t in DISTRICT_TILES.items():
        p = os.path.join(REPO_ASSETS, t)
        if os.path.exists(p):
            faces[d] = face_stats(p)
    for d, (fm, em) in faces.items():
        info.append("playfield %s: face median %.1f, edge %.1f" % (d, fm, em))
        if d != "null" and not (FACE[0] <= fm <= FACE[1]):
            problems.append("playfield %s: face median L* %.1f outside %s" % (d, fm, FACE))
        if d != "null" and not (EDGE[0] <= em <= EDGE[1]):
            problems.append("playfield %s: edge L* %.1f outside %s" % (d, em, EDGE))
    # 2-6 per plane
    for iid, it in ITEMS.items():
        if not painted(iid):
            info.append("%s: AI raw present, env_process owns it (not painted)" % iid)
            continue
        imgs = []
        for rel in pngs(iid):
            p = os.path.join(REPO_ASSETS, rel)
            if not os.path.exists(p):
                problems.append("missing %s" % rel)
                continue
            a = load_rgba(p)
            imgs.append(a)
            want = it["size"]
            base_rel = rel.replace("_b.png", ".png")
            mx = CONTRACT.get(base_rel)
            if want and (a.shape[1], a.shape[0]) != tuple(want):
                problems.append("%s: size %dx%d, expected %dx%d" % (rel, a.shape[1], a.shape[0], *want))
            if mx and (a.shape[1] > mx[0] or a.shape[0] > mx[1]):
                problems.append("%s: size %dx%d exceeds the contract %dx%d" % (rel, a.shape[1], a.shape[0], *mx))
            al = a[..., 3]
            if not np.isin(al, (0, 255)).all():
                problems.append("%s: soft alpha" % rel)
            if it["opaque"] and (al != 255).any():
                problems.append("%s: an opaque plane has transparent pixels" % rel)
            cols = {tuple(c) for c in a[al == 255][:, :3].tolist()}
            bad = cols - pal_rgb(it["pal"])
            if bad:
                problems.append("%s: %d colours outside palette %s" % (rel, len(bad), it["pal"]))
            for c in cols:
                for k, h in ep.PAL["reserved"].items():
                    if np.linalg.norm(np.array(c, float) - np.array(ep.hex2rgb(h), float)) < ep.PAL["min_reserved_distance"]:
                        problems.append("%s: colour %s within 48 of reserved %s" % (rel, c, k))
            kind = it["kind"]
            if kind in LADDER:
                med = float(np.median(Lmap(a)[al == 255]))
                lo, hi = LADDER[kind]
                lo2, hi2 = lo - TOL, min(hi + TOL, CAP.get(kind, 999))
                line = "%s: %s median L* %.1f (allowed %.0f..%.0f)" % (rel, kind, med, lo2, hi2)
                if not (lo2 <= med <= hi2):
                    problems.append("ladder " + line)
                elif verbose:
                    info.append(line)
                fm = faces.get(it["district"], (None,))[0]
                if fm is not None and kind != "fg" and fm - med < 2 * STEP:
                    problems.append("playfield: %s median %.1f is less than 2 steps under the %s face %.1f"
                                    % (rel, med, it["district"], fm))
                if kind in ("far", "mid", "near", "backwall"):
                    import env_process as envp
                    frac, smallest = envp.accent_stats(Image.open(p), it["pal"])
                    if frac > 0.02 + 1e-9 or (smallest and smallest < 3):
                        problems.append("%s: accents %.1f %% of the layer, smallest island %d px (max 2 %%, >= 3 px)"
                                        % (rel, frac * 100, smallest))
            if kind in PLANE_KINDS and iid not in NOT_BACKDROPS:
                Lc = composite_L(a, it["district"], kind, REPO_ASSETS)
                worst = (99.0, "")
                for ch in chars:
                    bm = band_median(Lc, ch, it["tile_x"], it["tile_y"])
                    d = abs(ch["med"] - bm)
                    worst = min(worst, (d, ch["name"]))
                    if d < CONTRAST:
                        problems.append("contrast: %s (median %.1f) over %s: backdrop %.1f, dL* %.1f < %d"
                                        % (ch["name"], ch["med"], rel, bm, d, CONTRAST))
                if verbose:
                    info.append("%s: lowest character contrast dL* %.1f (%s)" % (rel, worst[0], worst[1]))
        if it["tile_x"] and it["kind"] in PLANE_KINDS and imgs:
            problems += seam_problems(it["out"], imgs, 1)
        if it["tile_y"] and imgs:
            problems += seam_problems(it["out"], imgs, 0)
        if it["kind"] == "critters":
            fmin = min(fm for d, (fm, em) in faces.items() if d != "null") if faces else 99
            cp, cm = critter_problems(os.path.join(REPO_ASSETS, it["out"]), fmin)
            problems += cp
            info.append("critters: median L* %.1f (lowest face %.1f)" % (cm, fmin))
    # foreign (AI) planes: reported only
    for rel, (kind, district) in FOREIGN.items():
        p = os.path.join(REPO_ASSETS, rel)
        if not os.path.exists(p):
            continue
        a = load_rgba(p)
        med = float(np.median(Lmap(a)[a[..., 3] > 0]))
        Lc = composite_L(a, district, kind, REPO_ASSETS)
        worst = min(chars, key=lambda c: abs(c["med"] - band_median(Lc, c, True, False)))
        bm = band_median(Lc, worst, True, False)
        info.append("INFO %s (AI, not painted here): %s median %.1f; lowest contrast %s dL* %.1f"
                    % (rel, kind, med, worst["name"], abs(worst["med"] - bm)))
    return report(problems, info, verbose)


def report(problems, info, verbose=True):
    if verbose:
        for i in info:
            print("  " + i)
    for p in problems:
        print("PROBLEM " + p)
    print("paint_env --check:", "OK" if not problems else "%d problems" % len(problems))
    return 1 if problems else 0


# =========================================================================== review
def review(out_dir):
    """x2 / x3 nearest composites per kind (planes stacked with fog bands and the district grade),
    written outside the repo."""
    os.makedirs(out_dir, exist_ok=True)
    grades = json.load(open(os.path.join(REPO_ASSETS, "vfx", "atmos", "district_grades.json")))["districts"]
    fog_a = Image.open(os.path.join(REPO_ASSETS, "vfx", "atmos", "fog_band_a.png")).convert("RGBA")
    fog_b = Image.open(os.path.join(REPO_ASSETS, "vfx", "atmos", "fog_band_b.png")).convert("RGBA")

    def img(rel):
        return Image.open(os.path.join(REPO_ASSETS, rel)).convert("RGBA")

    def grade(im, district):
        g = np.array(ep.hex2rgb(grades[district]["bg_modulate"]), float) / 255.0
        a = np.asarray(im).astype(float)
        a[..., :3] *= g
        return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")

    def fog(scr, band, y, district):
        col = np.array(ep.hex2rgb(grades[district]["fog"]), float)
        b = np.asarray(band).astype(float)
        tint = np.zeros_like(b)
        tint[..., :3] = col
        tint[..., 3] = b[..., 3]
        t = Image.fromarray(tint.astype(np.uint8), "RGBA")
        for x in range(0, 480, t.width):
            scr.alpha_composite(t, (x, y))

    def stack(name, district, layers, sky=None, fogs=()):
        scr = Image.new("RGBA", (480, 270), (0, 0, 0, 255))
        if sky:
            scr.alpha_composite(img(sky))
        else:
            bg = district_backdrop(district, 480, REPO_ASSETS)
            scr = Image.fromarray(np.concatenate([bg, np.full((270, 480, 1), 255, np.uint8)], -1), "RGBA")
        for k, rel in enumerate(layers):
            if rel is None:
                continue
            if isinstance(rel, tuple) and rel[0] == "fog":
                fog(scr, fog_a if rel[1] == "a" else fog_b, rel[2], district)
                continue
            im = img(rel)
            x0 = 480 - im.width if im.width < 480 and "ledge" in rel else 0
            for x in range(x0, 480, im.width):
                scr.alpha_composite(im, (x, 270 - im.height))
        scr = grade(scr, district)
        for s in (2, 3):
            scr.resize((480 * s, 270 * s), Image.NEAREST).save(os.path.join(out_dir, "%s_x%d.png" % (name, s)))
        return scr

    stacks = {
        "uc_pursuit": ("undercity", ["undercity/uc_far.png", ("fog", "a", 150), "undercity/uc_mid_pipeworks.png",
                                     "undercity/uc_near_columns.png", ("fog", "b", 190)], "undercity/uc_sky_vault.png"),
        "uc_ward": ("undercity", ["undercity/uc_backwall_ward.png", ("fog", "b", 190)], None),
        "uc_shaft": ("undercity", ["undercity/uc_far.png", "undercity/uc_shaft_near.png", ("fog", "b", 190)],
                     "undercity/uc_sky_vault.png"),
        "uc_tunnel": ("undercity", ["undercity/uc_far.png", ("fog", "a", 150), "undercity/uc_tunnel_mid.png",
                                    ("fog", "b", 190)], "undercity/uc_sky_vault.png"),
        "uc_boss": ("undercity", ["undercity/uc_boss_bay.png", ("fog", "b", 190)], None),
        "ll_street": ("lowlight", ["lowlight/ll_far_skyline.png", ("fog", "a", 150), "lowlight/ll_mid_blocks.png",
                                   "lowlight/ll_near_street.png", ("fog", "b", 190)], "lowlight/ll_sky_night.png"),
        "ll_roofs": ("lowlight", ["lowlight/ll_far_skyline_b.png", ("fog", "a", 150), "lowlight/ll_mid_roofs.png",
                                  ("fog", "b", 190)], "lowlight/ll_sky_storm.png"),
        "ll_canal": ("lowlight", ["lowlight/ll_far_skyline.png", ("fog", "a", 150), "lowlight/ll_canal_mid.png",
                                  ("fog", "b", 190)], "lowlight/ll_sky_night.png"),
        "ll_tower": ("lowlight", ["lowlight/ll_far_skyline.png", "lowlight/ll_tower_near.png", ("fog", "b", 190)],
                     "lowlight/ll_sky_night.png"),
        "ll_interior": ("lowlight", ["lowlight/ll_backwall_interior.png", ("fog", "b", 190)], None),
        "relay": ("relay", ["relay/relay_backwall.png", ("fog", "a", 170), "relay/relay_mid_concourse.png"], None),
        "null": ("null", ["null/null_far_strata.png"], None),
        "pit": ("lowlight", ["lowlight/ll_far_skyline.png", "challenge/pit_rig_near.png"], "lowlight/ll_sky_night.png"),
        "title": ("title", ["title/title_far_spires.png", ("fog", "a", 150), "title/title_mid_rooftops.png",
                            "title/title_near_ledge.png"], "title/title_sky.png"),
    }
    for name, (district, layers, sky) in stacks.items():
        stack(name, district, layers, sky)
    # sets: fg atlases, tiles, critters, landmarks at x3 on a mid grey
    for rel in ("undercity/uc_fg_set.png", "lowlight/ll_fg_set.png", "relay/relay_fg_set.png",
                "undercity/uc_tiles.png", "lowlight/ll_tiles.png", "relay/relay_tiles.png",
                "props/life_critters.png", "lowlight/ll_far_bell_tower.png", "lowlight/ll_train_far.png"):
        im = img(rel)
        bg = Image.new("RGBA", im.size, (64, 60, 72, 255))
        bg.alpha_composite(im)
        bg.resize((im.width * 3, im.height * 3), Image.NEAREST).save(
            os.path.join(out_dir, "set_%s_x3.png" % os.path.basename(rel)[:-4]))
    print("review composites in", out_dir)


def main(argv):
    if "--check" in argv:
        return check("--quiet" not in argv)
    if "--review" in argv:
        review(argv[argv.index("--review") + 1])
        return 0
    ids = [a for a in argv if not a.startswith("-")] or list(ITEMS)
    for iid in ids:
        if iid not in ITEMS:
            print("unknown item", iid)
            return 2
    for rel in build(ids, OUT):
        print("wrote", rel)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
