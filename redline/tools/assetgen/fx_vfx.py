"""fx_vfx.py: code-authored pixel VFX strips for REDLINE (owner fx_ui).

Usage:  python3 tools/assetgen/fx_vfx.py            build everything into assets/vfx/ (atmosphere textures: assets/vfx/atmos/)
        python3 tools/assetgen/fx_vfx.py --check    rebuild in place + validate (assetgen.py --check rebuilds in a temp dir and diffs)
        python3 tools/assetgen/fx_vfx.py ID [ID..]  build only these manifest ids

All sprites are grey MASKS (tones 96/176/255, hard alpha) meant to be tinted
in-engine (Palette.color for gameplay colours, district dust colour for dust,
UiTheme/pale steel for neutral smears). Atmosphere textures (fog, shafts,
glows, vignette) are white or black with 3-5 quantised alpha steps (they are
textures, not sprites, so they are exempt from the hard-alpha sprite rule).
Every strip gets a SpriteSheetSpec .tres and a .json sidecar (cell, origin,
rows, per-row origin overrides, fps, tint hint).
"""
from __future__ import annotations

import math
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fxlib import (OUT, SS, bayer, blank, check_png, cov_ellipse, cov_poly, dissolve, line, merge, over,  # noqa: E402
                   preview, put, put_over, remove_islands, ring, save, sheet, smooth, write_json, write_tres)

VFX = os.path.join(OUT, "vfx")
RES = "res://assets/vfx/"
# Atmosphere textures (quantised soft alpha) live apart from the hard-alpha
# sprite strips: ArtValidator allows up to 4 alpha levels only under vfx/atmos/.
ATMOS = os.path.join(VFX, "atmos")
RES_ATMOS = RES + "atmos/"
BUILT = {}  # id -> list of files


def emit(item_id, name, rows, cw, ch, origin, fps, tint, loops=(), row_origins=None, notes=""):
    """rows: list of (anim, frames). Writes png + tres + json."""
    img = sheet(rows, cw, ch)
    png = save(img, os.path.join(VFX, name + ".png"))
    anims = []
    for r, (anim, frames) in enumerate(rows):
        f = fps[anim] if isinstance(fps, dict) else fps
        anims.append((anim, r, len(frames), f, anim in loops))
    write_tres(os.path.join(VFX, name + ".tres"), RES + name + ".png", cw, ch, origin, anims, row_origins or {})
    write_json(os.path.join(VFX, name + ".json"), {
        "id": item_id, "texture": RES + name + ".png", "cell": [cw, ch], "origin": list(origin),
        "rows": [{"name": a, "row": r, "frames": n, "fps": f, "loop": lp} for a, r, n, f, lp in anims],
        "row_origins": row_origins or {}, "tint": tint, "notes": notes, "facing": "+x (flip_h for facing -1)"})
    preview(png)
    BUILT.setdefault(item_id, []).extend([png, png[:-4] + ".tres", png[:-4] + ".json"])
    return png


def save_tex(item_id, name, rgba, tint, notes=""):
    png = save(rgba, os.path.join(ATMOS, name + ".png"))
    write_json(os.path.join(ATMOS, name + ".json"), {"id": item_id, "texture": RES_ATMOS + name + ".png",
                                                    "size": [rgba.shape[1], rgba.shape[0]], "tint": tint, "notes": notes})
    preview(png)
    BUILT.setdefault(item_id, []).extend([png, png[:-4] + ".json"])
    return png


# ================================================================== slash smears
def smear_frame(cw, ch, hb, a0, a1, ut, uh, wmax, diss, ox=0, radial=1.0):
    """Crescent inside the ellipse inscribed in hitbox hb (w,h) + 1 px, centred in the cell."""
    cx, cy = cw / 2, ch / 2
    ax, ay = (hb[0] / 2 + 1) * radial, (hb[1] / 2 + 1) * radial
    span = abs(a1 - a0)
    s = 1 if a1 >= a0 else -1
    yy, xx = np.mgrid[0:ch * SS, 0:cw * SS]
    px = (xx + 0.5) / SS - cx
    py = (yy + 0.5) / SS - cy
    r = np.sqrt((px / ax) ** 2 + (py / ay) ** 2)
    th = np.degrees(np.arctan2(py, px))
    u = (((th - a0) * s) % 360) / span
    v = (u - ut) / max(1e-6, (uh - ut))
    ok = (u <= 1.0) & (v >= 0) & (v <= 1)
    vv = np.clip(v, 0, 1)
    w = wmax * (vv ** 1.3) * np.clip((1 - vv) / 0.10 + 0.25, 0, 1)
    inside = ok & (r <= 1.0) & (r >= 1.0 - w)
    edge_px = 1.1 / max(ax, ay)
    rel = np.where(w > 0, (1.0 - r) / np.maximum(w, 1e-6), 1)
    tone = np.where((1.0 - r) < max(edge_px, 0) + 0 * rel, 3, np.where(rel < 0.55, 2, 1))
    tone = np.where(inside, tone, 0).astype(np.float32)
    cov = inside.reshape(ch, SS, cw, SS).mean(axis=(1, 3))
    tsum = tone.reshape(ch, SS, cw, SS).sum(axis=(1, 3))
    cnt = np.maximum(inside.reshape(ch, SS, cw, SS).sum(axis=(1, 3)), 1)
    tmax = tone.reshape(ch, SS, cw, SS).max(axis=(1, 3))
    f = np.where(cov >= 0.42, np.maximum(np.round(tsum / cnt), np.where(tmax == 3, 3, 0)), 0).astype(np.uint8)
    # tail dissolves in dither: pixels near the tail end get thinned
    vpix = v.reshape(ch, SS, cw, SS).mean(axis=(1, 3))
    tail = (vpix < 0.35) & (f > 0)
    b = bayer(ch, cw, ox)
    f[tail & (b > np.clip(vpix / 0.35, 0, 1))] = 0
    f[tail & (f == 3) & (vpix < 0.15)] = 2
    if diss > 0:
        dissolve(f, diss, ox)
        f[(f == 3)] = 2 if diss > 0.3 else 3
    return remove_islands(f)


def build_slash():
    cw = ch = 48
    specs = {
        # name: (hitbox w,h, a0, a1, wmax, [(ut, uh, wscale, dissolve)])
        "light": ((28, 24), -120, 60, 0.58, [(0.0, 0.7, 1, 0), (0.05, 1.0, 1, 0), (0.45, 1.0, 0.75, 0.5)]),
        "heavy": ((38, 34), -150, 80, 0.75, [(0.0, 0.4, 1, 0), (0.0, 0.85, 1, 0), (0.2, 1.0, 1, 0), (0.55, 1.0, 0.7, 0.55)]),
        "launcher": ((26, 44), 80, -110, 0.62, [(0.0, 0.55, 1, 0), (0.05, 1.0, 1, 0), (0.5, 1.0, 0.7, 0.55)]),
        "air": ((32, 36), -160, 100, 0.52, [(0.0, 0.5, 1, 0), (0.1, 1.0, 1, 0), (0.5, 1.0, 0.7, 0.55)]),
        "spike": ((32, 34), -40, 140, 0.66, [(0.0, 0.55, 1, 0), (0.05, 1.0, 1, 0), (0.5, 1.0, 0.7, 0.55)]),
    }
    rows = []
    for name, (hb, a0, a1, wm, frames) in specs.items():
        fr = [smear_frame(cw, ch, hb, a0, a1, ut, uh, wm * ws, d, ox=i) for i, (ut, uh, ws, d) in enumerate(frames)]
        rows.append((name, fr))
    # katar: two thin crossing arcs, fast
    k = []
    for i, (ut, uh, d) in enumerate([(0.0, 1.0, 0), (0.45, 1.0, 0.5)]):
        a = smear_frame(cw, ch, (24, 22), -70, 45, ut, uh, 0.45, d, ox=i)
        b = smear_frame(cw, ch, (24, 22), 60, -50, max(0, ut - 0.1), uh, 0.4, d, ox=i + 1, radial=0.72)
        k.append(merge(a, b))
    rows.append(("katar", k))
    # katar_spin: a full-circle whirl, head rotates 90 deg per frame
    ks = []
    for i in range(4):
        head = -90 + i * 90
        ks.append(smear_frame(cw, ch, (36, 40), head - 250, head, 0.1, 1.0, 0.40, 0.25 if i == 3 else 0, ox=i))
    rows.append(("katar_spin", ks))
    return emit("vfx_slash_smears", "slash_smears", rows, cw, ch, (24, 24), 24, "pale steel / weapon colour (modulate)",
                notes="Cell centre = world_hitbox centre; each smear stays within its AttackData hitbox + 2 px "
                      "(light=blade_light_2, heavy=blade_heavy, launcher, air=blade_air_light, spike=blade_air_heavy, "
                      "katar=katar_light_*, katar_spin). Play at 24 fps (the active window is 0.06-0.12 s). "
                      "Replaces SlashArc._draw when present.")


