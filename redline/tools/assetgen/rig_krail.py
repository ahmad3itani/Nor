"""Warden Krail boss rig -> assets/bosses/warden_krail_sheet.png (+ .tres). Cell 96x80, origin (48,78)."""
from __future__ import annotations

import json
import math
import re
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pixrig import Layer, add, mul, lerp2, tup, tfwd, tdn, dirv, merge, Anim  # noqa
from humanoid import Skeleton, REST  # noqa
from pixrig import hex2rgb, red_mask  # noqa
import numpy as np
from figure import draw_figure, seq, cyc  # noqa
from rig_enemies import walk, emit, PAL  # noqa
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

K = PAL["palettes"]["char_boss_krail"]["colors"]
W, H = 96, 80
O = K["outline"]
# AD redo: coat ramp lifted one step (mid coat_1 -> coat_2, median L >= 26) so he stops sinking into dark rooms
COAT = [K["coat_1"], K["coat_2"], K["coat_3"]]
COATB = [K["coat_0"], K["coat_1"], K["coat_2"]]
ARM = [K["armor_0"], K["armor_1"], K["armor_2"]]
LEA = [K["leather_0"], K["leather_1"]]
PAL.setdefault("_allowed", {})["warden_krail"] = ["#e8283c"]  # visor band: sanctioned Warden red

sk = Skeleton(dict(hip=(44, 50), thigh=12.0, shin=12.5, foot=4.2, torso=15.0, neck=5.6, head_r=4.0,
                   uarm=8.5, farm=8.0, shoulder_drop=2.0, ground=77.6))


def head(f, j, p, S):
    hd = p["lean"] + p["head"]
    c = j["head"]
    # tall cylindrical helm
    pts = [add(c, add(tfwd(hd, -3.6), tdn(hd, 3.6))), add(c, add(tfwd(hd, 4.2), tdn(hd, 3.6))),
           add(c, add(tfwd(hd, 3.8), tup(hd, 6.4))), add(c, add(tfwd(hd, -3.4), tup(hd, 6.6)))]
    f.part(Layer(W, H).poly(pts), [K["armor_0"], K["armor_1"], K["armor_2"], K["rain_sheen"]], light=1, shade=1, sep=O)
    # crest ridge
    f.part(Layer(W, H).capsule(add(c, add(tfwd(hd, -2.8), tup(hd, 6.8))), add(c, add(tfwd(hd, 3.0), tup(hd, 6.6))), 0.8), [K["armor_0"], K["armor_1"]], light=0, thr=0.4)
    # red visor band (narrow): 1 px tall, 5 wide at the front
    col = K["visor"] if p.get("visor", 1) >= 1 else (K["leather_1"] if p.get("visor", 1) > 0.3 else K["armor_0"])
    for i in range(5):
        f.px(add(add(c, tfwd(hd, 0.2 + i)), tup(hd, 0.8)), col)
    if p.get("visor_flare"):
        for i in range(5):
            f.px(add(add(c, tfwd(hd, 0.2 + i)), tup(hd, 1.8)), K["visor"])
    # collar band (AD redo, replaces the gorget blob): 3 px tall, follows the neck
    n = j["neck"]
    fw = tfwd(p["lean"])
    band = [add(add(n, mul(fw, -3.6)), mul(j["up"], 1.9)), add(add(n, mul(fw, 3.4)), mul(j["up"], 1.5)),
            add(add(n, mul(fw, 3.6)), mul(j["up"], -1.2)), add(add(n, mul(fw, -3.8)), mul(j["up"], -0.8))]
    f.part(Layer(W, H).poly(band), [K["armor_0"], K["armor_1"], K["armor_2"]], light=1, shade=1, sep=O)


def detail(f, j, p, S):
    fw = tfwd(p["lean"])
    hip, neck = j["hip"], j["neck"]
    # belt + buckle, coat closure line
    f.part(Layer(W, H).capsule(add(hip, add(mul(fw, -4.6), mul(j["up"], 2.5))), add(hip, add(mul(fw, 4.4), mul(j["up"], 2.5))), 1.1), LEA, light=0)
    f.px(add(hip, add(mul(fw, 3.6), mul(j["up"], 2.5))), K["armor_2"])
    for k in (0.3, 0.5, 0.7):
        f.px(add(lerp2(neck, hip, k), mul(fw, 3.8)), K["armor_1"])


