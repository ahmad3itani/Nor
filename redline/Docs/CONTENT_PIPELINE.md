# REDLINE Content Pipeline (M6)

How to add rooms, enemies and art without touching engine code, and how to prove they work. Every command below runs from `redline/`.

## The gate: validate everything
```bash
godot --headless res://devtools/content/ValidateContent.tscn    # exit 1 on errors; add -- --out=/abs/report.md to save the report
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn     # full suite (it runs the validator too)
```

The validator checks:
- **References:** every literal `res://` path in scenes, data, scripts and `project.godot` must exist.
- **Data:** every resource in `data/` passes its own `validate()`. Dialogue gifts, shop items and quest rewards must exist in the catalog; menus opened by dialogue must exist; map notes must point at map rooms.
- **Rooms:**
  - a theme and names;
  - a world-map entry;
  - exactly one default spawn, and unique spawn ids;
  - a spawn for every Anchor;
  - exits that land on real entries;
  - hint actions that exist in the input map;
  - globally unique `persist_id`s;
  - enemies with data.
- **Quests and dialogue:** every flag that data requires must be set somewhere. Flags that are set but never read produce warnings.
- **Art:** the Art Bible checks (below).
- **Collectible tracker:** a table per room.

## Rooms
**Metrics come from the real player.** `data/level/traversal_default.tres` stores the recorded arcs of the run-jump, slide-jump, dodge-jump and dash-jump.

| Technique | Peak (px) | Reach (px, centre) | Widest gap with 6 px margin |
|---|---|---|---|
| Run-jump | 56 | 103 | 103 |
| Slide-jump | 45 | 118 | 118 |
| Dodge-jump | 56 | 149 | 149 |
| Dash-jump | 56 | 237 | 237 |

After changing movement tuning, run `godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn -- --write-metrics`. `test_room_templates` fails until you do.

**Templates** (`world/templates/`, `@tool` scenes you drop into a room):

| Template | What it builds | Guarantees |
|---|---|---|
| `GapChallenge` | Near and far ledges sized for a technique (+ margin, optional rise), with an optional catch well | The route bot clears it with that technique. The editor warns when a weaker technique also clears it ("not a gate"). |
| `ClimbSteps` | Zig-zag one-way steps | Warns when `step_rise` exceeds the real jump peak minus safety (48 px steps are the norm) |
| `Doorway` | An edge exit plus its entry spawn (36 px inside, facing in) | Doorways line up on the world map; you never spawn inside an exit |
| `JumpArcPreview` | An editor-only drawing of where each technique lands | Uses the recorded arcs, not formulas |

In the editor, templates bake their nodes into the scene. If a script writes a template without its children, it builds them at runtime, and the map, validator, heatmaps and economy audit expand it too.

**Scripted rooms:** `tools/roomgen/` (Python 3, standard library only) is the generator that wrote the Lowlight rooms.

```bash
python3 -B tools/roomgen/lowlight.py --check   # does every scene still match its script?
python3 -B tools/roomgen/lowlight.py           # regenerate (byte-identical when nothing changed)
```

The `.tscn` files are what the game loads. If you edit a room in Godot, `--check` will report it as drifted; after that, mirror the change in the script or stop regenerating that room.

**Checklist for a new room:**
1. Build it (editor + templates, or roomgen).
2. Add an offset in `data/world/world_map.tres`. `test_world_map` checks the doorways line up.
3. Add a `RouteBot` route in `tests/unit/test_slice_routes.gd`.
4. Run the validator and the tests.
5. Check the room in game with the dev console (teleport).

## Enemies
Enemies are data (bible §32, "composable modules"). An `EnemyData` holds a `brain` (`EnemyBrain`) assembled from modules in `enemies/modules/`:

| Slot | Modules |
|---|---|
| Movement (one) | `MoveApproach` (keep/retreat distance), `MoveHold`, `MoveHover`, `MoveSlowTurn` |
| Attack rules (ordered, first match wins) | `AttackRule`: range band, height difference, line of sight, on floor, target in front, face on start |
| Guard (optional) | `GuardFrontal` |
| Looks (any number) | `LookSpringLegs`, `LookEye`, `LookRotor`, `LookShieldPlate` |

**A new enemy** is:
1. An `EnemyData` (`.tres`) with its attacks.
2. A brain (`data/enemies/brains/<id>.tres`).
3. A copy of a variant scene with its `data` swapped.

**Example:** the Signal Drone (`data/enemies/signal_drone.tres`) was made that way and is tested. Write code only for a genuinely new module; keep it stateless and store per-enemy state with `ModularBehavior.mem()` and `remember()`. Bosses can keep bespoke scripts (Warden Krail).

## Art
The rules are in `Docs/ART_BIBLE.md`. Mechanically:
1. Export to `assets/<district or character>/<subject>_<action>[_variant].png`: horizontal strips, fixed cell, crisp alpha.
2. Create a `SpriteSheetSpec` (`.tres`): `texture_path`, `cell_size`, `origin` (the feet, bottom-centre) and `SpriteAnim`s. The animation names are the ones the visuals ask for:
   - **Enemies:** `idle`, `move`, `windup`, `attack`, `hurt`, `death`.
   - **Rook:** the state ids (`idle`, `run`, `slide`, `crouch`, `dodge`, `dash`, `hurt`, `heal`), plus `jump_rise` and `jump_fall`, plus attack ids or `attack`.
   
   Missing animations fall back (for example `windup` → `attack` → `idle`).
3. Point `EnemyData.sprite`, or the player visual's `sprite`, at the spec. The placeholder is replaced; telegraphs, health bars, afterimages and blinks stay.
4. Validate. `ArtValidator` checks:
   - snake_case names;
   - alpha only 0 or 255;
   - sheet size is a multiple of the cell;
   - animations fit inside the sheet;
   - palette size (a warning above 64 colours);
   - reserved gameplay colours outside `ui/` and `vfx/`;
   - the project's nearest filtering.

## Dev console (debug builds, backquote key)
- Teleport to any room entry.
- Spawn any enemy.
- Quick boss restart.
- Unlock-all profile.
- Save-state inspector (save now, copy JSON).
- Hitbox view.
- Performance graph.

The logic lives in `devtools/DevActions.gd`, which scripts and tests can call too.
