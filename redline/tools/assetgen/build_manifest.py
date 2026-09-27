#!/usr/bin/env python3
"""Builds art_manifest.json (next to this script) (ART_DIRECTION.md is the prose companion).

Every asset: id, category, target_px, frames, palette_ref, generation_prompt,
post_process, owner, priority, plus planning fields: source (ai | ai_concept+rig
| ai_texture+script | code), est_generations, est_credits, cell/origin for
sheets, out (game-ready path under redline/assets/), used_by (code hook).

Credits: gpt-image-2 ~185/gen measured in the pilot; budgeted at 190.
Usage: python3 build_manifest.py [--check]   (prints the per-priority totals)
"""
import json, os, sys

CR = 190

# ---------------------------------------------------------------- preambles
ENV = ("Hand-crafted 2D pixel art for a side-scrolling metroidvania, strict side-on orthographic view "
       "with no perspective vanishing lines, crisp hard-edged pixel clusters, no anti-aliasing, no blur, "
       "no gradients banding, limited palette, depth from value and atmospheric haze only, melancholic hushed "
       "mood, damp air, original design. No text, no letters, no logos, no readable signage, no people, no "
       "creatures, no UI, no border, no watermark. World: Veyra, a vertical rain-soaked megacity of decaying "
       "brutalist civic infrastructure: stained concrete, riveted steel, rust, hanging cables, pipes, old transit lines.")
KEY = (" The entire background behind the shapes is one flat solid pure magenta (#FF00FF) with no gradient, "
       "no shadow, no texture and no magenta tint on the shapes; shapes have clean hard edges against it.")
TILE_X = " The composition must continue off both the left and right edges so it can tile horizontally; no framing objects at the edges."
CHAR = ("Pixel art character design sheet for a 2D side-scrolling action game, strict side view facing right, "
        "full body, crisp hard pixel clusters, a 1-pixel dark plum outline, no anti-aliasing, flat cel shading with "
        "a top-left key light, limited palette, poses evenly spaced in a grid with generous empty space between "
        "them, on one flat solid pure magenta (#FF00FF) background, no ground shadow, no text, no labels, no numbers, "
        "no UI. Original design that does not resemble any existing game character. Mood: melancholic, grimy, "
        "hand-crafted, readable silhouette at very small size.")
PROP = ("Pixel art prop sheet for a 2D side-scrolling metroidvania, strict side view, each object separate and "
        "evenly spaced in a grid with generous empty space, crisp hard pixel clusters, no outline on environment "
        "props, three value steps per material plus a thin top-edge highlight, top-left key light, limited palette, "
        "on one flat solid pure magenta (#FF00FF) background, no shadows on the background, no text, no letters, "
        "no logos, no people. Original design, grimy decaying civic infrastructure of a rain-soaked megacity.")
UI = ("Pixel art user-interface kit for a dark atmospheric 2D action game, crisp hard pixels, no anti-aliasing, "
      "ornamental but restrained industrial filigree: thin double steel lines, small riveted corner brackets, "
      "hairline cable flourishes, a tiny glowing seam motif. Elements drawn in white and light grey only (they are "
      "tinted in-engine), each element separate on one flat solid pure magenta (#FF00FF) background, no text, "
      "no letters, no numbers, no icons of real brands.")

# ---------------------------------------------------------------- post-process recipes
PP_SKY = "center-crop 16:9, box-downscale to 480x270, ordered-dither allowed (Bayer 4x4, sky only), quantize to palette ({p}) max 20 colours, clamp brightness so top 30% <= far layer value, no alpha"
PP_LAYER = "crop to band, box-downscale to {w} wide, chroma-key #FF00FF (tolerance 90, then despill fringe to nearest palette colour), hard alpha 0/255, remove islands < 4 px, quantize to palette ({p}) max {n} colours, make_tileable_x (32 px mirrored cross-fade at seam before quantize), value-compress so max value is >= 2 steps below the tileset edge colour"
PP_TILE = "centre 1024 crop, box-downscale to 128x128 material swatch, quantize to palette ({p}) 3 values + edge, then script-cut into a 16 px autotile sheet (top edge / face / fill x4 / underside / corners / one-way L-M-R) with the theme edge_color as a 1 px top highlight; seamless wrap check on fill tiles"
PP_PROP = "chroma-key #FF00FF, box-downscale each cell so the object matches target_px, hard alpha, quantize to palette ({p}), no outline, 1 px top-edge highlight from edge colour, origin bottom-centre, slice to individual PNGs + one atlas"
PP_CHAR = ("chroma-key #FF00FF, box-downscale each pose so body height = {h} px, hard alpha, quantize to palette ({p}) <= {n} colours, "
           "1 px outline pass (per-region darkest ramp colour, never pure black), stray-pixel removal; poses become the rig's key frames "
           "(tools/rig_*.py builds the full strip: layered parts + procedural secondary motion), cell {cell}, origin {origin}; "
           "ValidateContent sheet check")
PP_UI = "chroma-key #FF00FF, box-downscale to target, snap to 1 px lines, quantize to palette (ui) greyscale masks only (state colours are applied in-engine via Palette.color), 9-slice margins as noted"

items = []


def add(**kw):
    kw.setdefault("frames", {})
    kw.setdefault("source", "ai")
    kw.setdefault("est_generations", 1 if kw["source"] != "code" else 0)
    kw["est_credits"] = kw["est_generations"] * CR
    items.append(kw)


# =============================================================== TITLE
add(id="title_sky", category="title", target_px=[480, 270], palette_ref="title", owner="env", priority=1,
    generation_prompt=ENV + " Title screen sky only: a vast night sky over an unseen megacity, heavy low rain clouds lit "
    "from below by a faint cold city glow, one pale hazy break in the clouds upper right, slanted rain veils, deep indigo "
    "to violet-grey, very low contrast, no buildings, 16:9.",
    post_process=PP_SKY.format(p="title"), out="assets/title/title_sky.png", used_by="TitleBackdrop (new layered title scene)")
add(id="title_far_spires", category="title", target_px=[480, 200], palette_ref="title", owner="env", priority=1,
    generation_prompt=ENV + " Title far layer: the distant vertical megacity Veyra as a wall of impossibly tall stacked "
    "towers and spires connected by thin sky-bridges and cables, a few tiny muted warm and cold window lights, "
    "silhouettes in dark blue-violet fading into rain haze, one tall central spire slightly off-centre." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="title", n=12), out="assets/title/title_far.png")
add(id="title_mid_rooftops", category="title", target_px=[480, 180], palette_ref="title", owner="env", priority=1,
    generation_prompt=ENV + " Title middle layer: a ragged line of wet rooftops, water tanks, antenna masts, hanging "
    "cable arcs and a dead elevated rail line crossing the frame, dark slate violet with a thin cold rim light on top "
    "edges, sparse muted lit windows." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="title", n=14), out="assets/title/title_mid.png")
add(id="title_near_ledge", category="title", target_px=[480, 120], palette_ref="title", owner="env", priority=1,
    generation_prompt=ENV + " Title near layer: the foreground edge of a broken concrete rooftop ledge on the right third "
    "with a bent railing, a dead lamp post and drooping cables, near-black with a faint cold rim light, left two thirds "
    "empty magenta (the title menu sits there)." + KEY,
    post_process=PP_LAYER.format(w=480, p="title", n=10).replace("make_tileable_x (32 px mirrored cross-fade at seam before quantize), ", ""),
    out="assets/title/title_near.png", notes="Rook stands on this ledge as a code-rigged silhouette (rook sheet 'title_stand' pose), coat and scarf animated.")
