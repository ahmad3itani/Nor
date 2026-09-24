# REDLINE Art Bible (v0.1, drafted at M3)

Bible §40 requires this document before any final asset is produced. It fixes the technical frame the placeholder build already uses, so commissioned or in-house art drops in without code changes. **Every asset must be checked against it.**

> **Status:** everything in the current build is procedural placeholder art: rectangles, `Decor` props, `NeonSign`, and the `DistrictBackdrop` skyline and rain. The rules below exist so the placeholders can be replaced one at a time.

---

## 1. Reference canvas and scaling
- **Canvas:** 480×270 game pixels, scaled by whole numbers: ×4 at 1080p, ×8 at 4K (D-003).
- The world renders inside a 480×270 `SubViewport` with nearest-neighbour filtering. UI renders at native resolution on top (D-004). **Never mix pixel densities inside the world layer** (bible §25).
- One art pixel equals one game pixel. Nothing is drawn at half-pixel offsets or sub-pixel scales, and nothing is rotated except VFX.

## 2. Sprite scale

| Thing | Collider / size (px) | Sprite target (px) |
|---|---|---|
| Rook standing | 12 × 34 | 40–44 tall (the head can overhang the collider by 2–4 px) |
| Rook low (slide / crouch) | 12 × 16 | 18–20 tall |
| Needle | 12 × 26 | 30 |
| Shield | 18 × 30 | 34, plus the shield plate |
| Hopper | 12 × 16 | 20 |
| Scout Drone | 14 × 10 | 18 × 14, with the rotor extra |
| Watcher | 12 × 12 | 16 |
| Enforcer (elite) | 14 × 30 | 36 |
| Warden Krail | 22 × 44 | 52–56 |
| Tiles | 16 × 16 grid | Geometry is authored on a 16 px grid (see the lab grids) |

- The **sprite origin is bottom-centre, at the feet**. This matches every `CharacterBody2D` and `Decor` origin in the code.
- Hurtboxes are the colliders plus 1 px on each side. Silhouettes must never suggest a hitbox larger than that.

## 3. Palette philosophy
- **Each district owns a palette** (bible §25), stored as a `DistrictTheme` resource (`data/districts/*.tres`). Art should sample from it; if the art needs new colors, update the theme first.
- **Lowlight:** cold blue-violet night, wet concrete, and restrained neon in three accents: amber `#ffcf5a`, cyan `#58e0e8` and Redline red `#e8283c`.
- **The Relay:** warm rust and sodium light, almost no cyan. It's safe, human and lived-in.
- **Redline red (`#e8283c`) is reserved:** use it for Rook's visor, the Core, danger telegraphs and the Anchor Core. Never use it for decoration players could mistake for a threat, except as a rare neon accent.
- **Reserved gameplay colors:**
  - telegraphs are red `#ff3b4f`;
  - blocks and guards are light blue `#7fd7ff`;
  - healing is green `#7dff9a`;
  - Scrap is gold `#ffd36b`;
  - memory is pale blue `#9fd8ff`;
  - elites get a gold outline `#ffcf5a`.
  
  Keep them reserved so colorblind-safe variants can swap them in one place.

## 4. Outlines and shading
- **Characters:** a 1 px dark outline (`#1a1320` range), colored per region, with no pure black. Enemies use a slightly warmer outline than the environment so they separate at speed.
- **Environment:** no outlines. Shape comes from value steps: 3 values per material, plus 1 edge highlight on top edges (the `edge_color` in the theme).
- **Shading:** hand-placed clusters with a top-left key light unless the room's lighting says otherwise. No dithering gradients on characters; limited ordered dither is allowed on large backgrounds.
- **Gameplay must stay readable without bloom** (bible §25). Glow is an accent layer only.

## 5. Lighting
- 2D lights are accents: neon spill, the Anchor glow, muzzle flashes. They never replace painted shading.
- There are at most 4 dynamic lights on screen in normal play (bible §33).
- Each district defines one "lighting language". Lowlight: pools of neon on wet surfaces and dark verticals.

## 6. Animation
- **Base rate 12 fps** for most loops. Fast actions (attacks, dodge, dash) use 15–24 fps via held or smeared frames. Hitstop freezes on the impact frame.
- **Rook's minimum set** (bible §25): idle, run, turn, jump rise/apex/fall, land, hard land, slide, crouch, dodge, dash, 3-hit slash chain, heavy, launcher, air slash, air spike, shoot (per ranged weapon), hurt, heal, death and interact.
- **Anticipation:** every enemy wind-up needs a pose that holds for the **whole telegraph** (≥ 0.3 s, validated in data). The current red "!" and hitbox outline are accessibility aids and should stay available as an option.
- **Smear frames:** one smear per attack, at most 2 px beyond the real hitbox. Smears must never read wider than what actually hits.
- **Squash and stretch:** use the code values in `PlayerPlaceholderVisual` as the target feel. A jump is about 0.72 × 1.3 and a land is about 1.35 × 0.7, easing back within about 0.15 s.

## 7. VFX
- VFX sit on the same pixel grid as the world. Particles are 1–2 px squares (see `HitSpark`, `DustBurst`).
- The vocabulary is fixed by bible §26: slash arcs, impact sparks, dust, rain, steam, debris, electricity, Pulse particles, glass, speed lines, afterimages, explosion silhouettes and shockwaves.
- Keep VFX readable: no full-screen flashes. With flash reduction on, pulses become static tints.

## 8. Parallax and backgrounds
- **Sky:** a gradient, screen-fixed.
- **Far layer:** skyline with a motion scale of 0.12 horizontal and 0.03 vertical.
- **Mid layer:** skyline with a motion scale of 0.3 horizontal and 0.07 vertical.
- **Foreground silhouettes** (future): a motion scale of 1.15–1.3, never covering the player's collision band.
- Background layers repeat every 960 px horizontally (`DistrictBackdrop.PERIOD`). Keep them lower-contrast than playable geometry by at least 2 value steps.

## 9. Naming and export
- Files use `snake_case`: `<subject>_<action>_<variant>.png`. Examples: `rook_run.png`, `needle_attack_windup.png`, `lowlight_tiles_concrete.png`.
- Sprite sheets are horizontal strips with a fixed cell size per character (for example Rook at 48×48, origin at bottom-centre, cell x = 24 and y = 46). Frame counts go in the import metadata, not the filename.
- Export as PNG, 8-bit indexed where possible, with no premultiplied alpha. Import with the Lossless preset and nearest filtering (the project default).
- Folder layout: `art/<district or character>/...` for source files and `assets/...` for exported, imported files.

## 10. Audio (companion notes)
- The placeholder SFX and music are synthesized from data (`data/audio/placeholder_sfx.tres`, `audio/MusicSynth.gd`).
- **Replacements must keep the same ids and stem layout.** SFX: set `override_stream`. Music: supply five synced stems (pad, bass, drums, arp, lead) of equal length per district, so `MusicDirector` can keep fading layers by state.

## 11. Sourcing rules (bible §3, §40)
- Study the reference games' principles, never their assets, characters, silhouettes or maps.
- AI-generated imagery may be used for **ideation and reference only**. Final assets need consistency with this document, clean-up, animation compatibility and clear commercial rights.
- **Checklist for any delivered asset:** right canvas and scale? Origin correct? Palette from the district theme? Reserved colors respected? Readable with bloom off and flash reduction on? Named and exported to spec?
