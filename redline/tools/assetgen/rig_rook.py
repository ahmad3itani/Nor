"""Rook: code rig -> assets/rook/rook_sheet.png + rook_sheet.tres (cell 48x48, origin 24,46).

Usage: python3 rig_rook.py [--check] [--test]
"""
from __future__ import annotations

import json
import tempfile
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, Frame, Anim, dirv, tup, tfwd, tdn, add, mul, lerp2, interp_pose, merge, write_sheet, preview, check_sheet, red_mask  # noqa
from humanoid import Skeleton, REST, chain  # noqa
from pixrig import shift, dilate, hex2rgb  # noqa
import numpy as np
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

ROOT = REDLINE
PAL = json.load(open(os.path.join(DATA, "palettes.json")))
C = PAL["palettes"]["char_rook"]["colors"]
RESERVED = list(PAL["reserved"].values())

W = H = 48
ORIGIN = (24, 46)
SK = Skeleton(dict(hip=(24, 25), thigh=9.5, shin=9.5, foot=3.2, torso=11.5, neck=4.6, head_r=3.2,
                   uarm=6.5, farm=6.0, shoulder_drop=1.5, ground=45.6))

COAT = [C["coat_0"], C["coat_1"], C["coat_2"], C["coat_3"]]
SUIT = [C["suit_0"], C["suit_1"], C["suit_2"]]
HELM = [C["suit_1"], C["suit_2"], C["suit_2"]]  # AD redo: mid lifted #2c2838 -> #3d3850; rim is coat_1
STRAP = [C["strap_0"], C["strap_1"]]
METAL = [C["metal_0"], C["metal_1"], C["blade_edge"]]
OUT = C["outline"]


def _edge_rim(f, idx_list, colour, rows=None, top=True, back=True):
    """1 px rim light on pixels still owned by the given parts whose top or back (-x)
    neighbour is background in the final alpha (the rim only lands against the scene)."""
    own = np.isin(f.owner, idx_list) & f.alpha
    if rows is not None:
        yy = np.arange(f.h)[:, None]
        own &= (yy >= rows[0]) & (yy <= rows[1])
    r = np.zeros_like(own)
    if top:
        r |= own & ~shift(f.alpha, 0, 1)
    if back:
        r |= own & ~shift(f.alpha, 1, 0)
    f.rgb[r] = hex2rgb(colour)
    return r


def _last(f):
    return f._n - 1