add(id="title_logo", category="title", target_px=[208, 40], palette_ref="ui", owner="fx_ui", priority=1, est_generations=2,
    source="ai",
    generation_prompt=UI + " A single game title wordmark reading exactly 'REDLINE' in tall condensed industrial capital "
    "letters with sharp chiselled serifs, a thin horizontal crack running through all letters like a healed scar, "
    "pixel art, white on magenta, very wide aspect.",
    post_process="chroma-key, box-downscale to 208x40, threshold to 3 greys, hand/script cleanup of letterforms; the crack line becomes a separate 1 px mask tinted Redline red in code with a slow ember crawl; fallback: script-drawn pixel wordmark if letters garble",
    out="assets/ui/title_logo.png")

# =============================================================== UNDERCITY
add(id="uc_sky_vault", category="bg_layer", target_px=[480, 270], palette_ref="uc_env", owner="env", priority=1,
    generation_prompt=ENV + " Underground: the dark vaulted ceiling of a colossal flooded cistern seen from far below, "
    "ribbed concrete arches dissolving into black, faint sea-green haze and a few thin light shafts falling from "
    "broken grates far above, no floor visible, extremely dark and low contrast, 16:9.",
    post_process=PP_SKY.format(p="uc_env"), out="assets/undercity/uc_sky.png", used_by="DistrictBackdrop sky (Undercity, screen-fixed)")
add(id="uc_far_cistern", category="bg_layer", target_px=[480, 200], palette_ref="uc_env", owner="env", priority=1,
    generation_prompt=ENV + " Undercity far layer: distant rows of enormous cylindrical concrete columns and sluice gates "
    "of a flooded civic disposal complex, standing in still black water, silhouettes in dark sea-green grey fading into "
    "mist, a few tiny dim sea-green service tubes, very low contrast." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="uc_env", n=10), out="assets/undercity/uc_far.png")
add(id="uc_mid_pipeworks", category="bg_layer", target_px=[480, 220], palette_ref="uc_env", owner="env", priority=1,
    generation_prompt=ENV + " Undercity middle layer: rusted giant pipes, pump housings, catwalk railings and hanging "
    "chains over flood water, rust and wet concrete, sea-green fog between elements, one or two small dim sodium "
    "lamps, reflections on still water at the bottom edge." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="uc_env", n=16), out="assets/undercity/uc_mid.png")
add(id="uc_near_columns", category="bg_layer", target_px=[480, 270], palette_ref="uc_env", owner="env", priority=1,
    generation_prompt=ENV + " Undercity near background layer: a few massive stained concrete pillars and sagging cable "
    "bundles, hanging algae strands and drip stains, dark sea-green concrete with rust streaks, widely spaced with "
    "lots of empty magenta between them." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="uc_env", n=14), out="assets/undercity/uc_near.png")
add(id="uc_fg_silhouettes", category="bg_layer", target_px=[480, 270], palette_ref="uc_env", owner="env", priority=1,
    generation_prompt=ENV + " Foreground silhouette kit, near-black shapes only with a faint sea-green rim: hanging chains, "
    "broken pipe ends dangling from above, a sagging cable, rubble mounds and a rusted rail stub for the bottom edge, "
    "each shape separate." + KEY,
    post_process="chroma-key, box-downscale by the same factor as uc_near, hard alpha, 2-3 colours (near-black + rim), slice to separate FG sprites (top-hanging and bottom-rising); placed only above y-top 40 px or below the floor line, never over the player's collision band",
    out="assets/undercity/uc_fg_*.png")
add(id="uc_shaft_near", category="bg_layer", target_px=[480, 270], palette_ref="uc_env", owner="env", priority=2,
    generation_prompt=ENV + " Undercity vertical shaft background: a deep square maintenance shaft wall with ladder rungs, "
    "cable trays, pipe runs and a stopped lift counterweight rail, continuous from top edge to bottom edge so it tiles "
    "vertically, dark sea-green concrete, dim." + KEY,
    post_process=PP_LAYER.format(w=480, p="uc_env", n=14) + ", make_tileable_y too",
    out="assets/undercity/uc_shaft_near.png", used_by="Maintenance Shaft, Broken Lift (tall rooms: y-tiled near layer)")
add(id="uc_backwall_ward", category="bg_layer", target_px=[480, 270], palette_ref="uc_env", owner="env", priority=2,
    generation_prompt=ENV + " Undercity interior back wall at 0.9 depth: a derelict medical intake ward wall, tiled lower "
    "half with missing tiles, stained upper concrete, empty gurney bays, pipe runs, a boarded observation window, "
    "damp sea-green light, low contrast, continuous horizontally." + TILE_X,
    post_process=PP_LAYER.format(w=480, p="uc_env", n=14).replace("chroma-key #FF00FF (tolerance 90, then despill fringe to nearest palette colour), hard alpha 0/255, remove islands < 4 px, ", ""),
    out="assets/undercity/uc_backwall_ward.png", used_by="Wake, Medical Ruin")
add(id="uc_boss_bay", category="bg_layer", target_px=[480, 270], palette_ref="uc_env", owner="env", priority=2,
    generation_prompt=ENV + " Collector Bay backdrop: a cavernous sorting bay with a huge circular ceiling hatch far above "
    "(closed, dark), conveyor gantries, stacked cargo cages, a spotlight rig pointing down, all in dark sea-green and "
    "rust, no red anywhere, 16:9.",
    post_process=PP_SKY.format(p="uc_env"), out="assets/undercity/uc_boss_bay.png", used_by="Collector Bay (single-screen arena: full backdrop)")

# =============================================================== LOWLIGHT
add(id="ll_sky_night", category="bg_layer", target_px=[480, 270], palette_ref="ll_env", owner="env", priority=1,
    generation_prompt=ENV + " Lowlight night sky: low heavy rain clouds over a megacity, lit from below by a diffuse "
    "cold blue-violet city glow, distant searchlight haze, falling rain veils, no buildings, very low contrast, 16:9.",
    post_process=PP_SKY.format(p="ll_env"), out="assets/lowlight/ll_sky.png")
add(id="ll_sky_storm", category="bg_layer", target_px=[480, 270], palette_ref="ll_env", owner="env", priority=2,
    generation_prompt=ENV + " Storm sky for an elevated rail chase: torn racing clouds, heavier diagonal rain, a faint "
    "internal cloud glow suggesting distant lightning, cold violet-grey, 16:9, no buildings.",
    post_process=PP_SKY.format(p="ll_env"), out="assets/lowlight/ll_sky_storm.png", used_by="Rainline Chase, Neon Roofs; lightning = code flash layer, static tint under flash reduction")
add(id="ll_far_skyline", category="bg_layer", target_px=[480, 200], palette_ref="ll_env", owner="env", priority=1,
    generation_prompt=ENV + " Lowlight far layer: a dense distant skyline of tall residential slab towers and stacked "
    "housing blocks with a few spires, hazy blue-violet silhouettes in the rain, tiny muted warm and teal window dots, "
    "a distant elevated rail viaduct crossing low, very low contrast." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=10), out="assets/lowlight/ll_far.png")
add(id="ll_mid_blocks", category="bg_layer", target_px=[480, 220], palette_ref="ll_env", owner="env", priority=1,
    generation_prompt=ENV + " Lowlight middle layer: wet apartment block facades, fire escapes, laundry lines, AC units, "
    "water tanks and small unlit sign frames, slate and dark brick, cold rim light from the wet sky, sparse muted "
    "warm and teal windows, rain haze." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=16), out="assets/lowlight/ll_mid.png")