def front_pre(f, j, p, S):
    pass


def front(f, j, p, S):
    sh, el, ha, ua, fa = j["fa"]
    # baton
    if p.get("baton", 1):
        ang = fa + p.get("wpn", 0)
        tip = add(ha, dirv(ang, 17))
        f.part(Layer(W, H).capsule(add(ha, dirv(ang, -2.5)), tip, 1.3, 1.1), [K["armor_0"], K["baton_body"], K["armor_1"]], light=1, sep=O, thr=0.4)
        f.part(Layer(W, H).capsule(add(ha, dirv(ang, 14.5)), tip, 1.2), [K["baton_arc"]], light=0, shade=0, thr=0.4)
    # massive riveted pauldron over the lead shoulder (AD redo): ~12x9 px in armour steel_2,
    # 3 rivets, 1 px top highlight, a raised gardbrace flange that climbs to the visor line so the
    # silhouette steps up asymmetrically on the lead side.
    fw = tfwd(p["lean"])
    up = j["up"]
    c = add(sh, add(mul(fw, -2.6), mul(up, 2.4)))
    L = Layer(W, H).ellipse(c, 7.0, 4.8)
    # short raised flange at the back-top of the plate: the step that breaks the shoulder line
    flange = [add(c, add(mul(fw, -6.6), mul(up, 0.6))), add(c, add(mul(fw, -6.2), mul(up, 7.0))),
              add(c, add(mul(fw, -3.4), mul(up, 5.6))), add(c, add(mul(fw, -2.0), mul(up, 3.0)))]
    L.poly(flange)
    m = f.part(L, [K["armor_1"], K["armor_2"], K["armor_2"], K["rain_sheen"]], light=1, shade=1, sep=O)
    # 1 px top highlight across the plate
    top = m & ~np.roll(m, 1, 0)
    f.rgb[top & (f.owner == f._n - 1)] = hex2rgb(K["rain_sheen"])
    # lower lame line + 3 rivets
    f.part(Layer(W, H).capsule(add(c, add(mul(fw, -5.0), mul(up, -1.6))), add(c, add(mul(fw, 5.0), mul(up, -1.6))), 0.55), [K["armor_0"]], light=0, shade=0, thr=0.4)
    for dx in (-3.2, 0, 3.2):
        f.px(add(c, add(mul(fw, dx), mul(up, 0.6))), K["armor_0"])


S = dict(W=W, H=H, sk=sk, outline=O,
         leg=dict(ramp=[K["coat_1"], K["coat_2"], K["coat_2"]], ramp_back=[K["coat_0"], K["coat_1"], K["coat_1"]], r=(3.0, 2.5, 2.1),
                  boot=[K["leather_0"], K["leather_1"]], boot_r=2.5),
         arm=dict(ramp=COAT, ramp_back=COATB, r=(3.0, 2.5, 2.1), hand=LEA, hand_r=2.2),
         # AD redo: shoulders/greatcoat widened (~30-34 px at the hem, flaring 4-6 px wider at the bottom)
         torso=dict(ramp=COAT, nb=8.0, nf=6.4, cf=7.6, hf=6.2, hb=7.0, chest_drop=5),
         skirt=dict(ramp=COAT, fseg=6.4, bseg=7.8, n=3, base=-22, fbase=14, width_f=6.2, width_b=7.0, jag=1.0, amp=3.5, split=6, grow=0.1),
         # 1 px rim light along the back edge of the coat (coat_3) and the helm (rain sheen)
         rim=[dict(colour=K["coat_3"], only=[K["coat_1"], K["coat_2"], K["coat_0"]], top=False),
              dict(colour=K["armor_2"], only=[K["armor_0"], K["armor_1"]], top=True, back=True)],
         head=head, detail=detail, front=front)