def draw(p: dict, weapon: str = "blade", core: float = 1.0) -> Frame:
    j = SK.solve(p)
    kick = p.get("kick", 0.0)
    if kick:
        sh_, el_, ha_, ua_, fa_ = j["fa"]
        j["fa"] = (sh_, add(el_, (-kick * 0.5, 0)), add(ha_, (-kick, 0)), ua_, fa_)
    f = Frame(W, H)
    hip, neck, head, up = j["hip"], j["neck"], j["head"], j["up"]
    lean = p["lean"]
    perp = tfwd(lean)  # torso-forward direction
    WB, WF = 4.4, 3.9  # torso half widths back / front (widened +1 px per side, AD redo)
    rim_suit, rim_helm = [], []

    # ---- back arm (sleeve + glove)
    sh, el, ha, ua, fa = j["ba"]
    L = Layer(W, H).capsule(sh, el, 1.7, 1.5).capsule(el, ha, 1.5, 1.2)
    f.part(L, [C["coat_0"], C["coat_1"], C["coat_1"]], light=0)
    _glove(f, ha)
    if weapon == "katar":
        _katar(f, ha, fa + p["wpn"], back=True, length=p.get("klen", 6.0))

    # ---- back leg
    hp, kn, an, ft, h_, sa = j["bl"]
    L = Layer(W, H).capsule(hp, kn, 1.9, 1.5).capsule(kn, an, 1.5, 1.3)
    f.part(L, [C["suit_0"], C["suit_1"], C["suit_2"]], light=1)
    rim_suit.append(_last(f))
    f.part(Layer(W, H).capsule(an, ft, 1.4, 1.0).capsule(add(an, (0, -1.5)), an, 1.5, 1.4), [C["strap_0"], C["strap_0"], C["strap_1"]], light=0)

    # ---- coat skirt (behind front leg), long torn tail at the back
    drag, lift, ph, amp = p["drag"], p["lift"], p["ph"], 4.0 * p["flutter"]
    cl = p.get("coat_len", 1.0)
    hipF = add(hip, mul(perp, WF - 0.1))
    hipB = add(hip, mul(perp, -WB - 0.1))
    front = chain(hipF, p["fl_h"] * 0.45 - 2 + p.get("flare", 0) * 0.6, 3.6 * cl, 3, drag * 0.45, ph, amp * 0.5, lift=lift * 0.5)
    back = chain(hipB, -14 - p.get("flare", 0), 5.0 * cl, 3, drag, ph + 0.8, amp, grow=0.12, lift=lift)
    fe, be = front[-1], back[-1]
    mid1 = lerp2(fe, be, 0.35)
    mid2 = lerp2(fe, be, 0.62)
    hem = [add(mid1, (0, -1.2)), add(lerp2(fe, be, 0.5), (0, 0.8)), add(mid2, (0, -1.4)), add(lerp2(fe, be, 0.8), (0, 1.0))]
    skirt = [add(neck, mul(perp, 2.8)), hipF] + front[1:] + hem + back[::-1][:-1] + [hipB, add(neck, mul(perp, -WB))]
    f.part(Layer(W, H).poly(skirt), COAT, light=1, shade=1)

    # ---- torso: coat body with the suit opening at the chest
    tb = [add(neck, mul(perp, -WB)), add(neck, mul(perp, WF)), add(add(neck, mul(up, -4)), mul(perp, WF + 0.3)),
          add(hip, mul(perp, WF - 0.2)), add(hip, mul(perp, -WB + 0.2))]
    f.part(Layer(W, H).poly(tb), COAT, light=1, shade=1)
    op = [add(add(neck, mul(perp, 1.5)), mul(up, -1.0)), add(add(neck, mul(perp, WF - 0.2)), mul(up, -1.0)),
          add(hip, mul(perp, WF - 0.2)), add(hip, mul(perp, 2.1))]
    f.part(Layer(W, H).poly(op), SUIT, light=0, shade=0)
    # belt strap
    bl = [add(add(hip, mul(up, 1.8)), mul(perp, -WB + 0.6)), add(add(hip, mul(up, 1.8)), mul(perp, WF - 0.2)),
          add(add(hip, mul(up, 0.8)), mul(perp, WF - 0.2)), add(add(hip, mul(up, 0.8)), mul(perp, -WB + 0.6))]
    f.part(Layer(W, H).poly(bl), STRAP, light=0, shade=0, thr=0.45)
    # diagonal chest strap
    f.part(Layer(W, H).capsule(add(neck, mul(perp, -2.6)), add(add(hip, mul(up, 2.5)), mul(perp, 3.0)), 0.5), [C["strap_1"]], light=0, shade=0, thr=0.4)

    # ---- front leg
    hp, kn, an, ft, h_, sa = j["fl"]
    L = Layer(W, H).capsule(hp, kn, 2.2, 1.7).capsule(kn, an, 1.7, 1.35)
    f.part(L, SUIT, light=1, sep=OUT)
    rim_suit.append(_last(f))
    f.part(Layer(W, H).capsule(an, ft, 1.4, 1.0).capsule(add(an, (0, -1.8)), an, 1.6, 1.5), STRAP + [C["strap_1"]], light=1)

    # ---- scarf (short, ragged) behind the head; 'scarf' cycles an extra phase
    sc = chain(add(neck, mul(perp, -1.4)), -80, 2.8, 2, -drag * 0.8 + 10 + p.get("scarf", 0), ph + 1.7, 12 * p["flutter"], lift=0)
    L = Layer(W, H).capsule(sc[0], sc[1], 1.6, 1.2).capsule(sc[1], sc[2], 1.2, 0.7)
    f.part(L, [C["coat_0"], C["coat_1"], C["coat_1"]], light=1, thr=0.45)
    # collar (wider with the torso)
    f.part(Layer(W, H).capsule(add(neck, mul(perp, -2.8)), add(neck, mul(perp, 2.4)), 1.5), [C["coat_0"], C["coat_1"], C["coat_2"]], light=1)

    # ---- head: smooth helmet-mask, mid lifted one step (suit_1 -> suit_2), rim added below
    hd = p["head"] + lean
    hL = Layer(W, H).ellipse(add(head, (0.2, -0.3)), 3.4, 3.7).capsule(add(head, tfwd(hd, 1.2)), add(head, add(tfwd(hd, 2.4), tdn(hd, 1.8))), 1.6)
    f.part(hL, HELM, light=0, shade=1, sep=OUT)
    rim_helm.append(_last(f))
    # visor slit: 3 px horizontal red at the front of the face
    vf = add(head, tfwd(hd, 1.6))
    for i in range(3):
        f.px(add(add(vf, tfwd(hd, i)), tup(hd, 0.6)), C["visor"])
    if p.get("glint"):
        f.px(add(add(vf, tfwd(hd, 2)), tup(hd, 0.6)), C["core_hot"])

    # ---- chest Core seam (2x3 red, pulses via core)
    cs = add(add(neck, mul(up, -3.2)), mul(perp, 2.6))
    col = C["core_hot"] if core > 1.2 else C["core_glow"]
    if core > 0.2:
        for dy in range(3):
            f.px(add(cs, mul(up, -dy)), col)
            if core > 0.6:
                f.px(add(add(cs, mul(up, -dy)), mul(perp, -1)), C["core_glow"])

    # ---- front arm + weapon
    sh, el, ha, ua, fa = j["fa"]
    if "wabs" in p:
        p = dict(p, wpn=p["wabs"] - fa)
    blen = p.get("blen", 10.0)
    L = Layer(W, H).capsule(sh, el, 1.8, 1.6)
    f.part(L, COAT[:3], light=1, sep=OUT)
    # forearm: its own part so its underside gets a 1 px darker line (no more white sticks)
    fm = f.part(Layer(W, H).capsule(el, ha, 1.5, 1.2), [C["coat_1"], C["coat_2"], C["coat_3"]], light=1, shade=0, sep=OUT)
    under = fm & ~shift(fm, 0, -1)
    f.rgb[under & (f.owner == _last(f))] = hex2rgb(C["coat_0"])
    if weapon == "blade" and p.get("wpn_on", 1):
        _blade(f, ha, fa + p["wpn"], length=blen)
    elif weapon == "katar":
        _katar(f, ha, fa + p["wpn"], length=p.get("klen", 6.0))
    elif weapon in ("pistol", "scatter", "revolver"):
        _gun(f, ha, weapon, rise=p.get("rise", 0))
    _glove(f, ha)

    # ---- rim light against the scene (top + back edges): helmet coat_1, undersuit coat_0
    top_y = int(math.floor(min(head[1] - 4.5, sh[1])))
    _edge_rim(f, rim_helm, C["coat_1"])
    _edge_rim(f, rim_suit, C["coat_0"], top=False)
    f.outline(OUT)
    return f


