"""The Sweeper (Lowlight rail pursuer) -> assets/lowlight/sweeper_sheet.png (+ .tres). Cell 80x160, origin (40,158).
Headlight cone and hazard lamps stay code-drawn (Palette chase_*); the housings here are unlit.
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, Frame, Anim, rot, add, merge  # noqa
from rig_enemies import emit, PAL  # noqa
from rig_machines import Xf  # noqa

L = PAL["palettes"]["ll_env"]["colors"]
W, H = 80, 160
O = PAL["palettes"]["char_enemy"]["colors"]["outline"]
MET = [L["metal_0"], L["metal_1"], L["metal_2"], L["edge"]]
CON = [L["concrete_0"], L["concrete_1"], L["concrete_2"]]
REST = dict(tilt=0.0, x=0.0, drop=0.0, spin=0, shake=0.0, rail=1)


def draw(p, i=0):
    f = Frame(W, H)
    if p["rail"]:
        pass
    if p["rail"]:
        f.part(Layer(W, H).rect(0, 1, 80, 5), [L["metal_0"], L["metal_1"], L["metal_2"]], light=1)
        for x in range(4, 80, 12):
            f.px((x, 3), L["concrete_0"])
    piv = (40 + p["x"], 4 + p["drop"])
    xf = Xf(piv, p["tilt"], (p["shake"], 0))
    X = lambda x, y: xf((40 + p["x"] + x, 4 + p["drop"] + y))  # noqa
    # trolley wheels + hanger
    for dx in (-8, 8):
        f.part(Layer(W, H).circle(X(dx, 1), 3), [L["metal_0"], L["metal_1"], L["metal_2"]], light=1, sep=O)
    f.part(Layer(W, H).poly([X(-5, 2), X(5, 2), X(4, 14), X(-4, 14)]), MET, light=1, sep=O)
    # slab body with grime streaks
    body = [X(-26, 14), X(24, 14), X(29, 22), X(29, 118), X(24, 126), X(-24, 126), X(-29, 118), X(-29, 20)]
    f.part(Layer(W, H).poly(body), [L["concrete_1"], L["concrete_2"], L["concrete_3"], L["edge"]], light=2, shade=2, sep=O)
    # panel seams, rivets, hazard chevrons (muted), rain streaks
    for y in (40, 70, 100):
        f.part(Layer(W, H).capsule(X(-27, y), X(27, y), 0.5), [L["concrete_0"]], light=0, shade=0, thr=0.35)
    for y in (18, 44, 74, 104, 122):
        for x in (-25, 25):
            f.px(X(x, y), L["edge"])
    for k in range(5):
        a, b = X(-20 + k * 9, 110), X(-16 + k * 9, 118)
        f.part(Layer(W, H).capsule(a, b, 1.2), [L["brick_1"] if k % 2 else L["sodium_spill"]], light=0, shade=0)
    for k, x in enumerate((-18, -6, 9, 20)):
        f.part(Layer(W, H).capsule(X(x, 26 + k * 7), X(x, 60 + k * 9), 0.45), [L["concrete_0"] if k % 2 else L["wet_hi"]], light=0, shade=0, thr=0.35)
    # vents/grille
    f.part(Layer(W, H).rect(*X(-18, 76), *X(-4, 94)) if p["tilt"] == 0 else Layer(W, H).poly([X(-18, 76), X(-4, 76), X(-4, 94), X(-18, 94)]), [L["metal_0"], L["metal_1"]], light=0)
    for y in range(78, 94, 3):
        f.part(Layer(W, H).capsule(X(-17, y), X(-5, y), 0.45), [L["metal_2"]], light=0, shade=0, thr=0.35)
    # hazard lamp housings (unlit) front-top, headlight housing
    for y in (22, 34):
        f.part(Layer(W, H).circle(X(27, y), 3.2), [L["metal_0"], L["metal_1"], L["metal_2"]], light=1, sep=O)
        f.part(Layer(W, H).circle(X(27.5, y), 1.6), [L["concrete_0"]], light=0, shade=0)
    f.part(Layer(W, H).poly([X(26, 56), X(33, 53), X(33, 66), X(26, 63)]), [L["metal_0"], L["metal_1"], L["metal_2"]], light=1, sep=O)
    # scraper blades
    for dx, s in ((-30, -1), (30, 1)):
        f.part(Layer(W, H).poly([X(dx * 0.8, 124), X(dx * 1.05, 146), X(dx * 1.05 - s * 3, 148), X(dx * 0.7, 128)]), MET, light=1, sep=O)
    # brush drums (two), bristle stripes rotate with spin
    for dx in (-13, 13):
        c = X(dx, 138)
        f.part(Layer(W, H).circle(c, 11), [L["brick_0"], L["brick_1"], L["brick_2"]], light=1, sep=O)
        for k in range(6):
            a = (p["spin"] * 20 + k * 60) * (1 if dx > 0 else 1)
            e = add(c, rot((0, -10), a))
            f.part(Layer(W, H).capsule(add(c, rot((0, -4), a)), e, 0.8), [L["brick_0"]], light=0, shade=0, thr=0.35)
        f.part(Layer(W, H).circle(c, 3), MET, light=1)
    f.outline(O)
    return f


def P(**kw):
    return merge(REST, kw)


def build():
    A = [Anim("parked", [draw(P()).image()], 1, False)]
    A.append(Anim("warn", [draw(P(shake=[0, 1, -1, 0][k], spin=k)).image() for k in range(4)], 12, True))
    A.append(Anim("chase", [draw(P(tilt=-4 + math.sin(k) * 0.8, spin=k * 2, shake=(k % 2) * 0.6)).image() for k in range(6)], 12, True))
    A.append(Anim("regroup", [draw(P(tilt=t, spin=k)).image() for k, t in enumerate((3, 5, 2))], 10, False))
    A.append(Anim("derail", [draw(P(tilt=t, x=x, drop=d, spin=k * 3, rail=1)).image() for k, (t, x, d) in enumerate(((-4, 0, 0), (5, 0, 2), (9, 0, 6), (12, 0, 12), (14, 0, 20), (15, 0, 30), (16, 0, 42), (16, 0, 56)))], 12, False))
    return A


if __name__ == "__main__":
    emit("sweeper", (W, H), (40, 158), build(), sub="lowlight")
