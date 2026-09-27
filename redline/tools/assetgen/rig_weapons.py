"""Rook's five weapons as 24x12 side-view sprites (origin bottom-centre) + a 120x12 atlas.
Out: assets/rook/weapons/weapon_<id>.png, assets/rook/weapons/weapons_atlas.png
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, Frame, preview, check_sheet  # noqa
from PIL import Image
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

ROOT = REDLINE
PAL = json.load(open(os.path.join(DATA, "palettes.json")))
C = PAL["palettes"]["char_rook"]["colors"]
W, H = 24, 12
STEEL = [C["metal_0"], C["metal_1"], C["blade_edge"]]
DARK = [C["suit_0"], C["suit_1"], C["suit_2"]]
GRIP = [C["strap_0"], C["strap_1"]]


def blade():
    f = Frame(W, H)
    f.part(Layer(W, H).poly([(8, 5), (22.5, 4.5), (23.5, 6), (8, 8)]), STEEL, light=1, shade=1)
    f.part(Layer(W, H).rect(9, 6, 20, 7), [C["metal_0"]], light=0, shade=0)  # hollow channel
    f.part(Layer(W, H).rect(6, 3, 8, 10), [C["metal_0"], C["metal_1"]], light=1)  # guard
    f.part(Layer(W, H).rect(1, 5, 6, 8), GRIP, light=1)
    f.px((0.5, 6), C["metal_1"])
    return f


def _katar_px(f, gx, gy, dx, dy, back=False):
    """One punch-dagger drawn pixel by pixel along a unit diagonal (dx, dy):
    3 px dark grip (with a 1 px cross-guard), then a 5 px steel blade with a #e6e2ee top edge."""
    grip = C["suit_0"] if back else C["suit_1"]
    for k in range(3):
        f.px((gx + dx * k, gy + dy * k), grip)
    # side bars of the H-grip (katars are gripped crosswise)
    f.px((gx + dx * 2 - dy, gy + dy * 2 + dx), C["metal_0"])
    f.px((gx + dx * 2 + dy, gy + dy * 2 - dx), C["metal_0"])
    for k in range(3, 8):
        body = C["metal_0"] if back else C["metal_1"]
        f.px((gx + dx * k, gy + dy * k), body)
        # 1 px bright edge on the upper side of the blade, tapering to the tip
        if k < 7:
            f.px((gx + dx * k + dy * 0 - (1 if dy >= 0 else 0) * 0, gy + dy * k - 1), C["blade_edge"] if not back else C["metal_1"])


def katars():
    # AD redo: two crossed punch-daggers that read at 24x12
    f = Frame(W, H)
    _katar_px(f, 8, 9, 1, -1, back=True)   # rear dagger, rising
    _katar_px(f, 8, 2, 1, 1)               # front dagger, falling (crosses the first)
    return f


def pistol():
    f = Frame(W, H)
    f.part(Layer(W, H).rect(6, 3, 18, 6), STEEL, light=1, shade=1)
    f.part(Layer(W, H).poly([(7, 5), (11, 5), (10, 11), (6, 11)]), GRIP + [C["strap_1"]], light=1)
    f.part(Layer(W, H).rect(11, 6, 13, 8), [C["metal_0"]], light=0, shade=0)
    return f


def scatter():
    f = Frame(W, H)
    f.part(Layer(W, H).rect(8, 3, 23, 5).rect(8, 5, 22, 7), STEEL, light=1, shade=1)
    f.part(Layer(W, H).poly([(1, 5), (9, 3), (9, 8), (2, 10)]), GRIP + [C["strap_1"]], light=1)
    f.part(Layer(W, H).rect(12, 7, 16, 8), [C["metal_0"]], light=0, shade=0)
    return f


def revolver():
    f = Frame(W, H)
    f.part(Layer(W, H).rect(9, 3, 24, 5), STEEL, light=1, shade=1)
    f.part(Layer(W, H).ellipse((9, 5.5), 2.6, 2.2), [C["metal_0"], C["metal_1"], C["metal_1"]], light=1)
    f.part(Layer(W, H).poly([(3, 5), (8, 5), (6, 11), (2, 11)]), GRIP + [C["strap_1"]], light=1)
    f.px((12, 3), C["blade_edge"])
    return f


# ------------------------------------------------------------------ 16x16 UI icons (AD redo)
IW = 16


