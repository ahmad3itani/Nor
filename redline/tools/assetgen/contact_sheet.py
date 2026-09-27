#!/usr/bin/env python3
"""Build tools/assetgen/_preview/contact_sheet.png: key art of the overhaul at x2 nearest, grouped by section.
Reads only files under assets/. Usage: python3 tools/assetgen/contact_sheet.py"""
import os, re
from PIL import Image, ImageDraw, ImageFont
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from assetgen_paths import ASSETS, AUDIO, DATA, PREVIEW, RAW, REDLINE, SOURCE_OUT  # noqa: E402

ROOT = REDLINE
OUT = ASSETS
S = 2
W = 1920
BG = (16, 16, 22)
TILE_BG = (30, 30, 40)
FG = (220, 220, 230)
HEAD = (232, 40, 60)
FONT = ImageFont.load_default()


def p(*a):
    return os.path.join(OUT, *a)


def anims(tres):
    txt = open(tres).read()
    res = {}
    for m in re.finditer(r'name = &"([^"]+)"\s*row = (\d+)\s*first_frame = (\d+)\s*frame_count = (\d+)', txt):
        res[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
    cell = re.search(r"cell_size = Vector2i\((\d+), (\d+)\)", txt)
    return res, (int(cell.group(1)), int(cell.group(2)))


def frames(sheet, tres, names):
    """Middle frame of each named anim (idle uses frame 0), laid side by side."""
    im = Image.open(sheet).convert("RGBA")
    an, (cw, ch) = anims(tres)
    cells = []
    for n in names:
        if n not in an:
            continue
        r, f0, cnt = an[n]
        f = f0 if n == "idle" else f0 + cnt // 2
        cells.append(im.crop((f * cw, r * ch, (f + 1) * cw, (r + 1) * ch)))
    out = Image.new("RGBA", (cw * len(cells), ch), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        out.paste(c, (i * cw, 0))
    return out


def rows(sheet, n=None, maxw=None):
    im = Image.open(sheet).convert("RGBA")
    if n is not None:
        im = im.crop((0, 0, im.width, n))
    if maxw and im.width > maxw:
        im = im.crop((0, 0, maxw, im.height))
    return im


def title_comp():
    sky = Image.open(p("title", "title_sky.png")).convert("RGBA")
    logo = Image.open(p("title", "title_logo.png")).convert("RGBA")
    crack = Image.open(p("title", "title_logo_crack.png")).convert("RGBA")
    # tint crack mask Core red
    r, g, b, a = crack.split()
    red = Image.new("RGBA", crack.size, (232, 40, 60, 255))
    red.putalpha(a)
    x, y = (sky.width - logo.width) // 2, 70
    sky.alpha_composite(logo, (x, y))
    sky.alpha_composite(red, (x, y))
    return sky


def uc_comp():
    base = Image.new("RGBA", (480, 270), (12, 20, 19, 255))
    far = Image.open(p("undercity", "uc_far.png")).convert("RGBA")
    base.alpha_composite(far, (0, 20))
    fog = Image.open(p("vfx", "atmos", "fog_band_a.png")).convert("RGBA")
    # tint fog to undercity fog colour
    fr, fg, fb, fa = fog.split()
    tint = Image.new("RGBA", fog.size, (43, 61, 56, 255))
    tint.putalpha(fa)
    for xx in range(0, 480, fog.width):
        base.alpha_composite(tint, (xx, 190))
    shaft = Image.open(p("vfx", "atmos", "light_shaft_b.png")).convert("RGBA")
    sr, sg, sb, sa = shaft.split()
    st = Image.new("RGBA", shaft.size, (158, 204, 184, 255))
    st.putalpha(sa.point(lambda v: v // 2))
    base.alpha_composite(st, (300, 0))
    rook = frames(p("rook", "rook_sheet.png"), p("rook", "rook_sheet.tres"), ["idle"])
    base.alpha_composite(rook, (120, 270 - 48 - 6))
    return base


SECTIONS = []


def sec(name, items):
    SECTIONS.append((name, items))


sec("Title + environment (AI: gpt-image-2, pixelized)", [
    ("title_sky + title_logo (code) + crack tint", title_comp()),
    ("uc_far + fog_band_a + light_shaft_b + Rook idle", uc_comp()),
])

C = [
    ("rook", "rook", "rook_sheet", ["idle", "run", "jump_rise", "dash", "slide", "blade_light_1", "blade_heavy", "katar_spin", "shoot_revolver", "heal", "death"]),
    ("needle", "enemies", "needle_sheet", ["idle", "move", "windup", "attack", "death"]),
    ("shield", "enemies", "shield_sheet", ["idle", "move", "attack", "guard_break", "death"]),
    ("enforcer", "enemies", "enforcer_sheet", ["idle", "move", "attack_baton", "attack_lunge", "death"]),
    ("hopper", "enemies", "hopper_sheet", ["idle", "move", "windup", "attack", "death"]),
    ("scout_drone", "enemies", "scout_drone_sheet", ["idle", "move", "windup", "death"]),
    ("signal_drone", "enemies", "signal_drone_sheet", ["idle", "move", "windup", "death"]),
    ("watcher", "enemies", "watcher_sheet", ["idle", "windup", "attack", "death"]),
    ("collector_eye", "undercity", "collector_eye_sheet", ["emerge", "track", "fire", "retract"]),
    ("warden_krail", "bosses", "warden_krail_sheet", ["idle", "move", "stagger", "phase2_roar", "death"]),
    ("collector_drone", "bosses", "collector_drone_sheet", ["idle", "windup_press", "sweep", "phase2", "death"]),
    ("sweeper_pursuer", "lowlight", "sweeper_sheet", ["parked", "warn", "chase", "derail"]),
    ("npc_orr", "npcs", "orr_sheet", ["idle", "talk", "tune_radio"]),
    ("npc_mara", "npcs", "mara_sheet", ["idle", "talk", "work"]),
    ("npc_nix", "npcs", "nix_sheet", ["idle", "talk", "draw"]),
    ("npc_vell", "npcs", "vell_sheet", ["idle", "talk", "shuffle"]),
    ("npc_iko", "npcs", "iko_sheet", ["idle", "talk", "lean"]),
]
sec("Characters (code pixel rigs, 0 credits): idle + key poses", [
    (f"{cid} ({', '.join(n)})" if cid == "rook" else cid, frames(p(sub, f + ".png"), p(sub, f + ".tres"), n)) for cid, sub, f, n in C
])

port = Image.new("RGBA", (48 * 7, 48), (0, 0, 0, 0))
for i, n in enumerate(["rook", "orr", "mara", "nix", "vell", "iko", "krail"]):
    port.paste(Image.open(p("portraits", f"portrait_{n}.png")).convert("RGBA").crop((0, 0, 48, 48)), (i * 48, 0))
sec("Portraits + weapons", [
    ("portraits: rook orr mara nix vell iko krail", port),
    ("weapons_atlas (sprites / icons / masks)", rows(p("rook", "weapons", "weapons_atlas.png"))),
])

sec("VFX (code; grey masks are tinted in engine)", [
    ("slash_smears (rows 1-3)", rows(p("vfx", "slash_smears.png"), 144)),
    ("hit_sparks", rows(p("vfx", "hit_sparks.png"))),
    ("death_burst", rows(p("vfx", "death_burst.png"))),
    ("death_burst_boss (first 8)", rows(p("vfx", "death_burst_boss.png"), maxw=768)),
    ("dust", rows(p("vfx", "dust.png"))),
    ("splash", rows(p("vfx", "splash.png"))),
    ("anchor_rest", rows(p("vfx", "anchor_rest.png"))),
    ("shockwave", rows(p("vfx", "shockwave.png"))),
    ("perfect_dodge", rows(p("vfx", "perfect_dodge.png"))),
    ("projectiles", rows(p("vfx", "projectiles.png"))),
    ("muzzle", rows(p("vfx", "muzzle.png"))),
    ("heal", rows(p("vfx", "heal.png"))),
    ("pulse_motes", rows(p("vfx", "pulse_motes.png"))),
    ("electric_arc", rows(p("vfx", "electric_arc.png"))),
    ("steam", rows(p("vfx", "steam.png"))),
    ("debris", rows(p("vfx", "debris.png"))),
    ("ambient_particles", rows(p("vfx", "ambient_particles.png"))),
    ("light_shaft_a", rows(p("vfx", "atmos", "light_shaft_a.png"))),
    ("lamp_glow 8/16/32/tube", None),
])
# lamp glows combined
g = [Image.open(p("vfx", "atmos", f"lamp_glow_{n}.png")).convert("RGBA") for n in ("8", "16", "32", "tube")]
gl = Image.new("RGBA", (sum(i.width for i in g) + 12, max(i.height for i in g)), (0, 0, 0, 0))
x = 0
for i in g:
    gl.alpha_composite(i, (x, 0)); x += i.width + 4
SECTIONS[-1][1][-1] = ("lamp_glow 8/16/32/tube", gl)

def pick():
    a = Image.open(p("props", "pickups.png")).convert("RGBA")
    a.alpha_composite(Image.open(p("props", "pickups_fill.png")).convert("RGBA"))
    return a


sec("UI kit, pickups, Null tiles (code)", [
    ("hud_kit", rows(p("ui", "hud_kit.png"))),
    ("hud_kit_fill (mask)", rows(p("ui", "hud_kit_fill.png"))),
    ("menu_kit", rows(p("ui", "menu_kit.png"))),
    ("dialogue_frame", rows(p("ui", "dialogue_frame.png"))),
    ("boss_bar", rows(p("ui", "boss_bar.png"))),
    ("icons", rows(p("ui", "icons.png"))),
    ("style_ranks", rows(p("ui", "style_ranks.png"))),
    ("pickups (frame + fill mask composited)", pick()),
    ("null_tiles", rows(p("null", "null_tiles.png"))),
])

PAD = 10
LABEL_H = 14


def layout():
    y = PAD
    placed = []
    for name, items in SECTIONS:
        placed.append(("H", name, (PAD, y)))
        y += 22
        x = PAD
        rowh = 0
        for label, im in items:
            w, h = im.width * S, im.height * S
            tw = max(w, len(label) * 6) + 8
            th = h + LABEL_H + 8
            if x + tw > W - PAD and x > PAD:
                x = PAD; y += rowh + PAD; rowh = 0
            placed.append(("T", (label, im), (x, y)))
            x += tw + PAD
            rowh = max(rowh, th)
        y += rowh + PAD * 2
    return placed, y


placed, H = layout()
sheet = Image.new("RGBA", (W, H), BG + (255,))
d = ImageDraw.Draw(sheet)
for kind, data, (x, y) in placed:
    if kind == "H":
        d.text((x, y + 4), data, fill=HEAD, font=FONT)
        d.line((x, y + 18, W - PAD, y + 18), fill=(60, 60, 75))
        continue
    label, im = data
    w, h = im.width * S, im.height * S
    tw = max(w, len(label) * 6) + 8
    d.rectangle((x, y, x + tw - 1, y + h + LABEL_H + 7), fill=TILE_BG)
    big = im.resize((w, h), Image.NEAREST)
    sheet.alpha_composite(big, (x + 4, y + 4))
    d.text((x + 4, y + h + 6), label, fill=FG, font=FONT)
os.makedirs(PREVIEW, exist_ok=True)
sheet.convert("RGB").save(os.path.join(PREVIEW, "contact_sheet.png"), optimize=True)
print("wrote", os.path.join(PREVIEW, "contact_sheet.png"), sheet.size)