add(id="ll_near_street", category="bg_layer", target_px=[480, 270], palette_ref="ll_env", owner="env", priority=1,
    generation_prompt=ENV + " Lowlight near background layer at street level: shuttered shopfronts, a dead market stall "
    "frame, drainpipes, overhead cable bundles and a sodium street lamp, wet concrete, puddle reflections along the "
    "bottom, widely spaced elements with empty magenta between." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=16), out="assets/lowlight/ll_near_street.png", used_by="Flooded Alley, Market Run, Smuggler Route")
add(id="ll_mid_roofs", category="bg_layer", target_px=[480, 220], palette_ref="ll_env", owner="env", priority=1,
    generation_prompt=ENV + " Lowlight rooftop middle layer: a sea of wet flat rooftops, stairwell huts, satellite dishes, "
    "antenna forests, billboard backs (no text), water tanks and cable arcs between buildings, cold violet night." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=16), out="assets/lowlight/ll_mid_roofs.png", used_by="Neon Roofs, Rainline Chase, Security Station roof")
add(id="ll_fg_silhouettes", category="bg_layer", target_px=[480, 270], palette_ref="ll_env", owner="env", priority=1,
    generation_prompt=ENV + " Foreground silhouette kit, near-black shapes with a faint cold rim: hanging cable loops, a "
    "dangling unlit sign bracket, drainpipe, railing stubs, a traffic-light pole top, broken gutter, each shape separate." + KEY,
    post_process="as uc_fg_silhouettes (palette ll_env)", out="assets/lowlight/ll_fg_*.png")
add(id="ll_tower_near", category="bg_layer", target_px=[480, 270], palette_ref="ll_env", owner="env", priority=2,
    generation_prompt=ENV + " Lowlight vertical background: the inner lightwell of a tall apartment tower / bell tower, "
    "stacked balconies, stair landings, cables and bell rope pulleys, continuous top to bottom so it tiles vertically, "
    "wet slate and brick, dim." + KEY,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=14) + ", make_tileable_y too", out="assets/lowlight/ll_tower_near.png",
    used_by="Apartment Stack, Bell Tower, Power Block (tall rooms)")
add(id="ll_backwall_interior", category="bg_layer", target_px=[480, 270], palette_ref="ll_env", owner="env", priority=2,
    generation_prompt=ENV + " Lowlight interior back wall at 0.9 depth: a municipal substation / security station interior "
    "wall, cable trays, breaker cabinets, conduit, grimy tile, caged ceiling lights (unlit), continuous horizontally, "
    "low contrast slate violet." + TILE_X,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=14).replace("chroma-key #FF00FF (tolerance 90, then despill fringe to nearest palette colour), hard alpha 0/255, remove islands < 4 px, ", ""),
    out="assets/lowlight/ll_backwall_interior.png", used_by="Power Block, Security Station interiors")
add(id="ll_far_bell_tower", category="bg_layer", target_px=[480, 220], palette_ref="ll_env", owner="env", priority=2,
    generation_prompt=ENV + " Lowlight landmark far layer: the silhouette of a tall old bell tower with an industrial "
    "freight lift cage clinging to its side, rising above the rooftops, Warden banners hanging from it (blank, no "
    "symbols), rain haze, blue-violet." + KEY,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=10).replace("make_tileable_x (32 px mirrored cross-fade at seam before quantize), ", ""),
    out="assets/lowlight/ll_far_bell.png", used_by="Rainline Chase, Neon Roofs horizon (single landmark placed once at a fixed x)")
add(id="ll_canal_mid", category="bg_layer", target_px=[480, 220], palette_ref="ll_env", owner="env", priority=3,
    generation_prompt=ENV + " Smuggler canal middle layer: a flooded canal between leaning buildings, a rusted floodgate "
    "far off, moored flat boats, rope lines, dripping undersides of walkways, blue-violet with faint violet chalk marks "
    "(no symbols readable)." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="ll_env", n=14), out="assets/lowlight/ll_canal_mid.png", used_by="Smuggler Route")
add(id="ll_train_far", category="prop", target_px=[160, 24], palette_ref="ll_env", owner="env", priority=2,
    generation_prompt=PROP + " A long distant elevated commuter train silhouette of three cars with a row of small lit "
    "windows, seen from the side, very simple dark blue-violet shape.",
    post_process=PP_PROP.format(p="ll_env"), out="assets/lowlight/ll_train_far.png",
    notes="Ambient life: crosses the far layer every 40-70 s with a faint rumble; windows muted warm.")

# =============================================================== RELAY
add(id="relay_backwall", category="bg_layer", target_px=[480, 270], palette_ref="relay_env", owner="env", priority=1,
    generation_prompt=ENV + " The Relay: back wall of an abandoned underground transit interchange turned into a warm "
    "resistance settlement, tiled station arches, a dead departures board frame (blank), patched tarps, strings of "
    "small warm bulbs, rust and old wood, warm sodium haze, lived-in, continuous horizontally." + TILE_X,
    post_process=PP_LAYER.format(w=480, p="relay_env", n=18).replace("chroma-key #FF00FF (tolerance 90, then despill fringe to nearest palette colour), hard alpha 0/255, remove islands < 4 px, ", ""),
    out="assets/relay/relay_backwall.png", used_by="Relay (backwall layer 0.85)")
add(id="relay_mid_concourse", category="bg_layer", target_px=[480, 220], palette_ref="relay_env", owner="env", priority=1,
    generation_prompt=ENV + " The Relay middle layer: the far side of a transit concourse, stopped escalators, an "
    "upper gallery with railings, hanging cloth partitions, stacked salvage crates and a derelict train car used as "
    "housing, warm lamplight pools, rust and ochre." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="relay_env", n=16), out="assets/relay/relay_mid.png")
add(id="relay_fg", category="bg_layer", target_px=[480, 270], palette_ref="relay_env", owner="env", priority=2,
    generation_prompt=ENV + " Relay foreground silhouettes, near-black warm-brown shapes with a faint amber rim: hanging "
    "cloth strips, a string of bulbs dipping in, a pipe, a stack of crates at the bottom edge, each shape separate." + KEY,
    post_process="as uc_fg_silhouettes (palette relay_env)", out="assets/relay/relay_fg_*.png")

# =============================================================== DEEP RIG / PIT
add(id="null_far_strata", category="bg_layer", target_px=[480, 200], palette_ref="null_env", owner="env", priority=3,
    generation_prompt=ENV + " Abstract deep industrial shaft far layer: stacked black machine strata, gantries and "
    "vertical rails fading into darkness, near-black with thin grey-white edge lines, stark, minimal." + KEY + TILE_X,
    post_process=PP_LAYER.format(w=480, p="null_env", n=6), out="assets/null/null_far.png", used_by="Deep Rig (kept graybox-stark on purpose)")
add(id="pit_rig_near", category="bg_layer", target_px=[640, 270], palette_ref="ll_env", owner="env", priority=3,
    generation_prompt=ENV + " Training pit near layer: a sunken concrete test pit under a rain canopy, rig lamp towers "
    "(unlit housings), bleachers of stacked crates, chain-link, blue-violet." + KEY,
    post_process=PP_LAYER.format(w=640, p="ll_env", n=14).replace("make_tileable_x (32 px mirrored cross-fade at seam before quantize), ", ""),
    out="assets/challenge/pit_near.png", used_by="Pulse Pit (single 640x270 screen)")

