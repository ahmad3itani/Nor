"""fx_ui.py: code-authored UI kit, title wordmark, rank glyphs, icons and pickups (owner fx_ui).

Usage:  python3 tools/assetgen/fx_ui.py           build everything into assets/ui, assets/title, assets/props
        python3 tools/assetgen/fx_ui.py --check   rebuild in place + validate (assetgen.py --check rebuilds in a temp dir and diffs)

The ElevenLabs image quota was exhausted (429 free_tier_image_limit_reached), so
every piece here is drawn on the 1 px grid from ASCII art and small procedures.

Two kinds of pixels:
  * FRAME pixels are baked in the `ui` palette (panel / line_0..2 / text): steel
    filigree that UiTheme may modulate as a whole.
  * FILL pixels are grey MASKS (255/176/96) that code tints with
    Palette.color(accent / heal / ammo / scrap / memory ...), so colour-blind and
    high-contrast modes keep working. Where a piece needs both, there is a
    `*_fill.png` twin with the same layout; draw the frame, then the tinted fill.
Every atlas has a .json sidecar with regions {name: [x, y, w, h]} and frame lists.
"""
from __future__ import annotations

import math
import os
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fxlib import (MASK, OUT, PAL, bayer, check_png, cov_poly, preview, save, ui, write_json,  # noqa: E402
                   write_tres)
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

UI = os.path.join(OUT, "ui")
TITLE = os.path.join(OUT, "title")
PROPS = os.path.join(OUT, "props")
BUILT = {}

# character -> colour. Upper-case / symbols = baked ui palette; W/M/D = masks.
BAKED = {"C": ui("text"), "c": ui("line_2"), "o": ui("line_1"), "d": ui("line_0"), "p": ui("panel"),
         "h": ui("panel_hi"), "k": ui("bg")}
MASKC = {"W": MASK[3], "M": MASK[2], "D": MASK[1]}
ALLC = {**BAKED, **MASKC}
UI_ALLOWED = [ui(k) for k in PAL["palettes"]["ui"]["colors"] if k not in ("accent_redline",)] + list(MASK.values())


class Atlas:
    def __init__(self, w, h):
        self.img = np.zeros((h, w, 4), np.uint8)
        self.fill = np.zeros((h, w, 4), np.uint8)
        self.regions = {}

    def paint(self, x, y, rows, name=None, target="auto"):
        """rows: list of strings. '.'/' ' = transparent."""
        h = len(rows)
        w = max(len(r) for r in rows)
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch in ". ":
                    continue
                col = ALLC[ch]
                dst = self.fill if (target == "fill" or (target == "auto" and ch in MASKC)) else self.img
                dst[y + j, x + i, :3] = col
                dst[y + j, x + i, 3] = 255
        if name:
            self.regions[name] = [x, y, w, h]
        return w, h

    def blit(self, x, y, arr, name=None, fill=False):
        h, w = arr.shape[:2]
        dst = self.fill if fill else self.img
        sel = arr[..., 3] > 0
        dst[y:y + h, x:x + w][sel] = arr[sel]
        if name:
            self.regions[name] = [x, y, w, h]


def grid(w, h, ch="."):
    return [[ch] * w for _ in range(h)]


def rows_of(g):
    return ["".join(r) for r in g]


def emit_atlas(item_id, folder, name, atlas, meta, with_fill=True):
    os.makedirs(folder, exist_ok=True)
    files = []
    p = save(atlas.img, os.path.join(folder, name + ".png"))
    files.append(p)
    preview(p)
    if with_fill and atlas.fill[..., 3].any():
        pf = save(atlas.fill, os.path.join(folder, name + "_fill.png"))
        files.append(pf)
        preview(pf)
        # composite preview: fill tinted with a sample accent over the frame
        comp = atlas.img.copy()
        tint = np.array(meta.get("preview_tint", (232, 40, 60)), np.float32) / 255.0
        sel = atlas.fill[..., 3] > 0
        comp[sel, :3] = (atlas.fill[sel, :3].astype(np.float32) * tint).astype(np.uint8)
        comp[sel, 3] = 255
        pc = os.path.join(os.path.dirname(p), "_" + name + "_preview.png")
        Image.fromarray(comp, "RGBA").save(pc)
        preview(pc, tag=name + "_composite.png")
        os.remove(pc)
    js = os.path.join(folder, name + ".json")
    write_json(js, {"id": item_id, "texture": f"res://assets/{os.path.basename(folder)}/{name}.png",
                    "fill_texture": (f"res://assets/{os.path.basename(folder)}/{name}_fill.png" if len(files) > 1 else None),
                    "regions": atlas.regions, **{k: v for k, v in meta.items() if k != "preview_tint"}})
    files.append(js)
    BUILT.setdefault(item_id, []).extend(files)


# ====================================================================== HUD kit
PIP_FRAME = [
    "..CCc..",
    ".ccccc.",
    "..o.o..",
    ".o...o.",
    "o.....o",
    "o.....o",
    "o.....o",
    "o.....o",
    ".ooooo.",
]
PIP_FILL = [
    ".......",
    ".......",
    "...M...",
    "..WMM..",
    ".MWMMM.",
    ".MWMMM.",
    ".MMMMM.",
    ".DMMMD.",
    ".......",
]
PIP_EMPTY_RESIDUE = [(r, c) for r in (7,) for c in range(1, 6)]


def pip_cell(frame_rows=PIP_FRAME, fill_rows=PIP_FILL, dx=2, dy=2):
    fr = grid(11, 15)
    fl = grid(11, 15)
    for j, r in enumerate(frame_rows):
        for i, ch in enumerate(r):
            if ch != ".":
                fr[dy + j][dx + i] = ch
    if fill_rows:
        for j, r in enumerate(fill_rows):
            for i, ch in enumerate(r):
                if ch != ".":
                    fl[dy + j][dx + i] = ch
    return fr, fl


