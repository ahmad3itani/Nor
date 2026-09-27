#!/usr/bin/env python3
"""REDLINE overhaul: environment asset post-processing (owner "env").

Reproduces every env output from the raw AI downloads:
    python3 tools/assetgen/env_process.py <id> [<id> ...]     # process named items
    python3 tools/assetgen/env_process.py --all               # every item whose raw exists
    python3 tools/assetgen/env_process.py --check             # verify outputs (palette, alpha, size)

Pipeline per mode (see RECIPES below; values follow art_manifest.json post_process):
  sky   : centre-crop 16:9 -> box downscale 480x270 -> remap lightness into the
          value-ladder range -> Bayer 4x4 ordered dither -> quantize to palette subset
          (max N colours) -> opaque PNG
  band  : chroma-key #FF00FF on the source (coverage mask), premultiplied box
          downscale to 480 wide, hard alpha at 50 % coverage, crop the band height,
          mirrored 32 px cross-fade seam (tileable x), lightness remap, quantize,
          remove islands < 4 px
  wall  : like band but opaque (interior backwalls)
  swatch: material swatch -> tileable 128x128 -> 4-value quantize -> 16 px autotile
          atlas 128x96 (+ layout json)
  sheet : chroma-key prop / silhouette sheet -> connected groups -> per-object PNG
          (common downscale factor) + atlas + json with origins (bottom-centre)
Only colours from palettes.json are ever written; reserved gameplay colours never are
(palettes.py already guarantees the palette itself stays >= 48 away from them).
"""
import json, os, sys
import numpy as np
from PIL import Image
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

ROOT = REDLINE
RAW = RAW
OUT = ASSETS
PAL = json.load(open(os.path.join(DATA, "palettes.json")))
KEY = np.array([255, 0, 255], float)

# ---------------------------------------------------------------- colour helpers

def srgb_to_lab(rgb):
    c = np.asarray(rgb, float) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], -1)


def lab_to_srgb(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    fy = (L + 16) / 116
    fx = fy + a / 500
    fz = fy - b / 200
    def inv(f):
        return np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787)
    xyz = np.stack([inv(fx), inv(fy), inv(fz)], -1) * np.array([0.95047, 1.0, 1.08883])
    Mi = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    c = xyz @ Mi.T
    c = np.clip(c, 0, 1)
    c = np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)
    return c * 255


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def palette(name):
    cols = PAL["palettes"][name]["colors"]
    names = list(cols)
    rgb = np.array([hex2rgb(cols[n]) for n in names], float)
    return names, rgb


def lum(rgb):
    return srgb_to_lab(np.asarray(rgb, float))[..., 0]

# ---------------------------------------------------------------- geometry helpers

def key_mask(img, tol=90):
    a = np.asarray(img.convert("RGB"), float)
    d = np.sqrt(((a - KEY) ** 2).sum(-1))
    # magenta-ish pixels (strong R and B, weak G) are key too: kills pink fringe
    pinkish = (a[..., 0] - a[..., 1] > 70) & (a[..., 2] - a[..., 1] > 70)
    return ~((d < tol) | pinkish)


def premult_downscale(img, mask, size):
    """Box-downscale colour using only unkeyed pixels; returns rgb, coverage."""
    a = np.asarray(img.convert("RGB"), float)
    m = mask.astype(float)
    num = np.zeros(size[::-1] + (3,))
    for c in range(3):
        num[..., c] = np.asarray(Image.fromarray((a[..., c] * m).astype(np.float32), "F").resize(size, Image.BOX))
    cov = np.asarray(Image.fromarray(m.astype(np.float32), "F").resize(size, Image.BOX))
    rgb = num / np.maximum(cov, 1e-6)[..., None]
    return rgb, cov


def box(img, size):
    return np.asarray(img.convert("RGB").resize(size, Image.BOX), float)


def centre_crop_169(img):
    w, h = img.size
    tw = min(w, int(round(h * 16 / 9)))
    th = int(round(tw * 9 / 16))
    x0, y0 = (w - tw) // 2, (h - th) // 2
    return img.crop((x0, y0, x0 + tw, y0 + th))


def seam_x(arr, n=32):
    """Mirrored cross-fade of the last n columns toward the mirror of the first n."""
    out = arr.copy()
    W = arr.shape[1]
    for i in range(n):
        t = (i + 0.5) / n
        out[:, W - n + i] = (1 - t) * arr[:, W - n + i] + t * arr[:, n - 1 - i]
    return out


def seam_y(arr, n=32):
    return np.swapaxes(seam_x(np.swapaxes(arr, 0, 1), n), 0, 1)


def label(mask):
    """4-connected components without scipy. Returns label array and count."""
    H, W = mask.shape
    lab = np.zeros((H, W), int)
    n = 0
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not lab[y, x]:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                while stack:
                    cy, cx = stack.pop()
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        yy, xx = cy + dy, cx + dx
                        if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not lab[yy, xx]:
                            lab[yy, xx] = n
                            stack.append((yy, xx))
    return lab, n


def remove_islands(alpha, min_px=4):
    lab, n = label(alpha)
    if n == 0:
        return alpha
    counts = np.bincount(lab.ravel())
    small = counts < min_px
    small[0] = False
    alpha = alpha.copy()
    alpha[small[lab]] = False
    # also fill 1-3 px holes
    lab2, n2 = label(~alpha)
    c2 = np.bincount(lab2.ravel())
    holes = c2 < min_px
    holes[0] = False
    alpha[holes[lab2]] = True
    return alpha

# ---------------------------------------------------------------- tone + quantize

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5


