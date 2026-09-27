"""Generic spec-driven humanoid figure drawer (enemies, bosses, NPCs) on pixrig + humanoid.

A spec is a dict:
  W, H, sk (Skeleton), outline (hex)
  leg:   dict(ramp, r=(hip, knee, ankle), boot=ramp or None, boot_r)
  arm:   dict(ramp, r=(shoulder, elbow, wrist), hand=ramp, hand_r)
  torso: dict(ramp, nb, nf, cf, hf, hb)  half-widths: neck back/front, chest front, hip front/back
  skirt: None or dict(ramp, fseg, bseg, n, base, split, jag, width_f, width_b, grow)
  rim:   optional list of dict(colour, only=[hex], top, back, rows, skip): 1 px rim light against the scene
  head(f, j, p, S), front(f, j, p, S), back(f, j, p, S), detail(f, j, p, S), over_legs(f, j, p, S): callbacks
"""
from __future__ import annotations

import math

from pixrig import Layer, Frame, add, mul, lerp2, tup, tfwd, tdn, dirv, merge, interp_pose, Anim
from humanoid import chain, REST


def limb(f, S, pts, radii, ramp, sep=None, light=1, shade=1, thr=0.5):
    L = Layer(S["W"], S["H"])
    for (a, b), (r0, r1) in zip(zip(pts, pts[1:]), zip(radii, radii[1:])):
        L.capsule(a, b, r0, r1)
    return f.part(L, ramp, light=light, shade=shade, sep=sep, thr=thr)


def poly(f, S, pts, ramp, sep=None, light=1, shade=1, thr=0.5):
    return f.part(Layer(S["W"], S["H"]).poly(pts), ramp, light=light, shade=shade, sep=sep, thr=thr)


def torso_pts(j, p, T):
    neck, hip = j["neck"], j["hip"]
    fw = tfwd(p["lean"])
    up = j["up"]
    chest = add(neck, mul(up, -T.get("chest_drop", 3.5)))
    return [add(neck, mul(fw, -T["nb"])), add(neck, mul(fw, T["nf"])), add(chest, mul(fw, T["cf"])),
            add(hip, mul(fw, T["hf"])), add(hip, mul(fw, -T["hb"]))]