# =============================================================== TILESETS
for tid, pal, pri, desc, used in [
    ("uc_tiles", "uc_env", 1, "cast concrete slabs with rust-streaked joints, algae in the cracks, a waterline stain band", "Undercity rooms (GrayboxBlock textured fill)"),
    ("ll_tiles", "ll_env", 1, "wet slate-violet concrete and dark brick, rain streaks, drain grates", "Lowlight rooms"),
    ("relay_tiles", "relay_env", 1, "warm old station floor tiles, worn stone, brass trims and wooden patch boards", "Relay"),
    ("ll_roof_tiles", "ll_env", 2, "tar-paper rooftop with gravel, metal flashing edges and puddles", "Neon Roofs, Rainline Chase, rooftop blocks"),
]:
    add(id=tid, category="tileset", target_px=[128, 96], palette_ref=pal, owner="env", priority=pri, source="ai_texture+script",
        frames={}, generation_prompt=ENV + f" A flat seamless material texture swatch, straight-on, filling the whole square: {desc}. "
        "Even lighting, no objects, no horizon, no vignette.",
        post_process=PP_TILE.format(p=pal), out="assets/%s/%s.png" % ({"uc": "undercity", "ll": "lowlight", "relay": "relay"}[tid.split("_")[0]], tid),
        used_by=used + "; GrayboxBlock draws the atlas when the room theme names one, else the flat placeholder")
add(id="null_tiles", category="tileset", target_px=[128, 96], palette_ref="null_env", owner="env", priority=3, source="code",
    generation_prompt="none (procedural: grey slab with 1 px white-grey edge and a faint 16 px grid scribe)",
    post_process="tools/tiles_null.py draws it", out="assets/null/null_tiles.png")

# =============================================================== PROPS
add(id="uc_props", category="prop", target_px=[32, 48], palette_ref="uc_env", owner="env", priority=1, est_generations=2,
    generation_prompt=PROP + " Undercity set: a square concrete pillar segment, a sodium lamp on a wall bracket, a sea-green "
    "service tube fixture (unlit housing), a rusted hospital gurney, a slab bench, stacked rusted crates, a pipe run "
    "segment with valve wheels, a hanging cable bundle, a wall grate, a drain outlet dripping, a disposal bin, a broken "
    "intake terminal. Dark sea-green concrete, rust and steel.",
    post_process=PP_PROP.format(p="uc_env"), out="assets/undercity/props/*.png",
    used_by="Decor kinds PILLAR/LAMP/CRATES/BENCH/PIPES/CABLES + NeonSign housings (Decor draws the sprite when present)")
add(id="uc_landmarks", category="prop", target_px=[128, 128], palette_ref="uc_env", owner="env", priority=2, est_generations=2,
    generation_prompt=PROP + " Undercity landmarks, larger objects: a giant pump wheel with spokes, a hanging freight lift "
    "car on cables, a derailed maintenance tram car tilted on its side, an extraction-pit machine with a claw crane over "
    "a pit rim, a large round ceiling hatch seen from below (closed).",
    post_process=PP_PROP.format(p="uc_env"), out="assets/undercity/landmarks/*.png",
    used_by="Maintenance Shaft pump wheel (turns, code), Broken Lift car (sways), Escape Tunnel tram, Medical Ruin pit, First Pursuit hatch (ring lit red only by code)")
add(id="ll_props", category="prop", target_px=[32, 48], palette_ref="ll_env", owner="env", priority=1, est_generations=2,
    generation_prompt=PROP + " Lowlight street set: a sodium street lamp post, a rooftop AC unit with fan, a planter box "
    "with scraggly weeds, a wet park bench, stacked cargo crates, a laundry line, an overhead cable span, a drainpipe with "
    "gutter, a fire escape segment, a newspaper box, a market stall awning frame, a water tank on stilts. Slate, dark "
    "brick, wet metal.",
    post_process=PP_PROP.format(p="ll_env"), out="assets/lowlight/props/*.png",
    used_by="Decor kinds LAMP/AC_UNIT/PLANTER/BENCH/CRATES/CABLES/BANNER")
add(id="ll_neon_plates", category="prop", target_px=[32, 12], palette_ref="ll_neon", owner="env", priority=1,
    generation_prompt=PROP + " Six empty neon sign frames of different shapes (long bar, square, vertical blade, arrow, "
    "circle, stacked two-line) with bent glass tubes forming abstract glyph-like strokes that are NOT letters, tubes "
    "drawn in pure white on dark metal backing plates.",
    post_process="chroma-key, downscale, tubes -> white mask layer, backing -> ll_env metal; NeonSign tints the tube mask with its colour and keeps flicker/broken logic; glow halo drawn by code (8 px quantized falloff)",
    out="assets/lowlight/neon/*.png", used_by="NeonSign (all districts; Undercity SEA tubes use the bar plate)")
add(id="ll_landmarks", category="prop", target_px=[128, 128], palette_ref="ll_env", owner="env", priority=2, est_generations=2,
    generation_prompt=PROP + " Lowlight landmarks: a large transformer core with coils and insulators, a security monitor "
    "wall of blank CRT screens in a steel frame, a canal floodgate with a wheel mechanism, a heavy bronze bell in a "
    "steel yoke, a derelict elevated-rail car.",
    post_process=PP_PROP.format(p="ll_env"), out="assets/lowlight/landmarks/*.png",
    used_by="Power Block Transformer Core (arcs by code: red->cyan per flag), Security Station Monitor Wall (screens flicker by code), Smuggler floodgate, Bell Tower bell, Rainline car")
add(id="relay_props", category="prop", target_px=[48, 48], palette_ref="relay_env", owner="env", priority=1, est_generations=2,
    generation_prompt=PROP + " The Relay hub set, warm and lived-in: a mechanic's workbench with vice and tools, a radio "
    "operator desk with a big valve radio and a small on-air lamp housing, a map table with pinned papers, a market "
    "stall with a patched awning, a circuit-broker's display case of small cards, stacked crates with rope, a bunk "
    "curtain, a bench made of a train seat, hanging bulb strings, a brazier drum.",
    post_process=PP_PROP.format(p="relay_env"), out="assets/relay/props/*.png",
    used_by="Decor WORKBENCH/RADIO/TRAIN_CAR/BENCH; WorldStateSwitch props (IkoStall, MaraBench, NixTowerSheet, OrrOnAir lamp)")
add(id="interact_anchor", category="prop", target_px=[32, 48], palette_ref="uc_env", owner="env", priority=1,
    frames={"idle": 8, "rest": 10, "active": 8},
    generation_prompt=PROP + " An 'Anchor' rest shrine: a squat reinforced conduit pylon with a cradle socket in its chest "
    "where a small core would sit, cables flowing into the floor like roots, a worn step to kneel on; three variants: "
    "dormant, awakening, active (socket drawn empty, the glow is added in-engine).",
    post_process=PP_PROP.format(p="uc_env") + "; socket glow = code-driven red mask (Anchor.CORE_COLOR), 8-frame breathe loop at 8 fps; neutral palette so it sits in every district",
    out="assets/props/anchor.png", used_by="world/anchors/Anchor.gd")
add(id="interact_grid", category="prop", target_px=[32, 64], palette_ref="ll_env", owner="env", priority=1,
    frames={"breaker_idle": 4, "breaker_hit": 5, "shutter_panel": 1, "gate": 1},
    generation_prompt=PROP + " Grid machinery: a wall-mounted industrial circuit breaker box with a big lever (off and on "
    "positions), a heavy segmented steel roller shutter panel with warning chevrons (grey, no colour), a sliding "
    "blast gate door, a clamp press head with pistons.",
    post_process=PP_PROP.format(p="ll_env") + "; state lights on breakers are code masks tinted from Palette (warning/danger), never baked",
    out="assets/props/grid/*.png", used_by="Breaker, PowerShutter, Gate, GridClamp")
