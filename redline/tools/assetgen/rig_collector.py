"""Collector Drone boss rig -> assets/bosses/collector_drone_sheet.png (+ .tres). Cell 96x96, origin (48,64) at the body bottom.

The eye lamp/lens, the cone and the cell glow stay code-drawn; the sprite's eye housing is dark.
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, Frame, Anim, rot, add, mul, lerp2, merge  # noqa
from rig_enemies import emit, PAL  # noqa
from rig_machines import Xf  # noqa

C = PAL["palettes"]["char_boss_collector"]["colors"]
W = H = 96
O = C["outline"]
HULL = [C["hull_0"], C["hull_1"], C["hull_2"], C["hull_3"]]
RUST = [C["rust_0"], C["rust_1"], C["rust_1"]]
CAB = [C["cable_0"], C["cable_1"], C["cable_1"]]
CAGE = [C["cage_0"], C["cage_1"], C["cage_1"]]
REST = dict(by=0.0, x=0.0, tilt=0.0, claw=0.0, press=0.0, hook=0.0, rot=0, cut=0, crack=0, lit=0, split=0.0, drop=0.0, spark=0, cells_out=0.0)


def draw(p, i=0):
    f = Frame(W, H)
    c = (48 + p["x"], 52 + p["by"] + p["drop"])  # hull centre; bottom ~64
    xf = Xf(c, p["tilt"])
    sp = p["split"]
    # --- rotors on outriggers (back pair drawn first, darker)
    rotors = [((-24, -15), True), ((22, -15), True), ((-16, -18), False), ((15, -18), False)]
    for k, ((ox, oy), front) in enumerate(rotors):
        if p["cut"] and k in (1, 3):
            # torn stub
            a = xf(add(c, (ox * 0.4, -6)))
            b = xf(add(c, (ox * 0.55, oy * 0.6)))
            f.part(Layer(W, H).capsule(a, b, 1.2), CAB, light=1, sep=O if front else None)
            continue
        if p["cut"] >= 2:
            continue
        a = xf(add(c, (ox * 0.35, -7)))
        hub = xf(add(c, (ox, oy)))
        ramp = HULL[:3] if front else [C["hull_0"], C["hull_0"], C["hull_1"]]
        f.part(Layer(W, H).capsule(a, hub, 1.5, 1.2), ramp, light=1, sep=O if front else None)
        f.part(Layer(W, H).ellipse(hub, 2.4, 1.8), [C["cable_0"], C["cable_1"], C["hull_2"]], light=1)
        span = 10.0 if (p["rot"] + k) % 2 == 0 else 6.0
        f.part(Layer(W, H).ellipse(add(hub, (0, -2.2)), span, 1.0 if front else 0.8), [C["rotor_blur"] if front else C["cable_1"]], light=0, shade=0, thr=0.4)
    # --- hook on chain (behind the hull)
    ha = xf(add(c, (-6, 10)))
    ang = p["hook"]
    chain_end = add(ha, rot((0, 16), ang))
    for t in range(8):
        q = lerp2(ha, chain_end, t / 7)
        f.part(Layer(W, H).circle(q, 0.8), CAB, light=0, thr=0.3)
    hk = Layer(W, H).capsule(chain_end, add(chain_end, rot((0, 3.5), ang)), 1.0).capsule(add(chain_end, rot((0, 3.5), ang)), add(chain_end, rot((3.2, 4.0), ang)), 0.9).capsule(add(chain_end, rot((3.2, 4.0), ang)), add(chain_end, rot((3.8, 1.8), ang)), 0.8)
    f.part(hk, [C["cable_0"], C["cage_1"], C["hull_2"]], light=1, sep=O)
    # --- hanging cage with three salvage cells (below the origin)
    if p["cells_out"] < 1:
        cg = xf(add(c, (4, 12)))
        tp, bt = add(cg, (0, 5)), add(cg, (0, 17))
        for t in range(4):
            q = lerp2(xf(add(c, (4, 10))), tp, t / 3)
            f.part(Layer(W, H).circle(q, 0.7), CAB, light=0, thr=0.3)
        # cells
        for k, dx in enumerate((-4, 0, 4)):
            if p["cells_out"] > 0 and k != 1:
                continue
            col = [C["cell_dim"], C["cell_dim"], C["cell_lit"]] if not p["lit"] else [C["cell_dim"], C["cell_lit"], C["cell_lit"]]
            f.part(Layer(W, H).rect(cg[0] + dx - 1.5, tp[1] + 3, cg[0] + dx + 1.5, bt[1] - 1), col, light=1, shade=1)
        # cage bars (cracked open in phase 2)
        L = Layer(W, H)
        L.capsule(add(tp, (-7, 1)), add(tp, (7, 1)), 0.7)
        L.capsule(add(bt, (-7, 0)), add(bt, (7, 0)), 0.8)
        for dx in (-7, -2, 2, 7):
            if p["crack"] and dx == 7:
                L.capsule(add(tp, (dx, 1)), add(tp, (dx + 4, 8)), 0.55)
                continue
            L.capsule(add(tp, (dx, 1)), add(bt, (dx, 0)), 0.55)
        f.part(L, CAGE, light=1, sep=O, thr=0.4)
    else:
        # cells rolled out onto the ground below
        for k, dx in enumerate((-10, 2, 14)):
            q = (c[0] + dx + p["cells_out"] * k, 78)
            f.part(Layer(W, H).rect(q[0] - 1.5, q[1] - 2, q[0] + 1.5, q[1] + 1), [C["cell_dim"], C["cell_dim"], C["cell_lit"]], light=1)
    # --- grabber claws (folded under / opened)
    for side, bx, ramp in ((-1, -12, [C["hull_0"], C["hull_1"], C["hull_1"]]), (1, 12, HULL[:3])):
        root = xf(add(c, (bx, 9)))
        op = p["claw"]
        elbow = add(root, rot((side * (3 + 3 * op), 5 + 2 * op), p["tilt"]))
        tipa = add(elbow, rot((side * (4 + 4 * op), 4 - 2 * op), p["tilt"]))
        tipb = add(elbow, rot((side * (1 - 1 * op), 6 + 1 * op), p["tilt"]))
        L = Layer(W, H).capsule(root, elbow, 1.6, 1.2).capsule(elbow, tipa, 1.1, 0.5).capsule(elbow, tipb, 1.1, 0.5)
        f.part(L, ramp, light=1, sep=O)
    # --- hull: hearse-like body (split in two halves on death)
    import numpy as np
    from pixrig import shift
    hpts = [(c[0] - 25, c[1] - 3), (c[0] - 20, c[1] - 12), (c[0] - 4, c[1] - 15), (c[0] + 13, c[1] - 14), (c[0] + 22, c[1] - 8),
            (c[0] + 25, c[1] + 2), (c[0] + 22, c[1] + 10), (c[0] - 20, c[1] + 10), (c[0] - 26, c[1] + 5)]
    m = Layer(W, H).poly(xf.pts(hpts)).mask()
    if sp > 0:
        X = np.arange(W)[None, :].repeat(H, 0)
        s_i = int(round(sp))
        cut = int(c[0]) + 1
        f.part(shift(m & (X < cut), -s_i, s_i // 2), HULL, light=2, shade=1, sep=O)
        f.part(shift(m & (X >= cut), s_i, s_i // 3), HULL, light=2, shade=1, sep=O)
    else:
        f.part(m, HULL, light=2, shade=1, sep=O)
        for x0 in (-12, 0, 11):
            f.part(Layer(W, H).capsule(xf((c[0] + x0, c[1] - 10)), xf((c[0] + x0 - 1, c[1] + 9)), 0.4), [C["hull_0"]], light=0, shade=0, thr=0.35)
        for (rx, ry) in ((-16, 5), (-5, 6), (6, 6), (17, 4), (-10, -6), (8, -7)):
            f.px(xf((c[0] + rx, c[1] + ry)), C["hull_3"])
        for (rx, ry, ln) in ((-8, -3, 5), (13, -2, 4), (-19, 1, 3)):
            f.part(Layer(W, H).capsule(xf((c[0] + rx, c[1] + ry)), xf((c[0] + rx, c[1] + ry + ln)), 0.5), RUST, light=0, shade=0, thr=0.35)
        band = xf.pts([(c[0] - 21, c[1] + 1), (c[0] + 22, c[1] + 1), (c[0] + 22, c[1] + 3), (c[0] - 22, c[1] + 3)])
        f.part(Layer(W, H).poly(band), [C["hull_1"]], light=0, shade=0)
    # --- press plate on the belly
    pp = p["press"]
    pl = xf.pts([(c[0] - 13, c[1] + 10.5 + pp), (c[0] + 11, c[1] + 10.5 + pp), (c[0] + 11, c[1] + 13.5 + pp), (c[0] - 13, c[1] + 13.5 + pp)])
    if pp > 0.5:
        for dx in (-8, 6):
            f.part(Layer(W, H).capsule(xf((c[0] + dx, c[1] + 9)), xf((c[0] + dx, c[1] + 10 + pp)), 0.9), CAB, light=1)
    f.part(Layer(W, H).poly(pl), [C["hull_0"], C["hull_1"], C["hull_2"]], light=1, sep=O)
    # --- lamp-eye housing at the front (lens drawn by code)
    ec = xf((c[0] + 19, c[1] - 2))
    if sp == 0 or True:
        exf = add(ec, (round(sp), round(sp) // 3))
        f.part(Layer(W, H).circle(exf, 5.2), [C["cable_0"], C["hull_1"], C["hull_2"]], light=1, sep=O)
        f.part(Layer(W, H).circle(exf, 3.6), [C["lamp_housing"]], light=0, shade=0)
        f.part(Layer(W, H).capsule(add(exf, (-4, -5)), add(exf, (4, -5.5)), 0.9), HULL[:2], light=0)  # visor hood
    f.outline(O)
    if p["spark"]:
        for k in range(5):
            q = add(c, (((i * 11 + k * 17) % 41) - 20, ((i * 7 + k * 13) % 23) - 16))
            f.px(q, C["hull_3"] if k % 2 else C["cell_lit"])
    return f


def P(**kw):
    return merge(REST, kw)


def build():
    A = []
    A.append(Anim("idle", [draw(P(by=-1.5 * math.sin(2 * math.pi * i / 6), rot=i, hook=4 * math.sin(2 * math.pi * i / 6 + 1)), i).image() for i in range(6)], 10, True))
    A.append(Anim("move", [draw(P(tilt=8, by=-1.0 * math.sin(2 * math.pi * i / 6), rot=i, hook=-14 + 3 * math.sin(i)), i).image() for i in range(6)], 10, True))
    A.append(Anim("windup_press", [draw(P(by=-2 * k, press=-1.5 * k / 3, rot=k, tilt=-2 * k / 3), k).image() for k in range(4)], 12, False))
    A.append(Anim("press", [draw(P(by=b, press=pr, rot=k, spark=int(k == 1)), k).image() for k, (b, pr) in enumerate(((2, 8), (4, 12), (4, 10), (1, 4)))], 18, False))
    A.append(Anim("windup_volley", [draw(P(tilt=-3 * k, x=-0.6 * k, rot=k), k).image() for k in range(4)], 12, False))
    A.append(Anim("volley", [draw(P(tilt=t, x=x, rot=k, spark=int(k == 0)), k).image() for k, (t, x) in enumerate(((-14, -4), (-10, -3), (-6, -1)))], 18, False))
    A.append(Anim("windup_dive", [draw(P(tilt=-8 * k / 3, by=-3 * k / 3, claw=0.33 * k, rot=k), k).image() for k in range(4)], 12, False))
    A.append(Anim("dive", [draw(P(tilt=t, by=b, claw=1.0, rot=k, hook=-30), k).image() for k, (t, b) in enumerate(((20, 2), (26, 5), (22, 6)))], 20, False))
    A.append(Anim("windup_sweep", [draw(P(hook=-20 - 15 * k, tilt=-2 * k, rot=k), k).image() for k in range(4)], 12, False))
    A.append(Anim("sweep", [draw(P(hook=h, tilt=t, rot=k), k).image() for k, (h, t) in enumerate(((-70, -6), (-30, 0), (20, 6), (60, 8), (40, 4), (10, 0)))], 16, False))
    A.append(Anim("hurt", [draw(P(tilt=-8, x=-3, by=-1, spark=1, rot=0), 0).image(), draw(P(tilt=5, x=-2, rot=1), 1).image(), draw(P(tilt=0, x=-1, rot=2), 2).image()], 14, False))
    ph = []
    for k in range(10):
        ph.append(draw(P(crack=int(k >= 3), lit=int(k >= 3 and k % 2 == 1) if k < 8 else 1, by=-2 * math.sin(k * 0.9), x=math.sin(k * 2.3) * (1.5 if k < 6 else 0.5), rot=k, spark=int(k in (3, 5))), k).image())
    A.append(Anim("phase2", ph, 12, False))
    A.append(Anim("rotors_cut", [draw(P(cut=1, crack=1, lit=1, tilt=t, by=b, spark=1, rot=k), k).image() for k, (t, b) in enumerate(((-6, 1), (8, 3), (-4, 3), (2, 2)))], 12, False))
    dd = []
    for k in range(14):
        t = k / 13
        drop = min(16, 30 * t * t)
        dd.append(draw(P(cut=2 if k > 2 else 1, crack=1, lit=int(k < 6), tilt=10 * math.sin(k * 1.3) * (1 - t) + 12 * t, drop=drop, split=max(0.0, (k - 8) * 1.2),
                         cells_out=1 if k >= 9 else 0, claw=min(1, t * 2), spark=int(k % 3 == 0), rot=k, hook=40 * t), k).image())
    A.append(Anim("death", dd, 12, False))
    return A


if __name__ == "__main__":
    emit("collector_drone", (W, H), (48, 64), build(), sub="bosses")