def build():
    B = merge(REST, dict(lean=2, head=-2, fa_s=12, fa_e=30, wpn=-15, ba_s=-4, ba_e=10, fl_h=6, fl_k=4, bl_h=-6, bl_k=4, drag=4, flutter=0.35))
    A = []
    A.append(Anim("idle", [draw_figure(merge(B, dict(y=0.6 * (1 - math.cos(2 * math.pi * i / 8)), ph=2 * math.pi * i / 8, wpn=-15 + 2 * math.sin(2 * math.pi * i / 8))), S).image() for i in range(8)], 8, True))
    A.append(Anim("move", cyc(S, lambda t, i: merge(B, walk(t, stride=22, knee=30, arm=10, lean=6, bob=1.2), dict(fa_s=12, fa_e=30, drag=14, flutter=0.8)), 8), 12, True))
    WB = merge(B, dict(lean=-6, fa_s=165, fa_e=20, wpn=10, ba_s=30, ba_e=50, fl_h=22, bl_h=-18))
    A.append(Anim("windup_baton", seq(S, [(0, B), (0.5, merge(WB, dict(fa_s=140))), (1, WB)], 4), 12, False))
    H1 = merge(B, dict(lean=22, x=4, fa_s=60, fa_e=0, wpn=0, ba_s=-30, fl_h=30, fl_k=30, bl_h=-24, drag=22))
    A.append(Anim("baton_1", seq(S, [(0, WB), (0.25, merge(H1, dict(fa_s=110))), (0.5, H1), (0.75, merge(H1, dict(fa_s=20))), (1, merge(B, dict(x=2)))], 5), 18, False))
    H2a = merge(B, dict(lean=10, fa_s=-30, fa_e=60, wpn=-60, x=2, fl_h=26, bl_h=-20))
    H2 = merge(B, dict(lean=16, x=5, fa_s=92, fa_e=0, wpn=0, ba_s=-40, fl_h=34, fl_k=30, bl_h=-28, drag=24))
    A.append(Anim("baton_2", seq(S, [(0, merge(B, dict(x=2))), (0.25, H2a), (0.5, H2), (0.75, merge(H2, dict(fa_s=120))), (1, merge(B, dict(x=3)))], 5), 18, False))
    WL = merge(B, dict(lean=28, y=4, fa_s=-30, fa_e=90, wpn=-60, fl_h=50, fl_k=80, bl_h=-30, bl_k=40, drag=4))
    A.append(Anim("windup_lunge", seq(S, [(0, B), (0.5, merge(WL, dict(y=2))), (1, WL)], 3), 12, False))
    LU = merge(B, dict(lean=36, x=6, fa_s=90, fa_e=0, wpn=0, fl_h=50, fl_k=40, bl_h=-50, bl_k=10, drag=45, lift=10))
    A.append(Anim("lunge", seq(S, [(0, WL), (0.33, LU), (0.66, merge(LU, dict(x=6.5))), (1, merge(B, dict(x=4)))], 4), 20, False))
    WBu = merge(B, dict(lean=-4, fa_s=40, fa_e=90, wpn=-40, ba_s=40, ba_e=90, y=1, visor_flare=1))
    A.append(Anim("windup_burst", seq(S, [(0, B), (0.5, merge(WBu, dict(visor_flare=0))), (1, WBu)], 4), 12, False))
    BU = merge(B, dict(lean=8, fa_s=110, fa_e=0, wpn=0, ba_s=-100, ba_e=0, fl_h=26, bl_h=-26, drag=30, flutter=1.4, lift=12))
    A.append(Anim("burst", seq(S, [(0, WBu), (0.34, BU), (0.67, merge(BU, dict(ph=2))), (1, B)], 4), 16, False))
    WS = merge(B, dict(lean=-10, head=-10, y=-1, fa_s=175, fa_e=10, wpn=0, ba_s=170, ba_e=10, fl_h=10, bl_h=-10))
    A.append(Anim("windup_slam", seq(S, [(0, B), (0.4, merge(WS, dict(fa_s=150, ba_s=140))), (1, WS)], 5), 12, False))
    SL = merge(B, dict(lean=42, head=10, y=8, fa_s=70, fa_e=0, wpn=10, ba_s=60, ba_e=0, fl_h=55, fl_k=95, bl_h=-30, bl_k=90, b_toe=50, drag=20, lift=16))
    A.append(Anim("slam", seq(S, [(0, WS), (0.2, merge(SL, dict(y=3, lean=20, fa_s=120, ba_s=110))), (0.4, SL), (0.7, merge(SL, dict(lift=6, drag=6))), (1, merge(B, dict(y=2, lean=10)))], 6), 16, False))
    BS = merge(B, dict(lean=-8, x=-6, fl_h=-10, bl_h=-30, bl_k=20, drag=-10, flutter=1.2))
    A.append(Anim("backstep", seq(S, [(0, B), (0.4, merge(BS, dict(x=-3, y=-1))), (0.8, BS), (1, merge(B, dict(x=-6)))], 4), 16, False))
    HU = merge(B, dict(lean=-10, head=-16, x=-2, fa_s=-20, drag=-10, flutter=1.3))
    A.append(Anim("hurt", seq(S, [(0, B), (0.4, HU), (1, merge(B, dict(x=-1)))], 3), 14, False))
    ST = merge(B, dict(y=12, lean=26, head=22, fl_h=80, fl_k=100, bl_h=-20, bl_k=140, b_toe=60, fa_s=40, fa_e=10, wpn=60, ba_s=10, ba_e=30, drag=0))
    A.append(Anim("stagger", seq(S, [(0, HU), (0.3, merge(ST, dict(y=8))), (0.6, ST), (0.8, merge(ST, dict(head=30, lean=30))), (1, ST)], 6), 12, False))
    RO = merge(B, dict(lean=-18, head=-34, fa_s=40, fa_e=100, ba_s=30, ba_e=110, wpn=-60, fl_h=24, bl_h=-24, drag=30, flutter=1.6, visor_flare=1))
    fr = seq(S, [(0, B), (0.2, merge(B, dict(lean=16, head=24, y=3, fl_h=20, fl_k=30))), (0.35, merge(RO, dict(visor_flare=0))), (0.5, RO), (0.7, merge(RO, dict(ph=3))), (0.85, merge(RO, dict(ph=5))), (1, B)], 10)
    A.append(Anim("phase2_roar", fr, 12, False))
    D1 = merge(ST, dict(baton=1, fa_s=-10, wpn=80))
    D2 = merge(ST, dict(baton=0, y=12, lean=34, head=40, fa_s=0, fa_e=0, visor=0.6))
    D3 = merge(ST, dict(baton=0, ground=0, x=-8, y=25, lean=90, head=20, fa_s=-20, fa_e=0, ba_s=-20, fl_h=-80, fl_k=-10, bl_h=-85, bl_k=-5, b_toe=0, visor=0.0))
    frames = seq(S, [(0, HU), (0.12, merge(HU, dict(lean=-16))), (0.3, merge(ST, dict(wpn=60))), (0.45, D1), (0.6, D2), (0.75, merge(D2, dict(lean=50, y=16, visor=0.4))),
                     (0.88, merge(D3, dict(visor=0.3))), (1, D3)], 16)
    A.append(Anim("death", frames, 12, False))
    return A