def remap_lightness(rgb, valid, lo, hi, p_lo=2, p_hi=99.3, chroma=1.0):
    """Linearly map source L* percentiles into [lo, hi]; keep hue, scale chroma."""
    lab = srgb_to_lab(rgb)
    Ls = lab[..., 0][valid]
    if Ls.size == 0:
        return rgb
    a, b = np.percentile(Ls, p_lo), np.percentile(Ls, p_hi)
    L = (lab[..., 0] - a) / max(b - a, 1e-3)
    L = lo + np.clip(L, 0, 1.15) * (hi - lo)
    lab[..., 0] = L
    lab[..., 1:] *= chroma
    return lab_to_srgb(lab)


def quantize(rgb, valid, pal_rgb, max_colors, dither=0.0, allowed=None, accents=None,
             accent_src=None, accent_mask=None):
    """Map to nearest palette colour in Lab; keep the max_colors most used.
    accents: palette indices usable only where accent_mask is True (bright source)."""
    plab = srgb_to_lab(pal_rgb)
    idx_all = np.arange(len(pal_rgb))
    base = idx_all if allowed is None else np.array(sorted(allowed))
    lab = srgb_to_lab(rgb)
    if dither:
        H, W = rgb.shape[:2]
        t = np.tile(BAYER4, (H // 4 + 1, W // 4 + 1))[:H, :W]
        lab[..., 0] += t * dither

    def nearest(cands, px):
        d = ((px[:, None, :] - plab[cands][None]) ** 2)
        d[..., 0] *= 1.6  # value matters most in pixel art readability
        return cands[np.argmin(d.sum(-1), 1)]

    flat = lab.reshape(-1, 3)
    v = valid.ravel()
    res = np.full(flat.shape[0], -1)
    res[v] = nearest(base, flat[v])
    # limit colour count by usage
    used, cnt = np.unique(res[v], return_counts=True)
    if len(used) > max_colors:
        keep = used[np.argsort(-cnt)[:max_colors]]
        res[v] = nearest(keep, flat[v])
    if accents is not None and accent_mask is not None:
        am = (accent_mask.ravel() & v)
        if am.any():
            src = srgb_to_lab(accent_src).reshape(-1, 3)
            res[am] = nearest(np.array(accents), src[am])
    out = np.zeros((flat.shape[0], 3), np.uint8)
    out[v] = pal_rgb[res[v]].astype(np.uint8)
    return out.reshape(rgb.shape), res.reshape(valid.shape)


def to_rgba(rgb, alpha):
    a = (alpha.astype(np.uint8) * 255)[..., None]
    rgb = np.where(alpha[..., None], rgb, 0).astype(np.uint8)
    return Image.fromarray(np.concatenate([rgb, a], -1), "RGBA")


# ---------------------------------------------------------------- AD redo helpers (accent hygiene, far-plane fixes)
ACCENT_NAMES = ("rust_0", "rust_1", "rust_2", "rust_3", "sea_dim", "water_glint", "sodium_dim", "sodium", "sea_tube",
                "window_warm_far", "window_warm", "window_cold_far", "window_cold", "window_rose", "sodium_street", "wet_hi",
                "lamp_core", "lamp_warm")


def accent_hygiene(q, alpha, names, prgb, t, allowed, min_island=3, max_frac=0.02):
    """AD rule for every env layer: accent colours (rust_*, sea_dim, water_glint, windows, lamps) survive only
    as clusters of >= min_island px (8-connected) and cover at most max_frac of the opaque layer; everything
    else falls back to the nearest non-accent palette colour of the remapped source."""
    acc_idx = [k for k, n in enumerate(names) if n in ACCENT_NAMES]
    if not acc_idx:
        return q, alpha
    acc_rgb = prgb[acc_idx].astype(np.uint8)
    is_acc = np.zeros(alpha.shape, bool)
    for c in acc_rgb:
        is_acc |= (q == c).all(-1)
    is_acc &= alpha
    base = [k for k in (allowed or range(len(names))) if names[k] not in ACCENT_NAMES]
    plab = srgb_to_lab(prgb[base])
    lab = srgb_to_lab(t)

    def fallback(mask):
        px = lab[mask]
        d = ((px[:, None, :] - plab[None]) ** 2)
        d[..., 0] *= 1.6
        q[mask] = prgb[np.array(base)[np.argmin(d.sum(-1), 1)]].astype(np.uint8)

    lab8, n = label8(is_acc)
    if n:
        cnt = np.bincount(lab8.ravel())
        small = cnt < min_island
        small[0] = False
        drop = small[lab8]
        if drop.any():
            fallback(drop)
        is_acc &= ~drop
        # cap: keep the largest clusters up to max_frac of the opaque area
        cap = int(max_frac * alpha.sum())
        if is_acc.sum() > cap:
            lab8, n = label8(is_acc)
            cnt = np.bincount(lab8.ravel())
            order = np.argsort(-cnt[1:]) + 1
            keep = np.zeros(n + 1, bool)
            tot = 0
            for k in order:
                if tot + cnt[k] > cap:
                    continue
                keep[k] = True
                tot += cnt[k]
            drop = is_acc & ~keep[lab8]
            fallback(drop)
    return q, alpha


def label8(mask):
    """8-connected components (flood fill; layers are small)."""
    H, W = mask.shape
    lab = np.zeros((H, W), int)
    n = 0
    for y, x in zip(*np.nonzero(mask)):
        if lab[y, x]:
            continue
        n += 1
        stack = [(y, x)]
        lab[y, x] = n
        while stack:
            cy, cx = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = cy + dy, cx + dx
                    if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n
                        stack.append((yy, xx))
    return lab, n


def accent_stats(img, pal):
    """(accent fraction of opaque px, smallest accent island) for the --check / review."""
    names, prgb = palette(pal)
    a = np.asarray(img.convert("RGBA"))
    op = a[..., 3] > 0
    m = np.zeros(op.shape, bool)
    for k, n_ in enumerate(names):
        if n_ in ACCENT_NAMES:
            m |= (a[..., :3] == prgb[k].astype(np.uint8)).all(-1)
    m &= op
    lab8, n = label8(m)
    smallest = int(np.bincount(lab8.ravel())[1:].min()) if n else 0
    return float(m.sum() / max(1, op.sum())), smallest


# uc_far_cistern: break the 4x repeated tower (heights +-12 px, one mirrored), 2-step vertical falloff on the
# tower bodies, bottom 30 px dithered into the far colour so the band dissolves into fog band A.
UC_TOWERS = [(30, 73, -8, False), (141, 187, 6, False), (255, 301, -12, False), (369, 417, 3, True)]  # x0, x1, dh (+ = taller), mirror
UC_ROOF = 62  # rows above this are tower bodies / sky only


def uc_far_pre(rgb, cov):
    rgb, cov = rgb.copy(), cov.copy()
    R = UC_ROOF
    for x0, x1, dh, mirror in UC_TOWERS:
        seg_rgb = rgb[:R, x0:x1].copy()
        seg_cov = cov[:R, x0:x1].copy()
        if mirror:
            seg_rgb, seg_cov = seg_rgb[:, ::-1], seg_cov[:, ::-1]
        out_rgb = np.zeros_like(seg_rgb)
        out_cov = np.zeros_like(seg_cov)
        for cx in range(seg_rgb.shape[1]):
            col = seg_cov[:, cx] > 0.5
            if not col.any():
                continue
            t0 = int(np.argmax(col))
            t1 = int(np.clip(t0 - dh, 1, R - 4))
            for y in range(t1, R):
                sy = R - (R - y) * (R - t0) / max(1, (R - t1))
                sy = int(np.clip(round(sy), 0, R - 1))
                out_rgb[y, cx] = seg_rgb[sy, cx]
                out_cov[y, cx] = seg_cov[sy, cx]
        rgb[:R, x0:x1] = out_rgb
        cov[:R, x0:x1] = out_cov
    return rgb, cov


def uc_far_falloff(t, alpha):
    lab = srgb_to_lab(t)
    R = UC_ROOF
    for x0, x1, dh, mirror in UC_TOWERS:
        sub = alpha[:R, x0:x1]
        if not sub.any():
            continue
        top = int(np.argmax(sub.any(1)))
        for y in range(top, R):
            u = (y - top) / max(1, R - top)
            lab[y, x0:x1, 0] += np.where(sub[y], 2.6 * (1 - u) - 2.6 * u, 0)  # lighter at the top, darker to the fog line
    return lab_to_srgb(lab)


def uc_far_post(q, alpha, names, prgb, t, allowed):
    far = prgb[names.index("far")].astype(np.uint8)
    H, W = alpha.shape
    band = 30
    B8 = np.array([[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26], [12, 44, 4, 36, 14, 46, 6, 38],
                   [60, 28, 52, 20, 62, 30, 54, 22], [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
                   [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]) / 64.0
    for y in range(H - band, H):
        p = (y - (H - band) + 1) / band
        row = (B8[y % 8][np.arange(W) % 8] < p) & alpha[y]
        q[y, row] = far
    return accent_hygiene(q, alpha, names, prgb, t, allowed)  # after the dither, so it cannot split clusters


# ---------------------------------------------------------------- recipes
# L ranges from the ART_DIRECTION value ladder (slightly widened at the top so
# rim light survives). allowed_max_L filters the palette for the layer.
# T02: every `out` below is the file-contract name that the code-painted layer
# (paint_env.py) also writes, at the contract size. Dropping a raw download into
# art/source/raw/<id>.png makes env_process own that file (paint_env.py then leaves the
# item alone), so an AI layer replaces a painted one with no code change. An AI layer
# must still pass paint_env.py --check (value ladder, character contrast) to ship.

RECIPES = {
    # id: dict(mode, palette, size, colors, L=(lo,hi), accents=[names], out)
    # AD redo: baked rain streaks suppressed (runtime rain front layer owns rain); L widened to 3-14
    "title_sky": dict(mode="sky", pal="title", size=(480, 270), colors=20, L=(3, 14),
                      out="title/title_sky.png", dither=4.0, derain=True, derain_passes=2,
                      break_boost=(98.8, 99.9), allow_hi=33, p_hi=96),
    "uc_sky_vault": dict(mode="sky", pal="uc_env", size=(480, 270), colors=20, L=(2, 10),
                         out="undercity/uc_sky_vault.png", dither=5.0),
    "ll_sky_night": dict(mode="sky", pal="ll_env", size=(480, 270), colors=20, L=(2, 10),
                         out="lowlight/ll_sky_night.png", dither=5.0),
    "ll_sky_storm": dict(mode="sky", pal="ll_env", size=(480, 270), colors=20, L=(2, 12),
                         out="lowlight/ll_sky_storm.png", dither=5.0),
    "uc_boss_bay": dict(mode="sky", pal="uc_env", size=(480, 270), colors=20, L=(3, 16),
                        out="undercity/uc_boss_bay.png", dither=3.0),
    "title_far_spires": dict(mode="band", pal="title", h=160, colors=12, L=(5, 14),
                             accents=["window_warm_far", "window_cold", "window_rose"],
                             out="title/title_far_spires.png", tile=True),
    "title_mid_rooftops": dict(mode="band", pal="title", h=150, colors=14, L=(4, 20),
                               accents=["window_warm", "window_warm_far", "window_cold", "rim"],
                               out="title/title_mid_rooftops.png", tile=True),
    "title_near_ledge": dict(mode="band", pal="title", h=120, w=200, colors=10, L=(2, 18),
                             accents=["rim"], out="title/title_near_ledge.png", tile=False),
    "uc_far_cistern": dict(mode="band", pal="uc_env", h=200, colors=10, L=(5, 15),
                           accents=["sea_dim"], out="undercity/uc_far.png", tile=True,
                           pre=lambda rgb, cov: uc_far_pre(rgb, cov), post_remap=lambda t, a: uc_far_falloff(t, a),
                           post=lambda *a: uc_far_post(*a)),
    "uc_mid_pipeworks": dict(mode="band", pal="uc_env", h=180, colors=16, L=(8, 18),
                             accents=["sodium_dim", "sodium", "water_glint"],
                             out="undercity/uc_mid_pipeworks.png", tile=True),
    "uc_near_columns": dict(mode="band", pal="uc_env", h=220, colors=14, L=(10, 18),
                            accents=["water_glint"], out="undercity/uc_near_columns.png", tile=True),
    "uc_shaft_near": dict(mode="band", pal="uc_env", h=270, colors=14, L=(8, 18),
                          out="undercity/uc_shaft_near.png", tile=True, tile_y=True),
    "uc_backwall_ward": dict(mode="wall", pal="uc_env", h=270, colors=14, L=(4, 20),
                             out="undercity/uc_backwall_ward.png", tile=True),
    "uc_tunnel_mid": dict(mode="band", pal="uc_env", h=160, colors=14, L=(8, 18),
                          accents=["water_glint"], out="undercity/uc_tunnel_mid.png", tile=True),
    "ll_far_skyline": dict(mode="band", pal="ll_env", h=160, colors=10, L=(5, 12),
                           accents=["window_warm_far", "window_cold_far"],
                           out="lowlight/ll_far_skyline.png", tile=True),
    "ll_mid_blocks": dict(mode="band", pal="ll_env", h=190, colors=16, L=(8, 18),
                          accents=["window_warm", "window_warm_far", "window_cold", "window_rose"],
                          out="lowlight/ll_mid_blocks.png", tile=True),
    "ll_mid_roofs": dict(mode="band", pal="ll_env", h=150, colors=16, L=(8, 18),
                         accents=["window_warm_far", "window_cold_far", "window_rose"],
                         out="lowlight/ll_mid_roofs.png", tile=True),
    "ll_near_street": dict(mode="band", pal="ll_env", h=200, colors=16, L=(10, 18),
                           accents=["sodium_street", "window_warm", "wet_hi"],
                           out="lowlight/ll_near_street.png", tile=True),
    "ll_canal_mid": dict(mode="band", pal="ll_env", h=150, colors=14, L=(8, 18),
                         accents=["violet_muted", "window_warm_far"],
                         out="lowlight/ll_canal_mid.png", tile=True),
    "ll_tower_near": dict(mode="band", pal="ll_env", h=270, colors=14, L=(8, 18),
                          accents=["window_warm"], out="lowlight/ll_tower_near.png",
                          tile=True, tile_y=True),
    "ll_backwall_interior": dict(mode="wall", pal="ll_env", h=270, colors=14, L=(4, 20),
                                 out="lowlight/ll_backwall_interior.png", tile=True),
    "ll_far_bell_tower": dict(mode="band", pal="ll_env", h=160, w=64, colors=10, L=(5, 14),
                              accents=["window_warm_far"], out="lowlight/ll_far_bell_tower.png", tile=False),
    "relay_backwall": dict(mode="wall", pal="relay_env", h=270, colors=18, L=(4, 20),
                           accents=["lamp_core", "lamp_warm"], out="relay/relay_backwall.png", tile=True),
    "relay_mid_concourse": dict(mode="band", pal="relay_env", h=180, colors=16, L=(7, 18),
                                accents=["lamp_core", "lamp_warm", "lamp_spill"],
                                out="relay/relay_mid_concourse.png", tile=True),
    "null_far_strata": dict(mode="band", pal="null_env", h=200, colors=6, L=(1, 12),
                            out="null/null_far_strata.png", tile=True),
    "pit_rig_near": dict(mode="band", pal="ll_env", h=200, colors=14, L=(8, 18),
                         out="challenge/pit_rig_near.png", tile=True),
    # tilesets: ramp = 3 face values darkest->lightest, edge = top highlight (T02 targets:
    # face L* 24-30, edge 45-55; Lowlight uses "oneway", the edge colour's family at L* 46.8)
    "uc_tiles": dict(mode="swatch", pal="uc_env", ramp=["concrete_1", "concrete_2", "concrete_3"],
                     extra=["algae_0", "rust_1"], edge="edge", under="void", out="undercity/uc_tiles.png"),
    "ll_tiles": dict(mode="swatch", pal="ll_env", ramp=["concrete_2", "brick_2", "concrete_3"],
                     extra=["brick_1", "metal_1"], edge="oneway", under="sky_top", out="lowlight/ll_tiles.png"),
    "ll_roof_tiles": dict(mode="swatch", pal="ll_env", ramp=["metal_0", "concrete_1", "concrete_2"],
                          extra=["puddle_1", "brick_0"], edge="wet_hi", under="sky_top",
                          out="lowlight/ll_roof_tiles.png"),
    "relay_tiles": dict(mode="swatch", pal="relay_env", ramp=["wood_0", "wood_1", "wood_2"],
                        extra=["stone_1", "brass"], edge="edge", under="sky_top", out="relay/relay_tiles.png"),
}
# prop / silhouette sheets: target box, palette, colour cap. `atlas` (T02) = the contract
# file the painted set also writes; the AI sheet's atlas replaces it there.
SHEETS = {
    "uc_props": dict(pal="uc_env", box=(32, 48), colors=14, out="undercity/props"),
    "ll_props": dict(pal="ll_env", box=(32, 48), colors=14, out="lowlight/props"),
    "relay_props": dict(pal="relay_env", box=(48, 48), colors=16, out="relay/props"),
    "ll_neon_plates": dict(pal="ll_env", box=(32, 12), colors=6, out="lowlight/neon", neon=True),
    "interact_anchor": dict(pal="uc_env", box=(32, 48), colors=12, out="props/anchor"),
    "interact_grid": dict(pal="ll_env", box=(32, 64), colors=12, out="props/grid"),
    "interact_misc": dict(pal="ll_env", box=(32, 48), colors=12, out="props/misc"),
    "uc_landmarks": dict(pal="uc_env", box=(128, 128), colors=16, out="undercity/landmarks"),
    "ll_landmarks": dict(pal="ll_env", box=(128, 128), colors=16, out="lowlight/landmarks"),
    "ll_train_far": dict(pal="ll_env", box=(160, 16), colors=8, out="lowlight/train", L=(5, 18),
                         atlas="lowlight/ll_train_far.png"),
    "uc_fg_silhouettes": dict(pal="uc_env", box=(160, 120), colors=3, out="undercity/fg",
                              fg=["void", "vault", "fog_dark"], atlas="undercity/uc_fg_set.png"),
    "ll_fg_silhouettes": dict(pal="ll_env", box=(160, 120), colors=3, out="lowlight/fg",
                              fg=["sky_top", "sky_1", "fog_dark"], atlas="lowlight/ll_fg_set.png"),
    "relay_fg": dict(pal="relay_env", box=(160, 120), colors=3, out="relay/fg",
                     fg=["sky_top", "sky_bottom", "lamp_spill"], atlas="relay/relay_fg_set.png"),
}


def raw_path(i):
    for ext in (".png", ".webp", ".jpg"):
        p = os.path.join(RAW, i + ext)
        if os.path.exists(p):
            return p
    return None


def save(img, rel):
    # swatches are source material (art/source/swatches), never game files
    p = os.path.join(SOURCE_OUT, "swatches", os.path.basename(rel)) if rel.endswith("_swatch.png") else os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, optimize=True)
    # x3 nearest review copy in tools/assetgen/_preview
    rv = os.path.join(PREVIEW, rel.replace("/", "__"))
    os.makedirs(os.path.dirname(rv), exist_ok=True)
    img.resize((img.width * 3, img.height * 3), Image.NEAREST).save(rv)
    return p


def accent_setup(names, rgb, r, src_rgb, valid):
    if not r.get("accents"):
        return None, None
    acc = [names.index(a) for a in r["accents"]]
    # accents only where the source is a local highlight (lamp, window, glint):
    # brighter than its 9x9 neighbourhood by 10 L* and in the top 3 %
    L = srgb_to_lab(src_rgb)[..., 0]
    k = 4
    P = np.pad(L, k, mode="edge")
    c = P.cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    n = 2 * k + 1
    loc = (c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]) / (n * n)
    thr = np.percentile(L[valid], 97) if valid.any() else 100
    return acc, (L >= thr) & (L - loc > 10) & valid


def derain(src, angles=range(-40, -19, 2), thr=2.5, half=4, side=3):
    """AD redo: suppress thin baked rain streaks before quantizing (the title has a runtime rain layer).
    Finds the dominant streak angle, marks pixels whose mean along that line is brighter than the
    mean of the parallel lines +-side px away, dilates the mask 1 px and fills it from those sides."""
    L = srgb_to_lab(src)[..., 0]
    H, W = L.shape
    yy, xx = np.mgrid[0:H, 0:W]

    def samp(arr, dx, dy):
        ys = np.clip(np.round(yy + dy).astype(int), 0, H - 1)
        xs = np.clip(np.round(xx + dx).astype(int), 0, W - 1)
        return arr[ys, xs]

    best = None
    for ang in angles:
        a = np.radians(ang)
        ux, uy = np.sin(a), np.cos(a)
        px, py = uy, -ux
        A = np.mean([samp(L, ux * k, uy * k) for k in range(-half, half + 1)], 0)
        S1 = np.mean([samp(L, ux * k + px * side, uy * k + py * side) for k in range(-half, half + 1)], 0)
        S2 = np.mean([samp(L, ux * k - px * side, uy * k - py * side) for k in range(-half, half + 1)], 0)
        r = A - 0.5 * (S1 + S2)
        score = np.sort(r.ravel())[-2000:].mean()
        if best is None or score > best[0]:
            best = (score, ang, r, (ux, uy, px, py))
    _, ang, r, (ux, uy, px, py) = best
    side_mean = 0.5 * (samp(L, px * side, py * side) + samp(L, -px * side, -py * side))
    m = (r > thr) & (L - side_mean > thr)
    m = m | np.roll(m, 1, 1) | np.roll(m, -1, 1)
    fill = np.zeros_like(src)
    for c in range(3):
        fill[..., c] = 0.5 * (samp(src[..., c], px * side, py * side) + samp(src[..., c], -px * side, -py * side))
    out = src.copy()
    out[m] = fill[m]
    return out, m, ang


def run_sky(i, r):
    names, prgb = palette(r["pal"])
    img = centre_crop_169(Image.open(raw_path(i)))
    src = box(img, r["size"])
    if r.get("derain"):
        src, m, ang = derain(src)
        for _ in range(r.get("derain_passes", 1) - 1):
            src, m2, _ = derain(src)
            m |= m2
        print(f"  derain: streak angle {ang} deg, {int(m.sum())} px suppressed")
    valid = np.ones(src.shape[:2], bool)
    lo, hi = r["L"]
    allowed = [k for k, L in enumerate(lum(prgb)) if L <= r.get("allow_hi", hi + 8)]
    t = remap_lightness(src, valid, lo, hi, p_hi=r.get("p_hi", 99.3))
    if r.get("break_boost"):
        # the pale cloud break (logo backdrop) gains one extra step: its brightest core lifts past cloud_1
        # toward moon_haze, the rim just around it to cloud_1; everything else stays in the 3-14 ladder
        Ls = srgb_to_lab(src)[..., 0]
        p1, p2 = np.percentile(Ls, r["break_boost"][0]), np.percentile(Ls, r["break_boost"][1])
        lab = srgb_to_lab(t)
        u = np.clip((Ls - p1) / max(p2 - p1, 1e-3), 0, 1)
        lab[..., 0] = np.where(Ls >= p1, np.maximum(lab[..., 0], 17 + 11 * u), lab[..., 0])
        t = lab_to_srgb(lab)
    q, _ = quantize(t, valid, prgb, r["colors"], dither=r.get("dither", 0), allowed=allowed)
    return save(Image.fromarray(q, "RGB"), r["out"])


def run_band(i, r):
    names, prgb = palette(r["pal"])
    img = Image.open(raw_path(i)).convert("RGB")
    W = r.get("w", 480)
    H = int(round(img.height * W / img.width))
    if r["mode"] == "wall":
        mask = np.ones((img.height, img.width), bool)
    else:
        mask = key_mask(img)
    rgb, cov = premult_downscale(img, mask, (W, H))
    # crop to band height: keep the bottom of the content
    h = min(r["h"], H)
    rows = np.where((cov > 0.5).any(1))[0]
    top_c = rows.min() if len(rows) else 0
    bottom = (rows.max() + 1) if len(rows) else H
    if r.get("anchor", "top") == "top" and bottom - top_c > h:
        y0 = max(0, top_c - 2)          # keep skyline tops, lose the lowest rows
        y1 = min(H, y0 + h); y0 = y1 - h
    else:
        y1 = max(h, min(H, bottom))
        y0 = y1 - h
    rgb, cov = rgb[y0:y1], cov[y0:y1]
    if r.get("pre"):
        rgb, cov = r["pre"](rgb, cov)
    if h < r["h"]:  # pad top (transparent) if source band shorter
        pad = r["h"] - h
        rgb = np.concatenate([np.zeros((pad, W, 3)), rgb])
        cov = np.concatenate([np.zeros((pad, W)), cov])
    if r.get("tile"):
        rgb = seam_x(rgb * cov[..., None])
        cov = seam_x(cov[..., None])[..., 0]
        rgb = rgb / np.maximum(cov, 1e-6)[..., None]
    if r.get("tile_y"):
        rgb = seam_y(rgb * cov[..., None])
        cov = seam_y(cov[..., None])[..., 0]
        rgb = rgb / np.maximum(cov, 1e-6)[..., None]
    alpha = cov > 0.5
    if r["mode"] != "wall":
        alpha = remove_islands(alpha, 4)
    lo, hi = r["L"]
    allowed = [k for k, L in enumerate(lum(prgb)) if L <= hi + 6 and names[k] not in (r.get("accents") or [])]
    t = remap_lightness(rgb, alpha, lo, hi, chroma=0.9)
    if r.get("post_remap"):
        t = r["post_remap"](t, alpha)
    acc, am = accent_setup(names, prgb, r, rgb, alpha)
    q, _ = quantize(t, alpha, prgb, r["colors"], allowed=allowed, accents=acc,
                    accent_src=rgb, accent_mask=am)
    # AD redo: every band/wall layer goes through accent hygiene (islands >= 3 px, accents <= 2 %)
    q, alpha = (r.get("post") or accent_hygiene)(q, alpha, names, prgb, t, allowed)
    img = Image.fromarray(q, "RGB") if r["mode"] == "wall" else to_rgba(q, alpha)
    return save(img, r["out"])


# ---------------------------------------------------------------- tiles
T = 16


def make_swatch(i, r):
    names, prgb = palette(r["pal"])
    img = Image.open(raw_path(i)).convert("RGB")
    s = min(img.size)
    img = img.crop(((img.width - s) // 2, (img.height - s) // 2, (img.width + s) // 2, (img.height + s) // 2))
    src = box(img, (160, 160))
    # make it wrap: cross-fade 32 px both axes then keep 128
    src = seam_x(src, 32)[:, 16:144]
    src = seam_y(src, 32)[16:144]
    idx = [names.index(n) for n in r["ramp"] + r.get("extra", [])]
    ramp = [names.index(n) for n in r["ramp"]]
    valid = np.ones(src.shape[:2], bool)
    lo, hi = lum(prgb[ramp[0]]) - 2, lum(prgb[ramp[-1]]) + 2
    t = remap_lightness(src, valid, lo, hi, p_lo=3, p_hi=97)
    q, qi = quantize(t, valid, prgb, len(idx), allowed=idx)
    return names, prgb, q, qi


def run_swatch(i, r):
    names, prgb, sw, qi = make_swatch(i, r)
    return build_atlas(names, prgb, sw, r)


def build_atlas(names, prgb, sw, r):
    edge = prgb[names.index(r["edge"])].astype(np.uint8)
    light = prgb[names.index(r["ramp"][2])].astype(np.uint8)
    dark = prgb[names.index(r["ramp"][0])].astype(np.uint8)
    under = prgb[names.index(r["under"])].astype(np.uint8)

    def fill(k):
        x = (k * 37) % 112
        y = (k * 53) % 112
        return sw[y:y + T, x:x + T].copy()

    def top(t, left=False, right=False):
        t[0, :] = edge
        t[1, :] = light
        if left:
            t[:, 0] = dark; t[0, 0] = light
        if right:
            t[:, -1] = dark; t[0, -1] = light
        return t

    def bottom(t, left=False, right=False):
        t[-1, :] = under
        t[-2, :] = dark
        if left:
            t[:, 0] = dark
        if right:
            t[:, -1] = dark
        return t

    def side(t, left=False, right=False):
        if left:
            t[:, 0] = dark
        if right:
            t[:, -1] = dark
        return t

    tiles, layout = [], []

    def add(name, t):
        layout.append(name); tiles.append(t)

    k = 0
    def nf():
        nonlocal k
        k += 1
        return fill(k)
    # row 0: tops
    add("top_L", top(nf(), left=True)); add("top_M", top(nf())); add("top_R", top(nf(), right=True))
    add("top_single", top(nf(), True, True))
    add("wall_L", side(nf(), left=True)); add("wall_R", side(nf(), right=True))
    t = nf(); t[0, 0] = edge; t[1, 0] = light; add("inner_TL", t)
    t = nf(); t[0, -1] = edge; t[1, -1] = light; add("inner_TR", t)
    # row 1: fills + undersides
    for j in range(4):
        add("fill_%d" % j, nf())
    add("under_L", bottom(nf(), left=True)); add("under_M", bottom(nf())); add("under_R", bottom(nf(), right=True))
    add("under_single", bottom(nf(), True, True))
    # row 2: one-way platforms (4 px thick slab on top, transparent below) + column + block
    def oneway(left=False, right=False):
        t = np.zeros((T, T, 4), np.uint8)
        f = nf()
        t[:5, :, :3] = f[:5]; t[:5, :, 3] = 255
        t[0, :, :3] = edge; t[1, :, :3] = light; t[4, :, :3] = dark
        if left:
            t[:5, 0, :3] = dark; t[0, 0, :3] = light
        if right:
            t[:5, -1, :3] = dark; t[0, -1, :3] = light
        return t
    add("oneway_L", oneway(left=True)); add("oneway_M", oneway()); add("oneway_R", oneway(right=True))
    add("oneway_single", oneway(True, True))
    add("col_top", top(nf(), True, True)); add("col_mid", side(nf(), True, True))
    add("col_bottom", bottom(nf(), True, True))
    t = bottom(top(nf(), True, True), True, True); add("block_single", t)
    # row 3: faces under top (lit band) + inner bottom corners + wall bottoms
    for j in range(4):
        t = nf(); t[0, :] = light; add("face_%d" % j, t)
    t = nf(); t[-1, 0] = dark; add("inner_BL", t)
    t = nf(); t[-1, -1] = dark; add("inner_BR", t)
    add("wall_L_bottom", bottom(nf(), left=True)); add("wall_R_bottom", bottom(nf(), right=True))
    # rows 4-5: 16 more fill variants
    for j in range(4, 20):
        add("fill_%d" % j, nf())
    atlas = np.zeros((96, 128, 4), np.uint8)
    for n, t in enumerate(tiles):
        y, x = (n // 8) * T, (n % 8) * T
        if t.shape[-1] == 3:
            t = np.concatenate([t, np.full((T, T, 1), 255, np.uint8)], -1)
        atlas[y:y + T, x:x + T] = t
    p = save(Image.fromarray(atlas, "RGBA"), r["out"])
    save(Image.fromarray(sw.astype(np.uint8), "RGB"), r["out"].replace(".png", "_swatch.png"))
    meta = {"tile": T, "cols": 8, "rows": 6, "names": layout,
            "note": "row-major index; one-way tiles are 5 px slabs with transparent lower part"}
    json.dump(meta, open(p.replace(".png", ".json"), "w"), indent=1)
    return p


# ---------------------------------------------------------------- sheets

def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def run_sheet(i, s, factor=None, min_area_frac=0.002, merge=6):
    names, prgb = palette(s["pal"])
    img = Image.open(raw_path(i)).convert("RGB")
    full = key_mask(img)
    # work on a 1/4 grid to find objects fast
    sw, sh = img.width // 4, img.height // 4
    _, c4 = premult_downscale(img, full, (sw, sh))
    m4 = dilate(c4 > 0.3, merge // 2 or 1)
    lab, n = label(m4)
    objs = []
    for k in range(1, n + 1):
        ys, xs = np.where(lab == k)
        if len(ys) < min_area_frac * sw * sh:
            continue
        objs.append((ys.min() * 4, xs.min() * 4, (ys.max() + 1) * 4, (xs.max() + 1) * 4))
    objs.sort(key=lambda b: (b[0] // 120, b[1]))
    if factor is None:
        # one common factor so relative scale survives; biggest object fits box*1.0
        bw, bh = s["box"]
        factor = max(max((b[3] - b[1]) / bw, (b[2] - b[0]) / bh) for b in objs)
        factor = max(factor, 2.5)
    outdir = s["out"]
    meta, sprites = [], []
    for j, (y0, x0, y1, x1) in enumerate(objs):
        crop = img.crop((x0, y0, x1, y1))
        cm = full[y0:y1, x0:x1]
        tw = max(1, int(round((x1 - x0) / factor)))
        th = max(1, int(round((y1 - y0) / factor)))
        rgb, cov = premult_downscale(crop, cm, (tw, th))
        alpha = remove_islands(cov > 0.5, 3)
        if not alpha.any():
            continue
        ys, xs = np.where(alpha)
        rgb, alpha = rgb[ys.min():ys.max() + 1, xs.min():xs.max() + 1], alpha[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        if s.get("fg"):
            allowed = [names.index(n) for n in s["fg"]]
            L = srgb_to_lab(rgb)[..., 0]
            q = np.zeros(rgb.shape, np.uint8)
            q[:] = prgb[allowed[0]]
            # rim: top-most opaque pixel of each column and bright source pixels
            thr = np.percentile(L[alpha], 85) if alpha.any() else 100
            q[(L >= thr) & alpha] = prgb[allowed[1]]
            top = alpha & ~np.vstack([np.zeros((1, alpha.shape[1]), bool), alpha[:-1]])
            q[top] = prgb[allowed[2]]
        elif s.get("neon"):
            # white tube mask where source is bright/unsaturated-white, backing = metal
            L = srgb_to_lab(rgb)[..., 0]
            q = np.zeros(rgb.shape, np.uint8)
            metal = [names.index(n) for n in ("metal_0", "metal_1", "metal_2")]
            qq, _ = quantize(remap_lightness(rgb, alpha, 8, 34), alpha, prgb, 3, allowed=metal)
            q[:] = qq
            tube = alpha & (L > np.percentile(L[alpha], 70))
            q[tube] = (255, 255, 255)
        else:
            lo, hi = s.get("L", (8, 55))
            t = remap_lightness(rgb, alpha, lo, hi, chroma=1.0)
            q, _ = quantize(t, alpha, prgb, s["colors"])
            # 1 px top-edge highlight from the palette edge colour
            if "edge" in names:
                top = alpha & ~np.vstack([np.zeros((1, alpha.shape[1]), bool), alpha[:-1]])
                q[top] = prgb[names.index("edge")]
        spr = to_rgba(q, alpha)
        rel = "%s/%s_%02d.png" % (outdir, i, j)
        save(spr, rel)
        sprites.append(spr)
        meta.append({"file": os.path.basename(rel), "w": spr.width, "h": spr.height,
                     "origin": [spr.width // 2, spr.height], "src_box": [int(x0), int(y0), int(x1), int(y1)]})
    # atlas: simple shelf pack, 1 px gap
    AW = max(256, max(sp.width for sp in sprites) + 2)
    x = y = rowh = 0
    pos = []
    for sp in sprites:
        if x + sp.width > AW:
            x, y, rowh = 0, y + rowh + 1, 0
        pos.append((x, y)); x += sp.width + 1; rowh = max(rowh, sp.height)
    atlas = Image.new("RGBA", (AW, y + rowh), (0, 0, 0, 0))
    for sp, (px, py), m in zip(sprites, pos, meta):
        atlas.paste(sp, (px, py)); m["atlas_xy"] = [px, py]
    if s.get("atlas"):
        # T02 file contract: the atlas replaces the painted set of the same name (paint_env.py)
        p = save(atlas, s["atlas"])
        regions = [{"name": "%s_%02d" % (i, k), "rect": m["atlas_xy"] + [m["w"], m["h"]],
                    "anchor": "bottom", "origin": [m["w"] // 2, m["h"]]} for k, m in enumerate(meta)]
        json.dump({"regions": regions, "palette": s["pal"], "note": "AI sheet %s (env_process.py)" % i},
                  open(p.replace(".png", ".json"), "w"), indent=1)
        return p
    p = save(atlas, "%s/%s_atlas.png" % (outdir, i))
    json.dump({"factor": factor, "sprites": meta}, open(p.replace(".png", ".json"), "w"), indent=1)
    return p


def process(i):
    if raw_path(i) is None:
        return None
    if i in SHEETS:
        return run_sheet(i, SHEETS[i])
    r = RECIPES[i]
    if r["mode"] == "sky":
        return run_sky(i, r)
    if r["mode"] in ("band", "wall"):
        return run_band(i, r)
    if r["mode"] == "swatch":
        return run_swatch(i, r)


def check():
    reserved = np.array([hex2rgb(h) for h in PAL["reserved"].values()], float)
    bad = 0
    for dp, _, fs in os.walk(OUT):
        for f in fs:
            if not f.endswith(".png"):
                continue
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, OUT)
            # scope: env outputs only (char sheets carry the sanctioned Redline red; vfx textures are soft by design)
            outs = {r["out"] for r in RECIPES.values()}
            outs |= {r["out"].replace(".png", "_swatch.png") for r in RECIPES.values()}
            dirs = tuple(sv["out"] + "/" for sv in SHEETS.values()) + ("null/",)
            if not (rel in outs or rel.startswith(dirs)):
                continue
            a = np.asarray(Image.open(p).convert("RGBA"))
            al = a[..., 3]
            if not np.isin(al, (0, 255)).all():
                print("SOFT ALPHA", p); bad += 1
            cols = np.unique(a[al == 255][:, :3], axis=0).astype(float)
            if len(cols):
                d = np.sqrt(((cols[:, None] - reserved[None]) ** 2).sum(-1)).min()
                if d < 48 and "neon" not in p:
                    print("RESERVED-NEAR", p, d); bad += 1
    # AD redo: accent hygiene on every band layer present (islands >= 3 px, accents <= 2 %)
    for i, r in RECIPES.items():
        p = os.path.join(OUT, r["out"])
        if r["mode"] in ("band", "wall") and os.path.exists(p):
            frac, smallest = accent_stats(Image.open(p), r["pal"])
            if frac > 0.02 + 1e-9 or (smallest and smallest < 3):
                print("ACCENT", r["out"], "frac %.3f smallest island %d" % (frac, smallest)); bad += 1
    print("check:", "OK" if not bad else "%d problems" % bad)
    return bad


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--check" in args:
        sys.exit(1 if check() else 0)
    ids = list(RECIPES) + list(SHEETS) if "--all" in args else args
    for i in ids:
        p = process(i)
        if p:
            print(i, "->", os.path.relpath(p, REDLINE))