def _glove(f, hand):
    """2x2 glove in strap brown (fingerless leather), top row lit."""
    x, y = int(math.floor(hand[0] - 0.5)), int(math.floor(hand[1] - 0.5))
    for dy in range(2):
        for dx in range(2):
            f.px((x + dx, y + dy), C["strap_1"] if dy == 0 else C["strap_0"])


def _blade(f, hand, ang, length=10.0):
    tip = add(hand, dirv(ang, length))
    base = add(hand, dirv(ang, 1.2))
    pommel = add(hand, dirv(ang, -1.6))
    n = dirv(ang + 90, 1.0)
    blade = [add(base, mul(n, 0.9)), add(tip, mul(n, 0.1)), add(tip, mul(n, -0.4)), add(base, mul(n, -0.9))]
    f.part(Layer(W, H).poly(blade), [C["metal_0"], C["metal_0"], C["blade_edge"]], light=1, shade=0, thr=0.35, sep=OUT)
    f.part(Layer(W, H).capsule(pommel, base, 0.8), [C["suit_0"], C["strap_0"]], light=0, thr=0.35)
    g = [add(base, mul(n, 1.6)), add(base, mul(n, -1.6))]
    f.part(Layer(W, H).capsule(g[0], g[1], 0.55), [C["metal_0"]], light=0, shade=0, thr=0.3)


def _katar(f, hand, ang, back=False, length=6.0):
    tip = add(hand, dirv(ang, length))
    n = dirv(ang + 90, 1.0)
    blade = [add(hand, mul(n, 1.0)), tip, add(hand, mul(n, -1.0))]
    f.part(Layer(W, H).poly(blade), METAL if not back else [C["metal_0"], C["metal_0"], C["metal_1"]], light=1, shade=0, thr=0.35)


# Gun stamps (pointing +x, (0,0) = the gripping hand). Letters: a metal_0, b metal_1, e blade_edge, s strap_0, t strap_1
GUNS = {
    # service pistol: 7 px slide, short grip
    "pistol": (["bbbbbbe",
                "aaaaaa.",
                "ss.....",
                "s......"], 0, 1),
    # scattergun: 10 px, 2 px-thick barrel, pump, short stock behind the hand
    "scatter": (["...bbbbbbbbbe",
                 "tttaaaaaaaaaa",
                 "ttss.sss.....",
                 "t............"], 3, 1),
    # heavy revolver: 8 px, 3x3 cylinder with a chamber pixel, long top barrel
    "revolver": ([".bbb.....",
                  ".bab.bbbe",
                  ".bbbaaaaa",
                  "ss.......",
                  "s........"], 1, 2),
}


def _gun(f, hand, kind, rise=0.0):
    rows, ox, oy = GUNS[kind]
    cmap = {"a": C["metal_0"], "b": C["metal_1"], "e": C["blade_edge"], "s": C["strap_0"], "t": C["strap_1"]}
    hx, hy = int(math.floor(hand[0])), int(math.floor(hand[1]))
    n = max(len(r) for r in rows)
    ring = np.zeros((H, W), bool)
    pts = []
    for ry, r in enumerate(rows):
        for rx, ch in enumerate(r):
            if ch == ".":
                continue
            dx = rx - ox
            lift = int(round(rise * max(0, dx) / max(1, n - ox - 1)))
            pts.append((hx + dx, hy + ry - oy - lift, cmap[ch]))
    m = np.zeros((H, W), bool)
    for x, y, c in pts:
        if 0 <= x < W and 0 <= y < H:
            m[y, x] = True
    ring = dilate(m) & ~m & f.alpha
    f.rgb[ring] = hex2rgb(OUT)
    for x, y, c in pts:
        f.px((x, y), c)
    f._n += 1


def edges(f):
    a = f.alpha
    e = ""
    if a[0].any():
        e += "T"
    if a[:, 0].any():
        e += "L"
    if a[:, -1].any():
        e += "R"
    return e