def icon(kind):
    f = Frame(IW, IW)
    if kind == "pulse_blade":
        f.part(Layer(IW, IW).poly([(5, 10.5), (14.5, 1.0), (15.2, 1.8), (6.2, 11.8)]), STEEL, light=1, shade=1)
        f.part(Layer(IW, IW).capsule((3.2, 9.0), (7.0, 12.8), 0.8), [C["metal_0"], C["metal_1"]], light=1)
        f.part(Layer(IW, IW).capsule((1.6, 14.4), (4.8, 11.2), 1.0), GRIP, light=1)
    elif kind == "split_katars":
        for (x0, y0, x1, y1, ramp) in ((3, 13, 13, 3, [C["metal_0"], C["metal_0"], C["metal_1"]]), (3, 3, 13, 13, STEEL)):
            f.part(Layer(IW, IW).poly([(x0 + (x1 - x0) * 0.35 - 1.2, y0 + (y1 - y0) * 0.35), (x1, y1), (x0 + (x1 - x0) * 0.35 + 1.2, y0 + (y1 - y0) * 0.35)]), ramp, light=1)
            f.part(Layer(IW, IW).capsule((x0, y0), (x0 + (x1 - x0) * 0.3, y0 + (y1 - y0) * 0.3), 1.0), DARK, light=0)
    elif kind == "service_pistol":
        f.part(Layer(IW, IW).rect(3, 4, 14, 8), STEEL, light=1, shade=1)
        f.part(Layer(IW, IW).poly([(4, 7), (8, 7), (7, 14), (3, 14)]), GRIP + [C["strap_1"]], light=1)
        f.part(Layer(IW, IW).rect(8, 8, 10, 10), [C["metal_0"]], light=0, shade=0)
    elif kind == "scattergun":
        f.part(Layer(IW, IW).poly([(4, 8), (15, 3), (15.8, 5.4), (5, 10.6)]), STEEL, light=1, shade=1)
        f.part(Layer(IW, IW).poly([(0.5, 12), (5, 8), (6, 11), (1.5, 15)]), GRIP + [C["strap_1"]], light=1)
        f.part(Layer(IW, IW).capsule((8, 8.6), (11, 7.2), 0.8), [C["strap_0"]], light=0, shade=0)
    elif kind == "heavy_revolver":
        f.part(Layer(IW, IW).rect(6, 4, 16, 6), STEEL, light=1, shade=1)
        f.part(Layer(IW, IW).ellipse((6.5, 6.5), 2.8, 2.6), [C["metal_0"], C["metal_1"], C["metal_1"]], light=1)
        f.part(Layer(IW, IW).poly([(2, 7), (6, 7), (5, 14), (1, 14)]), GRIP + [C["strap_1"]], light=1)
        f.px((6, 6), C["metal_0"])
    f.outline(C["outline"])
    return f.image()


def to_mask(im):
    """White/grey UI mask (tones 255 / 176 / 96, like the rest of the UI kit) from a baked icon."""
    import numpy as np
    a = np.asarray(im.convert("RGBA")).copy()
    op = a[..., 3] == 255
    lum = a[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]
    t = np.where(lum >= 150, 255, np.where(lum >= 60, 176, 96)).astype(np.uint8)
    out = np.zeros_like(a)
    out[op, 0] = out[op, 1] = out[op, 2] = t[op]
    out[op, 3] = 255
    return Image.fromarray(out, "RGBA")


def main():
    out = os.path.join(ASSETS, "rook", "weapons")
    os.makedirs(out, exist_ok=True)
    items = [("pulse_blade", blade), ("split_katars", katars), ("service_pistol", pistol), ("scattergun", scatter), ("heavy_revolver", revolver)]
    # atlas: row 0 = 24x12 in-hand sprites; row 1 = 16x16 baked icons; row 2 = 16x16 white/grey masks
    atlas = Image.new("RGBA", (W * len(items), H + 2 * IW), (0, 0, 0, 0))
    regions = {}
    for k, (name, fn) in enumerate(items):
        f = fn()
        f.outline(C["outline"])
        im = f.image()
        im.save(os.path.join(out, f"weapon_{name}.png"), optimize=True)
        atlas.paste(im, (k * W, 0))
        ic = icon(name)
        mk = to_mask(ic)
        ic.save(os.path.join(out, f"weapon_icon_{name}.png"), optimize=True)
        mk.save(os.path.join(out, f"weapon_icon_{name}_mask.png"), optimize=True)
        atlas.paste(ic, (k * W, H))
        atlas.paste(mk, (k * W, H + IW))
        regions[name] = {"sprite": [k * W, 0, W, H], "icon": [k * W, H, IW, IW], "icon_mask": [k * W, H + IW, IW, IW]}
    atlas.save(os.path.join(out, "weapons_atlas.png"), optimize=True)
    json.dump({"id": "rook_weapons", "texture": "res://assets/rook/weapons/weapons_atlas.png", "regions": regions,
               "notes": "row 0: 24x12 side-view sprites (origin bottom-centre); row 1: 16x16 baked steel icons (pause/inventory); "
                        "row 2: 16x16 white/grey masks (255/176/96) tinted by UiTheme/Palette.color"},
              open(os.path.join(out, "weapons_atlas.json"), "w"), indent=1)
    preview(atlas, os.path.join(out, "weapons_atlas_x3.png"), scale=6)
    print(json.dumps(dict(id="rook_weapons", items=len(items), **check_sheet(atlas, list(PAL["reserved"].values())))))


if __name__ == "__main__":
    main()
