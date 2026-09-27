"""Humanoid enemies as code rigs: Needle, Shield, Enforcer.

Usage: python3 rig_enemies.py [needle|shield|enforcer ...]   (default: all)
Output: assets/enemies/<id>_sheet.png + .tres (+ _x3 preview).
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, add, mul, lerp2, tup, tfwd, tdn, dirv, merge, Anim, write_sheet, preview, check_sheet  # noqa
from humanoid import Skeleton, REST  # noqa
from figure import draw_figure, seq, cyc, limb, poly  # noqa
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

ROOT = REDLINE
PAL = json.load(open(os.path.join(DATA, "palettes.json")))
E = PAL["palettes"]["char_enemy"]["colors"]
RESERVED = list(PAL["reserved"].values())


def walk(t, stride=24, knee=34, arm=18, bob=1.0, lean=6, dig=False):
    a = 2 * math.pi * t
    c, s = math.cos(a), math.sin(a)
    d = dict(lean=lean, y=-bob * abs(s) * 0.8,
             fl_h=stride * c, bl_h=-stride * c,
             fl_k=6 + knee * max(0.0, math.sin(a + 1.3)), bl_k=6 + knee * max(0.0, math.sin(a + 1.3 + math.pi)),
             fa_s=-arm * c + 5, ba_s=arm * c - 5, ph=a * 2)
    if dig:
        d["fl_h"], d["bl_h"] = -18 + 0.7 * stride * c, -18 - 0.7 * stride * c
        d["fl_k"] = -50 + 20 * max(0.0, math.sin(a + 1.3))
        d["bl_k"] = -50 + 20 * max(0.0, math.sin(a + 1.3 + math.pi))
    return d


def emit(name, cell, origin, anims, sub="enemies"):
    out_dir = os.path.join(ASSETS, sub)
    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, f"{name}_sheet.png")
    sheet = write_sheet(anims, cell, origin, png, f"res://assets/{sub}/{name}_sheet.png", os.path.join(out_dir, f"{name}_sheet.tres"))
    preview(sheet, os.path.join(out_dir, f"{name}_sheet_x3.png"))
    allowed = tuple(c.lower() for c in PAL.get("_allowed", {}).get(name, []))
    r = check_sheet(sheet, RESERVED, allowed_reserved=allowed)
    print(json.dumps(dict(id=name, anims=len(anims), frames=sum(len(a.frames) for a in anims), size=sheet.size, **r)))
    return sheet


def crack_pixels(f, pts, colour):
    for q in pts:
        f.px(q, colour)


# ====================================================================== NEEDLE
def needle():
    W = H = 40
    sk = Skeleton(dict(hip=(16, 22), thigh=6.5, shin=7.5, foot=2.6, torso=9.0, neck=3.6, head_r=2.8,
                       uarm=5.0, farm=5.0, shoulder_drop=1.2, ground=37.6))
    O = E["outline"]
    POR = [E["porcelain_0"], E["porcelain_1"], E["porcelain_1"]]
    SCR = [E["scrub_0"], E["scrub_1"], E["scrub_1"]]
    ST = [E["steel_0"], E["steel_1"], E["steel_2"]]

    def head(f, j, p, S):
        hd = p["lean"] + p["head"]
        c = j["head"]
        L = Layer(W, H).ellipse(c, 2.6, 3.1).capsule(add(c, tfwd(hd, 1.0)), add(c, add(tfwd(hd, 2.2), tdn(hd, 1.4))), 1.5)
        f.part(L, POR, light=1, shade=1, sep=O)
        # dark slit + crack
        for i in range(2):
            f.px(add(add(c, tfwd(hd, 1.2 + i)), tup(hd, 0.3)), E["lens_dark"])
        if p.get("crack", 0) >= 1:
            crack_pixels(f, [add(c, tup(hd, 1.5)), add(add(c, tup(hd, 0.6)), tfwd(hd, -0.6)), add(add(c, tdn(hd, 0.4)), tfwd(hd, -1.2))], E["outline_hi"])
        if p.get("crack", 0) >= 2:
            crack_pixels(f, [add(add(c, tup(hd, 2.2)), tfwd(hd, 0.8)), add(add(c, tdn(hd, 1.2)), tfwd(hd, 0.5))], E["outline_hi"])

    def front(f, j, p, S):
        sh, el, ha, ua, fa = j["fa"]
        ang = fa + p.get("wpn", 0)
        barrel_end = add(ha, dirv(ang, 3.2))
        tip = add(ha, dirv(ang, p.get("lance", 6.5)))  # AD redo: resting lance 3.5 px shorter (tip x <= 38)
        f.part(Layer(W, H).capsule(ha, barrel_end, 1.4, 1.2), POR, light=1, sep=O)
        f.part(Layer(W, H).capsule(barrel_end, tip, 0.6, 0.3), [E["steel_1"], E["steel_2"], E["steel_3"]], light=1, shade=0, thr=0.3, sep=O)

    def detail(f, j, p, S):
        # stained tabard front stripe + a rose stain
        hip, neck = j["hip"], j["neck"]
        fw = tfwd(p["lean"])
        f.px(add(lerp2(neck, hip, 0.55), fw), E["rose_0"])
        f.px(add(lerp2(neck, hip, 0.65), mul(fw, 0.2)), E["rose_0"])

    S = dict(W=W, H=H, sk=sk, outline=O,
             leg=dict(ramp=ST, r=(1.4, 1.0, 0.8), boot=[E["steel_0"], E["steel_1"]], boot_r=0.9),
             arm=dict(ramp=POR, ramp_back=[E["porcelain_0"], E["porcelain_0"], E["porcelain_1"]], r=(1.2, 1.0, 0.9), hand=None),
             torso=dict(ramp=SCR, nb=2.2, nf=1.6, cf=2.6, hf=2.3, hb=2.4, chest_drop=3),
             skirt=dict(ramp=[E["scrub_0"], E["scrub_0"], E["scrub_1"]], fseg=2.2, bseg=2.6, n=2, base=-6, width_f=2.2, width_b=2.4, jag=0.7, amp=2, from_neck=False),
             head=head, front=front, detail=detail, fit=True)
    BASE = merge(REST, dict(lean=55, head=-48, fa_s=40, fa_e=30, ba_s=-10, ba_e=30, fl_h=-16, fl_k=-50, bl_h=-22, bl_k=-48,
                            f_toe=0, b_toe=0, drag=4, flutter=0.5))
    A = []
    A.append(Anim("idle", [draw_figure(merge(BASE, dict(y=0.6 * (1 - math.cos(2 * math.pi * i / 6)), lean=55 + 2 * math.sin(2 * math.pi * i / 6),
                                                        fa_s=40 + 3 * math.sin(2 * math.pi * i / 6 + 1), ph=i)), S).image() for i in range(6)], 8, True))
    A.append(Anim("move", cyc(S, lambda t, i: merge(BASE, walk(t, stride=22, arm=6, lean=58, dig=True), dict(fa_s=40, fa_e=30, head=-50)), 8), 12, True))
    # windup (AD redo): the lance arm pulls back behind the torso over frames 1-3 (tip ends ~x 8-12),
    # crouching 2 px with the head down; the last frame holds.
    WU = merge(BASE, dict(lean=62, head=-40, y=2, fa_s=-120, fa_e=-10, wpn=0, ba_s=30, ba_e=40, fl_h=-8, fl_k=-64, bl_h=-30, bl_k=-44, lance=4.5))
    A.append(Anim("windup", seq(S, [(0, BASE), (0.34, merge(WU, dict(fa_s=-40, fa_e=40, y=1, head=-44))), (0.67, merge(WU, dict(fa_s=-95))), (1, WU)], 4), 12, False))
    AT = merge(BASE, dict(lean=58, head=-46, x=2, fa_s=92, fa_e=0, ba_s=-50, fl_h=10, fl_k=-30, bl_h=-50, bl_k=-40, lance=11))
    A.append(Anim("attack", seq(S, [(0, WU), (0.34, AT), (0.67, merge(AT, dict(lance=10))), (1, merge(BASE, dict(x=1)))], 4), 18, False))
    HU = merge(BASE, dict(lean=12, head=-50, x=-2, fa_s=30, fa_e=60, ba_s=-40))
    A.append(Anim("hurt", seq(S, [(0, BASE), (0.4, merge(HU, dict(crack=1))), (1, merge(BASE, dict(lean=30, x=-1, crack=1)))], 3), 14, False))
    D1 = merge(HU, dict(crack=2, lean=0, head=-60))
    D2 = merge(BASE, dict(crack=2, lean=70, head=20, y=4, fa_s=-10, fa_e=0, fl_h=-30, fl_k=-110, bl_h=-40, bl_k=-100))
    D3 = merge(D2, dict(lean=92, head=30, y=12, x=-4, fa_s=-30, fa_e=10, fl_h=-70, fl_k=-20, bl_h=-80, bl_k=-10, ground=0))
    A.append(Anim("death", seq(S, [(0, merge(HU, dict(crack=1))), (0.25, D1), (0.55, D2), (0.85, D3), (1, D3)], 8), 12, False))
    DO = merge(BASE, dict(lean=62, head=40, fa_s=-4, fa_e=5, ba_s=-6, ba_e=5, fl_h=0, fl_k=-90, bl_h=-10, bl_k=-100, y=3, flutter=0.1))
    A.append(Anim("dormant", [draw_figure(merge(DO, dict(y=3 + 0.5 * i)), S).image() for i in range(2)], 4, True))
    return emit("needle", (W, H), (20, 38), A)


# ====================================================================== SHIELD
def shield():
    W = H = 48
    sk = Skeleton(dict(hip=(23, 30), thigh=7.0, shin=7.0, foot=3.0, torso=10.0, neck=3.4, head_r=3.4,
                       uarm=5.0, farm=5.0, shoulder_drop=1.6, ground=45.6))
    O = E["outline"]
    # AD redo: padding ramp raised one step (mid warden_2 -> warden_3, new light warden_4 ~L47)
    WD = [E["warden_2"], E["warden_3"], E["warden_4"]]
    WDD = [E["warden_1"], E["warden_2"], E["warden_3"]]
    ST = [E["steel_0"], E["steel_1"], E["steel_2"], E["steel_3"]]

    def head(f, j, p, S):
        hd = p["lean"] + p["head"]
        c = j["head"]
        hm = f.part(Layer(W, H).ellipse(add(c, (0, -0.6)), 4.0, 3.8), [E["warden_1"], E["warden_3"], E["warden_4"]], light=1, sep=O)
        f.mask_rim(hm & (f.owner == f._n - 1), E["steel_2"])  # 1 px top + back rim on the dome
        # dark faceplate
        fp = [add(c, add(tfwd(hd, 0.6), tup(hd, 0.6))), add(c, add(tfwd(hd, 3.6), tup(hd, 0.6))), add(c, add(tfwd(hd, 3.4), tdn(hd, 2.8))), add(c, add(tfwd(hd, 0.4), tdn(hd, 2.6)))]
        f.part(Layer(W, H).poly(fp), [E["lens_dark"], E["lens_dark"], E["lens_glass"]], light=1, shade=0)

    def plate(f, j, p, S):
        sh, el, ha, ua, fa = j["fa"]
        ang = p.get("sh_ang", 0)  # slab tilt: 0 upright
        up = tup(ang)
        fw = tfwd(ang)
        c = add(ha, mul(fw, 1.5))
        top, bot = add(c, mul(up, 15 + p.get("sh_up", 0))), add(c, mul(up, -13 + p.get("sh_up", 0)))
        pts = [add(top, mul(fw, -2.6)), add(top, mul(fw, 3.4)), add(bot, mul(fw, 3.4)), add(bot, mul(fw, -2.6))]
        f.part(Layer(W, H).poly(pts), ST, light=1, shade=1, sep=O)
        for k in (0.12, 0.5, 0.88):
            f.px(add(lerp2(top, bot, k), mul(fw, -0.8)), E["steel_0"])
            f.px(add(lerp2(top, bot, k), mul(fw, 1.8)), E["steel_0"])
        f.part(Layer(W, H).poly([add(lerp2(top, bot, 0.3), mul(fw, 0.2)), add(lerp2(top, bot, 0.3), mul(fw, 1.2)), add(lerp2(top, bot, 0.33), mul(fw, 1.2)), add(lerp2(top, bot, 0.33), mul(fw, 0.2))]), [E["steel_0"]], light=0, shade=0, thr=0.3)

    def detail(f, j, p, S):
        fw = tfwd(p["lean"])
        # padded belt
        f.part(Layer(W, H).capsule(add(j["hip"], mul(fw, -3.5)), add(j["hip"], mul(fw, 3.2)), 1.0), [E["warden_0"], E["steel_0"]], light=0)

    S = dict(W=W, H=H, sk=sk, outline=O,
             leg=dict(ramp=WD, ramp_back=WDD, r=(2.8, 2.3, 1.9), boot=[E["steel_0"], E["steel_1"]], boot_r=1.7),
             arm=dict(ramp=WD, ramp_back=WDD, r=(2.6, 2.1, 1.8), hand=[E["steel_0"], E["steel_1"]], hand_r=1.5),
             torso=dict(ramp=WD, nb=4.8, nf=4.0, cf=5.0, hf=4.2, hb=4.6, chest_drop=4),
             head=head, detail=detail, front=lambda f, j, p, S: plate(f, j, p, S) if p.get("plate", 1) else None, fit=True,
             rim=[dict(colour=E["warden_4"], only=[E["warden_2"], E["warden_3"], E["warden_1"]], top=True, back=True)])
    BASE = merge(REST, dict(lean=10, head=-8, fa_s=70, fa_e=20, ba_s=-5, ba_e=40, fl_h=18, fl_k=24, bl_h=-18, bl_k=12, drag=0))
    A = []
    A.append(Anim("idle", [draw_figure(merge(BASE, dict(y=0.5 * (1 - math.cos(2 * math.pi * i / 6)), sh_up=0.4 * math.sin(2 * math.pi * i / 6))), S).image() for i in range(6)], 8, True))
    A.append(Anim("move", cyc(S, lambda t, i: merge(BASE, walk(t, stride=12, knee=20, arm=0, lean=12, bob=0.8), dict(fa_s=70, fa_e=20, ba_s=-5)), 8), 10, True))
    WU = merge(BASE, dict(lean=-4, x=-2, fa_s=40, fa_e=50, sh_ang=-10, fl_h=24, bl_h=-24, bl_k=20))
    A.append(Anim("windup", seq(S, [(0, BASE), (0.5, merge(WU, dict(x=-1))), (1, WU)], 4), 12, False))
    AT = merge(BASE, dict(lean=24, x=4, fa_s=86, fa_e=0, sh_ang=8, fl_h=34, fl_k=30, bl_h=-30, bl_k=6))
    A.append(Anim("attack", seq(S, [(0, WU), (0.34, AT), (0.67, merge(AT, dict(x=4))), (1, merge(BASE, dict(x=2)))], 4), 18, False))
    HU = merge(BASE, dict(lean=-8, head=-20, x=-2, sh_ang=-6))
    A.append(Anim("hurt", seq(S, [(0, BASE), (0.4, HU), (1, merge(BASE, dict(x=-1)))], 3), 14, False))
    GB = merge(BASE, dict(lean=-16, head=-24, x=-3, fa_s=150, fa_e=10, sh_ang=-40, sh_up=2, ba_s=-40, fl_h=30, bl_h=-30, bl_k=30))
    A.append(Anim("guard_break", seq(S, [(0, BASE), (0.3, GB), (0.7, merge(GB, dict(sh_ang=-55, lean=-12))), (1, merge(BASE, dict(lean=0, fa_s=40, fa_e=40, sh_ang=-15)))], 5), 14, False))
    D1 = merge(HU, dict(fa_s=100, sh_ang=-30))
    D2 = merge(BASE, dict(lean=40, head=10, y=6, fa_s=-20, fa_e=10, sh_ang=-80, plate=1, fl_h=70, fl_k=110, bl_h=-10, bl_k=120, b_toe=60))
    D3 = merge(D2, dict(lean=90, head=10, y=11, x=-3, ground=0, fa_s=-40, sh_ang=-90, fl_h=-80, fl_k=-10, bl_h=-85, bl_k=-5))
    A.append(Anim("death", seq(S, [(0, HU), (0.3, D1), (0.6, D2), (0.85, D3), (1, D3)], 8), 12, False))
    return emit("shield", (W, H), (24, 46), A)


# ====================================================================== ENFORCER
def enforcer():
    W = H = 48
    sk = Skeleton(dict(hip=(24, 26), thigh=8.5, shin=8.5, foot=3.0, torso=11.0, neck=4.2, head_r=3.2,
                       uarm=6.0, farm=5.8, shoulder_drop=1.6, ground=45.6))
    O = E["outline"]
    MR = [E["maroon_0"], E["maroon_1"], E["maroon_2"]]
    WD = [E["warden_0"], E["warden_1"], E["warden_2"]]
    ST = [E["steel_0"], E["steel_1"], E["steel_2"], E["steel_3"]]

    def head(f, j, p, S):
        hd = p["lean"] + p["head"]
        c = j["head"]
        f.part(Layer(W, H).ellipse(c, 3.0, 3.3).capsule(add(c, tfwd(hd, 1)), add(c, add(tfwd(hd, 2.2), tdn(hd, 1.8))), 1.5), [E["warden_1"], E["warden_2"], E["warden_3"]], light=1, sep=O)
        # peaked cap brim + crown
        brim = [add(c, add(tfwd(hd, -3.0), tup(hd, 1.6))), add(c, add(tfwd(hd, 5.0), tup(hd, 1.0))), add(c, add(tfwd(hd, 4.6), tup(hd, 0.2))), add(c, add(tfwd(hd, -3.0), tup(hd, 0.8)))]
        f.part(Layer(W, H).poly(brim), [E["steel_0"], E["steel_1"], E["steel_2"]], light=1, thr=0.4)
        crown = [add(c, add(tfwd(hd, -3.2), tup(hd, 1.2))), add(c, add(tfwd(hd, 2.8), tup(hd, 1.2))), add(c, add(tfwd(hd, 2.2), tup(hd, 4.2))), add(c, add(tfwd(hd, -2.6), tup(hd, 4.4)))]
        cm = f.part(Layer(W, H).poly(crown), [E["warden_1"], E["warden_2"], E["warden_3"]], light=1)
        f.mask_rim(cm & (f.owner == f._n - 1), E["steel_2"])  # AD redo: 1 px rim on the peaked cap
        # dark visor band
        for i in range(3):
            f.px(add(add(c, tfwd(hd, 0.8 + i)), tdn(hd, 0.2)), E["lens_dark"])

    def detail(f, j, p, S):
        fw = tfwd(p["lean"])
        n = j["neck"]
        # slate armoured collar
        f.part(Layer(W, H).capsule(add(n, mul(fw, -3.4)), add(n, mul(fw, 3.0)), 1.9), [E["steel_0"], E["steel_1"], E["steel_2"]], light=1)
        f.part(Layer(W, H).capsule(add(j["hip"], mul(fw, -3.2)), add(j["hip"], mul(fw, 3.0)), 0.8), [E["warden_0"]], light=0, shade=0)

    def baton(f, j, p, S):
        sh, el, ha, ua, fa = j["fa"]
        ang = fa + p.get("wpn", 0)
        tip = add(ha, dirv(ang, 11 * p.get("wlen_k", 1.0)))
        f.part(Layer(W, H).capsule(add(ha, dirv(ang, -1.5)), tip, 1.1, 0.9), [E["steel_0"], E["steel_1"], E["steel_2"]], light=1, sep=O, thr=0.4)
        f.px(tip, E["steel_3"])

    S = dict(W=W, H=H, sk=sk, outline=O,
             leg=dict(ramp=WD, r=(2.0, 1.6, 1.3), boot=[E["outline_hi"], E["steel_0"]], boot_r=1.5),
             arm=dict(ramp=MR, ramp_back=[E["maroon_0"], E["maroon_0"], E["maroon_1"]], r=(1.8, 1.5, 1.3), hand=[E["warden_0"], E["warden_1"]], hand_r=1.3),
             torso=dict(ramp=MR, nb=3.4, nf=2.8, cf=3.4, hf=3.0, hb=3.4, chest_drop=4),
             skirt=dict(ramp=MR, fseg=4.2, bseg=5.2, n=3, base=-8, width_f=3.0, width_b=3.4, jag=0.6, amp=3, split=2.5),
             head=head, detail=detail, front=baton, fit=True)
    BASE = merge(REST, dict(lean=6, head=-4, fa_s=20, fa_e=40, wpn=-20, ba_s=-8, ba_e=10, fl_h=8, fl_k=6, bl_h=-8, bl_k=6, drag=6))
    A = []
    A.append(Anim("idle", [draw_figure(merge(BASE, dict(y=0.6 * (1 - math.cos(2 * math.pi * i / 6)), ph=2 * math.pi * i / 6, flutter=0.4, wpn=-20 + 4 * math.sin(2 * math.pi * i / 6))), S).image() for i in range(6)], 8, True))
    A.append(Anim("move", cyc(S, lambda t, i: merge(BASE, walk(t, stride=24, knee=34, arm=14, lean=10), dict(fa_s=20, fa_e=40, drag=16, flutter=0.8)), 8), 12, True))
    # AD redo: the raised baton angles back over the shoulder (tip y >= 1); the swing keeps x <= 46
    WB = merge(BASE, dict(lean=-4, fa_s=150, fa_e=30, wpn=55, ba_s=30, ba_e=40, fl_h=20, bl_h=-18))
    A.append(Anim("windup_baton", seq(S, [(0, BASE), (0.5, merge(WB, dict(fa_s=130, wpn=40))), (1, WB)], 4), 12, False))
    AB = merge(BASE, dict(lean=26, x=0, fa_s=60, fa_e=0, wpn=0, ba_s=-30, fl_h=30, fl_k=30, bl_h=-24, drag=20))
    A.append(Anim("attack_baton", seq(S, [(0, WB), (0.25, merge(AB, dict(fa_s=100))), (0.5, AB), (0.75, merge(AB, dict(fa_s=30))), (1, merge(BASE, dict(x=1)))], 5), 18, False))
    WL = merge(BASE, dict(lean=30, y=3, fa_s=-20, fa_e=90, wpn=-60, fl_h=50, fl_k=80, bl_h=-30, bl_k=40, drag=4))
    A.append(Anim("windup_lunge", seq(S, [(0, BASE), (0.5, merge(WL, dict(y=2))), (1, WL)], 3), 12, False))
    AL = merge(BASE, dict(lean=36, x=1, fa_s=90, fa_e=0, wpn=0, fl_h=42, fl_k=36, bl_h=-40, bl_k=10, drag=26, lift=10, wlen_k=0.85))
    A.append(Anim("attack_lunge", seq(S, [(0, WL), (0.33, AL), (0.66, merge(AL, dict(x=2.5))), (1, merge(BASE, dict(x=2)))], 4), 20, False))
    HU = merge(BASE, dict(lean=-14, head=-18, x=-2, fa_s=-20, drag=-10, flutter=1.3))
    A.append(Anim("hurt", seq(S, [(0, BASE), (0.4, HU), (1, merge(BASE, dict(x=-1)))], 3), 14, False))
    K1 = merge(BASE, dict(y=8, lean=18, head=18, fl_h=80, fl_k=100, bl_h=-20, bl_k=140, b_toe=60, fa_s=-10, fa_e=10, wpn=40, drag=0))
    KM = merge(K1, dict(y=12, lean=50, head=20, fa_s=-20))
    # AD redo: falls face-down along the facing axis with the knees bent, so the prone pose fits x 2..45
    K2 = merge(K1, dict(y=16, x=-1, ground=0, lean=90, head=10, fa_s=-30, fa_e=0, fl_h=-80, fl_k=70, bl_h=-86, bl_k=60, b_toe=0))
    A.append(Anim("death", seq(S, [(0, HU), (0.2, merge(HU, dict(lean=-20))), (0.45, K1), (0.6, merge(K1, dict(lean=26, head=30))), (0.75, KM), (0.9, K2), (1, K2)], 10), 12, False))
    # generic aliases so EnemyVisual.play_first([windup, attack, ...]) works before the family hook lands
    A.append(Anim("windup", A[2].frames, 12, False))
    A.append(Anim("attack", A[3].frames, 18, False))
    return emit("enforcer", (W, H), (24, 46), A)


if __name__ == "__main__":
    which = sys.argv[1:] or ["needle", "shield", "enforcer"]
    for w in which:
        globals()[w]()