add(id="interact_pickups", category="prop", target_px=[16, 16], palette_ref="ui", owner="fx_ui", priority=1, source="code",
    frames={"scrap_spin": 6, "scrap_cache": 1, "memory_shard": 8, "core_shard": 8},
    generation_prompt="none (code-drawn 8-16 px pixel sprites: Scrap = gold #ffd36b nugget tinted by Palette currency; memory = pale-blue shard tinted memory; cache = crate with gold latch)",
    post_process="tools/pickups.py draws masks; tints at runtime", out="assets/props/pickups.png",
    used_by="ScrapPickup, ScrapCache, Collectible")
add(id="interact_misc", category="prop", target_px=[32, 48], palette_ref="ll_env", owner="env", priority=2, est_generations=2,
    generation_prompt=PROP + " Misc interactables: a wall weapon rack with an empty blade cradle, a small device pedestal "
    "(for an ability module), a rooftop signal repeater antenna box, a challenge terminal kiosk with a blank screen, a "
    "cracked breakable concrete wall section in three damage stages, a floor spike strip, a ceiling scanner emitter head.",
    post_process=PP_PROP.format(p="ll_env") + "; scanner beam and spike danger tint stay code-drawn Palette colours",
    out="assets/props/misc/*.png", used_by="WeaponPickup/PulseBladeRack, AbilityPickup/DashModule, SignalRepeater, ChallengeTerminal, BreakableWall, SpikeHazard, ScannerBeam")
add(id="collector_eye", category="prop", target_px=[32, 32], palette_ref="char_boss_collector", owner="char", priority=1,
    source="ai_concept+rig", cell=[32, 32], origin=[16, 4],
    frames={"dormant": 1, "emerge": 6, "track": 4, "lock": 2, "fire": 3, "retract": 6, "gone": 1},
    generation_prompt=CHAR + " A ceiling-rail surveillance eye pod: a brass-olive armoured housing hanging from a rail "
    "trolley, a round iris shutter lens (lens dark, no colour), cables trailing; poses: retracted, half emerged, fully "
    "emerged looking down-left, down, down-right.",
    post_process=PP_CHAR.format(h=20, p="char_boss_collector", n=16, cell="32x32", origin="(16,4) rail point"),
    out="assets/undercity/collector_eye.png", used_by="CeilingTracker (cone + red lens stay code-drawn)")
add(id="sweeper_pursuer", category="prop", target_px=[64, 146], palette_ref="ll_env", owner="char", priority=2,
    source="ai_concept+rig", cell=[80, 160], origin=[40, 158],
    frames={"parked": 1, "warn": 4, "chase": 6, "regroup": 3, "derail": 8},
    generation_prompt=CHAR.replace("character", "machine") + " The Sweeper: a tall rail-hung track-cleaning machine "
    "hanging from an overhead rail, a slab body with rotating brush drums and scraper blades at the bottom, hazard "
    "lamp housings (unlit), grime and rain streaks; poses: idle, leaning into motion, tipped off the rail.",
    post_process=PP_CHAR.format(h=146, p="ll_env", n=20, cell="80x160", origin="(40,158)") + "; headlight cone + lamps stay code (Palette chase_*)",
    out="assets/lowlight/sweeper.png", used_by="world/hazards/Pursuer.gd")

# =============================================================== AMBIENT LIFE (code-first, tiny)
add(id="life_critters", category="prop", target_px=[16, 16], palette_ref="char_enemy", owner="env", priority=2,
    source="ai_concept+rig", cell=[16, 16], origin=[8, 15],
    frames={"moth_flutter": 4, "rat_idle": 2, "rat_run": 4, "gull_idle": 2, "gull_peck": 4, "gull_fly": 4, "eel_ripple": 4},
    generation_prompt=CHAR.replace("character design sheet", "tiny creature sheet") + " Tiny ambient creatures, each "
    "about 6 to 12 pixels: a pale moth (wings open and closed), a grey sewer rat (standing, running), a scruffy city "
    "gull (standing, pecking, wings up, wings down), a thin dark eel ripple in water.",
    post_process=PP_CHAR.format(h=8, p="char_enemy", n=10, cell="16x16", origin="(8,15)") + "; if downscale is unreadable, hand-pixel from the concept (they are 4-12 px)",
    out="assets/life/critters.png", used_by="AmbientLife spawner (new, visual-only, no collision): moths at lamps, rats on floors, gulls on roofs (scatter when Rook runs near)")

# =============================================================== CHARACTERS
add(id="rook", category="character", target_px=[40, 44], palette_ref="char_rook", owner="char", priority=1,
    source="ai_concept+rig", est_generations=4, cell=[48, 48], origin=[24, 46],
    frames={"idle": 8, "idle_fidget": 12, "run": 8, "turn": 3, "jump_rise": 2, "air": 2, "jump_fall": 2, "land": 3,
            "land_hard": 5, "crouch": 2, "slide": 3, "dodge": 5, "dash": 4, "blade_light_1": 5, "blade_light_2": 5,
            "blade_light_3": 6, "blade_heavy": 8, "blade_launcher": 6, "blade_air_light": 5, "blade_air_heavy": 6,
            "katar_light_1": 4, "katar_light_2": 4, "katar_light_3": 4, "katar_light_4": 4, "katar_cross": 6,
            "katar_rising": 6, "katar_spin": 8, "katar_dive": 6, "shoot_pistol": 3, "shoot_scatter": 4,
            "shoot_revolver": 5, "hurt": 3, "heal": 10, "death": 12, "interact": 4, "rest": 6, "title_stand": 8},
    fps={"idle": 8, "idle_fidget": 12, "run": 14, "turn": 16, "land": 16, "land_hard": 14, "dodge": 20, "dash": 24,
         "blade_*": 18, "blade_heavy": 16, "katar_*": 20, "shoot_*": 18, "hurt": 14, "heal": 12, "death": 12, "rest": 8, "title_stand": 8},
    generation_prompt=CHAR + " The protagonist Rook, a lean wiry survivor about 7 heads tall: a close-fitting charcoal "
    "undersuit with worn straps, a long pale bone-white field coat with a torn asymmetric tail that flows behind, a "
    "short ragged scarf-collar, a smooth featureless dark helmet-mask with a single narrow horizontal red visor slit, "
    "a small red glowing seam scar on the chest where an implanted core shows through, a short single-edged blade held "
    "low. No horns, no cape hood, no big head. Poses: idle, run contact, run passing, jump rise, fall, landing crouch, "
    "slide, dash lean, slash wind-up, slash follow-through, heavy overhead, hurt recoil.",
    post_process=PP_CHAR.format(h=42, p="char_rook", n=20, cell="48x48", origin="(24,46)") + "; gen 1-2 = turnaround + key poses, gen 3-4 = rerolls/weapon poses; rig parts: head, visor(mask), torso+Core seam, coat tail (3-segment verlet, 1 px), scarf (2-segment), upper/lower arms, legs, blade; smears are separate vfx_slash_smears",
    out="assets/rook/rook.png + rook.tres (SpriteSheetSpec)", used_by="PlayerPlaceholderVisual.sprite (swap-in, no code change for state anims; turn/land/land_hard/idle_fidget need small hooks)")
