"""Machine enemies/props as code rigs: hopper, scout_drone, signal_drone, watcher, collector_eye.

Usage: python3 rig_machines.py [hopper scout_drone signal_drone watcher collector_eye]
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, Frame, Anim, rot, add, mul, lerp2, interp_pose, merge  # noqa
from rig_enemies import emit, PAL  # noqa

E = PAL["palettes"]["char_enemy"]["colors"]
CB = PAL["palettes"]["char_boss_collector"]["colors"]


class Xf:
    """Local->cell transform: rotate by tilt (deg, + = clockwise on screen) around pivot, then translate."""

    def __init__(self, pivot, tilt=0.0, off=(0, 0), flip=False):
        self.pv, self.t, self.off, self.flip = pivot, tilt, off, flip

    def __call__(self, p):
        q = (p[0] - self.pv[0], p[1] - self.pv[1])
        q = rot(q, self.t)
        return (self.pv[0] + q[0] + self.off[0], self.pv[1] + q[1] + self.off[1])

    def pts(self, ps):
        return [self(p) for p in ps]


def spring(L, a, b, coils, width, r=0.55):
    """A zig-zag coil spring between a and b."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    pts = [a]
    for i in range(1, coils * 2):
        t = i / (coils * 2)
        s = width if i % 2 else -width
        pts.append((a[0] + dx * t + nx * s, a[1] + dy * t + ny * s))
    pts.append(b)
    for p, q in zip(pts, pts[1:]):
        L.capsule(p, q, r)
    return L


def run_keys(draw, keys, n, W, H):
    out = []
    for i in range(n):
        t = i / (n - 1) if n > 1 else 0
        out.append(draw(interp_pose(keys, t), i).image())
    return out


# ====================================================================== HOPPER
def coil(f, hip, foot, turns, c_front, c_back, c_ring, width=1.5):
    """AD redo: a readable pixel coil spring. 'turns' full turns between hip and foot, 3 px wide:
    front diagonals in c_front (steel_2), back diagonals in c_back (steel_0), drawn back-first."""
    import numpy as np
    dx, dy = foot[0] - hip[0], foot[1] - hip[1]
    ln = math.hypot(dx, dy) or 1.0
    ux, uy = dx / ln, dy / ln
    nx, ny = -uy, ux
    halves = turns * 2
    segs = []
    for k in range(halves):
        u0, u1 = ln * k / halves, ln * (k + 1) / halves
        v0, v1 = (-width, width) if k % 2 == 0 else (width, -width)
        segs.append((k % 2, u0, v0, u1, v1))
    for layer in (1, 0):  # back diagonals first, then front
        for side, u0, v0, u1, v1 in segs:
            if side != layer:
                continue
            col = c_front if side == 0 else c_back
            for t in np.linspace(0, 1, 8):
                u, v = u0 + (u1 - u0) * t, v0 + (v1 - v0) * t
                f.px((hip[0] + ux * u + nx * v, hip[1] + uy * u + ny * v), col)
    # end rings so the coil visibly seats in the hip socket and the foot pad
    for q in (hip, foot):
        for v in (-width, 0, width):
            f.px((q[0] + nx * v, q[1] + ny * v), c_ring)


