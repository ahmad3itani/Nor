# CLAUDE.md: REDLINE (Godot project)

`redline/` is a standalone Godot 4.3 game project. It is unrelated to the Nor Next.js app in the parent directory.

## Before any change
- Read `Docs/DESIGN_BIBLE.md` and follow its §37 rules. The most important ones:
  - Don't implement future milestones unless asked.
  - Tuning and content belong in Resources (`data/`), not in code.
  - Keep keyboard and controller parity.
  - Commit in small logical units.
  - Flag conflicts with the bible in `Docs/DECISIONS.md` instead of silently changing the design.
- Current state: M0–M3, M5 (world framework), M6 (content pipeline) and **M7 batch 1** (Act I: the 00 Undercity district and the completed 01 Lowlight, `Docs/M7_DISTRICT_REPORT.md`, `Docs/DISTRICTS.md`) are done. New Game starts unarmed in Undercity/Wake. M4 (validation) tooling is done and the **§44 playtest is still pending** (`Docs/PLAYTEST_KIT.md`; which build it uses is D-068). When session files or a report come back, the next step is data-driven changes per failing §44 line (flag each in DECISIONS). **Do not start M7 batch 2 (Ironworks) or any later district or milestone unless the user asks** — bible §44 says not to scale content before the slice passes.
- Art and audio are procedural placeholders (D-026). Don't mass-produce final assets; anything final must follow `Docs/ART_BIBLE.md`.
- Keep `Docs/DECISIONS.md`, `CHANGELOG.md`, `TODO.md` and `KNOWN_ISSUES.md` up to date.

## Commands (run inside `redline/`)
```bash
godot --headless --import                                          # once per fresh clone (class cache)
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn        # all tests; must pass before pushing
godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn  # movement metrics per preset
godot --headless --fixed-fps 60 res://devtools/PerfProbe.tscn      # CPU cost under fight load [-- --room=res://… --at=x:y,…]
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn -- --filter=slice_routes   # route bot: every slice room is traversable
xvfb-run -a godot --fixed-fps 60 --rendering-driver opengl3 res://devtools/CaptureTour.tscn -- --out=/abs/dir [--tour=movement|combat|slice|undercity|ui]
godot --headless res://devtools/PlaytestReport.tscn -- --in=/abs/sessions --out=/abs/report   # M4 playtest report + heatmaps
godot --headless res://devtools/content/ValidateContent.tscn       # M6 content + art validation (exit 1 on errors)
godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn -- --write-metrics   # re-record jump arcs after tuning changes
python3 -B tools/roomgen/lowlight.py --check                          # pre-M7 Lowlight rooms still match their script?
for f in tools/roomgen/uc_*.py tools/roomgen/ll_*.py tools/roomgen/fixtures_*.py; do python3 -B "$f" --check || echo "DRIFT: $f"; done   # M7 rooms + test fixtures
```

## Conventions
- GDScript uses static typing and tabs. Comments explain design intent, not syntax.
- Movement: `Player.gd` is the motor (timers, stance, physics helpers), and `player/states/*.gd` holds one mode each. States read `PlayerInputFrame`, never `Input`.
- New tests go in `tests/unit/test_*.gd` and extend `RedlineTestCase`, using `check()` and `check_near()`. Use `ScriptedInputSource` to drive the player.
- EventBus signals must be explicit and typed. Never add a generic event channel.
- Combat: hits go through `Hurtbox.receive(HitInfo)` → `receive_hit()` → a `CombatResult` value. Attack, weapon and enemy numbers live in `data/` resources. Shared combat code lives in `combat/`.
- **Godot 4.3 pitfalls:**
  - Calling a method on a freed typed reference *crashes the engine*. Check `is_instance_valid` first.
  - GDScript lambdas capture locals **by value**. To write results from a callback, append to an array instead.
  - Don't read `Performance.TIME_PHYSICS_PROCESS` in fixed-fps headless runs; use `devtools/PerfProbe`.
- Run a subset of tests with `-- --filter=<substring>`.
- **World (M3):** profile progress lives in `Game.state` (`GameState`). Room state is persistent ids plus flags, never scene snapshots. Quests are derived from flags. Circuits are stat queries (`Game.circuit_mult/value`, see `Docs/CIRCUITS.md`). If a save key changes meaning, is renamed or is removed, bump `SaveManager.CURRENT_SCHEMA_VERSION` and add a migration and a test. A new optional key only needs a default in `GameState.from_dict` and a test that an old save still loads (`tests/fixtures/save_v3_slice.json`, D-087/D-090).
- **Rooms:** after any layout change, update the room's `RouteBot` steps (`tests/unit/test_slice_routes.gd` for the pre-M7 rooms, `test_undercity_routes.gd` / `test_lowlight_m7_routes.gd` for the M7 rooms, each room's functions below the frozen harness) and run `slice_routes`, `slice_world`, `door_contracts` and the room's route file. Doors are contracts: `test_door_contracts.gd` pins every M7 exit, entry and `requires_flag` (D-092). Decor origins are bottom-centre (a prop's `y` is its bottom edge). Level metrics: a jump rises 56.4 px (use ≤ 48 px steps), and a run-jump spans about 100 px centre to centre. A node name duplicated in a `.tscn` leaks bodies.
- **Pitfall:** a `preload()`ed const's typed-property assignment can fail to parse in 4.3; `load()` at runtime instead.
- **Pitfall:** a body added to the tree inside an exit rect fires it on the first physics step. `Room.gd` positions the player at its spawn before `add_child` (D-091); keep it that way.
- **Pitfall:** the ContentValidator reports any literal `res://` path to a file that doesn't exist yet. Build such a path with a format string guarded by `ResourceLoader.exists`, or land it with the file.
- **Playtest (M4):** `autoload/Playtest.gd` only listens to EventBus; gameplay must never depend on it. New things worth measuring get an explicit EventBus signal and a recorder handler, then a line in `PlaytestAnalyzer`. Experiments are `PlaytestVariant` data applied to a copy. Headless runs never record unless a test sets `Playtest.allow_headless` and a temp `Playtest.dir`. Recording is local only; never add networking.
- **Map (M5):** a new room needs an entry in `data/world/world_map.tres` (offset so its exits meet neighbours; `test_world_map` checks). Map icons come from the room scene itself (`WorldMapIndex`); use `MapMarker` only for things no node implies (ability gates). World consequences use `WorldStateSwitch` + `Game.check_condition`. Run `--filter=economy` after changing any price or drop.
- **Content (M6):** read `Docs/CONTENT_PIPELINE.md`. New enemies = EnemyData + a brain of modules (`enemies/modules/`), never a per-enemy script; new behaviour = a new stateless module. Gaps/steps use `world/templates/` (metrics recorded from the real player). Art swaps in via `SpriteSheetSpec`. Run `ValidateContent` before committing content. Dev tools go through `devtools/DevActions.gd`.
- **Districts (M7):** every district needs a mechanic thesis, visual thesis, enemy ecosystem and boss test, written in `Docs/DISTRICTS.md` before its rooms. One generator per room (`tools/roomgen/<uc|ll>_<room>.py`), a route test per room, and `--filter=economy` after adding enemies: the re-clear rule has 2 Scrap of headroom (K-49). Dash-only secrets need a target *below* the take-off and an every-frame air-dodge sweep (D-094).