add(id="rook_weapons", category="character", target_px=[24, 12], palette_ref="char_rook", owner="char", priority=2,
    source="ai_concept+rig", frames={"pulse_blade": 1, "split_katars": 1, "service_pistol": 1, "scattergun": 1, "heavy_revolver": 1},
    generation_prompt=PROP + " Five weapons for a pixel-art hero, side view, each separate: a short single-edged pulse "
    "blade with a hollow channel down the blade, a pair of split punch-katars, a compact service pistol, a sawn-off "
    "scattergun, a heavy long-barrel revolver. Steel and dark grip wrap, pale edge highlights.",
    post_process=PP_PROP.format(p="char_rook") + "; weapons are separate rig layers so one Rook sheet serves every loadout; also used as 16x16 UI icons",
    out="assets/rook/weapons/*.png")

ENEMIES = [
    ("needle", 1, [40, 40], [20, 38], 30, {"idle": 6, "move": 8, "windup": 4, "attack": 4, "hurt": 3, "death": 8, "dormant": 2},
     "The Needle: a decommissioned medical orderly automaton, thin and hunched, cracked porcelain faceplate with one "
     "dark slit, stained grey-teal scrub tabard, one forearm ending in a long syringe lance, backward-bent legs. Poses: "
     "idle hunch, walk, lance drawn back (wind-up), lunge stab, recoil, collapsing, slumped dormant."),
    ("shield", 1, [48, 48], [24, 46], 34, {"idle": 6, "move": 8, "windup": 4, "attack": 4, "hurt": 3, "guard_break": 5, "death": 8},
     "The Shield: a squat Warden riot trooper in slate-violet padded armour, a full-height rectangular riot slab shield "
     "(plain steel, no colour) held forward, a domed helmet with a dark faceplate. Poses: guard stance, shuffling "
     "advance, shield pulled back (wind-up), shield bash, staggered with shield knocked aside, falling."),
    ("hopper", 1, [32, 32], [16, 30], 20, {"idle": 4, "move": 6, "windup": 4, "attack": 3, "hurt": 2, "death": 6},
     "The Hopper: a small feral scavenger machine like a rusty mechanical frog-louse, khaki-olive plated shell, two "
     "big coiled spring legs, a single pale lamp eye, antenna whisker. Poses: crouched idle, hop up, deep compressed "
     "crouch (wind-up), mid-pounce stretched, flipped over."),
    ("scout_drone", 1, [32, 32], [16, 26], 18, {"idle": 4, "move": 4, "windup": 4, "attack": 3, "hurt": 2, "death": 6},
     "The Scout Drone: a small dented surveillance drone, dull brass hull the size of a lantern, one big lens eye (dark "
     "glass), a single top rotor, dangling antenna and a hooked tail sensor. Poses: hover, tilt forward, lens iris "
     "tightening (wind-up), recoil after firing, spinning and falling."),
    ("watcher", 1, [24, 24], [12, 22], 16, {"idle": 4, "windup": 4, "attack": 3, "hurt": 2, "death": 5},
     "The Watcher: a wall-mounted sentry lamp, an old municipal camera housing on a bracket with an iris shutter "
     "(lens dark), cable conduit, rust. Poses: shutters closed, open, open wide (wind-up), recoil, broken hanging."),
    ("enforcer", 1, [48, 48], [24, 46], 36, {"idle": 6, "move": 8, "windup_baton": 4, "attack_baton": 5, "windup_lunge": 3, "attack_lunge": 4, "hurt": 3, "death": 10},
     "The Enforcer: a tall elite Warden officer in a long dark maroon rain coat with a slate armoured collar, a peaked "
     "helmet with a dark visor band, a heavy shock baton (steel, no glow). Poses: idle, stride, baton raised, baton "
     "swing, low lunge wind-up, lunge thrust, recoil, falling to knees."),
    ("signal_drone", 3, [32, 32], [16, 26], 18, {"idle": 4, "move": 4, "windup": 4, "attack": 3, "hurt": 2, "death": 6},
     "The Signal Drone: a slender relay drone with a dish antenna and trailing cable, teal-grey hull, one lens. Poses: "
     "hover, tilt, charging, recoil, falling."),
]
for eid, pri, cell, origin, h, frames, desc in ENEMIES:
    add(id=eid, category="enemy", target_px=[cell[0] - 8, h], palette_ref="char_enemy", owner="char", priority=pri,
        source="ai_concept+rig", est_generations=2, cell=cell, origin=origin, frames=frames,
        generation_prompt=CHAR + " " + desc,
        post_process=PP_CHAR.format(h=h, p="char_enemy", n=16, cell="x".join(map(str, cell)), origin=str(tuple(origin))) +
        "; windup's last frame is held for the whole telegraph (>= 0.3 s); telegraph '!' and hitbox outline stay code; hurt flash via self_modulate",
        out=f"assets/enemies/{eid}.png + {eid}.tres", used_by=f"EnemyData.sprite in data/enemies/{eid}*.tres (remix/null variants: palette swap in code)")

add(id="collector_drone", category="boss", target_px=[72, 56], palette_ref="char_boss_collector", owner="char", priority=1,
    source="ai_concept+rig", est_generations=3, cell=[96, 96], origin=[48, 64],
    frames={"idle": 6, "move": 6, "windup_press": 4, "press": 4, "windup_volley": 4, "volley": 3, "windup_dive": 4, "dive": 3,
            "windup_sweep": 4, "sweep": 6, "hurt": 3, "phase2": 10, "rotors_cut": 4, "death": 14},
    generation_prompt=CHAR + " The Collector Drone, a hulking municipal corpse-collection drone: a heavy dented brass-"
    "olive hull like a hearse crossed with a garbage hopper, four stubby rotors on outriggers, a single large lamp-eye "
    "housing at the front (lens dark, no colour), two folded grabber claws underneath, a hook on a chain, a flat press "
    "plate on its belly, a hanging cargo cage holding three glass salvage cells. Poses: hovering idle, claws open "
    "diving, press plate slammed down, hook swinging, damaged with two rotors torn off, breaking apart.",
    post_process=PP_CHAR.format(h=48, p="char_boss_collector", n=24, cell="96x96", origin="(48,64) body bottom; cage hangs below") +
    "; the eye lamp, cone and cell glow stay code-drawn (Palette danger/collector_warning); cells recoloured away from heal green",
    out="assets/bosses/collector_drone.png + .tres", used_by="data/enemies/collector_drone.tres sprite; CollectorDroneBehavior should request family-specific anim names (small hook)")
add(id="warden_krail", category="boss", target_px=[56, 56], palette_ref="char_boss_krail", owner="char", priority=1,
    source="ai_concept+rig", est_generations=3, cell=[96, 80], origin=[48, 78],
    frames={"idle": 8, "move": 8, "windup_baton": 4, "baton_1": 5, "baton_2": 5, "windup_lunge": 3, "lunge": 4,
            "windup_burst": 4, "burst": 4, "windup_slam": 5, "slam": 6, "backstep": 4, "hurt": 3, "stagger": 6,
            "phase2_roar": 10, "death": 16},
    generation_prompt=CHAR + " Warden Krail, a towering district warden: a long heavy slate-violet rain greatcoat "
    "with a split tail, one massive riveted pauldron, a tall cylindrical helm with a single narrow red visor band, a "
    "gorget, heavy boots, and a long shock baton (dark steel shaft, pale tip). Imposing, stiff, disciplined. Poses: "
    "idle at attention, stride, baton raised overhead, horizontal baton sweep, crouched lunge wind-up, lunge thrust, "
    "both arms raised to slam the ground, kneeling staggered, head thrown back roaring, collapsing.",
    post_process=PP_CHAR.format(h=54, p="char_boss_krail", n=24, cell="96x80", origin="(48,78)") +
    "; baton crackle + phase-2 arc stay code (crackle_lit 2.5 Hz rule); WardenKrailNull = palette swap to null_env greys",
    out="assets/bosses/warden_krail.png + .tres", used_by="data/enemies/warden_krail*.tres sprite")