def hopper():
    W = H = 32
    O = E["outline"]
    KH = [E["khaki_0"], E["khaki_1"], E["khaki_2"]]
    ST = [E["steel_0"], E["steel_1"], E["steel_2"]]
    # comp: 1 = fully compressed (2 tight turns), 0 rest (3), -1 stretched (4 turns)
    # by: shell height offset (airborne height beyond ~4 px is moved by code, not drawn)
    # la: leg angle in shell space (deg, + = legs swing back), ground: 1 = feet planted
    REST = dict(by=0.0, tilt=0.0, comp=0.0, la=0.0, spark=0, flipy=0.0, ant=0.0, x=0.0, planted=1)

    def draw(p, i):
        f = Frame(W, H)
        ground = 29.6
        comp = p["comp"]
        body_c = (15 + p["x"], 17.5 + p["by"] + comp * 3.0)
        xf = Xf(body_c, p["tilt"])
        turns = 2 if comp >= 0.8 else (4 if comp <= -0.5 else 3)
        rest_len = {2: 5.0, 3: 7.5, 4: 10.0}[turns]
        for side, dx in (("b", -2.2), ("f", 2.0)):
            hip_l = (body_c[0] - 1.0 + dx, body_c[1] + 3.6)  # fixed hip joint on the shell underside
            hip = xf(hip_l)
            if p["planted"] and p["flipy"] < 0.5:
                foot = (hip[0] - 0.5 + dx * 0.4 - p["la"] * 0.06, ground)
            else:
                foot = xf(add(hip_l, rot((0, rest_len), p["la"])))
            # hip socket block (steel, part of the shell underside)
            f.part(Layer(W, H).ellipse(hip, 1.8, 1.2), [E["steel_0"], E["steel_1"], E["steel_2"]], light=1, shade=0, sep=O if side == "f" else None)
            if side == "b":
                coil(f, hip, foot, turns, E["steel_1"], E["outline_hi"], E["steel_0"])
            else:
                coil(f, hip, foot, turns, E["steel_2"], E["steel_0"], E["steel_1"])
            f.part(Layer(W, H).capsule(add(foot, (-1.6, 0.3)), add(foot, (1.8, 0.3)), 0.8), [E["steel_0"], E["steel_1"]], light=0)
        # shell
        shell = Layer(W, H).ellipse(body_c, 7.2, 4.8)
        f.part(shell, KH + [E["lamp_pale"]], light=1, shade=1, sep=O)
        for k in (-2.5, 1.5):
            a, b = xf((body_c[0] + k, body_c[1] - 4.2)), xf((body_c[0] + k - 1.0, body_c[1] + 3.0))
            f.part(Layer(W, H).capsule(a, b, 0.4), [E["khaki_0"]], light=0, shade=0, thr=0.35)
        f.px(xf((body_c[0] - 4, body_c[1] + 1)), E["brass_0"])
        eye = xf((body_c[0] + 5.2, body_c[1] - 0.8))
        f.part(Layer(W, H).circle(eye, 1.9), [E["steel_0"], E["steel_1"], E["steel_2"]], light=1, sep=O)
        f.part(Layer(W, H).circle(eye, 1.0), [E["lamp_pale"]], light=0, shade=0, thr=0.3)
        for a0, ln in ((-60 + p["ant"], 5), (-35 + p["ant"] * 1.3, 4)):
            base = xf((body_c[0] + 3.5, body_c[1] - 4))
            tipv = rot((0, -ln), a0 + p["tilt"])
            f.part(Layer(W, H).capsule(base, add(base, tipv), 0.35), [E["steel_2"]], light=0, shade=0, thr=0.25)
        f.outline(O)
        if p["spark"]:
            for k in range(3):
                f.px(add(body_c, ((i * 7 + k * 5) % 11 - 5, -(i * 3 + k * 4) % 8 - 3)), E["lamp_pale"])
        return f

    def fitd(p, i):
        p = dict(p)
        for _ in range(20):
            fr = draw(p, i)
            e = fr.edges()
            if not e:
                return fr
            if "T" in e:
                p["by"] += 1
            if "L" in e:
                p["x"] += 1
            if "R" in e:
                p["x"] -= 1
        raise RuntimeError(f"hopper pose clips {e}")

    def P(**kw):
        return merge(REST, kw)

    def run(keys, n):
        return [fitd(interp_pose(keys, i / (n - 1)), i).image() for i in range(n)]

    A = []
    A.append(Anim("idle", run([(0, P()), (0.5, P(comp=0.35, ant=6)), (1, P())], 4), 8, True))
    # hop cycle, in-cell part only (code adds the airborne arc): load, launch, stretch, tuck, reach, land
    mv = [P(comp=0.5), P(comp=0.95, tilt=-4), P(comp=-0.7, by=-3, tilt=-10, planted=0, la=18), P(comp=-0.2, by=-4, tilt=0, planted=0, la=6),
          P(comp=-0.6, by=-2, tilt=8, planted=0, la=-14), P(comp=0.6, tilt=0)]
    A.append(Anim("move", [fitd(m, i).image() for i, m in enumerate(mv)], 12, True))
    A.append(Anim("windup", run([(0, P()), (0.5, P(comp=0.9, tilt=-6)), (1, P(comp=1.2, tilt=-10, ant=12))], 4), 12, False))
    at = [P(comp=-1.0, by=-2, tilt=18, planted=0, la=40, x=4), P(comp=-0.8, by=-2, tilt=20, planted=0, la=34, x=5), P(comp=0.2, by=0, tilt=6, x=3)]
    A.append(Anim("attack", [fitd(m, i).image() for i, m in enumerate(at)], 18, False))
    A.append(Anim("hurt", [fitd(P(tilt=-14, x=0, comp=0.4, spark=1), 0).image(), fitd(P(tilt=-6, x=0, comp=0.2), 1).image()], 14, False))
    dd = [P(tilt=-20, comp=0.3, spark=1), P(tilt=-70, by=-3, comp=-0.4, spark=1, planted=0), P(tilt=-130, by=-3, comp=-0.5, planted=0), P(tilt=-180, by=0, flipy=1, spark=1, planted=0),
          P(tilt=-180, by=1, flipy=1, spark=1, planted=0, comp=-0.2), P(tilt=-180, by=1, flipy=1, planted=0, comp=0.2)]
    A.append(Anim("death", [fitd(m, i).image() for i, m in enumerate(dd)], 12, False))
    return emit("hopper", (W, H), (16, 30), A)


