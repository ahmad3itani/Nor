# REDLINE Content Pipeline (M6, extended in M7)

How to add rooms, enemies and art without touching engine code, and how to prove they work. Every command below runs from `redline/`.

## The gate: validate everything
```bash
godot --headless res://devtools/content/ValidateContent.tscn    # exit 1 on errors; add -- --out=/abs/report.md to save the report
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn     # full suite (it runs the validator too)
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn -- --filter=economy   # after any enemy, drop or price change
python3 -B tools/roomgen/lowlight.py --check                    # the pre-M7 rooms
for f in tools/roomgen/uc_*.py tools/roomgen/ll_*.py tools/roomgen/fixtures_*.py; do python3 -B "$f" --check || echo "DRIFT: $f"; done
```
All of these must pass before a content change lands. `--check` exits 1 when a scene no longer matches its script. Use `python3 -B` so no `__pycache__` is written into the repo.

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
  - enemies with data;
  - the **content protocol** (M7): any node may define `func content_errors(room: Node) -> PackedStringArray` (placement rules, e.g. a Breaker in grounded reach, a shutter column too far above the floor, a chase checkpoint off a block top) and `func content_flags() -> Dictionary` (flags and conditions it produces or reads, e.g. a lever's flag, a shutter's latch, a hint's `skip_when`). The validator runs it for every node, independent of the node's type.
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

**Scripted rooms:** `tools/roomgen/` (Python 3, standard library only). `lowlight.py` writes the pre-M7 rooms (Relay, Flooded Alley … Warden Tower). Since M7 **every new room has its own generator**: `uc_<room>.py` for the Undercity and `ll_<room>.py` for new Lowlight rooms. Each imports `RoomGen` and `finish` from `roomgen.py` and its district's palette module (`undercity_style.py`, `lowlight_style.py`), writes one room and calls `finish()`. Test fixtures have generators too (`fixtures_*.py`, writing `tests/fixtures/*.tscn`); `fixtures_scaffold.py --check` first runs a Python self-test of the helpers' emitted text.

```bash
python3 -B tools/roomgen/uc_wake.py --check    # does the scene still match its script?
python3 -B tools/roomgen/uc_wake.py            # regenerate (byte-identical when nothing changed)
```

**Exits across districts:** `exit(x, y, w, h, target, entry, flag)` takes a bare room name for Lowlight (`"BellTower"`) and a folder-qualified one for anything else (`"undercity/Wake"`).

**Helpers added in M7** (property names are what the node scripts export):

| Helper | Builds |
|---|---|
| `weapon_pickup(scene, weapon_id, flag, x, y)` | A `WeaponPickup` scene (`PulseBladeRack`, `ServicePistolDrop`) |
| `respawn_point(spawn_id, x, y, w, h)` | An `EntryCheckpoint`, a mid-room respawn before the first Anchor (also add `spawn(spawn_id, …)`) |
| `declare_flags(*flags)` | A `FlagDeclaration`: stub rooms only, stands in for a flag a later room will produce |
| `tracker(name, rail, y, wake_x, lost_x, config, visible_when)` | The Collector eye (`CeilingTracker`) |
| `breaker(bid, circuit, x, y)` / `shutter(sid, x, y, w, h, circuit, timing, latch_flag)` | The Grid: a player-only breaker and a latching `PowerShutter` (timing from `data/level/shutter_*.tres`) |
| `clamp(cid, x, top_y, width, raised_bottom, timing, circuits, hint_id, hint)` | A boss `GridClamp` |
| `scanner(sid, x, data, top_y, bottom_y, circuit, offline_open, offline_warn, phase)` | A `ScannerBeam` (`data/level/scanner_<data>.tres`); the node is named `Scanner_<sid>`, which the playtest recorder relies on |
| `chase(cid, data, path, speed_scale, start_area, end_area, checkpoints)` | A `ChaseDirector` with `ChaseCheckpoint`s (`data/world/chase/<data>.tres`) |
| `flow(…, drain_scale, drain_floor)` · `enemy(…, ai, data)` · `npc(…, present_when)` · `hint(…, skip_when)` | Per-zone drain, enemy data variants and dormant enemies, NPCs that appear by condition, hints that stay silent by condition |

**Decor:** a `decor()` or `neon()` origin is its **bottom-centre**, so `y` is the prop's bottom edge. Props placed by their top draw inside ceilings (several M7 specs did, D-098). Decor draws no text.

The `.tscn` files are what the game loads. If you edit a room in Godot, `--check` will report it as drifted; after that, mirror the change in the script or stop regenerating that room.

**Checklist for a new room:**
1. Build it (editor + templates, or its own roomgen script).
2. Add an offset in `data/world/world_map.tres`. `test_world_map` checks the doorways line up.
3. Add a `RouteBot` route: `tests/unit/test_slice_routes.gd` for the pre-M7 rooms, `test_undercity_routes.gd` / `test_lowlight_m7_routes.gd` for M7 rooms (your functions go below the frozen harness; use `_campaign(blade, pistol, core_shown)`, `_enter`, `_pacify`, `_assert_exit`). The route stops at the exit and asserts its contract.
4. If the room has doors other rooms rely on, add its row to `tests/unit/test_door_contracts.gd` (exit rect, target, own entry position and facing, `requires_flag`, asserted exactly).
5. Run the gate above. Run `--filter=economy` if it has enemies or Scrap.
6. Check the room in game with the dev console (teleport), and in `CaptureTour`.

**Building a whole district (the M7 world-skeleton flow, D-084):**
1. Write the district's four lines and §41 row in `DISTRICTS.md` and its palette in `ART_BIBLE.md` §3.
2. Land a **skeleton** first: a stub scene per room with final bounds, doors and spawns (no `requires_flag` yet), the world-map entries, the door plumbing in existing rooms, the `test_door_contracts` rows and a placeholder test per room. Where a flag's real producer is in a later room, the stub calls `declare_flags(...)`; the validator warns "stub flag declaration" instead of erroring on a consumed flag with no producer.
3. Replace one stub at a time. Each room change removes its own `FlagDeclaration` when it adds the real producer, sets its row's `requires_flag`, and passes the full gate with no expected failures.
4. Finish with the full walks and `test_no_stub_declarations_left`, then set the district's chart threshold from measured standable coverage (`test_thresholds_match_standable_coverage`).

**Rules learned in M7:**
- Never put a literal `res://` path to a file that doesn't exist yet into a scanned script, scene or resource; the reference scan fails. Use a format string guarded by `ResourceLoader.exists`, or land it with the file.
- A **Dash-only** target must sit *below* its take-off (64 px worked), and its negative test must sweep every air-dodge frame and late (coyote) take-offs. A gap at one height can't separate a dash-jump from a dodge-jump plus a late air dodge (D-094, K-48).
- A Needle on a ledge above a walkway needs `needle_ledge.tres` (aggro 160) or it lunges off (D-097).

**RouteBot pitfalls** (K-57):
- A `runjump` right after a `jump` landing can fire on the spot: the landing leaves a small backward drift, and the keep-speed check reads it as already at the edge. Put a short `run` step (or a `wait`) first.
- `["shoot", n, "diag"]` holds `move_x` toward the facing, so a multi-shot diagonal volley walks forward and drifts off the line. Use single diagonal shots, each after a `run` that sets the facing.
- A `jump` target must be *on* the platform, not in a gap before it: the steer stops a few px short (Collector Bay's catwalks needed 210/360, not 190/330).
- An interact needs Rook's 12 px body to overlap the use area; stop inside it, not beside it.
- New M7 steps: `["shoot", n, aim]`, `["dodge", x]`, `["dodgejump_airdodge", edge, x, delay_frames]`.

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