def fit(p, weapon="blade", core=1.0):
    """Draw, and if anything touches row 0 / column 0 / column 47, pull the pose in:
    shorten the weapon first, then angle it back behind the head (overheads) or down
    (forward sweeps), then lower raised arms, then step the body back. The smear VFX
    supplies the reach. Never changes the cell or origin."""
    p = dict(p)
    for _ in range(40):
        f = draw(p, weapon=weapon, core=core)
        e = edges(f)
        if not e:
            return f
        sh, el, ha, ua, fa = SK.solve(p)["fa"]
        ang = fa + (p["wabs"] - fa if "wabs" in p else p["wpn"])
        if weapon == "blade" and p.get("blen", 10.0) > 7.0 and ("T" in e or "R" in e):
            p["blen"] = p.get("blen", 10.0) - 1.0
            continue
        if weapon == "katar" and p.get("klen", 6.0) > 4.0 and ("T" in e or "R" in e):
            p["klen"] = p.get("klen", 6.0) - 0.5
            continue
        if "T" in e:
            if weapon == "blade" and 100 < (ang % 360) < 235:
                # angle the blade back behind the head
                p.pop("wabs", None)
                p["wpn"] = ang + 12 - fa
                continue
            if p.get("fa_s", 0) > 125 or p.get("ba_s", 0) > 125:
                if p.get("fa_s", 0) > 125:
                    p["fa_s"] -= 6; p["fa_e"] = p.get("fa_e", 0) + 6
                if p.get("ba_s", 0) > 125:
                    p["ba_s"] -= 6; p["ba_e"] = p.get("ba_e", 0) + 6
                continue
            p["y"] = p.get("y", 0) + 1
            continue
        if "R" in e:
            if weapon == "blade" and 20 < (ang % 360) < 150:
                p.pop("wabs", None)
                p["wpn"] = ang - 10 - fa
                continue
            p["x"] = p.get("x", 0) - 1
            continue
        if "L" in e:
            p["x"] = p.get("x", 0) + 1
            p["drag"] = p.get("drag", 0) - 6
            continue
    raise RuntimeError(f"pose does not fit the 48x48 cell: {e}")


# ================================================================== animations
def run_cycle(t):
    """t 0..1 -> run pose (8 frames: contact, down, passing, up, contact, down, passing, up)."""
    a = 2 * math.pi * t
    s = math.sin(a)
    c = math.cos(a)
    bob = -1.2 * abs(math.sin(a)) + 0.6
    return merge(REST, dict(
        y=-bob, lean=14, fl_h=28 * c + 6, fl_k=38 + 32 * max(0, -s) if False else 30 + 28 * max(0.0, math.sin(a + 1.2)),
        bl_h=-28 * c + 6, bl_k=30 + 28 * max(0.0, math.sin(a + 1.2 + math.pi)),
        f_toe=-10 * c, b_toe=10 * c,
        fa_s=-40 * c + 25, fa_e=60, ba_s=40 * c + 15, ba_e=55,
        drag=26 + 4 * s, ph=a * 2, flutter=0.6, wabs=-60))


def _feet(p):
    j = SK.solve(merge(REST, p))
    return j["fl"][2][0], j["bl"][2][0]


def _plant(p, feet, iters=30):
    """Adjust thigh angles so both ankles stay at the given x while the hip rocks (x)."""
    q = merge(REST, p)
    for side, key, tgt in (("fl", "fl_h", feet[0]), ("bl", "bl_h", feet[1])):
        lo, hi = -80.0, 80.0
        for _ in range(iters):
            mid = (lo + hi) / 2
            q[key] = mid
            ax = SK.solve(q)[side][2][0]
            if ax < tgt:
                lo = mid
            else:
                hi = mid
    return q


def frames_from(fn, n, weapon="blade", **kw):
    return [fit(fn(i / n), weapon=weapon, **kw).image() for i in range(n)]


def keyed(keys, n, weapon="blade", hold_last=False, core=1.0):
    out = []
    for i in range(n):
        t = i / (n - 1) if n > 1 else 0
        out.append(fit(merge(REST, interp_pose(keys, t)), weapon=weapon, core=core).image())
    return out


IDLE = merge(REST, dict(lean=4, fa_s=6, fa_e=20, wabs=-35, ba_s=-6, ba_e=18, fl_h=6, fl_k=6, bl_h=-6, bl_k=4, drag=8, flare=13))


