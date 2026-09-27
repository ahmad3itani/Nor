"""Relay NPC rigs: Orr, Mara (P1), Nix, Vell, Iko (P2). Cell 48x48, origin (24,46), figure 32-36 px.

Usage: python3 rig_npcs.py [orr mara nix vell iko]
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, add, mul, lerp2, tup, tfwd, tdn, dirv, merge, Anim  # noqa
from humanoid import Skeleton, REST  # noqa
from figure import draw_figure, seq, cyc  # noqa
from rig_enemies import emit, PAL  # noqa

N = PAL["palettes"]["char_npc"]["colors"]
W = H = 48
O = N["outline"]
SKIN = [N["skin_1"], N["skin_2"], N["skin_3"]]


def skel(scale=1.0, hip_y=29):
    s = scale
    return Skeleton(dict(hip=(24, hip_y), thigh=7.6 * s, shin=7.8 * s, foot=2.8, torso=10.0 * s, neck=4.0 * s, head_r=3.0,
                         uarm=5.6 * s, farm=5.2 * s, shoulder_drop=1.4, ground=45.6))


def human_head(hair, hair_style="short", blink=False, extra=None):
    def head(f, j, p, S):
        hd = p["lean"] + p["head"]
        c = j["head"]
        L = Layer(W, H).ellipse(c, 2.8, 3.1).capsule(add(c, tfwd(hd, 1.2)), add(c, add(tfwd(hd, 2.3), tdn(hd, 1.2))), 1.2)
        f.part(L, SKIN, light=1, sep=O)
        # hair cap on the back/top
        if hair_style == "short":
            hp = [add(c, add(tfwd(hd, -3.0), tdn(hd, 1.0))), add(c, add(tfwd(hd, -3.0), tup(hd, 2.2))), add(c, add(tfwd(hd, 0.0), tup(hd, 3.6))),
                  add(c, add(tfwd(hd, 2.6), tup(hd, 2.4))), add(c, add(tfwd(hd, 1.0), tup(hd, 1.2))), add(c, add(tfwd(hd, -1.2), tup(hd, 0.6)))]
        elif hair_style == "slick":
            hp = [add(c, add(tfwd(hd, -3.2), tdn(hd, 0.4))), add(c, add(tfwd(hd, -3.0), tup(hd, 2.4))), add(c, add(tfwd(hd, 0.6), tup(hd, 3.6))),
                  add(c, add(tfwd(hd, 3.0), tup(hd, 2.8))), add(c, add(tfwd(hd, 2.0), tup(hd, 1.8))), add(c, add(tfwd(hd, -1.0), tup(hd, 1.2)))]
        else:  # none (hood covers)
            hp = None
        if hp:
            f.part(Layer(W, H).poly(hp), hair, light=1, shade=0)
        # eye (1 px) and a mouth hint when talking
        eye = add(c, add(tfwd(hd, 1.6), tup(hd, 0.4)))
        f.px(eye, N["hair_0"] if not p.get("blink") else N["skin_1"])
        if p.get("mouth"):
            f.px(add(c, add(tfwd(hd, 2.2), tdn(hd, 1.4))), N["skin_0"])
        if extra:
            extra(f, j, p, S, c, hd)
    return head


def talk_frames(S, base, n=4):
    ks = []
    for i in range(n):
        ks.append(merge(base, dict(mouth=i % 2, fa_s=base["fa_s"] + (18 if i in (1, 2) else 0), fa_e=base["fa_e"] + (20 if i == 1 else 0), head=base["head"] + (3 if i % 2 else 0))))
    return [draw_figure(k, S).image() for k in ks]


# AD redo: a real 2-beat breath (chest + shoulders rise 1 px over 4 frames, twice per loop),
# a head tilt on frame 2 and a blink on frame 5, so every frame differs from the last by >= 8 px.
BREATH = [0.0, 0.5, 1.0, 0.5, 0.0, 0.5, 1.0, 0.5]


def idle_frames(S, base, n=8):
    fr = []
    tl = S["sk"].d["torso"]
    for i in range(n):
        b = BREATH[i % 8]
        up = 1.0 if b >= 0.75 else 0.0          # whole-pixel chest rise on the in-breath
        d = dict(torso_k=1.0 + up / tl, ph=2 * math.pi * i / n, blink=(i == 5),
                 fa_s=base["fa_s"] + 5 * b + (2 if i % 2 else -2), ba_s=base["ba_s"] - 4 * b + (-2 if i % 2 else 2),
                 head=base["head"] + (6 if i == 2 else 0) + (-2 if i in (6, 7) else 0))
        fr.append(draw_figure(merge(base, d), S).image())
    return fr


def warm_rim(only):
    """1 px warm rim (#c98548, Relay lamp_warm) on the lamp-facing edge (top + back, key light upper-left)."""
    return [dict(colour=N["lamp_rim"], only=only, top=True, back=True, rows=(0, 34))]  # upper body only (no glowing boots)


# ------------------------------------------------------------------ ORR
def orr():
    PON = [N["orr_poncho"], N["orr_poncho_hi"], N["orr_poncho_top"]]  # AD redo: one step lighter
    GREY = [N["hair_1"], N["grey_hair"], N["grey_hair"]]

    def phones(f, j, p, S, c, hd):
        # big padded headphones around the neck (AD redo: a 4x3 cup + band, reads at 1x)
        n = j["neck"]
        fw = tfwd(p["lean"])
        q = add(n, add(mul(fw, 0.2), mul(j["up"], 0.4)))
        x0, y0 = int(round(q[0] - 2)), int(round(q[1] - 1.5))
        f.part(Layer(W, H).rect(x0, y0, x0 + 4, y0 + 3), [N["orr_phones"], N["cloth_mid"], N["cloth_hi"]], light=1, shade=1, sep=O)
        f.px((x0 + 1, y0), N["grey_hair"])
        f.part(Layer(W, H).capsule((x0 + 3.5, y0 + 0.5), add(c, add(tfwd(hd, -1.0), tdn(hd, 2.4))), 0.45), [N["orr_phones"]], light=0, shade=0, thr=0.3)
        # stubble
        f.px(add(c, add(tfwd(hd, 1.6), tdn(hd, 1.8))), N["grey_hair"])

    def poncho(f, j, p, S):
        # blanket poncho: a trapezoid over the torso and upper arms
        n, hip = j["neck"], j["hip"]
        fw = tfwd(p["lean"])
        up = j["up"]
        pts = [add(n, mul(fw, -2.2)), add(n, mul(fw, 2.4)), add(add(hip, mul(up, 2.5)), mul(fw, 6.0)), add(add(hip, mul(up, 1.0)), mul(fw, 3.0)),
               add(add(hip, mul(up, 1.4)), mul(fw, -1.0)), add(add(hip, mul(up, 0.4)), mul(fw, -5.4))]
        f.part(Layer(W, H).poly(pts), PON, light=1, sep=O)
        # stripe weave
        for k in (0.45, 0.75):
            a = lerp2(add(n, mul(fw, -3)), add(hip, mul(fw, -4.6)), k)
            b = lerp2(add(n, mul(fw, 3)), add(hip, mul(fw, 5.4)), k)
            f.part(Layer(W, H).capsule(a, b, 0.45), [N["cloth_mid"]], light=0, shade=0, thr=0.35, clip=None)

    S = dict(W=W, H=H, sk=skel(0.95, 30), outline=O,
             leg=dict(ramp=[N["cloth_mid"], N["cloth_hi"], N["cloth_hi"]], r=(1.9, 1.5, 1.3), boot=[N["hair_0"], N["hair_1"]], boot_r=1.4),
             arm=dict(ramp=PON, r=(1.6, 1.3, 1.2), hand=[N["skin_1"], N["skin_2"]], hand_r=1.1),
             torso=dict(ramp=[N["cloth_mid"], N["cloth_hi"], N["cloth_hi"]], nb=2.6, nf=2.4, cf=3.0, hf=2.6, hb=2.8),
             head=human_head(GREY, "short", extra=phones), over_legs=poncho,
             rim=warm_rim([N["orr_poncho"], N["orr_poncho_hi"], N["cloth_mid"], N["cloth_hi"], N["grey_hair"]]))
    # AD redo: hunched 3 px further forward (older, stooped over the radio)
    B = merge(REST, dict(lean=32, head=-22, fa_s=30, fa_e=40, ba_s=-6, ba_e=30, fl_h=8, fl_k=10, bl_h=-8, bl_k=8, drag=0, flutter=0.2))
    A = [Anim("idle", idle_frames(S, B), 8, True), Anim("talk", talk_frames(S, B), 8, True)]
    TU = merge(B, dict(lean=20, head=10, fa_s=80, fa_e=10))
    fr = [draw_figure(merge(TU, dict(fa_e=10 + (8 if i % 2 else 0), fa_s=80 + (i % 3), head=10 + (i == 3) * 4, blink=(i == 4))), S).image() for i in range(6)]
    A.append(Anim("tune_radio", fr, 8, True))
    return emit("orr", (W, H), (24, 46), A, sub="npcs")


# ------------------------------------------------------------------ MARA
def mara():
    APR = [N["mara_apron"], N["mara_rust"], N["mara_rust_hi"]]  # AD redo: one step lighter
    SHIRT = [N["cloth_mid"], N["cloth_hi"], N["cloth_hi"]]

    def goggles(f, j, p, S, c, hd):
        g = add(c, add(tfwd(hd, 0.6), tup(hd, 2.6)))
        f.part(Layer(W, H).capsule(add(g, tfwd(hd, -2.2)), add(g, tfwd(hd, 2.0)), 1.0), [N["hair_1"], N["mara_goggle"], N["mara_goggle"]], light=1, thr=0.4)
        f.px(add(g, tfwd(hd, 1.2)), N["nix_paper"])

    def apron(f, j, p, S):
        n, hip = j["neck"], j["hip"]
        fw = tfwd(p["lean"])
        up = j["up"]
        pts = [add(add(n, mul(up, -1.5)), mul(fw, 0.8)), add(add(n, mul(up, -1.5)), mul(fw, 3.6)), add(add(hip, mul(up, -8.0)), mul(fw, 4.4)),
               add(add(hip, mul(up, -8.4)), mul(fw, -1.0)), add(hip, mul(fw, -0.4))]
        f.part(Layer(W, H).poly(pts), APR, light=1, sep=O)
        # scorch marks
        f.px(add(add(hip, mul(up, -4)), mul(fw, 2.4)), N["hair_0"])
        f.px(add(add(hip, mul(up, 1)), mul(fw, 2.0)), N["skin_0"])

    def hammer(f, j, p, S):
        if not p.get("hammer"):
            return
        sh, el, ha, ua, fa = j["fa"]
        ang = fa + p.get("wpn", 0)
        head_c = add(ha, dirv(ang, 6))
        f.part(Layer(W, H).capsule(ha, head_c, 0.6), [N["hair_1"], N["mara_apron"]], light=0, thr=0.35)
        n = dirv(ang + 90, 1.0)
        f.part(Layer(W, H).capsule(add(head_c, mul(n, -1.8)), add(head_c, mul(n, 1.8)), 1.1), [N["cloth_dark"], N["cloth_mid"], N["grey_hair"]], light=1, sep=O)

    S = dict(W=W, H=H, sk=skel(0.95, 29), outline=O,
             leg=dict(ramp=[N["mara_apron"], N["mara_rust"], N["mara_rust"]], r=(2.2, 1.8, 1.5), boot=[N["hair_0"], N["hair_1"]], boot_r=1.6),
             arm=dict(ramp=SKIN, r=(1.9, 1.6, 1.4), hand=[N["skin_1"], N["skin_2"]], hand_r=1.3),
             torso=dict(ramp=SHIRT, nb=4.0, nf=3.6, cf=4.6, hf=3.8, hb=3.8),  # stocky
             head=human_head([N["hair_0"], N["hair_1"], N["hair_1"]], "short", extra=goggles), over_legs=apron, front=hammer,
             rim=warm_rim([N["cloth_mid"], N["cloth_hi"], N["mara_apron"], N["mara_rust"], N["hair_1"]]))
    B = merge(REST, dict(lean=4, head=-2, fa_s=60, fa_e=100, ba_s=40, ba_e=110, fl_h=10, fl_k=6, bl_h=-10, bl_k=6, drag=0, flutter=0.2))  # arms crossed
    A = [Anim("idle", idle_frames(S, B), 8, True)]
    T = merge(B, dict(fa_s=40, fa_e=50, ba_s=-5, ba_e=30))
    A.append(Anim("talk", talk_frames(S, T), 8, True))
    WK = merge(B, dict(lean=16, head=8, hammer=1, ba_s=50, ba_e=40, fl_h=18, bl_h=-14))
    keys = [(0, merge(WK, dict(fa_s=150, fa_e=30, wpn=-20))), (0.35, merge(WK, dict(fa_s=160, fa_e=30, wpn=-20))), (0.55, merge(WK, dict(fa_s=60, fa_e=20, wpn=20, lean=20))),
            (0.7, merge(WK, dict(fa_s=55, fa_e=20, wpn=24, lean=21))), (1, merge(WK, dict(fa_s=140, fa_e=30, wpn=-20)))]
    A.append(Anim("work", seq(S, keys, 8), 12, True))
    return emit("mara", (W, H), (24, 46), A, sub="npcs")


# ------------------------------------------------------------------ NIX
def nix():
    COAT = [N["cloth_dark"], N["nix_paper"], N["nix_paper"]]
    SC = [N["nix_scarf"], N["nix_scarf"], N["nix_scarf_hi"]]

    def extra(f, j, p, S, c, hd):
        # long scarf tail (AD redo: hangs to the knee behind him, sways with the breath phase)
        n = j["neck"]
        from humanoid import chain
        sc = chain(add(n, tfwd(p["lean"], -1.6)), -12, 3.6, 5, 16, p["ph"], 5)
        L = Layer(W, H)
        for k, (a, b) in enumerate(zip(sc, sc[1:])):
            L.capsule(a, b, 1.4 - 0.12 * k, 1.3 - 0.12 * k)
        f.part(L, SC, light=1, sep=O)
        # brass monocle: ring + a 1 px bright glint
        f.px(add(c, add(tfwd(hd, 1.6), tup(hd, 0.4))), N["mara_goggle"])
        f.px(add(c, add(tfwd(hd, 1.6), tup(hd, 1.4))), N["mara_goggle"])
        f.px(add(c, add(tfwd(hd, 2.1), tup(hd, 0.9))), N["nix_paper"])
        f.part(Layer(W, H).capsule(add(n, tfwd(p["lean"], -2)), add(n, tfwd(p["lean"], 2.2)), 1.6), SC, light=1)

    def maps(f, j, p, S):
        hip, n = j["hip"], j["neck"]
        fw = tfwd(p["lean"])
        for k, off in ((0.35, 1.5), (0.7, -1.0), (1.2, 2.0)):
            q = add(lerp2(n, hip, k), mul(fw, off))
            f.part(Layer(W, H).rect(q[0] - 1, q[1] - 1, q[0] + 1, q[1] + 1), [N["nix_paper"]], light=0, shade=0)
            f.px(q, N["skin_0"])

    def pen(f, j, p, S):
        if p.get("pen"):
            sh, el, ha, ua, fa = j["fa"]
            f.part(Layer(W, H).capsule(ha, add(ha, dirv(fa - 30, 3)), 0.5), [N["hair_0"]], light=0, shade=0, thr=0.3)
            bh = j["ba"][2]
            f.part(Layer(W, H).rect(bh[0] - 1, bh[1] - 3, bh[0] + 4, bh[1] + 1), [N["skin_0"], N["nix_paper"], N["nix_paper"]], light=1)

    S = dict(W=W, H=H, sk=skel(1.03, 28), outline=O,
             leg=dict(ramp=[N["cloth_mid"], N["cloth_hi"], N["cloth_hi"]], r=(1.7, 1.4, 1.2), boot=[N["hair_0"], N["hair_1"]], boot_r=1.3),
             arm=dict(ramp=[N["cloth_mid"], N["cloth_hi"], N["cloth_hi"]], r=(1.5, 1.3, 1.1), hand=[N["skin_1"], N["skin_2"]], hand_r=1.0),
             torso=dict(ramp=[N["cloth_mid"], N["cloth_hi"], N["grey_hair"]], nb=2.6, nf=2.4, cf=2.8, hf=2.6, hb=2.8),
             skirt=dict(ramp=[N["cloth_mid"], N["cloth_hi"], N["grey_hair"]], fseg=4.0, bseg=4.6, n=3, base=-6, width_f=2.6, width_b=2.8, jag=0.8, amp=2),
             head=human_head([N["hair_0"], N["hair_1"], N["hair_1"]], "short", extra=extra), detail=maps, front=pen,
             rim=warm_rim([N["cloth_mid"], N["cloth_hi"], N["nix_scarf"], N["hair_1"]]))
    B = merge(REST, dict(lean=6, head=-4, fa_s=10, fa_e=30, ba_s=-6, ba_e=20, fl_h=6, fl_k=5, bl_h=-6, bl_k=5, drag=4, flutter=0.4))
    A = [Anim("idle", idle_frames(S, B), 8, True), Anim("talk", talk_frames(S, B), 8, True)]
    D = merge(B, dict(pen=1, head=24, lean=10, ba_s=50, ba_e=40, fa_s=50, fa_e=50))
    A.append(Anim("draw", [draw_figure(merge(D, dict(fa_e=50 + 6 * math.sin(i * 2.1), fa_s=50 + 4 * math.cos(i * 1.7), blink=(i == 3))), S).image() for i in range(6)], 8, True))
    return emit("nix", (W, H), (24, 46), A, sub="npcs")


# ------------------------------------------------------------------ VELL
def vell():
    CO = [N["vell_coat"], N["vell_coat_hi"], N["vell_coat_hi"]]  # AD redo: one step lighter

    def cards(f, j, p, S):
        hip, n = j["hip"], j["neck"]
        fw = tfwd(p["lean"])
        up = j["up"]
        # AD redo: coat hangs open; a dark lining panel with two columns of pale card flecks
        pan = [add(add(n, mul(up, -1.2)), mul(fw, 0.6)), add(add(n, mul(up, -1.2)), mul(fw, 2.6)),
               add(add(hip, mul(up, -5.0)), mul(fw, 3.4)), add(add(hip, mul(up, -5.0)), mul(fw, 1.0))]
        f.part(Layer(W, H).poly(pan), [N["cloth_dark"]], light=0, shade=0)
        for k in (0.15, 0.35, 0.55, 0.75, 0.95, 1.15):
            f.px(add(lerp2(n, hip, k), mul(fw, 1.4)), N["vell_card"])
            if k < 1.0:
                f.px(add(lerp2(n, hip, k + 0.1), mul(fw, 2.6)), N["nix_paper"])
        f.part(Layer(W, H).capsule(add(n, mul(fw, -2.2)), add(n, mul(fw, 2.4)), 1.3), CO, light=1)

    def fingers(f, j, p, S):
        # long 3 px fingers on both hands (the card broker's hands)
        for side in ("fa", "ba"):
            sh, el, ha, ua, fa = j[side]
            f.part(Layer(W, H).capsule(ha, add(ha, dirv(fa + 10, 3.0)), 0.45), [N["skin_1"], N["skin_2"]], light=0, shade=0, thr=0.3)

    def deck(f, j, p, S):
        if p.get("deck"):
            sh, el, ha, ua, fa = j["fa"]
            bh = j["ba"][2]
            f.part(Layer(W, H).rect(bh[0] - 1, bh[1] - 2, bh[0] + 2, bh[1] + 1), [N["vell_card"]], light=0, shade=0)
            f.part(Layer(W, H).rect(ha[0] - 1, ha[1] - 2 - p.get("lift_card", 0), ha[0] + 2, ha[1] + 1 - p.get("lift_card", 0)), [N["nix_paper"]], light=0, shade=0)

    S = dict(W=W, H=H, sk=skel(1.02, 28), outline=O,
             leg=dict(ramp=[N["cloth_mid"], N["cloth_mid"], N["cloth_hi"]], r=(1.3, 1.0, 0.9), boot=[N["hair_0"], N["hair_1"]], boot_r=1.1),
             arm=dict(ramp=CO, r=(1.2, 1.0, 0.8), hand=[N["skin_1"], N["skin_2"]], hand_r=0.8),
             torso=dict(ramp=CO, nb=1.9, nf=1.8, cf=2.1, hf=1.9, hb=2.0),
             skirt=dict(ramp=CO, fseg=4.6, bseg=5.2, n=3, base=-4, width_f=2.4, width_b=2.2, jag=0.5, amp=1.5),
             head=human_head([N["hair_0"], N["hair_0"], N["hair_1"]], "slick"), detail=cards,
             front=lambda f, j, p, S: (fingers(f, j, p, S), deck(f, j, p, S)),
             rim=warm_rim([N["vell_coat"], N["vell_coat_hi"], N["cloth_mid"]]))
    B = merge(REST, dict(lean=-2, head=4, fa_s=40, fa_e=70, ba_s=-8, ba_e=20, fl_h=10, fl_k=4, bl_h=-4, bl_k=4, drag=2, flutter=0.3))
    A = [Anim("idle", idle_frames(S, B), 8, True), Anim("talk", talk_frames(S, B), 8, True)]
    SH = merge(B, dict(deck=1, fa_s=50, fa_e=60, ba_s=40, ba_e=60, head=14))
    A.append(Anim("shuffle", [draw_figure(merge(SH, dict(lift_card=[0, 2, 4, 2, 0, 1][i], fa_s=50 + [0, 6, 12, 6, 0, 3][i])), S).image() for i in range(6)], 12, True))
    return emit("vell", (W, H), (24, 46), A, sub="npcs")


# ------------------------------------------------------------------ IKO
def iko():
    OIL = [N["iko_oilskin"], N["iko_oilskin_hi"], N["iko_oilskin_top"]]  # AD redo: one step lighter

    def hood(f, j, p, S, c, hd):
        # AD redo: the hood ends in a point that trails up and back (Iko's signature)
        pts = [add(c, add(tfwd(hd, -3.6), tdn(hd, 2.6))), add(c, add(tfwd(hd, -4.2), tup(hd, 2.0))), add(c, add(tfwd(hd, -6.6), tup(hd, 5.6))),
               add(c, add(tfwd(hd, -2.0), tup(hd, 3.8))), add(c, add(tfwd(hd, 0.4), tup(hd, 4.0))),
               add(c, add(tfwd(hd, 3.4), tup(hd, 2.2))), add(c, add(tfwd(hd, 1.2), tup(hd, 1.6))), add(c, add(tfwd(hd, -0.6), tdn(hd, 2.4)))]
        f.part(Layer(W, H).poly(pts), OIL, light=1, sep=O)
        # chalk-eye mark on the hood side
        q = add(c, add(tfwd(hd, -1.6), tup(hd, 1.6)))
        f.px(q, N["iko_chalk"])
        f.px(add(q, tfwd(hd, 1)), N["iko_chalk"])

    def rope(f, j, p, S):
        hip = j["hip"]
        fw = tfwd(p["lean"])
        c = add(hip, add(mul(fw, -3.6), mul(j["up"], -1.0)))
        # AD redo: a real rope coil at the hip: 3 stacked loops with a dark core
        L = Layer(W, H).ellipse(c, 3.0, 2.4)
        f.part(L, [N["mara_apron"], N["mara_goggle"], N["nix_paper"]], light=1, sep=O)
        f.part(Layer(W, H).ellipse(c, 1.3, 1.0), [N["hair_1"]], light=0, shade=0, thr=0.4)
        f.px(add(c, (-2, -1)), N["mara_apron"])
        f.px(add(c, (2, 1)), N["mara_apron"])

    S = dict(W=W, H=H, sk=skel(0.92, 30), outline=O,
             leg=dict(ramp=[N["cloth_mid"], N["cloth_hi"], N["cloth_hi"]], r=(1.7, 1.4, 1.2), boot=[N["hair_0"], N["hair_1"]], boot_r=1.3),
             arm=dict(ramp=OIL, r=(1.5, 1.3, 1.1), hand=[N["skin_1"], N["skin_2"]], hand_r=1.0),
             torso=dict(ramp=OIL, nb=2.6, nf=2.4, cf=2.9, hf=2.6, hb=2.8),
             skirt=dict(ramp=OIL, fseg=2.6, bseg=4.2, n=3, base=-12, width_f=2.6, width_b=2.8, jag=1.0, amp=3, split=1.5),
             head=human_head([N["hair_0"], N["hair_1"], N["hair_1"]], "none", extra=hood), over_legs=rope,
             rim=warm_rim([N["iko_oilskin"], N["iko_oilskin_hi"], N["cloth_mid"], N["cloth_hi"]]))
    B = merge(REST, dict(lean=4, head=0, fa_s=20, fa_e=40, ba_s=-8, ba_e=20, fl_h=8, fl_k=6, bl_h=-6, bl_k=6, drag=8, flutter=0.6))
    A = [Anim("idle", idle_frames(S, B), 8, True), Anim("talk", talk_frames(S, B), 8, True)]
    LE = merge(B, dict(lean=-12, x=-2, head=6, fa_s=-10, fa_e=120, ba_s=-20, ba_e=110, fl_h=22, fl_k=4, bl_h=-4, bl_k=6))
    A.append(Anim("lean", [draw_figure(merge(LE, dict(y=0.4 * (1 - math.cos(2 * math.pi * i / 6)), blink=(i == 4), ph=i, head=6 + (i in (2, 3)) * 6)), S).image() for i in range(6)], 8, True))
    return emit("iko", (W, H), (24, 46), A, sub="npcs")


if __name__ == "__main__":
    for w in (sys.argv[1:] or ["orr", "mara", "nix", "vell", "iko"]):
        globals()[w]()