# ================================================================== hit sparks
def spark_frame(cw, ch, t, rays, shards, core_r, rng_seed, ring_r=None, back=False):
    f = blank(cw, ch)
    cx, cy = cw // 2, ch // 2
    rng = random.Random(rng_seed)
    tone_ray = 3 if t < 0.35 else (2 if t < 0.7 else 1)
    for ang, L, wid in rays:
        head = L * smooth(0.25 + t * 1.5)
        tail = L * max(0.0, t - 0.25) * 1.4
        if head - tail < 1:
            continue
        a = math.radians(ang)
        for wo in range(wid):
            ox, oy = -math.sin(a) * wo, math.cos(a) * wo
            line(f, cx + math.cos(a) * tail + ox, cy + math.sin(a) * tail + oy,
                 cx + math.cos(a) * head + ox, cy + math.sin(a) * head + oy, tone_ray)
        # hot tip
        put_over(f, cx + math.cos(a) * head, cy + math.sin(a) * head, 3 if t < 0.6 else 2)
    if t < 0.35 and core_r > 0:
        for dy in range(-core_r, core_r + 1):
            for dx in range(-core_r, core_r + 1):
                if abs(dx) + abs(dy) <= core_r:
                    put_over(f, cx + dx, cy + dy, 3 if abs(dx) + abs(dy) < core_r else 2)
    for k in range(shards):
        ang = rng.uniform(-40, 40) + (180 if back and k % 2 else 0)
        sp = rng.uniform(6, 13)
        d = sp * (0.2 + t) + 2
        g = 6 * t * t
        x = cx + math.cos(math.radians(ang)) * d
        y = cy + math.sin(math.radians(ang)) * d + g
        tone = 3 if t < 0.4 else (2 if t < 0.8 else 1)
        put_over(f, x, y, tone)
        if t < 0.6:
            put_over(f, x - math.cos(math.radians(ang)), y - math.sin(math.radians(ang)), max(1, tone - 1))
    if ring_r is not None:
        rr = ring_r * smooth(0.2 + t)
        m = ring(cw, ch, cx, cy, rr, rr * 0.9)
        rm = blank(cw, ch)
        rm[m] = 2 if t < 0.5 else 1
        dissolve(rm, max(0, t - 0.4) * 1.2)
        merge(f, rm)
    return f


def build_sparks():
    cw = ch = 32
    rows = []
    small_rays = [(0, 12, 1), (-55, 7, 1), (55, 7, 1), (180, 4, 1), (-25, 9, 1), (25, 9, 1)]
    rows.append(("spark_small", [spark_frame(cw, ch, i / 3.5, small_rays, 4, 2, 11) for i in range(4)]))
    heavy_rays = [(0, 14, 2), (-45, 10, 1), (45, 10, 1), (-90, 6, 1), (90, 6, 1), (180, 5, 1), (-20, 11, 1), (20, 11, 1)]
    rows.append(("spark_heavy", [spark_frame(cw, ch, i / 4.5, heavy_rays, 7, 3, 12) for i in range(5)]))
    # guard: a shield arc facing the attacker (-x) + sparks deflected back and up
    g = []
    for i in range(4):
        t = i / 3.5
        fr = spark_frame(cw, ch, t, [(180, 9, 1), (-140, 8, 1), (140, 8, 1), (-110, 6, 1)], 5, 1, 13, back=True)
        arc = blank(cw, ch)
        rr = 7 + 2 * t
        for k in range(24):
            a = math.radians(115 + 130 * k / 23)
            put_over(arc, 16 + math.cos(a) * rr, 16 + math.sin(a) * rr * 1.2, 3 if t < 0.4 else (2 if t < 0.8 else 1))
        dissolve(arc, max(0, t - 0.5))
        g.append(merge(fr, arc))
    rows.append(("spark_guard", g))
    crit_rays = [(a, 13 if a % 90 == 0 else 8, 1) for a in range(0, 360, 45)] + [(0, 15, 2)]
    rows.append(("spark_crit", [spark_frame(cw, ch, i / 4.5, crit_rays, 8, 3, 14, ring_r=13) for i in range(5)]))
    return emit("vfx_hit_sparks", "hit_sparks", rows, cw, ch, (16, 16), 24, "hit colour via Palette (guard = Palette guard)",
                notes="Drawn for hit.direction = +x; rotate the sprite to the hit direction (snap to 45 deg to keep "
                      "pixels crisp). Under flash reduction modulate tone 3 down (multiply 0.7) so no white core shows.")


