# assets/

Exported, game-ready art and audio (Art Bible §9). Sources live in `art/source/` (never imported, `art/.gdignore`); the scripts that make every file here live in `tools/assetgen/`.

- `assets/<district or character>/<subject>[_<action>[_variant]].png` (snake_case). Sheets are horizontal strips with a fixed cell size.
- Each sheet gets a `SpriteSheetSpec` (`.tres`) next to it: cell size, origin (bottom-centre, at the feet) and animations (a `SpriteAnim.origin` may override the origin per animation). Point `EnemyData.sprite`, the player visual's `sprite` or `NpcProfile.sprite` at it, and the placeholder drawing is replaced. No code changes.
- A `.json` sidecar keeps the numbers the tools work from (cell, origin, rows, tint hint).
- Check before committing: `godot --headless res://devtools/content/ValidateContent.tscn` (names, crisp alpha, sheet sizes, palette size, reserved colours) and `python3 -B tools/assetgen/assetgen.py --check` (rebuild drift, provenance, import flags).

| Folder | What |
|---|---|
| `rook/`, `enemies/`, `bosses/`, `npcs/`, `lowlight/`, `undercity/` | character sheets (code pixel rigs); `*_mask.png` = tint mask for Palette colours |
| `portraits/` | dialogue portraits, 48x48 strips (frame 0 neutral, frame 1 talk) |
| `props/`, `ui/`, `title/` | pickups, UI kit (`X.png` + `X_fill.png` tint mask + `.json` regions), title sky and logo |
| `null/` | Deep Rig tiles (16 px autotile layout in the `.json`) |
| `vfx/` | grey mask VFX strips (tones 96/176/255), tinted in code |
| `vfx/atmos/` | fog, light shafts, lamp glows, vignette: textures with up to 4 alpha levels, plus `district_grades.json` |
| `audio/sfx/`, `audio/ui/`, `audio/footsteps/` | OGG one-shots; `<id>.tres` = AudioStreamRandomizer over the takes |
| `audio/ambience/`, `audio/music/` | loops (`loop=true`, `loop_offset=0` in the committed `.import`) |

Provenance: every file has a row in `SOURCES.csv` (`out_files` lists it; `rights` says whether it is own work or generator output). Generator output is marked "ElevenLabs output, check plan terms" until the rights decision is recorded.