NPCS = [
    ("npc_orr", 1, {"idle": 8, "talk": 4, "tune_radio": 6},
     "Orr, an older radio operator: hunched, grey stubble, big padded headphones around the neck, a blanket poncho over "
     "a patched jumpsuit, fingerless gloves, sitting-height stool pose and standing pose, one pose turning a radio dial."),
    ("npc_mara", 1, {"idle": 8, "talk": 4, "work": 8},
     "Mara, a stocky mechanic woman in her forties: rolled sleeves, heavy scorched leather apron, welding goggles pushed "
     "up on short cropped hair, a wrench in a belt loop; poses: standing arms crossed, gesturing while talking, "
     "hammering at a bench."),
    ("npc_nix", 2, {"idle": 8, "talk": 4, "draw": 6},
     "Nix, a lanky cartographer: long layered coat pinned with scraps of hand-drawn maps, a long scarf, a brass lens "
     "monocle on a cord, pencil behind ear; poses: standing, talking with a rolled map, sketching on a board."),
    ("npc_vell", 2, {"idle": 8, "talk": 4, "shuffle": 6},
     "Vell, a thin sly circuit broker: long dark green-grey coat lined inside with rows of small circuit cards, narrow "
     "face, slicked hair, long fingers; poses: standing with coat held open, talking, shuffling cards between hands."),
    ("npc_iko", 2, {"idle": 8, "talk": 4, "lean": 6},
     "Iko, a young canal smuggler: hooded oilskin cape in dark violet, a chalk eye symbol on the hood, rope coil over "
     "shoulder, boots, crates nearby; poses: leaning on a crate, talking with a shrug, glancing over shoulder."),
]
for nid, pri, frames, desc in NPCS:
    add(id=nid, category="npc", target_px=[32, 36], palette_ref="char_npc", owner="char", priority=pri,
        source="ai_concept+rig", est_generations=2, cell=[48, 48], origin=[24, 46], frames=frames,
        generation_prompt=CHAR + " A non-hostile hub character for a warm lamp-lit underground settlement. " + desc,
        post_process=PP_CHAR.format(h=36, p="char_npc", n=16, cell="48x48", origin="(24,46)") + "; idle includes a 2-frame blink and a slow breath",
        out=f"assets/npcs/{nid[4:]}.png + .tres", used_by="NPC.gd (figure=true) draws the sheet when the profile has one; pending tick stays code")

# =============================================================== PORTRAITS
add(id="portraits", category="portrait", target_px=[48, 48], palette_ref="char_npc", owner="char", priority=3, est_generations=2,
    frames={"rook": 1, "orr": 2, "mara": 2, "nix": 2, "vell": 2, "iko": 2, "krail": 1},
    generation_prompt=CHAR.replace("full body", "head-and-shoulders bust portraits") + " Bust portraits in a row, 3/4 "
    "view facing right: Rook (dark helmet-mask with red visor slit, bone-white coat collar), Orr (headphones, poncho), "
    "Mara (goggles on forehead), Nix (monocle, scarf), Vell (slicked hair, card-lined collar), Iko (violet hood), "
    "Warden Krail (cylindrical helm, red visor band).",
    post_process=PP_CHAR.format(h=48, p="char_npc", n=24, cell="48x48", origin="(24,47)") + "; second frame per NPC = talk/blink variant hand-edited",
    out="assets/portraits/*.png", used_by="Dialogue box (optional portrait slot, new)")

# =============================================================== VFX (code-first)
VFX = [
    ("vfx_slash_smears", 1, {"light": 3, "heavy": 4, "launcher": 3, "air": 3, "spike": 3, "katar": 2, "katar_spin": 4},
     "Crescent smear sprites generated per attack from AttackData hitbox (<= 2 px beyond hitbox, Art Bible 6); 3-tone white/pale-steel, tail dissolves in dither; replaces SlashArc drawing when present"),
    ("vfx_hit_sparks", 1, {"spark_small": 4, "spark_heavy": 5, "spark_guard": 4, "spark_crit": 5},
     "Directional star-burst + 1-2 px shards along hit.direction; guard spark uses Palette guard blue; white core suppressed under flash reduction (HitSpark rules)"),
    ("vfx_dust", 1, {"land": 5, "land_hard": 6, "run_puff": 4, "slide": 4, "dash_trail": 4, "wall_scrape": 4},
     "Pixel puff sprites in district dust colour (uc concrete_3 / ll concrete_3 / relay stone_3); water districts swap to splash"),
    ("vfx_splash", 1, {"step": 4, "land": 6, "drip": 4, "rain_hit": 3, "ripple": 6},
     "Water splash/ripple for flooded floors and puddles, rain impact ticks on top edges"),
    ("vfx_pulse_motes", 1, {"mote": 4, "absorb_stream": 1},
     "Pulse residue: 1-2 px pale motes drift from kills/destroyed props and stream into Rook's chest seam (homing, 0.4 s); pale white-violet body, the last pixel before absorption flicks Core red"),
    ("vfx_death_burst", 1, {"small": 8, "large": 10, "boss": 16},
     "Enemy death: body flashes to silhouette, splits into 2-3 chunks + motes + a shock ring; boss version adds a held white-free freeze frame and debris rain"),
    ("vfx_projectiles", 1, {"pistol_bolt": 2, "pellet": 1, "revolver_round": 2, "enemy_bolt": 3, "collector_tag": 3, "ground_wave": 4},
     "Projectile sprites; enemy shots use Palette danger via mask tint (colour-blind safe)"),
    ("vfx_muzzle", 1, {"pistol": 2, "scatter": 3, "revolver": 3}, "Muzzle flashes 2-3 frames, white core suppressed under flash reduction"),
    ("vfx_shockwave", 2, {"ring": 6, "ground_wave": 6}, "Expanding 1 px rings / ground shock (Krail slam, Collector press wave)"),
    ("vfx_heal", 1, {"heal_rise": 8}, "Heal: rising pixel crosses and a ring in Palette heal (mask tint)"),
    ("vfx_anchor_rest", 1, {"bloom": 10, "embers": 6}, "Anchor rest: roots light up floor-to-socket, embers rise, gentle quantized radial glow"),
    ("vfx_perfect_dodge", 2, {"flourish": 6, "afterimage": 1},
     "Perfect dodge / parry flourish: a sharp 4-point glint + afterimage silhouette (Rook sheet frame recoloured coat_1 at 40 %); needs a combat event hook"),
    ("vfx_electric_arc", 2, {"arc": 4}, "Procedural jagged polyline arcs (Krail baton, Transformer Core, broken tubes); obeys 3 Hz flash rule"),
    ("vfx_steam", 2, {"puff": 6}, "Steam vents: slow rising quantized puffs"),
    ("vfx_debris", 2, {"concrete": 4, "glass": 4, "sparks_fall": 4}, "BreakableWall chunks, glass shards, falling sparks"),
    ("vfx_light_shafts", 1, {}, "God-ray quads: quantized 3-step alpha trapezoids with slow dust motes inside; per-room placement data; not Light2D (no dynamic-light budget used)"),
    ("vfx_fog", 1, {}, "Tileable fog band textures 256x64 (4 alpha steps, quantized noise) scrolling 3-8 px/s at two depths"),
    ("vfx_lamp_glow", 1, {}, "Additive halo sprites (8/16/32 px, 3 quantized steps) for lamps and neon; bloom-free readability"),
    ("vfx_grade_vignette", 1, {}, "Per-district backdrop grade (CanvasModulate on background layers only, never on the gameplay layer) + 1 soft vignette texture; reserved colours stay exact"),
    ("vfx_ambient_particles", 1, {"mote": 2, "spore": 3, "ash": 2, "drip": 4},
     "Drifting motes/spores/ash per district (Undercity drips + spores, Lowlight rain + ash, Relay dust in lamp light); pooled CPUParticles2D; density follows the proposed ambient-motion setting"),
]
for vid, pri, frames, desc in VFX:
    add(id=vid, category="vfx", target_px=[32, 32], palette_ref="ui", owner="fx_ui", priority=pri, source="code",
        frames=frames, generation_prompt="none (procedural, tools/vfx_*.py or runtime code): " + desc,
        post_process="authored by script on the 1 px grid; masks tinted at runtime from Palette where a gameplay colour is meant",
        out=f"assets/vfx/{vid[4:]}.png")
