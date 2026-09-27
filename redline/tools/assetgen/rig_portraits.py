"""48x48 3/4-view bust portraits (P3). NPCs get a 2nd talk/blink frame.
Out: assets/portraits/portrait_<name>.png (horizontal strip, 48x48 cells) + portraits_atlas_x3.png preview.
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
P = PAL["palettes"]
R, N, K = P["char_rook"]["colors"], P["char_npc"]["colors"], P["char_boss_krail"]["colors"]
W = H = 48
SKIN = [N["skin_0"], N["skin_1"], N["skin_2"], N["skin_3"]]


def L():
    return Layer(W, H)


def shoulders(f, ramp, wide=17, y=40):
    f.part(L().ellipse((22, y + 8), wide, 11), ramp, light=2, shade=1)


def face(f, talk=False, blink=False, brow=None, beard=None):
    f.part(L().rect(19, 30, 27, 38), SKIN[:3], light=1)  # neck
    f.part(L().ellipse((24, 22), 8.5, 10).poly([(28, 16), (33.5, 23), (32, 28), (27, 31)]), SKIN, light=2, shade=2)
    # ear, eye, brow, nose, mouth
    f.part(L().ellipse((18.5, 23), 1.6, 2.4), [N["skin_0"], N["skin_1"]], light=0)
    ey = (29, 21)
    if blink:
        f.part(L().rect(28, 21, 31, 22), [N["skin_0"]], light=0, shade=0)
    else:
        f.part(L().rect(28, 20, 30, 22), [N["hair_0"]], light=0, shade=0)
        f.px((28, 20), N["skin_3"])
    f.part(L().rect(27, 18, 31, 19), [brow or N["hair_1"]], light=0, shade=0)
    f.px((33, 24), N["skin_1"])
    f.px((32, 25), N["skin_0"])
    if talk:
        f.part(L().rect(28, 27, 31, 29), [N["hair_0"]], light=0, shade=0)
    else:
        f.part(L().rect(28, 28, 31, 29), [N["skin_0"]], light=0, shade=0)
    if beard:
        for x, y in ((26, 30), (28, 30), (30, 30), (25, 28), (31, 29), (27, 31), (29, 31)):
            f.px((x, y), beard)


def finish(f, outline=N["outline"]):
    f.outline(outline)
    return f.image()


def rook(v):
    f = Frame(W, H)
    f.part(L().ellipse((22, 50), 21, 14), [R["coat_0"], R["coat_1"], R["coat_2"], R["coat_3"]], light=2, shade=1)
    f.part(L().rect(19, 30, 28, 40), [R["suit_0"], R["suit_1"]], light=0)  # neck seal
    f.part(L().poly([(13, 33), (19, 31), (21, 40), (14, 42)]).poly([(28, 31), (34, 33), (33, 42), (27, 40)]), [R["coat_0"], R["coat_1"], R["coat_2"]], light=1, sep=R["outline"])  # scarf-collar
    hm = f.part(L().ellipse((24, 21), 10, 11.5).poly([(28, 14), (34.5, 22), (33, 30), (25, 33)]), [R["suit_1"], R["suit_2"], R["suit_2"]], light=0, shade=2)
    f.mask_rim(hm, R["coat_1"])  # AD redo: helmet mid lifted + coat_1 rim on top/back, matches the sheet
    f.part(L().rect(26, 21, 34, 23), [R["visor"]], light=0, shade=0)
    f.px((31, 21), R["core_hot"])
    f.part(L().rect(23, 42, 25, 46), [R["core_glow"]], light=0, shade=0)
    return [finish(f, R["outline"])]


def krail(v):
    f = Frame(W, H)
    shoulders(f, [K["coat_1"], K["coat_2"], K["coat_3"]], 20)
    f.part(L().ellipse((14, 39), 9, 6), [K["armor_0"], K["armor_1"], K["armor_2"], K["rain_sheen"]], light=2, shade=1, sep=K["outline"])  # pauldron
    for x in (9, 13, 17):
        f.px((x, 42), K["armor_0"])
    f.part(L().rect(15, 31, 33, 34), [K["armor_0"], K["armor_1"], K["armor_2"]], light=1, shade=1)  # collar band (AD redo)
    f.part(L().poly([(14, 4), (32, 5), (34, 30), (15, 31)]), [K["armor_0"], K["armor_1"], K["armor_2"], K["rain_sheen"]], light=2, shade=2, sep=K["outline"])
    f.part(L().rect(23, 18, 34, 20), [K["visor"]], light=0, shade=0)
    f.part(L().rect(15, 3, 32, 5), [K["armor_0"], K["armor_1"]], light=0)
    return [finish(f, K["outline"])]


# AD redo: one head per NPC (skull, jaw, skin ramp, features), not a shared template.
SK_WEATHER = [N["skin_0"], N["skin_1"], N["skin_2"], N["skin_3"]]         # Orr
SK_WARM = [N["skin_1"], N["skin_2"], N["skin_3"], N["skin_pale"]]         # Mara
SK_PALE = [N["skin_2"], N["skin_3"], N["skin_pale"], N["skin_pale"]]      # Nix
SK_ASH = [N["skin_deep_1"], N["skin_deep_2"], N["skin_2"], N["skin_3"]]   # Vell
SK_DEEP = [N["skin_deep_0"], N["skin_deep_1"], N["skin_deep_2"], N["skin_2"]]  # Iko


def head2(f, sk, skull, jaw, eye=(29, 21), talk=False, blink=False, brow=None, brow_y=18, mouth_y=28, nose=(33, 24), neck=(19, 30, 27, 38)):
    """skull: (cx, cy, rx, ry); jaw: polygon for the lower face / chin (3/4 view facing right)."""
    f.part(L().rect(*neck), sk[:3], light=1)
    f.part(L().ellipse(skull[:2], skull[2], skull[3]).poly(jaw), sk, light=2, shade=2)
    f.part(L().ellipse((skull[0] - skull[2] + 2.5, skull[1] + 1), 1.6, 2.4), [sk[0], sk[1]], light=0)  # ear
    ex, ey = eye
    if blink:
        f.part(L().rect(ex - 1, ey + 1, ex + 2, ey + 2), [sk[0]], light=0, shade=0)
    else:
        f.part(L().rect(ex - 1, ey - 1, ex + 2, ey + 2), [N["hair_0"]], light=0, shade=0)
        f.px((ex - 1, ey - 1), sk[3])
    if brow:
        f.part(L().rect(ex - 2, brow_y, ex + 3, brow_y + 1), [brow], light=0, shade=0)
    f.px(nose, sk[1])
    f.px((nose[0] - 1, nose[1] + 1), sk[0])
    if talk:
        f.part(L().rect(ex - 1, mouth_y - 1, ex + 3, mouth_y + 1), [N["hair_0"]], light=0, shade=0)
        f.px((ex, mouth_y), N["skin_0"])
    else:
        f.part(L().rect(ex - 1, mouth_y, ex + 3, mouth_y + 1), [sk[0]], light=0, shade=0)


def npc(name, v):
    f = Frame(W, H)
    talk, blink = v == 1, v == 1
    if name == "orr":
        # broad, older: wide skull, heavy grey beard, headphones slung over the neck
        shoulders(f, [N["orr_poncho"], N["orr_poncho_hi"], N["orr_poncho_top"]], 20)
        head2(f, SK_WEATHER, (23, 22, 9.6, 9.6), [(29, 15), (34, 23), (33, 29), (28, 32), (19, 31)], eye=(29, 21), talk=talk, blink=blink,
              brow=N["grey_hair"], brow_y=17, mouth_y=28, neck=(18, 30, 28, 38))
        f.part(L().poly([(18, 26), (22, 31), (27, 33), (32, 30), (34, 26), (32, 27), (27, 28) if not talk else (27, 30), (23, 27)]), [N["hair_1"], N["grey_hair"], N["grey_hair"]], light=1)
        f.part(L().poly([(14, 19), (16, 11), (22, 8), (28, 9), (22, 12), (18, 19)]), [N["hair_1"], N["grey_hair"]], light=1)  # thin grey hair
        f.part(L().ellipse((21, 37), 8.5, 3.0), [N["orr_phones"], N["cloth_mid"], N["cloth_hi"]], light=1, sep=N["outline"])      # band
        f.part(L().rect(26, 33, 32, 40), [N["orr_phones"], N["cloth_mid"], N["cloth_hi"]], light=1, shade=1, sep=N["outline"])  # cup
        f.px((28, 34), N["grey_hair"])
    elif name == "mara":
        # square-jawed, goggles pushed up on the forehead
        shoulders(f, [N["cloth_mid"], N["cloth_hi"], N["cloth_hi"]], 20)
        f.part(L().poly([(17, 40), (22, 40), (21, 48), (16, 48)]).poly([(28, 40), (33, 40), (32, 48), (27, 48)]), [N["mara_apron"], N["mara_rust"], N["mara_rust_hi"]], light=1)
        head2(f, SK_WARM, (24, 21, 8.4, 9.0), [(28, 14), (34, 22), (34, 29), (31, 32), (22, 32), (19, 28)], eye=(29, 21), talk=talk, blink=blink,
              brow=N["hair_1"], brow_y=18, mouth_y=28)
        f.part(L().poly([(15, 21), (16, 11), (22, 8), (30, 9), (33, 13), (24, 12), (19, 16), (18, 23)]), [N["hair_0"], N["hair_1"], N["hair_1"]], light=1)
        f.part(L().capsule((15, 13.5), (33, 13.5), 2.2), [N["hair_1"], N["mara_goggle"], N["mara_goggle"]], light=1, sep=N["outline"])
        f.part(L().circle((29, 13.5), 1.6), [N["nix_paper"]], light=0, shade=0)
        f.part(L().circle((23, 13.5), 1.6), [N["nix_paper"]], light=0, shade=0)
        f.px((30, 26), N["skin_1"])  # scorch freckle
    elif name == "nix":
        # narrow, long face, pale; 2x2 brass monocle glint
        shoulders(f, [N["cloth_mid"], N["cloth_hi"], N["grey_hair"]], 17)
        head2(f, SK_PALE, (24, 20, 7.0, 10.0), [(27, 13), (32, 21), (31, 30), (27, 34), (22, 31)], eye=(29, 20), talk=talk, blink=blink,
              brow=N["hair_1"], brow_y=17, mouth_y=29, nose=(32, 24), neck=(20, 30, 27, 38))
        f.part(L().poly([(16, 22), (16, 11), (21, 7), (29, 7), (31, 11), (23, 11), (19, 18)]), [N["hair_0"], N["hair_1"]], light=1)
        f.part(L().capsule((13, 36), (33, 34), 3.4).capsule((15, 37), (11, 47), 3), [N["nix_scarf"], N["nix_scarf"], N["nix_scarf_hi"]], light=1, sep=N["outline"])
        f.part(L().circle((29.5, 20.5), 2.6), [N["mara_goggle"]], light=0, shade=0)
        f.part(L().circle((29.5, 20.5), 1.4), [N["hair_0"]] if not blink else [N["skin_2"]], light=0, shade=0)
        f.part(L().rect(30, 18, 32, 20), [N["nix_paper"]], light=0, shade=0)  # 2x2 glint
        f.part(L().rect(33, 44, 38, 48), [N["nix_paper"]], light=0, shade=0)
    elif name == "vell":
        # gaunt: hollow cheek, sharp chin; high collar lined with card flecks up to the jaw
        head2(f, SK_ASH, (24, 20, 7.6, 9.4), [(28, 13), (33, 21), (31, 28), (29, 33), (24, 31), (21, 27)], eye=(29, 20), talk=talk, blink=blink,
              brow=N["hair_0"], brow_y=16, mouth_y=28, nose=(33, 23))
        f.px((27, 25), N["skin_deep_1"])
        f.px((26, 26), N["skin_deep_1"])  # hollow cheek
        shoulders(f, [N["vell_coat"], N["vell_coat_hi"], N["vell_coat_hi"]], 16)
        f.part(L().poly([(12, 44), (14, 30), (20, 27), (22, 40)]).poly([(35, 44), (34, 30), (31, 29), (29, 40)]), [N["cloth_dark"], N["vell_coat"], N["vell_coat_hi"]], light=1, sep=N["outline"])
        for x, y in ((16, 33), (18, 36), (15, 39), (19, 41), (33, 33), (32, 37), (33, 41)):
            f.px((x, y), N["vell_card"])
        f.part(L().poly([(15, 22), (15, 12), (22, 7), (32, 10), (33, 14), (24, 13), (18, 16)]), [N["hair_0"], N["hair_0"], N["hair_1"]], light=1)
        f.px((31, 27), N["skin_deep_1"])  # sly smirk
    elif name == "iko":
        # young, hooded; the chalk-eye mark sits on the hood
        shoulders(f, [N["iko_oilskin"], N["iko_oilskin_hi"], N["iko_oilskin_top"]], 18)
        head2(f, SK_DEEP, (24, 22, 8.0, 8.8), [(28, 16), (33, 23), (32, 28), (28, 31), (21, 29)], eye=(29, 22), talk=talk, blink=blink,
              brow=N["hair_0"], brow_y=19, mouth_y=28)
        f.part(L().poly([(12, 34), (13, 14), (18, 7), (8, 2), (24, 5), (31, 7), (35, 14), (31, 14), (26, 11), (19, 15), (18, 30), (20, 38)]),
               [N["iko_oilskin"], N["iko_oilskin_hi"], N["iko_oilskin_top"]], light=2, sep=N["outline"])
        f.part(L().ellipse((16, 20), 2.2, 1.4), [N["iko_chalk"]], light=0, shade=0)
        f.px((16, 20), N["iko_oilskin"])
        f.px((14, 20), N["iko_chalk"])
        f.px((18, 20), N["iko_chalk"])
    return finish(f)


def main():
    out = os.path.join(ASSETS, "portraits")
    os.makedirs(out, exist_ok=True)
    sets = {"rook": rook(0), "krail": krail(0)}
    for n in ("orr", "mara", "nix", "vell", "iko"):
        sets[n] = [npc(n, 0), npc(n, 1)]
    atlas = Image.new("RGBA", (W * 2, H * len(sets)), (0, 0, 0, 0))
    for r, (n, frs) in enumerate(sets.items()):
        strip = Image.new("RGBA", (W * len(frs), H), (0, 0, 0, 0))
        for k, im in enumerate(frs):
            strip.paste(im, (k * W, 0))
            atlas.paste(im, (k * W, r * H))
        strip.save(os.path.join(out, f"portrait_{n}.png"), optimize=True)
    preview(atlas, os.path.join(out, "portraits_atlas_x3.png"))
    allowed = ("#e8283c",)
    print(json.dumps(dict(id="portraits", n=len(sets), frames=sum(len(v) for v in sets.values()), **check_sheet(atlas, list(PAL["reserved"].values()), allowed))))


if __name__ == "__main__":
    main()
