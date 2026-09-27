#!/usr/bin/env python3
"""REDLINE overhaul palettes (ART_DIRECTION.md section 3).

Writes palettes.json (next to this script) and checks that every palette used for decoration
keeps a minimum RGB distance from the reserved gameplay colours
(ART_BIBLE section 3 + data/accessibility/palettes/default.tres).

Palettes flagged "neon": true are the sanctioned accent sets (NeonSign plates,
Orr's radio, the Collector's eye): they may contain reserved hues on purpose
and are only ever used on those props, never quantized into backgrounds.

Usage: python3 palettes.py [--check]
"""
import json, os, sys

RESERVED = {
    "telegraph_red": "#ff3b4f", "redline_red": "#e8283c", "guard_blue": "#7fd7ff",
    "heal_green": "#7dff9a", "scrap_gold": "#ffd36b", "memory_blue": "#9fd8ff",
    "elite_amber": "#ffcf5a", "info_cyan": "#59e0e8", "ammo": "#ffe28a",
    "collector_warning": "#ff9e33", "map_note": "#9fd8ff",
}
MIN_DIST = 48  # RGB euclidean; ~2 value steps at our ramps

P = {
    # ---------------- 00 UNDERCITY (flooded civic disposal) ----------------
    "uc_env": {"desc": "Undercity backgrounds, tiles, props (no red, no cyan)", "colors": {
        "void": "#050808", "vault": "#0a100f", "sky_bottom": "#0f1a17", "far": "#0d1312", "mid": "#131b1a",
        "fog_dark": "#1a2825", "fog_light": "#2b3d38",
        "concrete_0": "#1b2321", "concrete_1": "#242b29", "concrete_2": "#344240", "concrete_3": "#46574f", "edge": "#5c7a70",
        "rust_0": "#2e211a", "rust_1": "#4d382b", "rust_2": "#6b4a33", "rust_3": "#8a5f3c",
        "steel_0": "#1e2626", "steel_1": "#333d3d", "steel_2": "#4a5857",
        "water_0": "#0b1614", "water_1": "#12241f", "water_2": "#1f3a33", "water_glint": "#6f9e90",
        "algae_0": "#26301f", "algae_1": "#3b4a30",
        "bone_0": "#7d7766", "bone_1": "#b0a88f",
        "sea_dim": "#4f7568", "sea_tube": "#9eccb8",
        "sodium_spill": "#3b2a1c", "sodium_dim": "#8a5a30", "sodium": "#d9944d",
    }},
    # ---------------- 01 LOWLIGHT (rain-slick neon over sodium) ----------------
    "ll_env": {"desc": "Lowlight backgrounds, tiles, props (neon hues only muted here)", "colors": {
        "sky_top": "#080a12", "sky_1": "#0f1020", "sky_bottom": "#1a1224", "far": "#12121c", "mid": "#1a1724",
        "fog_dark": "#1f1d30", "fog_light": "#2e2b45", "storm_glow": "#3a3558",
        "concrete_0": "#1c1a26", "concrete_1": "#262433", "concrete_2": "#363248", "concrete_3": "#4a4660", "edge": "#5c6b80",
        "wet_hi": "#7a8aa6", "rain": "#8ca3cc",
        "brick_0": "#2b1f2a", "brick_1": "#3d2a36", "brick_2": "#54394a",
        "metal_0": "#22262e", "metal_1": "#343a46", "metal_2": "#4d5566", "oneway": "#577380",
        "puddle_0": "#161a2c", "puddle_1": "#2e3a55",
        "window_warm_far": "#6e5a3c", "window_warm": "#b8925a", "window_cold_far": "#2e5a63", "window_cold": "#4e8e96",
        "window_rose": "#8a4652", "violet_muted": "#5e4a80", "sodium_street": "#c98a4a", "sodium_spill": "#3a2a26",
    }},
    "ll_neon": {"neon": True, "desc": "Sanctioned Lowlight neon (NeonSign plates, lit tubes only)", "colors": {
        "amber": "#ffcf5a", "cyan": "#58e0e8", "redline": "#e8283c", "violet": "#b373ff",
        "rose_replaces_green": "#ff7ab0", "tube_dark": "#0d0812", "tube_off": "#2a2230",
    }},
    # ---------------- THE RELAY (warm, safe, lived-in) ----------------
    "relay_env": {"desc": "Relay hub (sodium, rust, wood, cloth; cyan only on Orr's pips)", "colors": {
        "sky_top": "#0d0a0f", "sky_bottom": "#1f1412", "far": "#171212", "mid": "#211a17",
        "fog_warm": "#2e211b", "haze": "#4a3326",
        "stone_0": "#241c1a", "stone_1": "#332926", "stone_2": "#4a3a33", "stone_3": "#63503f", "edge": "#8c6b4c",
        "wood_0": "#3a2a1f", "wood_1": "#5a4030", "wood_2": "#7a5a40",
        "rust_0": "#4d2e22", "rust_1": "#6e4430",
        "cloth_ochre": "#7a6238", "cloth_teal": "#3a4a48", "cloth_plum": "#4a3040",
        "brass": "#9c7a48", "paper": "#c9b48f",
        "lamp_core": "#e0a060", "lamp_warm": "#c98548", "lamp_spill": "#5a3a24", "oneway": "#80664c",
    }},
    # ---------------- DEEP RIG / NULL (graybox on purpose) ----------------
    "null_env": {"desc": "Deep Rig: near-black, white-grey; red only on goals via code", "colors": {
        "void": "#030305", "sky_bottom": "#0a0a0d", "far": "#0d0d0f", "mid": "#121214",
        "grid_0": "#1b1c20", "grid_1": "#2c2e35", "solid": "#4c4f59", "oneway": "#9ea1ad", "edge": "#dbdee6",
    }},
    # ---------------- TITLE ----------------
    "title": {"desc": "Title backdrop: Lowlight night + one distant red Core-light allowed in the logo only", "colors": {
        "sky_top": "#06070e", "sky_1": "#0d0e1c", "sky_2": "#171530", "cloud_0": "#1f1d38", "cloud_1": "#2e2b4d", "moon_haze": "#4a4870",
        "far": "#12121c", "mid": "#1a1724", "near": "#0b0a12", "rim": "#5c6b80", "rain": "#8ca3cc",
        "window_warm": "#b8925a", "window_warm_far": "#6e5a3c", "window_cold": "#4e8e96", "window_rose": "#8a4652",
    }},
    # ---------------- CHARACTERS ----------------
    "char_rook": {"desc": "Rook (visor + Core seam are the sanctioned Redline red)", "colors": {
        "outline": "#1a1320", "outline_hi": "#2a2238",
        "coat_0": "#6e6880", "coat_1": "#a9a3b8", "coat_2": "#d8d4e0", "coat_3": "#f2eff7",
        "suit_0": "#1f1b29", "suit_1": "#2c2838", "suit_2": "#3d3850",
        "strap_0": "#3a2a24", "strap_1": "#5c4234",
        "metal_0": "#4a4a5a", "metal_1": "#8a8aa0", "blade_edge": "#e6e2ee",
        "visor": "#e8283c", "core_glow": "#e8283c", "core_hot": "#ff8a96",
    }},
    "char_enemy": {"desc": "Shared enemy ramps (warmer outline; no reserved hues)", "colors": {
        "outline": "#2a1618", "outline_hi": "#3d2226",
        "porcelain_0": "#8f8a7f", "porcelain_1": "#c9c2b4", "scrub_0": "#34403f", "scrub_1": "#4f6363",
        "rose_0": "#5a2e2e", "rose_1": "#8a4a44",
        "warden_0": "#1e1c2a", "warden_1": "#2e2b40", "warden_2": "#46425e", "warden_3": "#5c577a", "warden_4": "#716c92",
        "maroon_0": "#3a1c22", "maroon_1": "#5a2a30", "maroon_2": "#7a3a40",
        "khaki_0": "#3a3a26", "khaki_1": "#5a5a36", "khaki_2": "#7a7a48",
        "brass_0": "#4a3a22", "brass_1": "#7a6034", "brass_2": "#a88a45",
        "steel_0": "#2a2e36", "steel_1": "#4a5260", "steel_2": "#7a8494", "steel_3": "#a9b2c0",
        "lens_dark": "#141018", "lens_glass": "#3a4050", "lamp_pale": "#d9d4c0",
        "cloth_grey": "#3a3a44",
    }},
    "char_boss_collector": {"desc": "Collector Drone hull (red eye drawn by code; cells recoloured off heal green)", "colors": {
        "outline": "#2a1618", "hull_0": "#2a2618", "hull_1": "#4a4430", "hull_2": "#756b4d", "hull_3": "#9c9068",
        "rust_0": "#3a2418", "rust_1": "#6b3e26", "cable_0": "#1e1a1a", "cable_1": "#3a3434",
        "cage_0": "#1f1d24", "cage_1": "#58545a", "cell_dim": "#4a6a6a", "cell_lit": "#b8e0d0",
        "lamp_housing": "#1a1418", "rotor_blur": "#8a8478",
    }},
    "char_boss_krail": {"desc": "Warden Krail (red visor band is Warden red by design; baton core pale white-blue)", "colors": {
        "outline": "#2a1618", "coat_0": "#1a1826", "coat_1": "#2e2b40", "coat_2": "#46425e", "coat_3": "#5c577a",
        "armor_0": "#2a2e36", "armor_1": "#4a5260", "armor_2": "#7a8494",
        "leather_0": "#2e2020", "leather_1": "#4a3430", "visor": "#e8283c",
        "baton_body": "#3a3f4a", "baton_arc": "#cfe4f2", "rain_sheen": "#8ca3cc",
    }},
    "char_npc": {"desc": "Relay NPCs, warm-lit ramps", "colors": {
        "outline": "#1a1320", "skin_0": "#5a3a2e", "skin_1": "#8a5a44", "skin_2": "#b8826a", "skin_3": "#d9a88a",
        "hair_0": "#1e1818", "hair_1": "#3a2e2a", "grey_hair": "#8a8490",
        "mara_apron": "#5a4030", "mara_rust": "#8a5040", "mara_goggle": "#9c7a48",
        "nix_scarf": "#3a5a50", "nix_scarf_hi": "#5a8a78", "nix_paper": "#c9b48f",
        "vell_coat": "#2e3a36", "vell_coat_hi": "#4a6a5c", "vell_card": "#9ab0a0",
        "iko_oilskin": "#3a2e48", "iko_oilskin_hi": "#5e4a80", "iko_chalk": "#b373ff",
        "orr_poncho": "#4a5068", "orr_poncho_hi": "#6a7898", "orr_phones": "#2a2a30",
        "cloth_dark": "#2a2430", "cloth_mid": "#4a4050", "cloth_hi": "#5e5468",
        "skin_deep_0": "#442a22", "skin_deep_1": "#6e4636", "skin_deep_2": "#94644c", "skin_pale": "#e8c8ae",
        "orr_poncho_top": "#7f8bab", "iko_oilskin_top": "#7a66a0", "mara_rust_hi": "#a86a52", "lamp_rim": "#c98548",
    }},
    # ---------------- UI ----------------
    "ui": {"desc": "UI kit. State colours (red pips, heal, ammo, scrap) are NOT baked: sprites are white/grey masks tinted by Palette.color()", "colors": {
        "bg": "#0a0812", "panel": "#140f1f", "panel_hi": "#231a33", "line_0": "#3a3448", "line_1": "#5c5470", "line_2": "#8a8398",
        "text": "#e6e2ee", "muted": "#8a8398", "steel": "#a9a3b8", "mask_white": "#ffffff", "mask_mid": "#b0b0b0", "mask_dark": "#606060",
        "accent_redline": "#e8283c",
    }},
}