def build():
    A = []

    def add_anim(name, frames, fps, loop):
        A.append(Anim(name, frames, fps, loop))

    # idle: breathing (1 px), hem sway, glint on frame 5
    fr = []
    for i in range(8):
        a = 2 * math.pi * i / 8
        p = merge(IDLE, dict(y=0.5 * (1 - math.cos(a)) * 0.9, lean=4 + 1.2 * math.sin(a), ph=a, flutter=0.35,
                             fa_s=6 + 2 * math.sin(a), ba_s=-6 + 2 * math.sin(a), glint=(i == 4)))
        fr.append(fit(p, core=0.9 + 0.4 * (i in (3, 4, 5))).image())
    add_anim("idle", fr, 8, True)

    # idle_fidget: shoulder roll, glance at the chest seam, settle
    keys = [(0, IDLE), (0.2, merge(IDLE, dict(fa_s=0, ba_s=-2, lean=2, y=-0.5))),
            (0.4, merge(IDLE, dict(head=35, lean=8, fa_s=30, fa_e=70))),
            (0.65, merge(IDLE, dict(head=40, lean=9, fa_s=32, fa_e=75))),
            (0.85, merge(IDLE, dict(head=5, lean=5, fa_s=10))), (1.0, IDLE)]
    fr = [fit(merge(REST, interp_pose(keys, i / 11)), core=1.5 if 5 <= i <= 7 else 1.0).image() for i in range(12)]
    add_anim("idle_fidget", fr, 12, False)

    add_anim("run", frames_from(run_cycle, 8), 14, True)

    # turn: coat whips across (drag swings from + to -)
    keys = [(0, merge(run_cycle(0), dict(drag=26))), (0.5, merge(IDLE, dict(lean=-6, drag=-10, flutter=1.4, fl_h=18, bl_h=-14, fl_k=20))),
            (1, merge(IDLE, dict(lean=8, drag=14, fl_h=10, bl_h=-10)))]
    add_anim("turn", keyed(keys, 3), 16, False)

    AIR = merge(REST, dict(ground=0, fl_h=30, fl_k=60, bl_h=-12, bl_k=40, fa_s=40, fa_e=40, ba_s=-30, ba_e=30, wpn=-70, lean=6))
    add_anim("jump_rise", [fit(merge(AIR, dict(y=-2 + i, lift=-10, drag=-4, ph=i * 1.5, f_toe=20, b_toe=30))).image() for i in range(2)], 12, True)
    add_anim("air", [fit(merge(AIR, dict(y=-1, fl_h=24, fl_k=45, lift=6, drag=10, ph=1 + i * 1.6, fa_s=60, ba_s=-40))).image() for i in range(2)], 12, True)
    add_anim("jump_fall", [fit(merge(AIR, dict(y=-1, fl_h=14, fl_k=24, bl_h=-8, bl_k=18, lift=22, drag=14, ph=i * 2.0, flutter=1.4, fa_s=100, fa_e=10, ba_s=-80, ba_e=10, f_toe=15, b_toe=15))).image() for i in range(2)], 12, True)

    CROUCHP = merge(REST, dict(y=6, lean=24, fl_h=62, fl_k=110, bl_h=10, bl_k=100, fa_s=20, fa_e=50, ba_s=-20, ba_e=40, wpn=-80, drag=4, b_toe=20))
    keys = [(0, CROUCHP), (0.5, merge(CROUCHP, dict(y=3, lean=16, fl_h=40, fl_k=70, bl_h=0, bl_k=60))), (1, IDLE)]
    add_anim("land", keyed(keys, 3), 16, False)
    KNEE = merge(REST, dict(y=10, lean=30, fl_h=70, fl_k=110, bl_h=-30, bl_k=130, b_toe=60, fa_s=45, fa_e=10, ba_s=-30, ba_e=30, wpn=-100, drag=2, lift=-6))
    keys = [(0, KNEE), (0.3, merge(KNEE, dict(y=10, lean=34))), (0.6, CROUCHP), (0.85, merge(CROUCHP, dict(y=3, lean=14, fl_h=30, fl_k=50, bl_k=50))), (1, IDLE)]
    add_anim("land_hard", keyed(keys, 5), 14, False)

    CR = merge(REST, dict(y=0, lean=32, fl_h=78, fl_k=125, bl_h=6, bl_k=120, b_toe=40, fa_s=25, fa_e=50, ba_s=-10, ba_e=40, wpn=-80, drag=0, flutter=0.3))
    add_anim("crouch", [fit(merge(CR, dict(lean=30 + i * 3, ph=i))).image() for i in range(2)], 12, False)
    # slide (AD redo): knee slide, 18-20 px tall. Lead leg forward ~20 deg off the floor with a
    # normal shin, trailing knee down, torso leaning into it, coat flat behind; 3 frames each lower.
    SL = merge(REST, dict(x=-3, lean=54, head=-24, torso_k=0.7, neck_k=0.6, fl_h=74, fl_k=6, f_toe=-20, bl_h=-52, bl_k=100, b_toe=40,
                          fa_s=30, fa_e=60, ba_s=-60, ba_e=40, wabs=-95, drag=80, lift=0, flutter=0.4, coat_len=0.62, scarf=-10))
    add_anim("slide", [fit(merge(SL, dict(y=0.5 * i, lean=54 + 2 * i, fl_h=74 + 2 * i, drag=80 + 3 * i, lift=-3 * i, ph=i * 2.1, scarf=-10 + 20 * i))).image() for i in range(3)], 14, False)

    DG = merge(REST, dict(y=4, lean=45, fl_h=60, fl_k=100, bl_h=-30, bl_k=90, fa_s=70, fa_e=60, ba_s=-60, ba_e=40, wpn=-120, drag=50, lift=20, flutter=1.2))
    keys = [(0, merge(IDLE, dict(lean=18, y=2))), (0.25, DG), (0.6, merge(DG, dict(lean=55, drag=70, ph=2))), (0.85, merge(DG, dict(lean=30, drag=40, y=2, ph=4))), (1, merge(IDLE, dict(lean=12)))]
    add_anim("dodge", keyed(keys, 5), 20, False)
    # dash (AD redo): torso leans forward ~28 deg, coat streams horizontally behind with a
    # 1 px flutter step per frame, scarf cycles, legs scissor through a push-off.
    DS = merge(REST, dict(lean=28, head=-6, fa_s=-20, fa_e=60, ba_s=-70, ba_e=30, wabs=-130, drag=80, lift=6, flutter=0.5,
                          coat_len=0.85, ground=1))
    DSL = [dict(fl_h=40, fl_k=30, bl_h=-45, bl_k=40, f_toe=0, b_toe=40, ph=0.0, scarf=0, y=0),
           dict(fl_h=20, fl_k=70, bl_h=-20, bl_k=80, f_toe=20, b_toe=60, ph=1.6, scarf=25, y=-1),
           dict(fl_h=55, fl_k=45, bl_h=-60, bl_k=20, f_toe=-10, b_toe=20, ph=3.2, scarf=45, y=0),
           dict(fl_h=30, fl_k=90, bl_h=-30, bl_k=100, f_toe=30, b_toe=70, ph=4.8, scarf=15, y=-1)]
    add_anim("dash", [fit(merge(DS, DSL[i], dict(fa_s=-20 + 12 * (i % 2), lift=6 + 4 * (i % 2)))).image() for i in range(4)], 24, False)

    # ---- blade chain: anticipation, strike, follow-through, settle
    STAN = merge(IDLE, dict(fl_h=18, bl_h=-14, fl_k=12, bl_k=8, lean=10))

    def slash(name, n, wind, hit, follow, fps=18):
        keys = [(0, STAN), (0.22, merge(STAN, wind)), (0.45, merge(STAN, hit)), (0.72, merge(STAN, follow)), (1.0, merge(STAN, dict(lean=8)))]
        add_anim(name, keyed(keys, n), fps, False)

    slash("blade_light_1", 5, dict(fa_s=140, fa_e=30, wabs=-110, lean=0, drag=4), dict(fa_s=70, fa_e=0, wpn=0, lean=20, drag=20, x=2), dict(fa_s=20, fa_e=10, wpn=-10, lean=22, drag=16, x=2))
    slash("blade_light_2", 5, dict(fa_s=20, fa_e=40, wpn=-40, lean=18), dict(fa_s=110, fa_e=10, wpn=10, lean=10, x=2, drag=18), dict(fa_s=160, fa_e=20, wpn=20, lean=6, x=2, drag=10))
    slash("blade_light_3", 6, dict(fa_s=150, fa_e=20, wabs=-120, lean=-4, y=-1), dict(fa_s=80, fa_e=0, wpn=0, lean=26, x=3, drag=26), dict(fa_s=10, fa_e=10, wpn=-20, lean=30, x=3, drag=20, fl_h=30, fl_k=40))
    keys = [(0, STAN), (0.2, merge(STAN, dict(fa_s=175, fa_e=30, ba_s=160, ba_e=20, wpn=20, lean=-10, y=-1))), (0.35, merge(STAN, dict(fa_s=180, fa_e=30, ba_s=165, ba_e=20, wpn=20, lean=-12, y=-1))),
            (0.55, merge(STAN, dict(fa_s=60, fa_e=0, ba_s=50, ba_e=10, wpn=0, lean=34, y=3, x=3, fl_h=40, fl_k=60, drag=30))), (0.8, merge(STAN, dict(fa_s=40, fa_e=0, ba_s=30, wpn=-10, lean=30, y=3, x=3, fl_h=40, fl_k=60, drag=18))), (1, STAN)]
    add_anim("blade_heavy", keyed(keys, 8), 16, False)
    keys = [(0, merge(STAN, dict(fa_s=-20, fa_e=40, wpn=-100, lean=24, y=3, fl_h=40, fl_k=60))), (0.3, merge(STAN, dict(fa_s=-30, fa_e=20, wpn=-110, lean=28, y=4, fl_h=45, fl_k=70))),
            (0.6, merge(STAN, dict(fa_s=160, fa_e=10, wpn=10, lean=-6, y=-2, drag=-10, lift=24, flutter=1.4))), (1, merge(STAN, dict(fa_s=170, fa_e=20, wpn=10, lean=-4, y=-1, lift=10)))]
    add_anim("blade_launcher", keyed(keys, 6), 18, False)
    AIRS = merge(AIR, dict(y=-1))
    keys = [(0, merge(AIRS, dict(fa_s=150, fa_e=30, wpn=10, lean=0))), (0.4, merge(AIRS, dict(fa_s=70, wpn=0, lean=18, drag=20))), (0.75, merge(AIRS, dict(fa_s=10, wpn=-20, lean=20, drag=14))), (1, AIRS)]
    add_anim("blade_air_light", keyed(keys, 5), 18, False)
    keys = [(0, merge(AIRS, dict(fa_s=170, fa_e=10, wpn=20, lean=-6, fl_h=40, fl_k=80))), (0.3, merge(AIRS, dict(fa_s=170, wpn=20, lean=-8, fl_h=45, fl_k=90))),
            (0.55, merge(AIRS, dict(fa_s=20, fa_e=0, wpn=-10, lean=20, fl_h=10, fl_k=10, bl_h=-4, bl_k=10, lift=26, drag=0))), (1, merge(AIRS, dict(fa_s=10, fa_e=0, wpn=-10, lean=22, fl_h=8, fl_k=8, bl_k=10, lift=30)))]
    add_anim("blade_air_heavy", keyed(keys, 6), 18, False)

    # ---- katars (same rig, katar weapon layer on both hands)
    K = merge(STAN, dict(fa_s=60, fa_e=60, ba_s=40, ba_e=70, wpn=0))

    def kat(name, n, keys, fps=20):
        add_anim(name, keyed(keys, n, weapon="katar"), fps, False)

    # katar lights (AD redo): odd hits lead with the front (right) hand high, even hits with the
    # back (left) hand low; each hit has its own torso twist (sh_x +-2) and step (+-2 px foot).
    kat("katar_light_1", 4, [(0, K), (0.33, merge(K, dict(fa_s=30, fa_e=115, sh_x=-1, lean=6))),
                             (0.66, merge(K, dict(fa_s=112, fa_e=-4, sh_x=2, lean=16, x=1, fl_h=28, fl_k=18))), (1, merge(K, dict(sh_x=1, fl_h=24)))])
    kat("katar_light_2", 4, [(0, merge(K, dict(sh_x=1, fl_h=24))), (0.33, merge(K, dict(ba_s=5, ba_e=105, sh_x=1, lean=10, fa_s=40, fa_e=90))),
                             (0.66, merge(K, dict(ba_s=62, ba_e=-4, sh_x=-2, lean=24, y=1, x=1, bl_h=-26, bl_k=14, fa_s=20, fa_e=100))), (1, merge(K, dict(sh_x=-1, bl_h=-20)))])
    kat("katar_light_3", 4, [(0, merge(K, dict(sh_x=-1, bl_h=-20))), (0.33, merge(K, dict(fa_s=10, fa_e=130, sh_x=-2, lean=2, y=1))),
                             (0.66, merge(K, dict(fa_s=135, fa_e=-8, sh_x=2, lean=6, x=2, y=-1, fl_h=34, fl_k=24, lift=8))), (1, merge(K, dict(sh_x=1, x=1, fl_h=26)))])
    kat("katar_light_4", 4, [(0, merge(K, dict(sh_x=1, x=1, fl_h=26))), (0.33, merge(K, dict(ba_s=-10, ba_e=110, fa_s=20, fa_e=110, sh_x=2, lean=4, y=1))),
                             (0.66, merge(K, dict(ba_s=78, ba_e=-6, fa_s=10, fa_e=120, sh_x=-2, lean=30, x=2, y=2, fl_h=42, fl_k=55, bl_h=-30, drag=26))), (1, K)])
    kat("katar_cross", 6, [(0, K), (0.3, merge(K, dict(fa_s=150, fa_e=40, ba_s=150, ba_e=40, lean=-4))), (0.55, merge(K, dict(fa_s=40, fa_e=0, ba_s=60, ba_e=0, lean=24, x=2, drag=20))), (0.8, merge(K, dict(fa_s=20, ba_s=30, lean=26, x=2))), (1, K)])
    kat("katar_rising", 6, [(0, merge(K, dict(y=3, lean=24, fl_h=40, fl_k=60))), (0.3, merge(K, dict(y=4, lean=28, fa_s=-10, fa_e=40, fl_h=45, fl_k=70))), (0.6, merge(K, dict(y=-2, lean=-6, fa_s=170, fa_e=0, lift=20, drag=-6))), (1, merge(K, dict(y=-1, fa_s=160, lift=10)))])
    kat("katar_spin", 8, [(i / 7, merge(K, dict(lean=10 + 12 * math.sin(i), fa_s=90 + 40 * math.cos(i * 1.6), ba_s=80 - 40 * math.cos(i * 1.6), fa_e=10, ba_e=10, drag=40 * math.sin(i * 1.6), ph=i, flutter=1.5))) for i in range(8)])
    kat("katar_dive", 6, [(0, merge(AIR, dict(fa_s=150, ba_s=150, wpn=0))), (0.35, merge(AIR, dict(lean=40, fa_s=60, fa_e=0, ba_s=50, ba_e=0, fl_h=10, fl_k=20, lift=30))), (1, merge(AIR, dict(lean=45, fa_s=40, fa_e=0, ba_s=30, ba_e=0, fl_h=6, fl_k=10, bl_k=10, lift=34)))])

    # ---- guns: aim, recoil, recover
    # guns (AD redo): full-size weapon stamps (pistol 7, scattergun 10 w/ 2 px barrel, revolver 8 w/
    # cylinder); recoil scales: pistol 1 px arm kick, scatter 3 px body rock with planted feet,
    # revolver 2 px kick + muzzle rising 2 px over 2 frames.
    AIM = merge(STAN, dict(fa_s=84, fa_e=4, ba_s=20, ba_e=50, lean=6, wpn_on=1))
    add_anim("shoot_pistol", [fit(merge(AIM, d), weapon="pistol").image() for d in
                              (dict(), dict(kick=1, lean=5, drag=12), dict(kick=0.4, lean=6))], 18, False)
    base_feet = _feet(AIM)
    fr = []
    for d in (dict(), dict(x=-3, lean=-2, kick=1, rise=1, drag=16, head=-4), dict(x=-2, lean=1, kick=0.5, rise=0, drag=12), dict(x=-1, lean=4)):
        q = _plant(merge(AIM, d), base_feet)
        fr.append(fit(q, weapon="scatter").image())
    add_anim("shoot_scatter", fr, 18, False)
    add_anim("shoot_revolver", [fit(merge(AIM, d), weapon="revolver").image() for d in
                                (dict(), dict(kick=2, rise=1, lean=3, drag=12), dict(kick=2, rise=2, lean=2, head=-3, drag=14),
                                 dict(kick=1, rise=1, lean=4), dict(lean=6))], 18, False)

    HURT = merge(REST, dict(lean=-18, head=-14, x=-2, fa_s=-30, fa_e=50, ba_s=-50, ba_e=40, fl_h=24, fl_k=20, bl_h=-12, bl_k=14, drag=-12, flutter=1.4, wpn=-60))
    add_anim("hurt", keyed([(0, IDLE), (0.4, HURT), (1, merge(HURT, dict(lean=-6, head=-4, x=-1)))], 3), 14, False)

    # heal: injector to the chest, seam brightens (heal tint itself is code)
    HL = merge(IDLE, dict(fa_s=40, fa_e=120, wpn=-120, lean=10, head=20))
    fr = []
    for i in range(10):
        t = i / 9
        p = merge(REST, interp_pose([(0, IDLE), (0.25, HL), (0.5, merge(HL, dict(y=1, lean=14))), (0.8, merge(HL, dict(head=-10, lean=0, y=-0.5))), (1, IDLE)], t))
        fr.append(fit(p, core=1.6 if 3 <= i <= 7 else 1.0).image())
    add_anim("heal", fr, 12, False)

    # death: knees, slump; visor dims last
    DK = merge(REST, dict(y=9, lean=20, head=20, fl_h=80, fl_k=110, bl_h=-20, bl_k=150, b_toe=70, fa_s=0, fa_e=10, ba_s=-10, ba_e=10, wpn=-40, drag=0, flutter=0.2))
    DF = merge(DK, dict(y=14, lean=70, head=30, fa_s=-10, ba_s=-20, fl_h=90, fl_k=120))
    fr = []
    for i in range(12):
        t = i / 11
        p = merge(REST, interp_pose([(0, HURT), (0.2, merge(HURT, dict(lean=-24))), (0.45, DK), (0.7, merge(DK, dict(lean=30, head=35))), (0.9, DF), (1, DF)], t))
        f = fit(p, core=1.0 - t)
        if i == 11:
            # visor out: repaint red pixels in outline_hi
            import numpy as np
            m = (f.rgb == np.array([0xE8, 0x28, 0x3C], np.uint8)).all(-1) & f.alpha
            f.rgb[m] = (0x3D, 0x38, 0x50)
        fr.append(f.image())
    add_anim("death", fr, 12, False)

    INT = merge(IDLE, dict(fa_s=85, fa_e=10, wpn=-120, lean=10, head=5))
    add_anim("interact", keyed([(0, IDLE), (0.5, INT), (1, INT)], 4), 10, False)
    RK = merge(REST, dict(y=8, lean=16, head=24, fl_h=80, fl_k=95, bl_h=-20, bl_k=140, b_toe=70, fa_s=60, fa_e=40, ba_s=-10, ba_e=20, wpn=-150, drag=0, flutter=0.3))
    add_anim("rest", [fit(merge(RK, dict(y=8 + 0.5 * (1 - math.cos(2 * math.pi * i / 6)), ph=i, head=24 + math.sin(i) * 2)), core=0.8 + 0.4 * (i in (2, 3))).image() for i in range(6)], 8, True)
    add_anim("title_stand", [fit(merge(IDLE, dict(drag=38 + 8 * math.sin(2 * math.pi * i / 8), lift=6, ph=2 * math.pi * i / 8 * 2, flutter=1.3, head=-4, lean=2))).image() for i in range(8)], 8, True)
    return A