# ====================================================================== DRONES
def _drone(name, hull, lens_r=3.0, dish=False, cable=False):
    W = H = 32
    O = E["outline"]
    REST = dict(by=0.0, x=0.0, tilt=0.0, iris=1.0, rotor=0, spin=0.0, dead=0, spark=0)

    def draw(p, i):
        f = Frame(W, H)
        c = (16 + p["x"], 16 + p["by"])
        xf = Xf(c, p["tilt"] + p["spin"])
        # tail sensor hook + dangling antenna (behind)
        tail = xf.pts([(c[0] - 7, c[1] + 1), (c[0] - 10, c[1] + 2), (c[0] - 11, c[1] + 4.5), (c[0] - 9.6, c[1] + 5.5)])
        L = Layer(W, H)
        for a, b in zip(tail, tail[1:]):
            L.capsule(a, b, 0.6)
        f.part(L, [E["steel_0"], E["steel_1"]], light=0, thr=0.35)
        ant0 = xf((c[0] - 2, c[1] + 5))
        ant1 = add(ant0, (math.sin(p.get("sway", 0)) * 1.5 - 1, 6))
        f.part(Layer(W, H).capsule(ant0, ant1, 0.35), [E["steel_2"]], light=0, shade=0, thr=0.25)
        f.px(ant1, E["steel_3"])
        if cable:
            pts = [xf((c[0] - 6, c[1] + 3))]
            for k in range(1, 4):  # AD redo: trailing cable shortened so it ends at x >= 2
                pts.append(add(pts[-1], (-1.8, 1.7 + math.sin(p.get("sway", 0) + k) * 0.8)))
            L = Layer(W, H)
            for a, b in zip(pts, pts[1:]):
                L.capsule(a, b, 0.45)
            f.part(L, [E["cloth_grey"], E["steel_0"]], light=0, shade=0, thr=0.3)
        # hull: rounded lantern body
        hp = xf.pts([(c[0] - 7, c[1] - 4), (c[0] + 5, c[1] - 5), (c[0] + 8, c[1] - 1), (c[0] + 7, c[1] + 4), (c[0] - 4, c[1] + 6), (c[0] - 8, c[1] + 2)])
        f.part(Layer(W, H).poly(hp), hull, light=1, shade=1, sep=O)
        # dents + rivets
        for q in ((c[0] - 4, c[1] - 1), (c[0] + 1, c[1] + 3), (c[0] - 1, c[1] - 3)):
            f.px(xf(q), hull[0])
        # cap ring
        f.part(Layer(W, H).capsule(xf((c[0] - 5, c[1] - 4.5)), xf((c[0] + 4, c[1] - 5.3)), 0.8), [E["steel_0"], E["steel_1"]], light=0)
        # rotor mast + blur
        if not p["dead"]:
            mast0, mast1 = xf((c[0] - 1, c[1] - 5)), xf((c[0] - 1, c[1] - 8))
            f.part(Layer(W, H).capsule(mast0, mast1, 0.6), [E["steel_1"]], light=0, shade=0, thr=0.35)
            span = 8.0 if p["rotor"] % 2 == 0 else 4.0
            f.part(Layer(W, H).ellipse(mast1, span, 0.8), [E["steel_2"] if p["rotor"] % 2 == 0 else E["steel_1"]], light=0, shade=0, thr=0.4)
        # dish (signal drone)
        if dish:
            d0 = xf((c[0] + 1, c[1] - 6))
            d1 = xf((c[0] + 4, c[1] - 10))
            f.part(Layer(W, H).capsule(d0, d1, 0.5), [E["steel_1"]], light=0, shade=0, thr=0.3)
            f.part(Layer(W, H).ellipse(d1, 2.6, 1.2), [E["steel_1"], E["steel_2"], E["steel_3"]], light=1, thr=0.4)
        # the big lens (dark glass; the aim line/pupil stay code-drawn)
        lc = xf((c[0] + 5.5, c[1] + 0.5))
        f.part(Layer(W, H).circle(lc, lens_r), [E["steel_0"], E["steel_1"], E["steel_2"]], light=1, sep=O)
        f.part(Layer(W, H).circle(lc, lens_r - 0.9), [E["lens_dark"], E["lens_glass"], E["lens_glass"]], light=1, shade=0)
        ir = max(0.5, (lens_r - 1.6) * p["iris"])
        f.part(Layer(W, H).circle(lc, ir), [E["lens_dark"]], light=0, shade=0, thr=0.3)
        f.px(add(lc, (-1, -1)), E["steel_3"])
        f.outline(O)
        if p["spark"]:
            for k in range(3):
                f.px(add(c, ((i * 5 + k * 7) % 13 - 6, (i * 3 + k * 5) % 9 - 6)), E["lamp_pale"])
        return f

    _draw = draw

    def draw(p, i):  # AD redo: keep every frame 1 px inside the cell (x shift only; origin unchanged)
        p = dict(p)
        for _ in range(12):
            fr = _draw(p, i)
            e = fr.edges()
            if not e:
                return fr
            if "L" in e:
                p["x"] += 1
            if "R" in e:
                p["x"] -= 1
            if "T" in e:
                p["by"] += 1
        raise RuntimeError(f"{name} pose clips {e}")

    def P(**kw):
        return merge(REST, kw)

    A = []
    A.append(Anim("idle", [draw(P(by=-0.8 * math.sin(2 * math.pi * i / 4), rotor=i, sway=i * 1.6), i).image() for i in range(4)], 12, True))
    A.append(Anim("move", [draw(P(tilt=12, by=-0.5 * math.sin(2 * math.pi * i / 4), rotor=i, sway=i * 1.6 + 1), i).image() for i in range(4)], 12, True))
    A.append(Anim("windup", [draw(P(iris=1.0 - 0.25 * i, tilt=-4 - i, rotor=i, x=-0.4 * i), i).image() for i in range(4)], 12, False))
    A.append(Anim("attack", [draw(P(iris=0.3, tilt=-16, x=-2, rotor=0, spark=1), 0).image(), draw(P(iris=0.5, tilt=-10, x=-1.5, rotor=1), 1).image(), draw(P(iris=0.8, tilt=-4, x=-0.5, rotor=2), 2).image()], 18, False))
    A.append(Anim("hurt", [draw(P(tilt=-22, x=-2, by=1, rotor=0, spark=1), 0).image(), draw(P(tilt=-10, x=-1, rotor=1), 1).image()], 14, False))
    A.append(Anim("death", [draw(P(spin=60 * i, by=min(10, 1.2 * i * i), rotor=i, dead=(i >= 3), spark=(i % 2 == 0)), i).image() for i in range(6)], 12, False))
    return emit(name, (W, H), (16, 26), A)


