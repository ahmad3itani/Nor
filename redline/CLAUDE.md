# CLAUDE.md: REDLINE (Godot project)

`redline/` is a standalone Godot 4.3 game project. It is unrelated to the Nor Next.js app in the parent directory.

## Before any change
- Read `Docs/DESIGN_BIBLE.md` and follow its §37 rules. The most important ones:
  - Don't implement future milestones unless asked.
  - Tuning and content belong in Resources (`data/`), not in code.
  - Keep keyboard and controller parity.
  - Commit in small logical units.
  - Flag conflicts with the bible in `Docs/DECISIONS.md` instead of silently changing the design.
- Current state: M0–M3 are done; M4 (validation) tooling is done and **waiting for a human playtest** (`Docs/PLAYTEST_KIT.md`). When session files or a report come back, the next step is data-driven changes per failing §44 line (flag each in DECISIONS). **Do not start M5 or later unless the user asks.**
- Art and audio are procedural placeholders (D-026). Don't mass-produce final assets; anything final must follow `Docs/ART_BIBLE.md`.
- Keep `Docs/DECISIONS.md`, `CHANGELOG.md`, `TODO.md` and `KNOWN_ISSUES.md` up to date.

## Commands (run inside `redline/`)
```bash
godot --headless --import                                          # once per fresh clone (class cache)
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn        # all tests; must pass before pushing
godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn  # movement metrics per preset
godot --headless --fixed-fps 60 res://devtools/PerfProbe.tscn      # CPU cost under fight load [-- --room=res://… --at=x:y,…]
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn -- --filter=slice_routes   # route bot: every slice room is traversable
xvfb-run -a godot --fixed-fps 60 --rendering-driver opengl3 res://devtools/CaptureTour.tscn -- --out=/abs/dir [--tour=movement|combat|slice|ui]
godot --headless res://devtools/PlaytestReport.tscn -- --in=/abs/sessions --out=/abs/report   # M4 playtest report + heatmaps
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
- **World (M3):** profile progress lives in `Game.state` (`GameState`). Room state is persistent ids plus flags, never scene snapshots. Quests are derived from flags. Circuits are stat queries (`Game.circuit_mult/value`, see `Docs/CIRCUITS.md`). If you change a save field, bump `SaveManager.CURRENT_SCHEMA_VERSION` and add a migration and a test.
- **Rooms:** after any layout change to `world/rooms/lowlight/*.tscn`, update the `RouteBot` steps in `tests/unit/test_slice_routes.gd` and run the `slice_routes` and `slice_world` tests. Level metrics: a jump rises 56.4 px (use ≤ 48 px steps), and a run-jump spans about 100 px centre to centre. A node name duplicated in a `.tscn` leaks bodies.
- **Pitfall:** a `preload()`ed const's typed-property assignment can fail to parse in 4.3; `load()` at runtime instead.
- **Playtest (M4):** `autoload/Playtest.gd` only listens to EventBus; gameplay must never depend on it. New things worth measuring get an explicit EventBus signal and a recorder handler, then a line in `PlaytestAnalyzer`. Experiments are `PlaytestVariant` data applied to a copy. Headless runs never record unless a test sets `Playtest.allow_headless` and a temp `Playtest.dir`. Recording is local only; never add networking.