def draw_figure(p, S) -> Frame:
    j = S["sk"].solve(p)
    f = Frame(S["W"], S["H"])
    O = S["outline"]
    A, Lg, T = S["arm"], S["leg"], S["torso"]
    fw = tfwd(p["lean"])
    if S.get("back_pre"):
        S["back_pre"](f, j, p, S)
    # back arm
    sh, el, ha, ua, fa = j["ba"]
    if p.get("arm_back", 1):
        limb(f, S, [sh, el, ha], A["r"], A.get("ramp_back", A["ramp"]), light=0)
        if A.get("hand"):
            f.part(Layer(S["W"], S["H"]).circle(ha, A["hand_r"]), A["hand"], light=0)
    if S.get("back"):
        S["back"](f, j, p, S)
    # back leg
    hp, kn, an, ft, _, _ = j["bl"]
    limb(f, S, [hp, kn, an], Lg["r"], Lg.get("ramp_back", Lg["ramp"]), light=1)
    if Lg.get("boot"):
        L = Layer(S["W"], S["H"]).capsule(an, ft, Lg["boot_r"], Lg["boot_r"] * 0.7).capsule(add(an, (0, -1.5)), an, Lg["boot_r"] + 0.2)
        f.part(L, Lg.get("boot_back", Lg["boot"]), light=0)
    # skirt / coat tail
    K = S.get("skirt")
    hip, neck = j["hip"], j["neck"]
    if K:
        drag, lift, ph, amp = p["drag"], p["lift"], p["ph"], K.get("amp", 4.0) * p["flutter"]
        hipF = add(hip, mul(fw, K["width_f"]))
        hipB = add(hip, mul(fw, -K["width_b"]))
        front = chain(hipF, p["fl_h"] * 0.4 - 2 + K.get("fbase", 0), K["fseg"], K["n"], drag * 0.45, ph, amp * 0.5, lift=lift * 0.5)
        back = chain(hipB, K.get("base", -10), K["bseg"], K["n"], drag, ph + 0.8, amp, grow=K.get("grow", 0.1), lift=lift)
        fe, be = front[-1], back[-1]
        hem = []
        jag = K.get("jag", 1.0)
        for i, t in enumerate((0.25, 0.5, 0.75)):
            hem.append(add(lerp2(fe, be, t), (0, jag if i % 2 else -jag * 0.6)))
        if K.get("split"):
            # a notch splitting the tail in two
            hem.insert(2, add(lerp2(fe, be, 0.6), (0, -K["split"])))
        top = [add(neck, mul(fw, T["nf"] * 0.7)), hipF] if K.get("from_neck", True) else [hipF]
        pts = top + front[1:] + hem + back[::-1][:-1] + [hipB] + ([add(neck, mul(fw, -T["nb"]))] if K.get("from_neck", True) else [])
        poly(f, S, pts, K["ramp"], light=1)
    # torso
    poly(f, S, torso_pts(j, p, T), T["ramp"], light=1)
    if S.get("detail"):
        S["detail"](f, j, p, S)
    # front leg
    hp, kn, an, ft, _, _ = j["fl"]
    limb(f, S, [hp, kn, an], Lg["r"], Lg["ramp"], sep=O)
    if Lg.get("boot"):
        L = Layer(S["W"], S["H"]).capsule(an, ft, Lg["boot_r"], Lg["boot_r"] * 0.7).capsule(add(an, (0, -1.5)), an, Lg["boot_r"] + 0.2)
        f.part(L, Lg["boot"], light=1)
    if S.get("over_legs"):
        S["over_legs"](f, j, p, S)
    if S.get("head"):
        S["head"](f, j, p, S)
    # front arm
    sh, el, ha, ua, fa = j["fa"]
    if S.get("front_pre"):
        S["front_pre"](f, j, p, S)
    if p.get("arm_front", 1):
        limb(f, S, [sh, el, ha], A["r"], A["ramp"], sep=O)
        if A.get("hand"):
            f.part(Layer(S["W"], S["H"]).circle(ha, A["hand_r"]), A["hand"], light=0)
    if S.get("front"):
        S["front"](f, j, p, S)
    for R in (S.get("rim") or []):
        f.rim(R["colour"], only=R.get("only"), top=R.get("top", True), back=R.get("back", True), rows=R.get("rows"), skip=R.get("skip"))
    f.outline(O)
    if S.get("post"):
        S["post"](f, j, p, S)
    return f


def fit_figure(p, S, max_iter=40):
    """Draw; while anything touches row 0 / column 0 / the last column, pull the pose in:
    R/L -> step the body back 1 px; T -> angle the held weapon further back over the shoulder,
    then lower the raised arm. Keeps the cell and origin (AD redo clip rule)."""
    p = dict(p)
    rot = 0
    seen = set()
    for _ in range(max_iter):
        f = draw_figure(p, S)
        e = f.edges()
        if not e:
            return f
        side = set(e) & {"L", "R"}
        if side and (side == {"L", "R"} or (seen & {"L", "R"}) - side):
            # too long for the cell: pull the coat tail in and shorten the held weapon's reach
            p["drag"] = p.get("drag", 0) - 8
            p["wlen_k"] = max(0.6, p.get("wlen_k", 1.0) - 0.1)
        elif "R" in side:
            p["x"] = p.get("x", 0) - 1
        elif "L" in side:
            p["x"] = p.get("x", 0) + 1
        seen |= side
        if "T" in e:
            if rot < 6 and "wpn" in p:
                p["wpn"] = p["wpn"] + 12
                rot += 1
            elif p.get("fa_s", 0) > 100:
                p["fa_s"] -= 8
                p["fa_e"] = p.get("fa_e", 0) + 8
            else:
                p["y"] = p.get("y", 0) + 1
                p["ground"] = 0
    raise RuntimeError(f"pose does not fit the cell: {e}")


def render(p, S):
    return fit_figure(p, S) if S.get("fit") else draw_figure(p, S)


def seq(S, keys, n, extra=None):
    out = []
    for i in range(n):
        t = i / (n - 1) if n > 1 else 0.0
        p = merge(REST, interp_pose(keys, t))
        p["ground"] = 1 if p.get("ground", 1) >= 0.999 else 0  # never half-snap while blending into a fall
        if extra:
            p = merge(p, extra(i, t))
        out.append(render(p, S).image())
    return out


def cyc(S, fn, n):
    return [render(merge(REST, fn(i / n, i)), S).image() for i in range(n)]