def scout_drone():
    return _drone("scout_drone", [E["brass_0"], E["brass_1"], E["brass_2"]])


def signal_drone():
    return _drone("signal_drone", [E["scrub_0"], E["scrub_1"], E["steel_2"]], lens_r=2.4, dish=True, cable=True)


# ====================================================================== WATCHER
def watcher():
    W = H = 24
    O = E["outline"]
    REST = dict(open=0.5, tilt=0.0, x=0.0, spark=0, broken=0)

    def draw(p, i):
        f = Frame(W, H)
        # wall plate + bracket
        f.part(Layer(W, H).rect(1, 6, 4, 21), [E["steel_0"], E["steel_1"], E["steel_2"]], light=1)
        for y in (8, 18):
            f.px((2, y), E["outline_hi"])
        piv = (7.5, 12.0)
        f.part(Layer(W, H).capsule((3.5, 13), piv, 1.0), [E["steel_0"], E["steel_1"]], light=1)
        xf = Xf(piv, p["tilt"], (p["x"], 0))
        # conduit cable from housing to the wall bottom
        cab = [xf((9, 15)), (7.5, 18.5), (4.5, 20.5)]
        L = Layer(W, H)
        for a, b in zip(cab, cab[1:]):
            L.capsule(a, b, 0.6)
        f.part(L, [E["cloth_grey"], E["steel_0"]], light=0, thr=0.35)
        # housing
        hs = xf.pts([(7, 8.5), (18, 8.0), (19.5, 10.5), (19.5, 14.5), (18, 16), (8, 15.5)])
        f.part(Layer(W, H).poly(hs), [E["brass_0"], E["rose_0"], E["rose_1"]] if False else [E["steel_0"], E["steel_1"], E["steel_2"], E["steel_3"]], light=1, shade=1, sep=O)
        # hood lip
        f.part(Layer(W, H).poly(xf.pts([(8, 7.2), (20.5, 7.0), (21.5, 9.0), (8, 9.2)])), [E["steel_0"], E["steel_1"]], light=0)
        # rust streak
        f.px(xf((11, 14)), E["rose_0"])
        f.px(xf((11, 15)), E["rose_0"])
        # lens + iris shutters (lens dark; the tracking pupil is code-drawn)
        lc = xf((18.0, 12.0))
        f.part(Layer(W, H).circle(lc, 3.0), [E["steel_1"], E["steel_2"], E["steel_3"]], light=1, shade=1, sep=O)
        f.part(Layer(W, H).circle(lc, 1.9), [E["lens_dark"], E["lens_dark"], E["lens_glass"]], light=1, shade=0)
        cover = 2.4 * (1 - p["open"])
        if cover > 0.2:
            f.part(Layer(W, H).poly(xf.pts([(15.5, 9.8), (20.5, 9.8), (20.5, 9.8 + cover), (15.5, 9.8 + cover)])), [E["steel_1"], E["steel_2"]], light=0)
            f.part(Layer(W, H).poly(xf.pts([(15.5, 14.2 - cover), (20.5, 14.2 - cover), (20.5, 14.2), (15.5, 14.2)])), [E["steel_0"], E["steel_1"]], light=0)
        f.outline(O)
        if p["spark"]:
            f.px(add(lc, (1 + i % 2, -3)), E["lamp_pale"])
            f.px(add(lc, (-2, 3 + i % 2)), E["lamp_pale"])
        return f

    def P(**kw):
        return merge(REST, kw)

    A = []
    A.append(Anim("idle", [draw(P(open=o), i).image() for i, o in enumerate((0.55, 0.55, 0.1, 0.45))], 6, True))
    A.append(Anim("windup", [draw(P(open=o), i).image() for i, o in enumerate((0.6, 0.8, 1.0, 1.0))], 12, False))
    A.append(Anim("attack", [draw(P(open=1.0, x=-1.2, tilt=-3), 0).image(), draw(P(open=0.9, x=-0.6), 1).image(), draw(P(open=0.7), 2).image()], 18, False))
    A.append(Anim("hurt", [draw(P(open=0.2, tilt=-8, spark=1), 0).image(), draw(P(open=0.4, tilt=-3), 1).image()], 14, False))
    A.append(Anim("death", [draw(P(open=o, tilt=t, spark=s), i).image() for i, (o, t, s) in enumerate(((0.3, -10, 1), (0.1, 25, 1), (0.0, 55, 0), (0.0, 70, 1), (0.0, 66, 0)))], 12, False))
    return emit("watcher", (W, H), (12, 22), A)