def main():
    sheet = emit("warden_krail", (W, H), (48, 78), build(), sub="bosses")
    out_dir = os.path.join(ASSETS, "bosses")
    red_mask(sheet).save(os.path.join(out_dir, "warden_krail_sheet_mask.png"), optimize=True)
    tres = os.path.join(out_dir, "warden_krail_sheet.tres")
    t = open(tres).read().rstrip("\n") + '\nmetadata/mask_path = "res://assets/bosses/warden_krail_sheet_mask.png"\nmetadata/mask_note = "white mask of the baked red visor band; tint in code for colour-blind / high-contrast modes, the baked red stays as the fallback"\n'
    open(tres, "w").write(t)
    rows = re.findall(r'name = &"(\w+)"\nrow = (\d+)\nfirst_frame = 0\nframe_count = (\d+)\nfps = ([\d.]+)\nloop = (\w+)', t)
    json.dump({"id": "warden_krail", "texture": "res://assets/bosses/warden_krail_sheet.png", "cell": [W, H], "origin": [48, 78],
               "mask": "res://assets/bosses/warden_krail_sheet_mask.png",
               "mask_note": "white mask of the baked red visor band (same size as the sheet); tint in code, the baked red is the fallback",
               "rows": [{"name": n, "row": int(r), "frames": int(c), "fps": float(fp), "loop": lp == "true"} for n, r, c, fp, lp in rows]},
              open(os.path.join(out_dir, "warden_krail_sheet.json"), "w"), indent=1)
    return sheet


if __name__ == "__main__":
    main()