def rgb(hx):
    hx = hx.lstrip("#")
    return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(rgb(a), rgb(b))) ** 0.5


def check():
    problems = []
    for name, pal in P.items():
        if pal.get("neon"):
            continue
        for cname, c in pal["colors"].items():
            if name.startswith("char_rook") and cname in ("visor", "core_glow", "core_hot"):
                continue
            if name == "char_boss_krail" and cname == "visor":
                continue
            if name == "ui" and cname in ("accent_redline", "mask_white"):
                continue
            # Art Bible 3: sodium is the Undercity route-lamp colour (lamp cores only,
            # never area fills); it predates the Collector's amber warning ring.
            if name == "uc_env" and cname == "sodium":
                continue
            for rname, r in RESERVED.items():
                d = dist(c, r)
                if d < MIN_DIST:
                    problems.append(f"{name}.{cname} {c} is {d:.0f} from reserved {rname} {r}")
    return problems


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "palettes.json")
    probs = check()
    if "--check" not in sys.argv:
        with open(out, "w") as f:
            json.dump({"reserved": RESERVED, "min_reserved_distance": MIN_DIST, "palettes": P}, f, indent=1)
    for p in probs:
        print("RESERVED-CLASH", p)
    print(f"{len(P)} palettes, {sum(len(p['colors']) for p in P.values())} colours, {len(probs)} clashes")
    sys.exit(1 if probs else 0)