# ====================================================================== COLLECTOR EYE (ceiling rail tracker)
def collector_eye():
    W = H = 32
    O = CB["outline"]
    HULL = [CB["hull_0"], CB["hull_1"], CB["hull_2"], CB["hull_3"]]
    REST = dict(em=1.0, look=0.0, iris=1.0, x=0.0, recoil=0.0, trolley=1)

    def draw(p, i):
        f = Frame(W, H)
        # rail trolley at the top (origin 16,4 is the rail point)
        f.part(Layer(W, H).rect(9, 1, 23, 5), [CB["cable_0"], CB["cable_1"], CB["hull_1"]], light=1)
        for x in (11, 21):
            f.part(Layer(W, H).circle((x, 2.0), 1.4), [CB["cage_0"], CB["cage_1"]], light=1)
        em = p["em"]
        if em > 0.05:
            drop = 4 + 14 * em
            piv = (16 + p["x"], 5)
            xf = Xf(piv, p["look"])
            # telescoping neck
            f.part(Layer(W, H).capsule(xf((16 + p["x"], 5)), xf((16 + p["x"], drop - 2)), 1.6), [CB["cable_0"], CB["cable_1"], CB["cage_1"]], light=1)
            # trailing cable
            f.part(Layer(W, H).capsule(xf((13 + p["x"], 6)), xf((11 + p["x"], drop - 1)), 0.6), [CB["cable_0"], CB["cable_1"]], light=0, thr=0.35)
            # armoured pod
            c = xf((16 + p["x"], drop + 2 - p["recoil"]))
            f.part(Layer(W, H).ellipse(c, 6.0, 4.6), HULL, light=1, shade=1, sep=O)
            f.part(Layer(W, H).capsule(add(c, (-5.4, -1.5)), add(c, (5.4, -1.5)), 0.5), [CB["hull_0"]], light=0, shade=0, thr=0.35)
            # iris lens facing down / along the look direction (lens dark, the red lens stays code)
            lc = add(c, rot((0, 3.4), p["look"]))
            f.part(Layer(W, H).circle(lc, 2.6), [CB["lamp_housing"], CB["cage_0"], CB["cage_1"]], light=1, sep=O)
            f.part(Layer(W, H).circle(lc, max(0.6, 1.5 * p["iris"])), [CB["lamp_housing"]], light=0, shade=0, thr=0.3)
            f.px(add(c, (-3, -2)), CB["rust_1"])
        f.outline(O)
        return f

    def P(**kw):
        return merge(REST, kw)

    A = []
    A.append(Anim("dormant", [draw(P(em=0.0), 0).image()], 1, False))
    A.append(Anim("emerge", [draw(P(em=e), i).image() for i, e in enumerate((0.1, 0.3, 0.55, 0.8, 1.05, 1.0))], 12, False))
    A.append(Anim("track", [draw(P(look=lk), i).image() for i, lk in enumerate((25, 10, -10, -25))], 6, True))
    A.append(Anim("lock", [draw(P(iris=0.5), 0).image(), draw(P(iris=0.3), 1).image()], 12, False))
    A.append(Anim("fire", [draw(P(iris=0.3, recoil=2.0), 0).image(), draw(P(iris=0.5, recoil=1.0), 1).image(), draw(P(iris=0.8, recoil=0.0), 2).image()], 18, False))
    A.append(Anim("retract", [draw(P(em=e), i).image() for i, e in enumerate((1.0, 0.8, 0.55, 0.3, 0.1, 0.0))], 12, False))
    A.append(Anim("gone", [draw(P(em=0.0), 0).image()], 1, False))
    return emit("collector_eye", (W, H), (16, 4), A, sub="undercity")


if __name__ == "__main__":
    for w in (sys.argv[1:] or ["hopper", "scout_drone", "signal_drone", "watcher", "collector_eye"]):
        globals()[w]()