add(id="vfx_style_board", category="vfx", target_px=[480, 270], palette_ref="ui", owner="fx_ui", priority=2,
    generation_prompt=ENV.replace("No text, no letters, no logos, no readable signage, no people, no creatures, ", "No text, ") +
    " A pixel-art VFX reference board on a dark background: crescent sword slash smears, star-burst impact sparks, dust "
    "puffs, water splashes, electric arcs, tiny drifting glowing motes streaming toward a point, shock rings, arranged "
    "in a grid, white and pale steel only.",
    post_process="reference only (not shipped): pick shapes for the vfx_* scripts", out="art/source/vfx_board.png")

# =============================================================== UI
add(id="ui_hud_kit", category="ui", target_px=[160, 48], palette_ref="ui", owner="fx_ui", priority=1, est_generations=2,
    frames={"pip_full": 1, "pip_empty": 1, "pip_break": 5, "pip_refill": 4, "injector_full": 1, "injector_empty": 1, "core_frame": 1, "core_fill_flow": 6, "ammo_tick": 2},
    generation_prompt=UI + " HUD pieces: a row of small vertical ampoule-shaped health cells with steel caps (one full, "
    "one empty, one cracking), small syringe-injector icons, a long thin ornate meter frame with riveted end caps and "
    "a tiny core socket at its left end, small ammo tick marks.",
    post_process=PP_UI + "; pips 7x9, injector 4x7, core frame 72x9 (fill = scrolling 6-frame mask), ammo 2x5; everything tinted in CombatHud from Palette (accent/heal/ammo) so colour-blind modes work",
    out="assets/ui/hud_kit.png", used_by="CombatHud (texture path when present, draw_rect fallback)")
add(id="ui_dialogue_frame", category="ui", target_px=[48, 48], palette_ref="ui", owner="fx_ui", priority=1,
    generation_prompt=UI + " A dialogue box frame: a dark translucent panel with a thin double steel border, small "
    "riveted corner brackets, a short hanging cable flourish from the top-left corner, and a separate small speaker "
    "name plate tab.",
    post_process=PP_UI + "; 9-slice 48x48 with 12 px margins; name plate 9-slice 32x12 with 4 px margins; panel alpha from UiTheme.BG (HC = opaque)",
    out="assets/ui/dialogue_frame.png", used_by="DialogueBox / subtitles")
add(id="ui_menu_frame", category="ui", target_px=[64, 64], palette_ref="ui", owner="fx_ui", priority=1,
    frames={"cursor": 4},
    generation_prompt=UI + " A menu panel kit: a large panel frame with ornamental steel corner pieces and a thin "
    "divider line ornament with a small central diamond seam, a small flame-like cursor pip in four flicker stages, "
    "a selected-row bar with tapered ends.",
    post_process=PP_UI + "; panel 9-slice 64x64 16 px margins, divider 96x5, cursor 7x7 x4 frames (static under flash reduction), row bar 3-slice",
    out="assets/ui/menu_kit.png", used_by="MenuScreen/UiTheme (all menus)")
add(id="ui_boss_bar", category="ui", target_px=[232, 16], palette_ref="ui", owner="fx_ui", priority=2,
    generation_prompt=UI + " A long horizontal boss health bar frame with heavy ornamental end caps shaped like clamps, "
    "a thin centre tick, and a small plaque above the middle for a name.",
    post_process=PP_UI + "; 3-slice (caps 16 px), fill tinted accent, phase tick at 50 %",
    out="assets/ui/boss_bar.png", used_by="CombatHud boss bar")
add(id="ui_style_ranks", category="ui", target_px=[24, 16], palette_ref="ui", owner="fx_ui", priority=3, source="code",
    frames={"D": 1, "C": 1, "B": 1, "A": 1, "S": 1, "SS": 1, "SSS": 1, "REDLINE": 1},
    generation_prompt="none (code-drawn pixel letterforms with a chiselled bevel; rank letters are exempt from translation, D-163)",
    post_process="tools/ui_ranks.py", out="assets/ui/style_ranks.png")
add(id="ui_icons", category="ui", target_px=[16, 16], palette_ref="ui", owner="fx_ui", priority=3,
    frames={"anchor": 1, "npc": 1, "shop": 1, "memory": 1, "scrap": 1, "gate": 1, "boss": 1, "note": 1, "circuit": 1, "weapon": 1},
    generation_prompt=UI + " A set of ten tiny map and menu icons in a grid: a pylon shrine, a person bust, a shop "
    "awning, a crystal shard, a nugget, a barred gate, a skull-like mask, a pinned note, a circuit card, a blade.",
    post_process=PP_UI + "; 11x11 inside 16x16 cells; map colours from Palette (map_gate, map_note)",
    out="assets/ui/icons.png", used_by="MapMenu, JournalMenu, LoadoutMenu")


def totals():
    t = {1: [0, 0, 0], 2: [0, 0, 0], 3: [0, 0, 0]}
    for i in items:
        t[i["priority"]][0] += 1
        t[i["priority"]][1] += i["est_generations"]
        t[i["priority"]][2] += i["est_credits"]
    return t


def check():
    errs = []
    ids = set()
    cats = {"bg_layer", "tileset", "prop", "character", "enemy", "boss", "npc", "vfx", "ui", "portrait", "title"}
    for i in items:
        for k in ("id", "category", "target_px", "frames", "palette_ref", "generation_prompt", "post_process", "owner", "priority"):
            if k not in i:
                errs.append(f"{i.get('id')}: missing {k}")
        if i["id"] in ids:
            errs.append(f"duplicate {i['id']}")
        ids.add(i["id"])
        if i["category"] not in cats:
            errs.append(f"{i['id']}: bad category")
        if i["owner"] not in ("env", "char", "fx_ui"):
            errs.append(f"{i['id']}: bad owner")
    pals = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "palettes.json")))["palettes"]
    for i in items:
        if i["palette_ref"] not in pals:
            errs.append(f"{i['id']}: unknown palette {i['palette_ref']}")
    t = totals()
    if t[1][2] > 35000:
        errs.append(f"priority 1 over 35k: {t[1][2]}")
    return errs


if __name__ == "__main__":
    errs = check()
    if "--check" not in sys.argv:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "art_manifest.json"), "w") as f:
            json.dump(items, f, indent=1, ensure_ascii=False)
    t = totals()
    print(f"{len(items)} assets")
    for p in (1, 2, 3):
        print(f"P{p}: {t[p][0]} assets, {t[p][1]} gens, ~{t[p][2]} credits")
    print(f"all: ~{sum(v[2] for v in t.values())} credits")
    for e in errs:
        print("ERROR", e)
    sys.exit(1 if errs else 0)