def build_hud():
    A = Atlas(160, 56)
    x = 0
    cells = {}

    def put_cell(name, fr, fl):
        nonlocal x
        A.paint(x, 0, rows_of(fr), target="frame")
        A.paint(x, 0, rows_of(fl), target="fill")
        A.regions[name] = [x, 0, 11, 15]
        cells.setdefault(name.rsplit("_", 1)[0] if name[-1].isdigit() else name, []).append(name)
        x += 11

    fr, fl = pip_cell()
    put_cell("pip_full", fr, fl)
    fr, fl = pip_cell(fill_rows=None)
    for r, c in PIP_EMPTY_RESIDUE:
        fr[2 + r][2 + c] = "d"
    put_cell("pip_empty", fr, fl)
    # --- break: crack, split, shatter, fall, settle
    fr, fl = pip_cell()
    for (r, c) in ((3, 4), (4, 3), (5, 3), (6, 2), (7, 2)):
        fl[2 + r][2 + c] = "."
    fr[2 + 4][2 + 6] = "C"
    fr[2 + 3][2 + 5] = "C"
    put_cell("pip_break_0", fr, fl)
    fr, fl = pip_cell()
    fr2 = grid(11, 15)
    fl2 = grid(11, 15)
    for j in range(15):
        for i in range(11):
            s = -1 if i < 5 else 1
            if fr[j][i] != "." and not (j in (6, 7) and i in (2, 8)):
                ni = i + (s if j >= 4 else 0)
                if 0 <= ni < 11:
                    fr2[j][ni] = fr[j][i]
            if fl[j][i] != "." and (i, j) not in ((5, 6), (4, 7), (4, 8)):
                ni = i + (s if j >= 4 else 0)
                fl2[j][ni] = fl[j][i]
    put_cell("pip_break_1", fr2, fl2)
    shards_a = [(0, 5, "C"), (10, 4, "c"), (1, 9, "o"), (9, 10, "o"), (3, 13, "o"), (8, 12, "C")]
    drops_a = [(4, 8, "W"), (6, 9, "M"), (5, 11, "M")]
    for k, (fall, fade) in enumerate(((0, False), (2, False), (3, True))):
        fr = grid(11, 15)
        fl = grid(11, 15)
        for j, r in enumerate(PIP_FRAME[:2]):
            for i, ch in enumerate(r):
                if ch != ".":
                    fr[2 + j][2 + i] = ch
        if k == 2:  # settle: the hollow ampoule is back
            fr, fl = pip_cell(fill_rows=None)
            for r, c in PIP_EMPTY_RESIDUE:
                fr[2 + r][2 + c] = "d"
        for (i, j, ch) in shards_a:
            jj = min(14, j + fall + (k if i % 2 else 0))
            if k < 2 or jj == 14:
                fr[jj][i] = "d" if fade else ch
        if k < 2:
            for (i, j, ch) in drops_a:
                fl[min(14, j + fall * 2)][i] = ch
        put_cell(f"pip_break_{k + 2}", fr, fl)
    # --- refill: liquid rises with a bright surface line, cap flash at the end
    levels = [7, 6, 4, 2]
    for k, top in enumerate(levels):
        fr, fl = pip_cell(fill_rows=None)
        full = PIP_FILL
        for r in range(top, 8):
            for c in range(7):
                ch = full[r][c]
                if ch != ".":
                    fl[2 + r][2 + c] = "W" if (r == top and k < 3) else ch
        if k == 3:
            for c in range(1, 6):
                fr[2 + 1][2 + c] = "C"
        put_cell(f"pip_refill_{k}", fr, fl)
    # --- injectors 4x7 in 6x9 cells, ammo ticks 2x5 in 4x7 cells
    INJ = ["cccc", ".cc.", "oooo", "o..o", "o..o", "oooo", ".o.."]
    INJF = ["....", "....", "....", ".WM.", ".MM.", "....", "...."]
    A.paint(1, 17, INJ, target="frame"); A.paint(1, 17, INJF, target="fill"); A.regions["injector_full"] = [0, 16, 6, 9]
    A.paint(7, 17, INJ, target="frame"); A.paint(7, 17, ["....", "....", "....", "....", ".dd."], target="frame")
    A.regions["injector_empty"] = [6, 16, 6, 9]
    A.paint(14, 17, ["WM", "WM", "WM", "WM", "MD"], target="fill"); A.regions["ammo_tick_full"] = [13, 16, 4, 7]
    A.paint(18, 17, ["dd", "d.", "d.", "d.", "dd"], target="frame"); A.regions["ammo_tick_empty"] = [17, 16, 4, 7]
    # --- core meter frame 72x9 at (0,26)
    cf = grid(72, 9)
    for xx in range(10, 70):
        cf[0][xx] = "c"
        cf[8][xx] = "c"
        cf[2][xx] = "o"
        cf[6][xx] = "o"
    for xx in range(14, 70, 12):
        cf[0][xx] = "C"
        cf[8][xx] = "d"
    for yy in range(9):  # joint at the socket and the riveted right cap
        cf[yy][9] = "c"
        cf[yy][70] = "c"
        cf[yy][71] = "o" if yy in (0, 8) else "c"
    for yy in (1, 7):
        cf[yy][70] = "C"
        cf[yy][9] = "C"
    cf[4][71] = "C"
    for yy in range(9):  # socket diamond at the left end
        for xx in range(9):
            d = abs(xx - 4) + abs(yy - 4)
            if d == 4:
                cf[yy][xx] = "c"
            elif d == 3:
                cf[yy][xx] = "o"
            elif d == 2:
                cf[yy][xx] = "d"
    cf[0][4] = "C"
    A.paint(0, 26, rows_of(cf), name="core_frame", target="frame")
    A.paint(3, 29, [".W.", "WMW", ".W."], name="core_socket_fill", target="fill")
    # --- core fill flow: 6 frames of 60x3, diagonal bands scrolling 2 px/frame (period 12 = seamless loop)
    flow = []
    for f in range(6):
        g = grid(60, 3)
        for yy in range(3):
            for xx in range(60):
                v = (xx + yy * 2 - 2 * f) % 12
                g[yy][xx] = "W" if v < 3 else ("M" if yy < 2 or v < 9 else "D")
            g[yy][59] = "W"
        fx, fy = (f % 2) * 64, 38 + (f // 2) * 4
        A.paint(fx, fy, rows_of(g), name=f"core_fill_flow_{f}", target="fill")
        flow.append(f"core_fill_flow_{f}")
    meta = {
        "frames": {"pip_break": [f"pip_break_{k}" for k in range(5)], "pip_refill": [f"pip_refill_{k}" for k in range(4)],
                   "core_fill_flow": flow},
        "fps": {"pip_break": 12, "pip_refill": 12, "core_fill_flow": 10},
        "anchors": {"pip": "ampoule 7x9 sits at (2,2) inside each 11x15 cell (room for falling shards)",
                    "core_fill": "fill channel is x10..69, y3..5 of core_frame; crop the flow frame to the Core ratio",
                    "core_socket_fill": "draw at core_frame + (3,3)"},
        "tint": {"pip fill": "Palette accent (health)", "injector fill": "Palette heal", "ammo": "Palette ammo",
                 "core fill / socket": "Palette accent; critical pulse in code (static under flash reduction)",
                 "frame": "as is (UiTheme may modulate); high contrast: modulate to text colour"},
        "preview_tint": (232, 40, 60),
    }
    emit_atlas("ui_hud_kit", UI, "hud_kit", A, meta)


# ====================================================================== dialogue / menu / boss bar
def frame_box(w, h, bracket=6, fill="p", double=True, rivets=True):
    g = grid(w, h)
    for y in range(h):
        for x in range(w):
            edge = x in (0, w - 1) or y in (0, h - 1)
            inner = double and (x in (2, w - 3) or y in (2, h - 3)) and 2 <= x <= w - 3 and 2 <= y <= h - 3
            if edge:
                g[y][x] = "o"
            elif inner:
                g[y][x] = "d"
            elif fill and 1 <= x <= w - 2 and 1 <= y <= h - 2:
                g[y][x] = fill
    for (cx, cy, sx, sy) in ((0, 0, 1, 1), (w - 1, 0, -1, 1), (0, h - 1, 1, -1), (w - 1, h - 1, -1, -1)):
        for k in range(bracket):
            g[cy][cx + sx * k] = "c"
            g[cy + sy * k][cx] = "c"
            if k < bracket - 2:
                g[cy + sy][cx + sx * k] = "c" if k == 0 else g[cy + sy][cx + sx * k]
                g[cy + sy * k][cx + sx] = "c" if k == 0 else g[cy + sy * k][cx + sx]
        if rivets:
            g[cy + sy * 1][cx + sx * 1] = "C"
    return g


def build_dialogue():
    A = Atlas(96, 48)
    g = frame_box(48, 48, bracket=8)
    # small diamond seams at the bracket tips (inside the 12 px corner margins)
    for (x, y) in ((9, 0), (38, 0), (9, 47), (38, 47)):
        g[y][x] = "C"
    A.paint(0, 0, rows_of(g), name="panel_9slice", target="frame")
    # name plate 32x12, margins 4
    npg = grid(32, 12)
    for y in range(12):
        for x in range(32):
            if x in (0, 31) or y in (0, 11):
                npg[y][x] = "o"
            else:
                npg[y][x] = "h"
    for x in range(1, 31):
        npg[1][x] = "c"
    for (x, y) in ((0, 0), (31, 0), (0, 11), (31, 11)):
        npg[y][x] = "."
    for (x, y, ch) in ((2, 5, "C"), (1, 5, "c"), (3, 5, "c"), (2, 4, "c"), (2, 6, "c")):
        npg[y][x] = ch
    A.paint(48, 0, rows_of(npg), name="nameplate_9slice", target="frame")
    # cable flourish (placed outside the panel's top-left corner by code): sagging cable + plug
    cab = grid(20, 10)
    pts = [(x, 1 + int(round(5 * math.sin(math.pi * x / 16)))) for x in range(17)]
    for x, y in pts:
        cab[y][x] = "o"
        if 0 < x < 16:
            cab[min(9, y + 1)][x] = "d" if cab[min(9, y + 1)][x] == "." else cab[min(9, y + 1)][x]
    cab[0][0] = "c"; cab[1][0] = "C"
    for yy in range(1, 5):
        cab[yy][17] = "c"
    cab[5][17] = "C"; cab[5][16] = "o"; cab[5][18] = "o"; cab[6][17] = "d"
    A.paint(48, 14, rows_of(cab), name="cable_flourish", target="frame")
    # continue ember, 4 frames 7x7 (mask, tinted accent; static frame 0 under flash reduction)
    for f, rows in enumerate(EMBER_FRAMES):
        A.paint(48 + f * 8, 26, rows, name=f"continue_ember_{f}", target="fill")
    meta = {"nine_slice": {"panel_9slice": [12, 12, 12, 12], "nameplate_9slice": [4, 4, 4, 4]},
            "frames": {"continue_ember": [f"continue_ember_{f}" for f in range(4)]}, "fps": {"continue_ember": 6},
            "notes": "Panel alpha from UiTheme.BG (opaque in high contrast). cable_flourish hangs from the panel's top-left "
                     "corner at offset (-2,-1). Portrait slot optional (P3).", "preview_tint": (232, 40, 60)}
    emit_atlas("ui_dialogue_frame", UI, "dialogue_frame", A, meta)


EMBER_FRAMES = [
    ["...W...", "..WM...", "..WMM..", ".WMMM..", ".MMWMM.", ".DMWMD.", "..DMD.."],
    ["...W...", "...WM..", "..WMM..", "..WMMM.", ".MMWMM.", ".DMWMD.", "..DMD.."],
    ["..W....", "..WM...", "..WMM..", ".WMMMM.", ".MMWMM.", ".DMWMD.", "..DMD.."],
    ["...W...", "...M...", "..WMM..", ".WMMM..", ".MMWM..", ".DMWMD.", "..DMD.."],
]


def build_menu():
    A = Atlas(128, 96)
    g = frame_box(64, 64, bracket=14)
    # ornamental corners: a quarter-arc curl and a diamond in each 16 px corner
    for (ox, oy, sx, sy) in ((0, 0, 1, 1), (63, 0, -1, 1), (0, 63, 1, -1), (63, 63, -1, -1)):
        for k in range(0, 91, 6):
            a = math.radians(k)
            x = ox + sx * int(round(4 + 6 * (1 - math.cos(a))))
            y = oy + sy * int(round(4 + 6 * (1 - math.sin(a))))
            if g[y][x] in ("p", "d"):
                g[y][x] = "o"
        dx, dy = ox + sx * 7, oy + sy * 7
        for (px, py, ch) in ((0, 0, "C"), (1, 0, "c"), (-1, 0, "c"), (0, 1, "c"), (0, -1, "c")):
            g[dy + py][dx + px] = ch
        for k in range(3, 12, 4):  # rivets along the bracket arms
            g[oy][ox + sx * k] = "C"
            g[oy + sy * k][ox] = "C"
    A.paint(0, 0, rows_of(g), name="panel_9slice", target="frame")
    # divider 96x5 with a diamond seam
    dv = grid(96, 5)
    for x in range(96):
        d = abs(x - 47.5)
        if d < 3:
            continue
        if d < 30:
            dv[1][x] = "o"; dv[3][x] = "o"
        if d < 44 and (d < 36 or x % 2 == 0):
            dv[2][x] = "c" if d < 20 else "o"
    for (x, y, ch) in ((47, 0, "c"), (48, 0, "c"), (46, 1, "c"), (49, 1, "c"), (45, 2, "c"), (50, 2, "c"),
                       (46, 3, "c"), (49, 3, "c"), (47, 4, "c"), (48, 4, "c"), (47, 1, "C"), (48, 1, "C"),
                       (46, 2, "C"), (47, 2, "C"), (48, 2, "C"), (49, 2, "C"), (47, 3, "c"), (48, 3, "c")):
        dv[y][x] = ch
    A.paint(0, 66, rows_of(dv), name="divider", target="frame")
    for f, rows in enumerate(EMBER_FRAMES):
        A.paint(66 + f * 8, 0, rows, name=f"cursor_{f}", target="fill")
    # tapered row-selection bar, 3-slice 48x9 (caps 8): mask tinted accent
    rb = grid(48, 9)
    for x in range(48):
        edge = min(x, 47 - x)
        half = 4 if edge >= 8 else max(0, int(round(edge * 4 / 8)))
        for y in range(9):
            d = abs(y - 4)
            if d <= half:
                rb[y][x] = "W" if d == 0 else ("M" if d <= 1 else "D")
    A.paint(66, 10, rows_of(rb), name="row_bar_3slice", target="fill")
    meta = {"nine_slice": {"panel_9slice": [16, 16, 16, 16]}, "three_slice": {"row_bar_3slice": [8, 8]},
            "frames": {"cursor": [f"cursor_{f}" for f in range(4)]}, "fps": {"cursor": 6},
            "notes": "cursor + row bar are masks tinted Redline accent (replaces the flat red row highlight); cursor holds "
                     "frame 0 under flash reduction. District banner uses `divider` under the name.",
            "preview_tint": (232, 40, 60)}
    emit_atlas("ui_menu_frame", UI, "menu_kit", A, meta)


def build_boss_bar():
    A = Atlas(232, 48)
    g = grid(232, 16)
    for x in range(12, 220):
        g[4][x] = "o"; g[11][x] = "o"
        g[5][x] = "d"; g[10][x] = "d"
    for x in range(16, 216, 25):
        g[4][x] = "c"
    for (ox, s) in ((0, 1), (231, -1)):
        for y in range(2, 14):  # clamp spine
            for k in range(3):
                g[y][ox + s * k] = "c" if k < 2 else "o"
        for y in (2, 3, 12, 13):  # jaws
            for k in range(3, 14):
                if (y in (3, 12)) or k < 11:
                    g[y][ox + s * k] = "c" if y in (2, 13) else "o"
        for y in (6, 7, 8, 9):
            g[y][ox + s * 2] = "o"
            g[y][ox + s * 3] = "d"
        g[2][ox + s * 1] = "C"; g[13][ox + s * 1] = "C"; g[7][ox + s * 1] = "C"; g[8][ox + s * 1] = "c"
        g[2][ox + s * 13] = "C"; g[13][ox + s * 13] = "C"
    A.paint(0, 0, rows_of(g), name="bar_3slice", target="frame")
    fill = ["W" * 200, "M" * 200, "M" * 200, "D" * 200]
    A.paint(0, 18, fill, name="fill", target="fill")
    pl = grid(56, 9)
    for y in range(9):
        for x in range(56):
            inset = max(0, 2 - y) if y < 2 else 0
            if x < inset or x > 55 - inset:
                continue
            if y == 0 or y == 8 or x == inset or x == 55 - inset:
                pl[y][x] = "o"
            else:
                pl[y][x] = "h"
    for x in range(3, 53):
        pl[1][x] = "c"
    pl[4][4] = "C"; pl[4][51] = "C"
    A.paint(0, 24, rows_of(pl), name="name_plaque", target="frame")
    tick = [".c.", "cCc", ".c.", ".c.", ".c.", ".c.", "cCc", ".c."]
    A.paint(60, 24, tick, name="phase_tick", target="frame")
    shards = [
        [".........", "...c.c...", "....C....", "...c.c...", "....c....", "....c....", "....c....", "...cCc...", "....c....", ".........", ".........", "........."],
        [".........", "..c...c..", ".........", "...C.C...", "....o....", "...o.....", ".....o...", "...c.c...", "....C....", ".........", ".........", "........."],
        ["c.......c", ".........", "..o...o..", ".........", "...d.....", ".....o...", ".........", "..o...o..", ".........", "...c.....", ".........", "........."],
        [".........", ".........", ".........", "d.......d", ".........", "..d...d..", ".........", ".........", "...d.....", ".........", "..d...d..", "....d...."],
    ]
    for f, rows in enumerate(shards):
        A.paint(66 + f * 10, 24, rows, name=f"tick_shatter_{f}", target="frame")
    meta = {"three_slice": {"bar_3slice": [16, 16]}, "fill_rect_in_bar": [16, 6, 200, 4],
            "frames": {"tick_shatter": [f"tick_shatter_{f}" for f in range(4)]}, "fps": {"tick_shatter": 12},
            "notes": "Fill (mask) tinted Palette accent, cropped to HP ratio, drawn at bar + (16,6). phase_tick at 50 %; "
                     "on phase change play tick_shatter centred on the tick. name_plaque sits centred above the bar.",
            "preview_tint": (232, 40, 60)}
    emit_atlas("ui_boss_bar", UI, "boss_bar", A, meta)


# ====================================================================== glyphs: ranks + title
GLYPHS = {
    "D": ["#####..", "##..##.", "##...##", "##...##", "##...##", "##...##", "##...##", "##...##", "##...##", "##...##", "##..##.", "#####.."],
    "C": [".#####.", "##...##", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##...##", ".#####."],
    "B": ["######.", "##...##", "##...##", "##...##", "##..##.", "#####..", "##..##.", "##...##", "##...##", "##...##", "##...##", "######."],
    "A": ["..###..", ".##.##.", "##...##", "##...##", "##...##", "##...##", "#######", "#######", "##...##", "##...##", "##...##", "##...##"],
    "S": [".######", "##.....", "##.....", "##.....", ".##....", "..###..", "....##.", ".....##", ".....##", ".....##", ".....##", "######."],
    "R": ["######.", "##...##", "##...##", "##...##", "##..##.", "#####..", "##.##..", "##..##.", "##..##.", "##...##", "##...##", "##...##"],
    "E": ["#######", "##.....", "##.....", "##.....", "##.....", "######.", "##.....", "##.....", "##.....", "##.....", "##.....", "#######"],
    "L": ["##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "#######"],
    "I": ["######", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "######"],
    "N": ["##...##", "###..##", "###..##", "####.##", "##.#.##", "##.####", "##..###", "##..###", "##...##", "##...##", "##...##", "##...##"],
}


def glyph_mask(ch):
    rows = GLYPHS[ch]
    return np.array([[c == "#" for c in r] for r in rows], bool)


def bevel_tones(m):
    """Chiselled bevel: lit top/left faces 3, shaded bottom/right 1, body 2."""
    p = np.pad(m, 1)
    up = p[:-2, 1:-1]
    left = p[1:-1, :-2]
    down = p[2:, 1:-1]
    right = p[1:-1, 2:]
    t = np.where(m, 2, 0).astype(np.uint8)
    t[m & (~down | ~right)] = 1
    t[m & (~up | ~left)] = 3
    return t


def rank_tones(m):
    """Bevel for 2 px strokes: lit top/left 3, the rest 2, bottom edge 1 (reads solid, not hollow)."""
    p = np.pad(m, 1)
    up, left, down = p[:-2, 1:-1], p[1:-1, :-2], p[2:, 1:-1]
    t = np.where(m, 2, 0).astype(np.uint8)
    t[m & ~down] = 1
    t[m & (~up | ~left)] = 3
    return t


def word_mask(text, gap=1):
    ms = [glyph_mask(c) for c in text]
    w = sum(m.shape[1] for m in ms) + gap * (len(ms) - 1)
    out = np.zeros((12, w), bool)
    x = 0
    for m in ms:
        out[:, x:x + m.shape[1]] = m
        x += m.shape[1] + gap
    return out


def build_ranks():
    cw, ch = 24, 16
    names = ["D", "C", "B", "A", "S", "SS", "SSS"]
    img = np.zeros((ch, cw * 7 + 72, 4), np.uint8)
    regions = {}
    for k, nm in enumerate(names):
        m = word_mask(nm)
        t = rank_tones(m)
        ox = k * cw + (cw - m.shape[1]) // 2
        oy = 2
        for (v, col) in ((1, MASK[1]), (2, MASK[2]), (3, MASK[3])):
            sel = t == v
            img[oy:oy + 12, ox:ox + m.shape[1]][sel] = (*col, 255)
        regions[nm] = [k * cw, 0, cw, ch]
    m = word_mask("REDLINE")
    t = rank_tones(m)
    ox = cw * 7 + (72 - m.shape[1]) // 2
    for (v, col) in ((1, MASK[1]), (2, MASK[2]), (3, MASK[3])):
        img[2:14, ox:ox + m.shape[1]][t == v] = (*col, 255)
    regions["REDLINE"] = [cw * 7, 0, 72, ch]
    os.makedirs(UI, exist_ok=True)
    p = save(img, os.path.join(UI, "style_ranks.png"))
    preview(p, scale=4)
    js = os.path.join(UI, "style_ranks.json")
    write_json(js, {"id": "ui_style_ranks", "texture": "res://assets/ui/style_ranks.png", "regions": regions,
                    "tint": "rank colour from StyleMeter (masks); existing flash rules apply",
                    "notes": "7x12 chiselled glyphs (2 px strokes, lit top-left bevel). REDLINE spans a 72x16 region. "
                             "Rank letters are exempt from translation (D-163)."})
    BUILT.setdefault("ui_style_ranks", []).extend([p, js])


def build_title():
    W, H = 208, 40
    SX, SY = 3, 3
    text = "REDLINE"
    letters = []
    for c in text:
        g = glyph_mask(c)
        big = np.kron(g, np.ones((SY, SX), bool))
        # chisel: cut convex corners at 45 degrees (2 passes)
        for _ in range(2):
            p = np.pad(big, 1)
            up, dn, lf, rt = p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]
            corner = big & (((~up) & (~lf)) | ((~up) & (~rt)) | ((~dn) & (~lf)) | ((~dn) & (~rt)))
            big = big & ~corner
        # serifs: 1 px spurs where a stroke ends at the top or bottom row
        for y in (0, big.shape[0] - 1):
            row = big[y].copy()
            yy = 1 if y == 0 else big.shape[0] - 2
            src = big[yy]
            for x in range(big.shape[1]):
                if src[x] and not row[x]:
                    big[y, x] = True
        for y in (0, big.shape[0] - 1):
            xs = np.where(big[y])[0]
            if len(xs):
                runs = np.split(xs, np.where(np.diff(xs) > 1)[0] + 1)
                for r in runs:
                    for x in (r[0] - 1, r[-1] + 1):
                        if 0 <= x < big.shape[1]:
                            big[y, x] = True
        letters.append(big)
    # AD redo: heavier engraved caps (strokes thickened by 2 px), a tighter gap, and one continuous crack
    heavy = []
    for m in letters:
        h2 = np.zeros((m.shape[0], m.shape[1] + 2), bool)
        for dx in range(3):
            h2[:, dx:dx + m.shape[1]] |= m
        heavy.append(h2)
    letters = heavy
    gap = 3
    total = sum(m.shape[1] for m in letters) + gap * (len(letters) - 1)
    canvas = np.zeros((H, W), bool)
    x0 = (W - total) // 2
    x = x0
    oy = (H - letters[0].shape[0]) // 2
    for m in letters:
        canvas[oy:oy + m.shape[0], x:x + m.shape[1]] |= m
        x += m.shape[1] + gap
    x1 = x - gap  # right edge of the final E
    # the crack: ONE connected 1 px zig-zag path from the R's left edge to the E's right edge
    # (diagonal steps only, so it is 8-connected with no gaps, also across the letter gaps)
    rng = random.Random(1337)
    crack = np.zeros_like(canvas)
    y = oy + 19
    dy = 1
    xx = x0
    while xx < x1:
        seg = rng.randint(2, 4)
        for _ in range(seg):
            if xx >= x1:
                break
            crack[y, xx] = True
            y2 = y + dy
            if not (oy + 15 <= y2 <= oy + 23):
                dy = -dy
                y2 = y + dy
            y = y2
            xx += 1
        dy = -dy if rng.random() < 0.8 else dy
    letters_m = canvas & ~crack
    # 1 px bevel highlight on top edges only (3), bottom edges shaded (1), body (2)
    pp = np.pad(letters_m, 1)
    up, down = pp[:-2, 1:-1], pp[2:, 1:-1]
    tones = np.where(letters_m, 2, 0).astype(np.uint8)
    tones[letters_m & ~down] = 1
    tones[letters_m & ~up] = 3
    outline = np.zeros_like(canvas)
    p = np.pad(canvas, 1)
    for dy_ in (-1, 0, 1):
        for dx_ in (-1, 0, 1):
            outline |= p[1 + dy_:1 + dy_ + H, 1 + dx_:1 + dx_ + W]
    outline &= ~canvas
    col = {3: ui("text"), 2: ui("line_2"), 1: ui("line_1")}
    img = np.zeros((H, W, 4), np.uint8)
    img[outline] = (*ui("bg"), 255)
    for v, c in col.items():
        img[tones == v] = (*c, 255)
    img[crack & canvas] = (*ui("bg"), 255)  # the seam reads dark inside the letters when the crack layer is off
    cr = np.zeros((H, W, 4), np.uint8)
    cr[crack] = (255, 255, 255, 255)
    # a 1 px glow under the crack inside the letters (dim mask), gives the ember crawl something to light
    glow = np.zeros_like(crack)
    glow[1:] |= crack[:-1]
    glow[:-1] |= crack[1:]
    glow &= letters_m
    cr[glow] = (*MASK[1], 255)
    os.makedirs(TITLE, exist_ok=True)
    p = save(img, os.path.join(TITLE, "title_logo.png"))
    pc = save(cr, os.path.join(TITLE, "title_logo_crack.png"))
    # review composite over the title sky, crack tinted Redline red
    comp_path = os.path.join(PREVIEW, "fxui__title_logo_on_sky.png")
    sky_p = os.path.join(TITLE, "title_sky.png")
    if os.path.exists(sky_p):
        sky = Image.open(sky_p).convert("RGBA")
    else:
        sky = Image.new("RGBA", (480, 270), (13, 14, 28, 255))
    logo = Image.fromarray(img, "RGBA")
    crk = cr.copy().astype(np.float32)
    crk[..., :3] *= np.array([232, 40, 60]) / 255.0
    sky.alpha_composite(logo, ((480 - W) // 2, 60))
    sky.alpha_composite(Image.fromarray(crk.astype(np.uint8), "RGBA"), ((480 - W) // 2, 60))
    sky.resize((960, 540), Image.NEAREST).save(comp_path)
    preview(p, scale=4)
    preview(pc, scale=4)
    js = os.path.join(TITLE, "title_logo.json")
    write_json(js, {"id": "title_logo", "texture": "res://assets/ui/title_logo.png", "crack_mask": "res://assets/ui/title_logo_crack.png",
                    "size": [W, H], "notes": "AD redo: heavier engraved caps (strokes +2 px), 1 px top-edge bevel highlight, 1 px bg outline. "
                                              "The crack mask is ONE connected 1 px zig-zag path from the R to the final E (it crosses the "
                                              "letter gaps too) plus a dim 96 glow inside the letters; it is tinted Redline red in code with a slow ember crawl (a moving bright "
                                              "window along x, ~20 px/s); static under flash reduction. Letterforms are "
                                              "script-drawn (the manifest's fallback) because image generation was blocked."})
    BUILT.setdefault("title_logo", []).extend([p, pc, js])


# ====================================================================== icons (16x16, 11x11 art)
ICONS = {
    "anchor": ["....W......", "...WMW.....", "....M......", "..DMMMD....", "....M......", "....M......", "...WMW.....",
               "..WM.MW....", ".WM...MW...", "DDDDDDDDD..", "..........."],
    "npc": ["...DMMD....", "..MWWMMD...", "..MWMMMD...", "..DMMMD....", "...DMD.....", ".DMMMMMD...", "DMWMMMMMD..",
            "MWMMMMMMM..", "MWMMMMMMM..", "DMMMMMMMD..", "..........."],
    "shop": ["WWMWWMWWMW.", "MWDMWDMWDM.", ".D.D.D.D.D.", ".M.......M.", ".M..DDD..M.", ".M..D.D..M.", ".M..D.D..M.",
             ".M..D.D..M.", "DMMMMMMMMMD", "...........", "..........."],
    "memory": ["....W......", "...WWM.....", "...WMM.....", "..WWMMD....", "..WMMMD....", "..WMMDD....", "..WMMD.....",
               "...MMD.....", "...MD......", "....D......", "..........."],
    "scrap": ["...........", "...DMMD....", "..MWWMMD...", ".MWMMMMMD..", ".MWMMMMMD..", ".DMMMMMDD..", "..DMMMDD...",
              "...DDDD....", "...........", "...........", "..........."],
    "gate": ["MMMMMMMMMM.", "M.W.W.W.WM.", "M.W.W.W.WM.", "M.M.M.M.MM.", "MMMMMMMMMM.", "M.M.M.M.MM.", "M.M.M.M.MM.",
             "M.M.M.M.MM.", "M.M.M.M.MM.", "DDDDDDDDDD.", "..........."],
    "boss": ["..DMMMMMD..", ".MWWMMMMMD.", "MWM.MMM.MMD", "MW...M...MD", "MWM.MMM.MMD", "DMMMM.MMMMD", ".DMM...MMD.",
             "..DM.M.MD..", "..DMDMDMD..", "...D.D.D...", "..........."],
    "note": ["....WW.....", "....DD.....", ".WWWWMMMM..", ".WMMMMMMD..", ".WDDDDDMD..", ".WMMMMMMD..", ".WDDDDMMD..",
             ".WMMMMMMD..", ".WDDDMMMD..", ".MMMMMMMD..", "..........."],
    "circuit": ["DMMMMMMMMD.", "M.W...W..M.", "M.MMWMM..M.", "M...M....M.", "M.D.MMMW.M.", "M.M....M.M.", "M.MMWMMM.M.",
                "M........M.", "DMWMWMWMWD.", "..D.D.D.D..", "..........."],
    "weapon": ["........WW.", ".......WMD.", "......WMD..", ".....WMD...", "....WMD....", "...WMD.....", ".DWMD......",
               "..DD.......", ".DMD.......", "DMD........", "D.........."],
}


def build_icons():
    A = Atlas(16 * 5, 16 * 2)
    for k, (nm, rows) in enumerate(ICONS.items()):
        x, y = (k % 5) * 16, (k // 5) * 16
        A.paint(x + 2, y + 2, rows, target="fill")
        A.regions[nm] = [x, y, 16, 16]
    # icons are pure masks: write the fill layer as the main texture
    A.img, A.fill = A.fill, np.zeros_like(A.fill)
    emit_atlas("ui_icons", UI, "icons", A, {"tint": "Palette (map_gate, map_note, scrap, memory ...) or UiTheme text",
                                            "notes": "11x11 art inside 16x16 cells, grey masks."}, with_fill=False)


# ====================================================================== pickups
def build_pickups():
    cw = ch = 16
    base = np.zeros((ch * 4, cw * 8, 4), np.uint8)
    tint = np.zeros_like(base)

    def paint(arr, x, y, rows):
        for j, r in enumerate(rows):
            for i, c in enumerate(r):
                if c in ". ":
                    continue
                arr[y + j, x + i] = (*ALLC[c], 255)

    # scrap_spin: a faceted nugget turning (width from |cos|), 6 frames
    for f in range(6):
        a = 2 * math.pi * f / 6
        hw = 1 + 4 * abs(math.cos(a))
        m = cov_poly(cw, ch, [(8 - hw, 7), (8 - hw * 0.6, 4.5), (8 + hw * 0.5, 4), (8 + hw, 6.5), (8 + hw * 0.7, 10.5), (8 - hw * 0.7, 11)], 0.45)
        t = bevel_tones(m)
        face = math.cos(a) > 0
        for v, c in ((1, MASK[1]), (2, MASK[2]), (3, MASK[3])):
            tint[0:ch, f * cw:(f + 1) * cw][t == v] = (*c, 255)
        if f in (0, 3):  # glint
            gx = 6 if face else 9
            tint[5, f * cw + gx] = (*MASK[3], 255)
            tint[4, f * cw + gx] = (*MASK[3], 255)
    # scrap_cache: crate (baked steel) + latch (mask, scrap gold)
    crate = ["..cccccccccccc..", ".coooooooooooooc", ".ohhhhhhhhhhhhho", ".ohdddddddddddho", ".ohhhhhhhhhhhhho",
             ".ocooooooooooooo", ".ohhhhhhhhhhhhho", ".ohdddddddddddho", ".ohhhhhhhhhhhhho", ".ooooooooooooooo"]
    paint(base, 0, ch + 6, [r[:16] for r in crate])
    paint(tint, 6, ch + 9, ["WMMW", "MDDM", "WMMW"])
    # memory_shard: bobbing crystal with a glint sweep and an orbiting mote, 8 frames
    for f in range(8):
        bob = int(round(math.sin(2 * math.pi * f / 8) * 1))
        pts = [(8, 2 + bob), (10.5, 6 + bob), (9.5, 12 + bob), (8, 14 + bob), (6.5, 12 + bob), (5.5, 6 + bob)]
        m = cov_poly(cw, ch, pts, 0.45)
        t = bevel_tones(m)
        cell = tint[2 * ch:3 * ch, f * cw:(f + 1) * cw]
        for v, c in ((1, MASK[1]), (2, MASK[2]), (3, MASK[3])):
            cell[t == v] = (*c, 255)
        gy = 3 + f * 1.5 + bob
        for k in range(3):
            yy, xx = int(gy + k), 6 + k
            if 0 <= yy < ch and m[yy, xx]:
                cell[yy, xx] = (*MASK[3], 255)
        oa = 2 * math.pi * f / 8
        ox, oy = int(round(8 + math.cos(oa) * 6)), int(round(8 + bob + math.sin(oa) * 2))
        if not m[oy, ox]:
            cell[oy, ox] = (*MASK[3 if f % 2 else 2], 255)
    # core_shard: jagged fragment with a pulsing seam, 8 frames
    frag = [(4, 9), (6, 4), (9, 3), (12, 6), (11, 11), (7, 13)]
    m = cov_poly(cw, ch, frag, 0.45)
    t = bevel_tones(m)
    seam = [(6, 6), (7, 7), (8, 7), (9, 8), (10, 9)]
    for f in range(8):
        cell = tint[3 * ch:4 * ch, f * cw:(f + 1) * cw]
        for v, c in ((1, MASK[1]), (2, MASK[2]), (3, MASK[1])):
            cell[t == v] = (*c, 255)
        pulse = 0.5 + 0.5 * math.cos(2 * math.pi * f / 8)
        for (x, y) in seam:
            cell[y, x] = (*MASK[3 if pulse > 0.3 else 2], 255)
        if pulse > 0.8:  # halo pixels at peak
            b = bayer(ch, cw)
            p = np.pad(m, 2)
            near = np.zeros_like(m)
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    near |= p[2 + dy:2 + dy + ch, 2 + dx:2 + dx + cw]
            ring_ = near & ~m & (b < 0.35)
            cell[ring_] = (*MASK[1], 255)
    os.makedirs(PROPS, exist_ok=True)
    p1 = save(base, os.path.join(PROPS, "pickups.png"))
    p2 = save(tint, os.path.join(PROPS, "pickups_fill.png"))
    comp = base.copy()
    sel = tint[..., 3] > 0
    tints = [(255, 211, 107), (255, 211, 107), (159, 216, 255), (232, 40, 60)]
    for r in range(4):
        rs = slice(r * ch, (r + 1) * ch)
        s2 = sel[rs]
        comp[rs][s2] = np.concatenate([(tint[rs][s2][:, :3].astype(np.float32) * np.array(tints[r]) / 255).astype(np.uint8),
                                        np.full((s2.sum(), 1), 255, np.uint8)], 1)
    cp = os.path.join(PROPS, "_comp.png")
    Image.fromarray(comp, "RGBA").save(cp)
    preview(cp, scale=4, tag="pickups_composite.png")
    os.remove(cp)
    write_tres(os.path.join(PROPS, "pickups.tres"), "res://assets/props/pickups_fill.png", cw, ch, (8, 8),
               [("scrap_spin", 0, 6, 12, True), ("scrap_cache", 1, 1, 1, False), ("memory_shard", 2, 8, 8, True),
                ("core_shard", 3, 8, 8, True)])
    js = os.path.join(PROPS, "pickups.json")
    write_json(js, {"id": "interact_pickups", "texture": "res://assets/props/pickups.png",
                    "fill_texture": "res://assets/props/pickups_fill.png", "cell": [16, 16], "origin": [8, 8],
                    "rows": {"scrap_spin": 6, "scrap_cache": 1, "memory_shard": 8, "core_shard": 8},
                    "row_origins": {"scrap_cache": [8, 15]},
                    "tint": {"scrap_spin": "Palette scrap", "scrap_cache latch": "Palette scrap", "memory_shard": "Palette memory",
                             "core_shard": "Palette accent"},
                    "notes": "pickups.png holds baked parts (the cache crate); pickups_fill.png holds the tinted masks in the "
                             "same layout. The .tres points at the fill sheet (the animated part)."})
    BUILT.setdefault("interact_pickups", []).extend([p1, p2, os.path.join(PROPS, "pickups.tres"), js])


def check_all():
    errs = []
    for folder, allowed in ((UI, UI_ALLOWED), (TITLE, UI_ALLOWED), (PROPS, UI_ALLOWED)):
        for fn in sorted(os.listdir(folder)):
            if not fn.endswith(".png") or fn.startswith("_") or fn == "title_sky.png":
                continue
            errs += check_png(os.path.join(folder, fn), allowed=allowed, mask=False)
    return errs


def main(argv):
    for fn in (build_hud, build_dialogue, build_menu, build_boss_bar, build_ranks, build_title, build_icons, build_pickups):
        fn()
    errs = check_all()
    for e in errs:
        print("FAIL", e)
    print(f"built {sum(len(v) for v in BUILT.values())} files for {len(BUILT)} ids; {len(errs)} problems")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