def add_mask_palette_key(tres):
    """SpriteActor reads mask_palette_key as a StringName; pixrig's meta writer only
    emits plain strings, so the &"accent" line is added here, right after mask_path."""
    lines = open(tres).read().split("\n")
    out = []
    for ln in lines:
        out.append(ln)
        if ln.startswith("metadata/mask_path = "):
            out.append('metadata/mask_palette_key = &"accent"')
    open(tres, "w").write("\n".join(out))


def main():
    check = "--check" in sys.argv
    anims = build()
    out_dir = os.path.join(ASSETS, "rook")
    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, "rook_sheet.png")
    meta = {"mask_path": "res://assets/rook/rook_sheet_mask.png",
            "mask_note": "white mask of the baked red visor + Core seam (same size as the sheet); tint it in code for colour-blind / high-contrast modes, the baked red stays as the fallback"}
    sheet = write_sheet(anims, (W, H), ORIGIN, png if not check else os.path.join(tempfile.gettempdir(), "_rook_check.png"), "res://assets/rook/rook_sheet.png",
                        os.path.join(out_dir, "rook_sheet.tres") if not check else os.path.join(tempfile.gettempdir(), "_rook_check.tres"), meta=meta)
    add_mask_palette_key(os.path.join(out_dir, "rook_sheet.tres") if not check else os.path.join(tempfile.gettempdir(), "_rook_check.tres"))
    mask = red_mask(sheet)
    if not check:
        mask.save(os.path.join(out_dir, "rook_sheet_mask.png"), optimize=True)
        json.dump({"id": "rook", "texture": "res://assets/rook/rook_sheet.png", "cell": [W, H], "origin": list(ORIGIN),
                   "mask": meta["mask_path"], "mask_note": meta["mask_note"],
                   "rows": [{"name": a.name, "row": r, "frames": len(a.frames), "fps": a.fps, "loop": a.loop} for r, a in enumerate(anims)]},
                  open(os.path.join(out_dir, "rook_sheet.json"), "w"), indent=1)
    preview(sheet, os.path.join(out_dir, "rook_sheet_x3.png") if not check else os.path.join(tempfile.gettempdir(), "_rook_x3.png"))
    r = check_sheet(sheet, RESERVED, allowed_reserved=("#e8283c",))
    print(json.dumps(dict(anims=len(anims), frames=sum(len(a.frames) for a in anims), size=sheet.size, **r)))
    return 0 if r["soft_alpha"] == 0 and not r["reserved_hits"] else 1


if __name__ == "__main__":
    sys.exit(main())