# ================================================================== dust
def puff(f, cx, cy, r, t, seed, dither=True):
    """Shaded dust puff: lit top-left rim (3), body (2), shadow (1); dissolves with t
    (dither=False: fades by tone only, no ordered-dither holes)."""
    h, w = f.shape
    if r < 0.6:
        put(f, cx, cy, 2 if t < 0.6 else 1)
        return f
    m = cov_ellipse(w, h, cx, cy, r, r * 0.85)
    p = blank(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    d = ((xx + 0.5 - cx) * -0.7 + (yy + 0.5 - cy) * -0.7) / max(r, 1)
    p[m] = 2
    p[m & (d > 0.45)] = 3 if t < 0.5 else 2
    p[m & (d < -0.45)] = 1
    if dither:
        dissolve(p, max(0.0, (t - 0.55) * 2.0), seed, seed)
    elif t > 0.55:
        p[p > 1] -= 1  # fade by one tone instead of punching dither holes
    return merge(f, p)


def build_dust():
    cw = ch = 32
    rows = []
    land = []
    for i in range(5):
        t = i / 4
        f = blank(cw, ch)
        for s in (-1, 1):
            puff(f, 16 + s * (4 + 9 * t), 29 - 3 * t, 2.4 + 2.4 * t, t, i + 2)
            puff(f, 16 + s * (8 + 6 * t), 30 - 1 * t, 1.6 + 1.6 * t, t + 0.1, i + 5)
            puff(f, 16 + s * (1 + 4 * t), 29 - 1 * t, 1.8 + 1.2 * t, t + 0.05, i + 6)
        if i == 0:
            line(f, 10, 31, 22, 31, 2)
        land.append(remove_islands(f))
    rows.append(("land", land))
    hard = []
    rng = random.Random(3)
    peb = [(rng.uniform(-1, 1), rng.uniform(0.4, 1.0)) for _ in range(6)]
    for i in range(6):
        t = i / 5
        f = blank(cw, ch)
        for s in (-1, 1):
            puff(f, 16 + s * (5 + 9 * t), 28 - 5 * t, 3.2 + 3.0 * t, t, i + 7)
            puff(f, 16 + s * (2 + 5 * t), 28 - 3 * t, 2.6 + 2.2 * t, t + 0.1, i + 9)
            puff(f, 16 + s * (8 + 7 * t), 30 - 1 * t, 1.8 + 1.4 * t, t + 0.2, i + 3)
        if i <= 1:
            line(f, 16 - 8 - 4 * i, 31, 16 + 8 + 4 * i, 31, 3 - i)
        for vx, vy in peb:
            x = 16 + vx * 16 * t
            y = 30 - vy * 14 * t + 18 * t * t
            if y < 31 and i > 0:
                put_over(f, x, y, 2 if t < 0.7 else 1)
        hard.append(remove_islands(f))
    rows.append(("land_hard", hard))
    run = []
    for i in range(4):
        t = i / 3
        f = blank(cw, ch)
        # T06 redo: frame 2 was dither noise; it now fades by tone as one
        # smooth blob (the last frame keeps the dissolve to vanish).
        smooth_fade = i == 2
        puff(f, 12 - 6 * t, 29 - 3 * t, 1.8 + 2.0 * t, t, i, dither=not smooth_fade)
        if not smooth_fade:
            puff(f, 15 - 3 * t, 30 - 1 * t, 1.2 + 1.2 * t, t + 0.15, i + 1)
        run.append(remove_islands(f))
    rows.append(("run_puff", run))
    slide = []
    for i in range(4):
        t = i / 3
        f = blank(cw, ch)
        for k in range(5):
            x = 16 - 3 * k - 3 * t
            puff(f, x, 30 - 0.5 * k * t, 1.3 + 0.4 * k + 0.8 * t, min(1, t * 0.7 + k * 0.12), i + k)
        slide.append(remove_islands(f))
    rows.append(("slide", slide))
    dash = []
    rng = random.Random(5)
    lanes = [(rng.randint(12, 29), rng.randint(6, 14)) for _ in range(6)]
    for i in range(4):
        t = i / 3
        f = blank(cw, ch)
        for k, (y, L) in enumerate(lanes):
            x1 = 14 - 2 * k % 5 - 6 * t
            ln = max(0, L * (1 - t) - k % 3)
            if ln >= 1:
                line(f, x1 - ln, y, x1, y, 2 if t < 0.5 else 1)
                put_over(f, x1, y, 3 if t < 0.34 else 2)
        dash.append(f)
    rows.append(("dash_trail", dash))
    wall = []
    for i in range(4):
        t = i / 3
        f = blank(cw, ch)
        # wall surface is at x = 17 (+x side); dust and sparks peel off it and fall
        for k in range(3):
            puff(f, 15 - k * 1.5 - 2 * t, 16 + k * 3 + 4 * t, 0.8 + 0.6 * t, min(1, t + 0.15 * k), i + k)
        for k in range(3):
            put_over(f, 16 - k - 3 * t, 13 - k + 6 * t * t, 3 if t < 0.5 else 2)
        wall.append(remove_islands(f))
    rows.append(("wall_scrape", wall))
    return emit("vfx_dust", "dust", rows, cw, ch, (16, 31), 12, "district dust: uc concrete_3 #46574f, ll concrete_3 #4a4660, relay stone_3 #63503f",
                row_origins={"wall_scrape": [17, 16]},
                notes="Floor at y=31. Puffs drift toward -x (behind): flip with facing. wall_scrape origin is the wall contact "
                      "(wall on +x side). Flooded floors use splash.png instead.")


# ================================================================== splash
def drop(f, x, y, tone, tall=2):
    for k in range(tall):
        put_over(f, x, y + k, tone if k == 0 else max(1, tone - 1))


def build_splash():
    """AD redo: every row bold enough to read at 1x on the Undercity water colours.
    Tones: 3 (255) crown tips / droplet heads, 2 (176) crown body, 1 (96) fading tails."""
    cw = ch = 32
    S = 24  # water surface row
    cx = 16
    rows = []

    def crown(f, height, half_w, lean=1.0, tip=3, body=2):
        """A U-shaped splash wall: two columns rising from the surface, leaning outward, tips bright."""
        for s_ in (-1, 1):
            for k in range(1, height + 1):
                x = cx + s_ * (half_w + int(lean * k / 2))
                put_over(f, x, S - k, tip if k == height else body)
        for x in range(cx - half_w, cx + half_w + 1):
            put_over(f, x, S, body)

    def droplet(f, x, y, tall=2):
        put_over(f, x, y, 3)
        for k in range(1, tall):
            put_over(f, x, y + k, 2)

    def surface(f, w, tone=2):
        for x in range(cx - w // 2, cx - w // 2 + w):
            put_over(f, x, S, tone)

    def arc_pair(f, w, tone=3, tail=True):
        """Solid 1 px near arc (below the surface line) + back arc (above), ends fade to mid tone."""
        rx = w / 2
        ry = max(1.0, w / 9)
        for xi in range(-int(rx), int(rx) + 1):
            u = abs(xi) / max(rx, 1)
            off = ry * math.sqrt(max(0.0, 1 - u * u))
            t_ = tone if u < 0.7 else max(1, tone - 1)
            put_over(f, cx + xi, S + round(off), t_)
            if u > 0.35:
                put_over(f, cx + xi, S - round(off), max(1, t_ - 1))
        if tail:
            for xi in (-int(rx) - 1, int(rx) + 1):
                put_over(f, cx + xi, S, 1)

    # step: 2-droplet crown 3-4 px tall + a 5 px surface line
    step = []
    for i, (h, d_up) in enumerate(((2, 0), (4, 0), (2, 3), (0, 1))):
        f = blank(cw, ch)
        surface(f, 5)
        if h:
            crown(f, h, 1, lean=0.6)
        if i == 2:
            droplet(f, cx - 3, S - 6)
            droplet(f, cx + 3, S - 6)
        if i == 3:
            droplet(f, cx - 4, S - 3)
            droplet(f, cx + 4, S - 3)
            arc_pair(f, 9, tone=2)
        step.append(f)
    rows.append(("step", step))

    # land: a 7-9 px crown with 4 droplets arcing out over the frames
    land = []
    for i in range(6):
        t = (i + 1) / 6
        f = blank(cw, ch)
        surface(f, 9 + 2 * i if i < 3 else 13)
        h = [5, 8, 9, 7, 4, 0][i]
        if h:
            crown(f, h, 2 + (i // 2), lean=1.2)
        for k, (vx, vy) in enumerate(((-9, 12), (-5, 15), (5, 15), (9, 12))):
            x = cx + vx * t
            y = S - (vy * t * 2 - vy * t * t * 1.9)
            if i >= 1 and y <= S:
                droplet(f, x, y, 2 if t < 0.7 else 1)
        if i >= 3:
            arc_pair(f, 10 + 3 * i, tone=2 if i < 5 else 1)
        land.append(f)
    rows.append(("land", land))

    # drip: a 2 px droplet falls, a 3 px crown, then a ring
    dr = []
    for i in range(4):
        f = blank(cw, ch)
        if i == 0:
            droplet(f, cx, S - 5, 2)
        elif i == 1:
            surface(f, 5)
            crown(f, 3, 1, lean=0.4)
        elif i == 2:
            surface(f, 3, tone=1)
            droplet(f, cx, S - 3, 1)
            arc_pair(f, 8, tone=3)
        else:
            arc_pair(f, 12, tone=2)
        dr.append(f)
    rows.append(("drip", dr))

    # rain hit: tiny but bold (3 px crown, then a short line)
    rh = []
    for i in range(3):
        f = blank(cw, ch)
        if i == 0:
            put_over(f, cx, S - 2, 3); put_over(f, cx, S - 1, 2); surface(f, 3)
        elif i == 1:
            put_over(f, cx - 2, S - 2, 3); put_over(f, cx + 2, S - 2, 3); put_over(f, cx - 1, S - 1, 2); put_over(f, cx + 1, S - 1, 2); surface(f, 5)
        else:
            arc_pair(f, 7, tone=2, tail=False)
        rh.append(f)
    rows.append(("rain_hit", rh))

    # ripple: a solid 1 px arc pair expanding 6 -> 18 px wide with a mid-tone tail ring inside
    rp = []
    widths = [6, 9, 11, 14, 16, 18]
    for i, w in enumerate(widths):
        f = blank(cw, ch)
        arc_pair(f, w, tone=3 if i < 3 else (2 if i < 5 else 1))
        if i >= 2:
            arc_pair(f, widths[i - 2], tone=2 if i < 4 else 1, tail=False)
        rp.append(f)
    rows.append(("ripple", rp))
    return emit("vfx_splash", "splash", rows, cw, ch, (16, 24), 12, "water: uc water_glint #6f9e90 / ll wet_hi #7a8aa6",
                notes="AD redo: bold rows (crown tips 255, body 176, tails 96). Origin = the point on the water surface (row 24). "
                      "Ripples are a solid near arc + a back arc, so they read as lying on the surface at 1x.")


# ================================================================== pulse motes
def build_motes():
    cw, ch = 24, 8
    cx, cy = 12, 4
    rows = []
    mote = []
    for i in range(4):
        f = blank(cw, ch)
        if i == 0:
            put_over(f, cx, cy, 3)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                put_over(f, cx + dx, cy + dy, 1)
        elif i == 1:
            put_over(f, cx, cy, 3)
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                put_over(f, cx + dx, cy + dy, 2)
            for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
                put_over(f, cx + dx, cy + dy, 1)
        elif i == 2:
            put_over(f, cx, cy, 3)
            for dx, dy in ((1, 1), (-1, -1), (1, -1), (-1, 1)):
                put_over(f, cx + dx, cy + dy, 1)
        else:
            put_over(f, cx, cy, 2)
        mote.append(f)
    rows.append(("mote", mote))
    f = blank(cw, ch)
    for x in range(0, cx + 1):
        d = (cx - x) / cx  # 0 at head
        tone = 3 if d < 0.12 else (2 if d < 0.45 else 1)
        put_over(f, x, cy, tone)
        if d < 0.3:
            put_over(f, x, cy - 1 if x % 2 else cy + 1, 1 if d > 0.1 else 2)
    dissolve(f, 0.0)
    b = bayer(ch, cw)
    xs = np.arange(cw)[None, :].repeat(ch, 0)
    f[(xs < cx * 0.5) & (b < (1 - xs / (cx * 0.5)) * 0.7)] = 0
    put_over(f, cx + 1, cy, 2)
    rows.append(("absorb_stream", [f] + [blank(cw, ch)] * 3))
    png = emit("vfx_pulse_motes", "pulse_motes", rows, cw, ch, (12, 4), {"mote": 12, "absorb_stream": 1}, "pale white-violet (char_rook coat_2 #d8d4e0); last frame before absorption -> Palette accent (Core red)",
               loops=("mote",),
               notes="mote: 4-frame twinkle loop, spawn 3-8 per kill, drift then home into Rook's chest seam over 0.4 s. "
                     "absorb_stream: 1 frame (row padded with empty cells), a comet streak whose head sits on the origin; rotate to "
                     "the velocity. Use frame 0 only.")
    return png


# ================================================================== death burst
def chunk_poly(rng, size):
    n = rng.randint(4, 5)
    return [(math.cos(2 * math.pi * k / n + rng.uniform(-0.3, 0.3)) * size * rng.uniform(0.6, 1.0),
             math.sin(2 * math.pi * k / n + rng.uniform(-0.3, 0.3)) * size * rng.uniform(0.6, 1.0)) for k in range(n)]


def burst_frame(cw, ch, i, n, R, nchunks, nmotes, seed, boss=False):
    f = blank(cw, ch)
    cx, cy = cw / 2, ch / 2
    rng = random.Random(seed)
    t = i / (n - 1)
    # core: a short, small flash (boss: tone-2 fill with a white 1 px rim, never a white area)
    if i == 0:
        m = cov_ellipse(cw, ch, cx, cy, R * 0.22, R * 0.22)
        f[m] = 2 if boss else 3
        if boss:
            f[m & ~np.roll(m, 1, 0) | m & ~np.roll(m, -1, 0) | m & ~np.roll(m, 1, 1) | m & ~np.roll(m, -1, 1)] = 3
        for a in range(0, 360, 45):
            L = R * (0.5 if a % 90 == 0 else 0.34)
            line(f, cx + math.cos(math.radians(a)) * R * 0.24, cy + math.sin(math.radians(a)) * R * 0.24,
                 cx + math.cos(math.radians(a)) * L, cy + math.sin(math.radians(a)) * L, 3 if a % 90 == 0 else 2)
    # shock ring
    if i >= 1:
        rr = R * (0.3 + 0.7 * smooth(t * 1.4))
        m = ring(cw, ch, cx, cy, rr, rr * 0.92, width=1.5 if t < 0.3 else 1)
        rm = blank(cw, ch)
        rm[m] = 3 if t < 0.25 else (2 if t < 0.55 else 1)
        dissolve(rm, max(0, t - 0.35) * 1.6, i)
        merge(f, rm)
    # chunks on parabolic arcs, tumbling
    for k in range(nchunks):
        ang = -90 + (k - (nchunks - 1) / 2) * (150 / max(1, nchunks - 1)) + rng.uniform(-15, 15)
        sp = rng.uniform(0.55, 0.85) * R
        size = rng.uniform(1.8, 2.8) * (R / 16)
        poly = chunk_poly(rng, size)
        if i == 0:
            continue
        tt = t * 1.2
        x = cx + math.cos(math.radians(ang)) * sp * tt
        y = cy + math.sin(math.radians(ang)) * sp * tt + R * 1.1 * tt * tt
        rot = i * (0.9 + k * 0.3)
        pts = [(x + px * math.cos(rot) - py * math.sin(rot), y + px * math.sin(rot) + py * math.cos(rot)) for px, py in poly]
        m = cov_poly(cw, ch, pts, 0.45)
        c = blank(cw, ch)
        c[m] = 2
        c[m & ~np.roll(m, 1, 0)] = 3  # lit top edge
        c[m & ~np.roll(m, -1, 0)] = 1
        if t > 0.6:
            dissolve(c, (t - 0.6) * 2.2, k)
        over(f, c)
    # motes: scatter then slow (they re-spawn as homing pulse_motes in code)
    for k in range(nmotes):
        ang = rng.uniform(0, 360)
        sp = rng.uniform(0.35, 0.95) * R
        d = sp * (1 - (1 - min(1, t * 1.6)) ** 2)
        x = cx + math.cos(math.radians(ang)) * d
        y = cy + math.sin(math.radians(ang)) * d - t * R * 0.15
        if i >= 1 and not (t > 0.8 and k % 3 == 0):
            put_over(f, x, y, 3 if (i + k) % 3 == 0 else 2)
    return f


def build_death():
    cw = ch = 48
    rows = [("small", [burst_frame(cw, ch, i, 8, 14, 3, 8, 21) for i in range(8)]),
            ("large", [burst_frame(cw, ch, i, 10, 20, 4, 14, 22) for i in range(10)])]
    emit("vfx_death_burst", "death_burst", rows, cw, ch, (24, 24), 12, "enemy mid-tone (EnemyData.color after F5) or neutral",
         notes="Code flashes the body to a silhouette for 1 frame first (existing hit-flash), then spawns this. Chunks "
               "arc and fall; motes scatter and are re-emitted as homing pulse_motes.")
    B = 96
    frames = []
    for i in range(16):
        if i < 3:  # implosion: lines converge on the core
            f = blank(B, B)
            rr = 40 * (1 - i / 3)
            for a in range(0, 360, 30):
                r0, r1 = rr, rr + 6
                line(f, 48 + math.cos(math.radians(a)) * r0, 48 + math.sin(math.radians(a)) * r0,
                     48 + math.cos(math.radians(a)) * r1, 48 + math.sin(math.radians(a)) * r1, 2 if i < 2 else 3)
            m = cov_ellipse(B, B, 48, 48, 3 + i * 2, 3 + i * 2)
            f[m] = 2
            frames.append(f)
        elif i < 5:  # held freeze frame: cross-shaped core, no white fill
            f = burst_frame(B, B, 0, 13, 34, 5, 24, 30, boss=True)
            frames.append(f)
        else:
            j = i - 4
            f = burst_frame(B, B, j, 12, 40, 6, 26, 31, boss=True)
            if j >= 2:  # second ring and debris rain
                t = j / 11
                rr = 40 * 0.5 * smooth(t)
                m = ring(B, B, 48, 48, rr, rr * 0.9)
                rm = blank(B, B)
                rm[m] = 2 if t < 0.5 else 1
                dissolve(rm, t * 0.9, j)
                merge(f, rm)
                rng = random.Random(40)
                for k in range(10):
                    x = rng.uniform(8, 88)
                    y = (rng.uniform(0, 30) + j * 7) % 96
                    line(f, x, y, x, y + 2, 1 if k % 2 else 2)
            frames.append(f)
    emit("vfx_death_burst", "death_burst_boss", [("boss", frames)], B, B, (48, 48), 12, "neutral / boss accent",
         notes="Frames 0-2 implode, 3-4 are the held freeze (hitstop), 5-15 burst with a double ring, 6 chunks, motes "
               "and falling debris. No full-white area (flash-reduction safe). Separate file: 96x96 cells.")


# ================================================================== projectiles + muzzle
def build_projectiles():
    cw = ch = 16
    cx, cy = 8, 8
    rows = []
    pb = []
    for i in range(2):
        f = blank(cw, ch)
        line(f, 3 + i, cy, 9, cy, 1)
        line(f, 6, cy, 10, cy, 2)
        put_over(f, 11, cy, 3); put_over(f, 12, cy, 3); put_over(f, 11, cy - 1 + i, 2)
        pb.append(f)
    rows.append(("pistol_bolt", pb))
    f = blank(cw, ch)
    put_over(f, cx, cy, 3)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        put_over(f, cx + dx, cy + dy, 2)
    rows.append(("pellet", [f]))
    rr = []
    for i in range(2):
        f = blank(cw, ch)
        line(f, 1 + 2 * i, cy, 8, cy, 1)
        if i:
            f[cy, 1:8:2] = 0
        for x in range(9, 13):
            for y in (cy - 1, cy, cy + 1):
                put_over(f, x, y, 2)
        put_over(f, 13, cy, 2); put_over(f, 12, cy, 3); put_over(f, 11, cy, 3); put_over(f, 11, cy - 1, 3)
        rr.append(f)
    rows.append(("revolver_round", rr))
    eb = []
    for i in range(3):
        f = blank(cw, ch)
        r = 2 + (1 if i == 1 else 0)
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                d = abs(dx) + abs(dy)
                if d <= r:
                    put_over(f, 10 + dx, cy + dy, 3 if d == 0 else (2 if d < r else 1))
        line(f, 3 + i % 2, cy, 10 - r - 1, cy, 1)
        put_over(f, 6 - i, cy - 1, 1); put_over(f, 5 + i, cy + 1, 1)
        eb.append(f)
    rows.append(("enemy_bolt", eb))
    ct = []
    for i in range(3):
        f = blank(cw, ch)
        a0 = i * 20
        pts = [(cx + math.cos(math.radians(a0 + 60 * k)) * 3.6, cy + math.sin(math.radians(a0 + 60 * k)) * 3.6) for k in range(6)]
        m = cov_poly(cw, ch, pts, 0.45)
        f[m] = 2
        edge = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
        f[edge] = 1
        put_over(f, cx, cy, 3)
        line(f, cx - 7, cy, cx - 5, cy, 1)
        ct.append(f)
    rows.append(("collector_tag", ct))
    gw = []
    for i in range(4):
        f = blank(cw, ch)
        hgt = [5, 7, 6, 4][i]
        for x in range(2, 14):
            u = (x - 2) / 11
            yv = 15 - hgt * math.sin(math.pi * u) ** 0.7
            line(f, x, 15, x, yv, 1)
            put_over(f, x, yv, 3 if u > 0.45 else 2)
            if u > 0.6 and (x + i) % 2 == 0:
                put_over(f, x, yv - 1, 2)
        f[15, 2:14] = 2
        for k in range(2):
            put_over(f, 12 - 3 * k + i % 2, 15 - hgt - 2 - k, 1)
        gw.append(f)
    rows.append(("ground_wave", gw))
    emit("vfx_projectiles", "projectiles", rows, cw, ch, (8, 8), 12, "player shots: Palette ammo; enemy shots: Palette danger; collector_tag: Palette collector_warning",
         loops=tuple(n for n, _ in rows), row_origins={"ground_wave": [8, 15]},
         notes="Travel direction +x (rotate or flip). ground_wave sits on the floor (origin bottom-centre).")
    # muzzle flashes: origin at the barrel tip, flash toward +x
    rows = []
    mo = (2, 8)

    def star(f, x, y, arms, tone):
        for (dx, dy, L) in arms:
            for k in range(1, L + 1):
                put_over(f, x + dx * k, y + dy * k, tone if k < L else max(1, tone - 1))
        put_over(f, x, y, 3)

    f0 = blank(cw, ch)
    for dx in range(0, 3):
        for dy in (-1, 0, 1):
            put_over(f0, mo[0] + 1 + dx, mo[1] + dy, 3 if dy == 0 or dx == 1 else 2)
    star(f0, mo[0] + 2, mo[1], [(1, 0, 8), (0, -1, 3), (0, 1, 3), (1, -1, 3), (1, 1, 3)], 3)
    f1 = blank(cw, ch)
    star(f1, mo[0] + 2, mo[1], [(1, 0, 5), (1, -1, 2), (1, 1, 2)], 2)
    put_over(f1, mo[0] + 8, mo[1] - 1, 1); put_over(f1, mo[0] + 9, mo[1] + 1, 1)
    rows.append(("pistol", [f0, f1]))
    sc = []
    for i in range(3):
        f = blank(cw, ch)
        for a in (-30, -15, 0, 15, 30):
            L = [11, 8, 4][i]
            s0 = [0, 3, 6][i]
            line(f, mo[0] + 1 + math.cos(math.radians(a)) * s0, mo[1] + math.sin(math.radians(a)) * s0,
                 mo[0] + 1 + math.cos(math.radians(a)) * (s0 + L), mo[1] + math.sin(math.radians(a)) * (s0 + L), [3, 2, 1][i])
        if i == 0:
            for dy in (-2, -1, 0, 1, 2):
                put_over(f, mo[0] + 1, mo[1] + dy, 3)
        if i == 2:
            puff(f, mo[0] + 3, mo[1] - 1, 2.0, 0.5, 3)
        sc.append(f)
    rows.append(("scatter", sc))
    rv = []
    for i in range(3):
        f = blank(cw, ch)
        if i == 0:
            m = cov_ellipse(cw, ch, mo[0] + 3, mo[1], 2.5, 2.5)
            f[m] = 3
            star(f, mo[0] + 3, mo[1], [(1, 0, 10), (0, -1, 5), (0, 1, 5), (1, -1, 4), (1, 1, 4), (-1, -1, 2), (-1, 1, 2)], 3)
        elif i == 1:
            star(f, mo[0] + 3, mo[1], [(1, 0, 8), (0, -1, 4), (0, 1, 4), (1, -1, 3), (1, 1, 3)], 2)
            m = ring(cw, ch, mo[0] + 3, mo[1], 3, 3)
            f[m & (f == 0)] = 1
        else:
            puff(f, mo[0] + 4, mo[1] - 1, 2.6, 0.55, 4)
            puff(f, mo[0] + 8, mo[1] - 2, 1.6, 0.6, 5)
        rv.append(f)
    rows.append(("revolver", rv))
    emit("vfx_muzzle", "muzzle", rows, cw, ch, mo, 24, "Palette ammo (white core dropped under flash reduction: modulate 0.7)",
         notes="Origin at the barrel tip; flash points +x. 24 fps (2-3 frames = 0.08-0.12 s).")


# ================================================================== heal / anchor
def cross(f, x, y, tone):
    put_over(f, x, y, tone)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        put_over(f, x + dx, y + dy, max(1, tone - 1))


def big_cross(f, x, y, tone=3):
    """AD redo: 5x5 cross, 255 centre, 176 arms, 1 px 96 outline (7x7 with the outline)."""
    x, y = int(round(x)), int(round(y))
    body = [(0, 0)] + [(d * s_, 0) for d in (1, 2) for s_ in (-1, 1)] + [(0, d * s_) for d in (1, 2) for s_ in (-1, 1)]
    bset = set(body)
    for bx, by in body:
        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (bx + ox, by + oy)
            if q not in bset:
                put_over(f, x + q[0], y + q[1], 1)
    for bx, by in body:
        put_over(f, x + bx, y + by, 2 if (bx, by) != (0, 0) else tone)


def build_heal():
    cw = ch = 32
    # 3-4 crosses staggered in height (start frame, x offset, rise speed)
    crosses = [(-7, 0, 2.6), (6, 1, 3.0), (-1, 3, 2.8), (8, 4, 2.4)]
    fr = []
    for i in range(8):
        f = blank(cw, ch)
        t = i / 7
        if i < 6:
            rx, ry = 4 + 9 * t, 1 + 1.5 * t
            tone = 3 if t < 0.3 else (2 if t < 0.6 else 1)
            for xi in range(-int(rx), int(rx) + 1):
                u = abs(xi) / rx
                off = ry * math.sqrt(max(0.0, 1 - u * u))
                put_over(f, 16 + xi, 29 + round(off * 0.7), tone if u > 0.2 else max(1, tone - 1))
                if u > 0.7:
                    put_over(f, 16 + xi, 29 - round(off * 0.7), max(1, tone - 1))
        # 1 px vertical shimmer line on frames 2-5 (rises through the body)
        if 2 <= i <= 5:
            top = 26 - (i - 2) * 5
            for yy in range(top, top + 8):
                put_over(f, 16, yy, 2 if yy < top + 3 else 1)
        for (dx, start, sp) in crosses:
            k = i - start
            if 0 <= k <= 4:
                y = 25 - k * sp
                big_cross(f, 16 + dx, y, 3)
        fr.append(f)
    emit("vfx_heal", "heal", [("heal_rise", fr)], cw, ch, (16, 31), 12, "Palette heal",
         notes="AD redo: 5x5 crosses (255 centre, 176 arms, 96 outline) + a vertical shimmer on frames 2-5. "
               "Heal-tint mask: plays on injector use at Rook's feet.")


def build_anchor():
    cw = ch = 48
    sock = (24, 14)
    rng = random.Random(9)
    roots = []
    for k in range(5):
        x = 24 + (k - 2) * 7 + rng.randint(-1, 1)
        pts = [(x, 47)]
        for s in range(1, 9):
            u = s / 8
            px = x + (sock[0] - x) * smooth(u) + rng.uniform(-1.2, 1.2) * (1 - u)
            py = 47 + (sock[1] + 3 - 47) * u
            pts.append((px, py))
        roots.append(pts)
    bloom = []
    for i in range(10):
        f = blank(cw, ch)
        grow = min(1.0, (i + 1) / 5)
        for pts in roots:
            n = int(round(grow * (len(pts) - 1)))
            for s in range(n):
                line(f, *pts[s], *pts[s + 1], 2 if i < 7 else 1)
            if i < 5 and n >= 1:
                put_over(f, *pts[n], 3)
        if i >= 4:
            j = i - 4
            R = [3, 7, 10, 9, 7, 5][j]
            for rr, tone in ((R, 1), (R * 0.6, 2), (R * 0.3, 3)):
                m = cov_ellipse(cw, ch, sock[0], sock[1], rr, rr)
                g = blank(cw, ch)
                g[m] = tone
                if tone == 1:
                    dissolve(g, 0.5, j)
                merge(f, g)
        bloom.append(f)
    emb = []
    embers = [(rng.uniform(-10, 10), rng.uniform(0, 1), rng.uniform(0.8, 1.2)) for _ in range(7)]
    H = 34
    for i in range(6):
        f = blank(cw, ch)
        for k, (dx, ph, sp) in enumerate(embers):
            u = (ph + i / 6) % 1.0
            y = 44 - u * H
            x = 24 + dx + math.sin((u * 2 + k) * math.pi) * 1.5
            tone = 3 if u < 0.3 else (2 if u < 0.7 else 1)
            if (i + k) % 5 == 0:
                tone = max(1, tone - 1)
            put_over(f, x, y, tone)
            if u < 0.5:
                put_over(f, x, y + 1, 1)
        emb.append(f)
    emit("vfx_anchor_rest", "anchor_rest", [("bloom", bloom), ("embers", emb)], cw, ch, (24, 47), {"bloom": 12, "embers": 8},
         "Palette accent (Redline red) for roots/socket; embers can use lamp_core #e0a060 in the Relay",
         loops=("embers",), notes="Origin on the floor under the Anchor; socket at (24,14) in the cell. bloom plays once on "
                                  "rest, embers loop while resting.")


# ================================================================== atmosphere textures
def tile_noise(w, h, cells_x, cells_y, seed):
    """Periodic (x-tileable) value noise in [0,1]."""
    rng = np.random.default_rng(seed)
    g = rng.random((cells_y + 1, cells_x))
    xs = np.arange(w) / w * cells_x
    ys = np.arange(h) / h * cells_y
    x0 = np.floor(xs).astype(int)
    fx = xs - x0
    y0 = np.floor(ys).astype(int)
    fy = ys - y0
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    a = g[y0][:, x0 % cells_x]
    b = g[y0][:, (x0 + 1) % cells_x]
    c = g[np.minimum(y0 + 1, cells_y)][:, x0 % cells_x]
    d = g[np.minimum(y0 + 1, cells_y)][:, (x0 + 1) % cells_x]
    top = a + (b - a) * sx
    bot = c + (d - c) * sx
    return top + (bot - top) * sy[:, None]


def quant_alpha(dens, steps, rgb=(255, 255, 255), dither=True):
    """dens 0..1 -> RGBA with len(steps) alpha levels, Bayer-dithered between levels."""
    h, w = dens.shape
    n = len(steps)
    v = np.clip(dens, 0, 1) * n
    lo = np.floor(v).astype(int)
    fr = v - lo
    if dither:
        lo = lo + (fr > bayer(h, w)).astype(int)
    lo = np.clip(lo, 0, n)
    lv = np.array([0] + list(steps), np.uint8)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = rgb
    out[..., 3] = lv[lo]
    out[out[..., 3] == 0, :3] = 0
    return out


def build_fog():
    W, H = 256, 64
    yy = np.linspace(0, 1, H)[:, None]
    prof = np.exp(-((yy - 0.55) / 0.26) ** 2)
    n = 0.6 * tile_noise(W, H, 8, 4, 1) + 0.4 * tile_noise(W, H, 16, 8, 2)
    dens = np.clip((n * 1.3 - 0.25) * prof * 1.2, 0, 1)
    save_tex("vfx_fog", "fog_band_a", quant_alpha(dens, [18, 36, 56, 80]), "district fog_light (uc #2b3d38, ll #2e2b45, relay haze #4a3326)",
             notes="256x64, tileable in x, 4 alpha steps. Dense band: between far and mid (0.2 parallax, 3 px/s).")
    n2 = 0.55 * tile_noise(W, H, 4, 10, 3) + 0.45 * tile_noise(W, H, 12, 16, 4)
    prof2 = np.exp(-((yy - 0.5) / 0.32) ** 2)
    dens2 = np.clip((n2 * 1.6 - 0.6) * prof2 * 1.6, 0, 1)
    save_tex("vfx_fog", "fog_band_b", quant_alpha(dens2, [14, 28, 44, 64]), "district fog_light",
             notes="256x64, tileable in x, wispy horizontal streaks; near band (0.6 parallax, 6 px/s), lower alpha.")


def build_shafts():
    def shaft(w, h, beams, seed):
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        dens = np.zeros((h, w), np.float32)
        for (x_top, w_top, w_bot, slant, strength) in beams:
            u = yy / h
            cx = x_top + slant * yy
            half = (w_top + (w_bot - w_top) * u) / 2
            d = np.abs(xx - cx) / np.maximum(half, 0.5)
            core = np.clip(1.2 - d, 0, 1)
            fall = np.clip(1.0 - u * 0.95, 0, 1) ** 1.2 * np.clip(u * 8, 0, 1)
            dens = np.maximum(dens, core * fall * strength)
        dens *= 0.85 + 0.15 * tile_noise(w, h, 3, 12, seed)
        return quant_alpha(dens, [14, 28, 44])

    save_tex("vfx_light_shafts", "light_shaft_a", shaft(48, 160, [(18, 8, 30, 0.08, 1.0)], 5),
             "district light (uc sea_tube #9eccb8 / ll window_warm #b8925a / relay lamp_core #e0a060)",
             notes="Single slanted god-ray, 3 alpha steps, draw with blend add or mix at 1.0. Pair with ambient 'mote' "
                   "particles drifting inside the shaft. No Light2D.")
    save_tex("vfx_light_shafts", "light_shaft_b", shaft(112, 200, [(30, 10, 34, 0.14, 0.9), (54, 6, 22, 0.14, 0.7), (72, 12, 40, 0.14, 1.0)], 6),
             "district light", notes="Triple shaft through a grate, for large vertical rooms.")


def build_glow():
    for R in (8, 16, 32):
        yy, xx = np.mgrid[0:R, 0:R].astype(np.float32)
        d = np.sqrt((xx + 0.5 - R / 2) ** 2 + (yy + 0.5 - R / 2) ** 2) / (R / 2)
        dens = np.clip(1 - d, 0, 1) ** 1.4
        save_tex("vfx_lamp_glow", f"lamp_glow_{R}", quant_alpha(dens, [24, 52, 96], dither=R > 8),
                 "lamp colour (additive)", notes=f"{R}x{R} halo, 3 quantised alpha steps; blend add. Readable with bloom off.")
    w, h = 40, 12
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = np.maximum(np.abs(xx + 0.5 - w / 2) - (w / 2 - 6), 0) / 6
    dy = np.abs(yy + 0.5 - h / 2) / 6
    dens = np.clip(1 - np.sqrt(dx ** 2 + dy ** 2), 0, 1) ** 1.3
    save_tex("vfx_lamp_glow", "lamp_glow_tube", quant_alpha(dens, [20, 44, 80]), "neon tube colour (NeonSign), additive",
             notes="40x12 capsule halo for neon tubes / strip lamps; 9-slice-able horizontally (margins 8).")


def build_vignette():
    W, H = 480, 270
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xx + 0.5 - W / 2) / (W / 2)) ** 2 * 0.85 + ((yy + 0.5 - H / 2) / (H / 2)) ** 2)
    dens = np.clip((d - 0.62) / 0.75, 0, 1) ** 1.2
    rgba = quant_alpha(dens, [28, 56, 90, 130], rgb=(0, 0, 0))
    rgba[rgba[..., 3] == 0] = 0
    save_tex("vfx_grade_vignette", "vignette", rgba, "black (as is)",
             notes="480x270 screen vignette, 4 alpha steps, ordered dither. Sits above the background planes only "
                   "(under the playfield) so gameplay pixels are never darkened; Background dim may scale its alpha.")
    grades = {
        "undercity": {"bg_modulate": "#dfeee8", "fog": "#2b3d38", "shaft": "#9eccb8", "dust": "#46574f"},
        "lowlight": {"bg_modulate": "#e2e0f2", "fog": "#2e2b45", "shaft": "#b8925a", "dust": "#4a4660"},
        "relay": {"bg_modulate": "#fff0e0", "fog": "#4a3326", "shaft": "#e0a060", "dust": "#63503f"},
        "null": {"bg_modulate": "#e4e4ec", "fog": "#1b1c20", "shaft": "#dbdee6", "dust": "#4c4f59"},
        "title": {"bg_modulate": "#dcdcf4", "fog": "#2e2b4d", "shaft": "#4a4870", "dust": "#5c6b80"},
    }
    p = os.path.join(ATMOS, "district_grades.json")
    write_json(p, {"id": "vfx_grade_vignette", "rule": "bg_modulate applies to background ParallaxPlanes only, never the gameplay canvas (F11)",
                   "districts": grades})
    BUILT["vfx_grade_vignette"].append(p)


def build_ambient():
    cw = ch = 8
    rows = []
    rows.append(("mote", [(lambda f: (put_over(f, 4, 4, 3), f)[1])(blank(cw, ch)),
                          (lambda f: (put_over(f, 4, 4, 2), put_over(f, 3, 4, 1), put_over(f, 5, 4, 1), f)[3])(blank(cw, ch))]))
    sp = []
    for i in range(3):
        f = blank(cw, ch)
        f[3:5, 3:5] = 2
        put_over(f, 3, 3, 3)
        for k in range(4):
            a = math.radians(45 + 90 * k + i * 30)
            put_over(f, 4 + math.cos(a) * 2.4, 4 + math.sin(a) * 2.4, 1)
        sp.append(f)
    rows.append(("spore", sp))
    ash = []
    for i in range(2):
        f = blank(cw, ch)
        if i == 0:
            put_over(f, 3, 4, 2); put_over(f, 4, 4, 1)
        else:
            put_over(f, 4, 3, 2); put_over(f, 4, 4, 1)
        ash.append(f)
    rows.append(("ash", ash))
    dr = []
    for i in range(4):
        f = blank(cw, ch)
        if i == 0:
            put_over(f, 4, 0, 2)
        elif i == 1:
            put_over(f, 4, 0, 2); put_over(f, 4, 1, 3)
        elif i == 2:
            put_over(f, 4, 0, 1); put_over(f, 4, 2, 3); put_over(f, 4, 3, 2)
        else:
            put_over(f, 4, 5, 3); put_over(f, 4, 6, 2)
        dr.append(f)
    rows.append(("drip", dr))
    emit("vfx_ambient_particles", "ambient_particles", rows, cw, ch, (4, 4), {"mote": 4, "spore": 6, "ash": 6, "drip": 8},
         "per district: uc motes sea_tube #9eccb8 + spores bone_0 #7d7766; ll ash/rain #8ca3cc; relay dust lamp_core #e0a060",
         loops=("mote", "spore", "ash"), row_origins={"drip": [4, 0]},
         notes="Use frames as CPUParticles2D textures (AtlasTexture per row) or pooled Sprite2Ds; cap per room and "
               "scale by the ambient-motion setting (F7). drip plays once from a ceiling point, then the drop falls "
               "in code and ends with splash.drip.")


# ================================================================== P2
def build_shockwave():
    cw = ch = 64
    ringf = []
    for i in range(6):
        t = i / 5
        f = blank(cw, ch)
        R = 4 + 26 * smooth(t * 1.1)
        m = ring(cw, ch, 32, 32, R, R * 0.9, width=2 if t < 0.4 else 1)
        f[m] = 3 if t < 0.2 else (2 if t < 0.6 else 1)
        if i >= 1:
            m2 = ring(cw, ch, 32, 32, R * 0.7, R * 0.63)
            g = blank(cw, ch)
            g[m2] = 1
            dissolve(g, 0.4, i)
            merge(f, g)
        dissolve(f, max(0, t - 0.5) * 1.3, i)
        ringf.append(f)
    gw = []
    for i in range(6):
        t = i / 5
        f = blank(cw, ch)
        for s in (-1, 1):
            x0 = 32 + s * (4 + 26 * t)
            hgt = 9 * (1 - t) + 2
            for k in range(11):
                x = x0 - s * k
                y = 63 - hgt * math.sin(math.pi * min(1.0, (k + 1) / 11) ** 0.8) * (1 - 0.3 * k / 10)
                line(f, x, 63, x, y, 1)
                # T06 redo: a 2-tone crest, a bright lip over a mid-tone
                # shoulder, so the wave reads as a rolling front, not a fin.
                put_over(f, x, y, 3 if k < 5 and t < 0.6 else 2)
                if k < 8 and y + 1 < 63:
                    put_over(f, x, y + 1, 2)
            puff(f, x0 - s * 6, 61, 1.2 + 1.5 * t, t, i)
        f[63, int(32 - 26 * t - 4):int(32 + 26 * t + 5)] = np.maximum(f[63, int(32 - 26 * t - 4):int(32 + 26 * t + 5)], 1)
        gw.append(f)
    emit("vfx_shockwave", "shockwave", [("ring", ringf), ("ground_wave", gw)], cw, ch, (32, 32), 12, "Palette danger (enemy) / neutral",
         row_origins={"ground_wave": [32, 63]}, notes="ring: radial slam; ground_wave: Krail slam / Collector press "
                                                      "floor wave, travels both ways (visual only, hitboxes unchanged).")


def build_dodge():
    cw = ch = 48
    fl = []
    sizes = [(3, 1), (9, 2), (13, 2), (10, 1), (6, 1), (3, 0)]
    for i, (L, c) in enumerate(sizes):
        f = blank(cw, ch)
        diag = i in (3, 4)
        arms = [(1, 1), (-1, -1), (1, -1), (-1, 1)] if diag else [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for dx, dy in arms:
            LL = L if (dy == 0 or diag) else int(L * 1.3)
            for k in range(1, LL + 1):
                tone = 3 if k <= LL * 0.5 else (2 if k <= LL * 0.8 else 1)
                put_over(f, 24 + dx * k, 24 + dy * k, tone)
        for dy in range(-c, c + 1):
            for dx in range(-c, c + 1):
                if abs(dx) + abs(dy) <= c:
                    put_over(f, 24 + dx, 24 + dy, 3)
        if i >= 2:
            rng = random.Random(i)
            for _ in range(4):
                a = rng.uniform(0, 2 * math.pi)
                d = 6 + i * 2.5
                put_over(f, 24 + math.cos(a) * d, 24 + math.sin(a) * d, 2 if i < 5 else 1)
        fl.append(f)
    # AD redo: no baked afterimage frame. Code draws the afterimage from the LIVE Rook frame
    # (the current AnimatedSprite2D frame, modulate coat_1 #a9a3b8 at 40 % alpha, fading over
    # ~0.25 s), so it can never go stale when the Rook sheet changes.
    emit("vfx_perfect_dodge", "perfect_dodge", [("flourish", fl)], cw, ch, (24, 24),
         {"flourish": 18}, "flourish: white / Palette accent",
         notes="Flourish only (approved). The afterimage is NOT baked: code copies the live Rook sprite frame "
               "(same texture/region/flip), modulates it coat_1 #a9a3b8 at 40 % alpha and fades it over ~0.25 s.")


def jag(rng, x0, y0, x1, y1, depth, amp):
    if depth == 0:
        return [(x0, y0), (x1, y1)]
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2 + rng.uniform(-amp, amp)
    return jag(rng, x0, y0, mx, my, depth - 1, amp * 0.55)[:-1] + jag(rng, mx, my, x1, y1, depth - 1, amp * 0.55)


def build_arc():
    cw, ch = 48, 16
    fr = []
    for i in range(4):
        rng = random.Random(100 + i)
        f = blank(cw, ch)
        pts = jag(rng, 0, 8, 47, 8, 4, 6)
        for a, b in zip(pts, pts[1:]):
            line(f, *a, *b, 3)
        # glow fringe one pixel off the core
        g = blank(cw, ch)
        g[1:] = np.maximum(g[1:], (f[:-1] == 3) * 1)
        g[:-1] = np.maximum(g[:-1], (f[1:] == 3) * 1)
        dissolve(g, 0.35, i)
        f = np.where(f == 0, g, f).astype(np.uint8)
        for _ in range(2):
            k = rng.randint(3, len(pts) - 4)
            bx, by = pts[k]
            br = jag(rng, bx, by, bx + rng.uniform(6, 12), by + rng.choice([-1, 1]) * rng.uniform(3, 6), 2, 2)
            for a, b in zip(br, br[1:]):
                line(f, *a, *b, 2)
        fr.append(f)
    emit("vfx_electric_arc", "electric_arc", [("arc", fr)], cw, ch, (0, 8), 12, "baton_arc #cfe4f2 / tube colour",
         loops=("arc",), notes="Endpoints (0,8) and (47,8): scale x / rotate to span two points. Cycle frames at <= 3 Hz "
                               "for flashing (hold each 2-4 ticks) per the 3 Hz rule; under flash reduction hold frame 0.")


def build_steam():
    cw, ch = 16, 32
    fr = []
    for i in range(6):
        t = i / 5
        f = blank(cw, ch)
        for k in range(4):
            u = (t + k * 0.25) % 1.0
            y = 30 - u * 26
            x = 8 + math.sin(u * 5 + k) * 1.5
            r = 2.0 + u * 4.0
            p = blank(cw, ch)
            puff(p, x, y, r, 0.2, k + i)
            p[p == 3] = 2 if u > 0.3 else 3
            dissolve(p, max(0, u - 0.6) * 2.0, k + i, k)
            merge(f, p)
        fr.append(remove_islands(f))
    emit("vfx_steam", "steam", [("puff", fr)], cw, ch, (8, 31), 8, "fog_light / pale grey (#8a8398)",
         loops=("puff",), notes="Seamless 6-frame loop (puffs cycle with phase offsets); origin at the vent mouth.")


def build_debris():
    cw = ch = 8
    rows = []
    rng = random.Random(77)
    poly = chunk_poly(rng, 3.0)
    cf = []
    for i in range(4):
        rot = i * math.pi / 2 + 0.3
        pts = [(4 + px * math.cos(rot) - py * math.sin(rot), 4 + px * math.sin(rot) + py * math.cos(rot)) for px, py in poly]
        m = cov_poly(cw, ch, pts, 0.45)
        f = blank(cw, ch)
        f[m] = 2
        f[m & ~np.roll(m, 1, 0)] = 3
        f[m & ~np.roll(m, -1, 0)] = 1
        cf.append(f)
    rows.append(("concrete", cf))
    gf = []
    for i in range(4):
        f = blank(cw, ch)
        a = math.radians(i * 45)
        tri = [(4 + math.cos(a) * 3.5, 4 + math.sin(a) * 3.5), (4 + math.cos(a + 2.6) * 2, 4 + math.sin(a + 2.6) * 2),
               (4 + math.cos(a - 2.6) * 1.5, 4 + math.sin(a - 2.6) * 1.5)]
        m = cov_poly(cw, ch, tri, 0.4)
        f[m] = 1
        edge = m & ~np.roll(m, 1, 0)
        f[edge] = 3 if i % 2 == 0 else 2
        gf.append(f)
    rows.append(("glass", gf))
    sf = []
    for i in range(4):
        f = blank(cw, ch)
        L = [3, 2, 3, 1][i]
        put_over(f, 4, 6, 3 if i != 3 else 2)
        for k in range(1, L + 1):
            put_over(f, 4, 6 - k, 2 if k == 1 else 1)
        sf.append(f)
    rows.append(("sparks_fall", sf))
    emit("vfx_debris", "debris", rows, cw, ch, (4, 4), 12, "concrete: district concrete_2; glass: wet_hi #7a8aa6; sparks: sodium #d9944d",
         loops=("concrete", "glass", "sparks_fall"), notes="Particle textures: spawn 4-10 with gravity from BreakableWall / "
                                                           "glass props; frames are tumble cycles.")


BUILDERS = {
    "vfx_slash_smears": build_slash, "vfx_hit_sparks": build_sparks, "vfx_dust": build_dust, "vfx_splash": build_splash,
    "vfx_pulse_motes": build_motes, "vfx_death_burst": build_death, "vfx_projectiles": build_projectiles,
    "vfx_muzzle": build_projectiles, "vfx_heal": build_heal, "vfx_anchor_rest": build_anchor,
    "vfx_fog": build_fog, "vfx_light_shafts": build_shafts, "vfx_lamp_glow": build_glow,
    "vfx_grade_vignette": build_vignette, "vfx_ambient_particles": build_ambient,
    "vfx_shockwave": build_shockwave, "vfx_perfect_dodge": build_dodge, "vfx_electric_arc": build_arc,
    "vfx_steam": build_steam, "vfx_debris": build_debris,
}
TEXTURES = {"fog_band_a": 4, "fog_band_b": 4, "light_shaft_a": 3, "light_shaft_b": 3, "lamp_glow_8": 3,
            "lamp_glow_16": 3, "lamp_glow_32": 3, "lamp_glow_tube": 3, "vignette": 4}


def check_all():
    errs = []
    for folder in (VFX, ATMOS):
        for fn in sorted(os.listdir(folder)):
            if not fn.endswith(".png"):
                continue
            stem = fn[:-4]
            if (folder == ATMOS) != (stem in TEXTURES):
                errs.append(f"{fn}: soft-alpha textures belong in vfx/atmos/, hard-alpha strips in vfx/")
            errs += check_png(os.path.join(folder, fn), soft_alpha_steps=TEXTURES.get(stem), mask=True)
    return errs


def main(argv):
    ids = [a for a in argv if not a.startswith("-")]
    done = set()
    for k, fn in BUILDERS.items():
        if ids and k not in ids:
            continue
        if fn in done:
            continue
        fn()
        done.add(fn)
    errs = check_all()
    for e in errs:
        print("FAIL", e)
    print(f"built {sum(len(v) for v in BUILT.values())} files for {len(BUILT)} ids; {len(errs)} problems")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
