# CLAUDE.md: REDLINE (Godot project)

`redline/` is a standalone Godot 4.3 game project. It is unrelated to the Nor Next.js app in the parent directory.

## Before any change
- Read `Docs/DESIGN_BIBLE.md` and follow its §37 rules. The most important ones:
  - Don't implement future milestones unless asked.
  - Tuning and content belong in Resources (`data/`), not in code.
  - Keep keyboard and controller parity.
  - Commit in small logical units.
  - Flag conflicts with the bible in `Docs/DECISIONS.md` instead of silently changing the design.
- Current state: M0–M3, M5 (world framework), M6 (content pipeline), **M7 batch 1** (Act I: the 00 Undercity district and the completed 01 Lowlight, `Docs/M7_DISTRICT_REPORT.md`, `Docs/DISTRICTS.md`), the **M8 batch** (narrative systems + Act I integration, D-105: sequences, memory vignettes, NPC arcs, world state, the endings framework; `Docs/M8_NARRATIVE_REPORT.md`) and **M9** (endgame / accessibility at Act I scope, D-140: platform services with a local backend only, 30 achievements, 16 challenges with local boards and ghosts, NG+ and remix, the Deep Rig, catalog-driven settings and rebinding, localization readiness, the Undercity demo and checked-in export presets; `Docs/M9_ENDGAME_REPORT.md`) are done. Acts II–V and the finale are not built; the four endings are reachable only through the dev Ending theatre. New Game starts unarmed in Undercity/Wake. M4 (validation) tooling is done and the **§44 playtest is still pending** (`Docs/PLAYTEST_KIT.md`; which build it uses is D-068). When session files or a report come back, the next step is data-driven changes per failing §44 line (flag each in DECISIONS). **Do not start M7 batch 2 (Ironworks) or any later district or milestone unless the user asks** — bible §44 says not to scale content before the slice passes.
- Art and audio are procedural placeholders (D-026). Don't mass-produce final assets; anything final must follow `Docs/ART_BIBLE.md`.
- Keep `Docs/DECISIONS.md`, `CHANGELOG.md`, `TODO.md` and `KNOWN_ISSUES.md` up to date.

## Commands (run inside `redline/`)
```bash
godot --headless --import                                          # once per fresh clone (class cache)
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn        # all tests; must pass before pushing
godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn  # movement metrics per preset
godot --headless --fixed-fps 60 res://devtools/PerfProbe.tscn      # CPU cost under fight load [-- --room=res://… --at=x:y,…]
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn -- --filter=slice_routes   # route bot: every slice room is traversable
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn -- --filter=economy        # the filter needs the `--` separator, or the whole suite runs
xvfb-run -a godot --fixed-fps 60 --rendering-driver opengl3 res://devtools/CaptureTour.tscn -- --out=/abs/dir [--tour=movement|combat|slice|undercity|ui|story|endgame] [--only=a,c,n,s,l,d,v]   # endgame exits 1 on a missing shot
godot --headless res://devtools/PlaytestReport.tscn -- --in=/abs/sessions --out=/abs/report   # M4 playtest report + heatmaps
godot --headless res://devtools/content/ValidateContent.tscn       # M6 content + art validation (exit 1 on errors)
godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn -- --write-metrics   # re-record jump arcs after tuning changes
python3 -B tools/roomgen/lowlight.py --check                          # pre-M7 Lowlight rooms still match their script?
for f in tools/roomgen/uc_*.py tools/roomgen/ll_*.py tools/roomgen/fixtures_*.py; do python3 -B "$f" --check || echo "DRIFT: $f"; done   # M7 rooms + test fixtures
for f in tools/roomgen/null_*.py tools/roomgen/ch_*.py tools/roomgen/remix_act1.py; do python3 -B "$f" --check || echo "DRIFT: $f"; done   # M9 challenge rooms + NG+ remix data
godot --headless res://devtools/l10n/ExtractStrings.tscn -- --check   # M9 string catalog current (--write after changing player text)
godot --headless --fixed-fps 60 res://devtools/GhostBake.tscn -- --challenge=all --check   # M9 rig ghosts still match
python3 -B tools/build/build.py --check                                 # M9 export presets + no network in tools (no Godot needed)
python3 -B tools/build/build.py --targets linux,windows,macos,web --kinds full,demo --gzip-web --smoke   # builds in build/ (needs export templates)
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
- **Autoloads** (order in `project.godot`, §37.9): EventBus, Settings, Game, SaveManager, AudioManager, SceneRouter, InputGlyphs, MusicDirector, **Cinematics**, **Platform**, **Challenges**, Playtest. `Cinematics` (M8) depends on EventBus, Settings, Game, AudioManager, SceneRouter, InputGlyphs and MusicDirector, so it loads after them; Platform and Challenges (M9) load after Cinematics and before Playtest, which reads all three. Nothing loaded earlier may call them in `_ready`. Settings calls `BuildInfo.apply_demo_dirs()` first in its `_ready`. Autoload scripts have no `class_name`.
- **Dependencies (§37.9, D-166):** the game runtime has none beyond Godot 4.3. The Godot 4.3.stable export templates (`~/.local/share/godot/export_templates/4.3.stable`) are needed only for `build.py` builds and `--smoke`; `build.py --check` needs no Godot; rcedit is not used (`application/modify_resources=false`). No networking, no storefront SDK (D-141): the Steam backend is a documented slot only.
- **Story (M8):** read `CONTENT_PIPELINE.md` "Story content".
  - Scripted scenes are data: `SequenceData` step lists in `data/sequences/`, run by the `Cinematics` autoload; scene timing (skip holds, typing rate, line times) is `data/cinematics/cinematic_config.tres`. A skip and INSTANT run every remaining step's `finish()`, so no effect is lost; an abort (room left, Save & Quit, test teardown) runs no `finish()`, sets no flag and only restores, so the scene replays (D-106).
  - Headless runs default to `CinematicMode` INSTANT (`--cinematics=play|auto|instant` overrides), so route and boss tests stay byte-stable; sequence tests use AUTO (D-107). CaptureTour forces INSTANT for every tour but `story`.
  - Act I sequences never move Rook, and new text never names him (D-109).
  - All M8 state is flags, bool or int only (`seen_seq_*`, `mem_seen_*`, `arc_<npc>_*`, `ending_seen_*`, `act1_complete`, …); no new `GameState` key and no schema bump (D-116).
  - New resource types lint themselves through the resource content protocol: `content_flags()` (flags produced/read, conditions) and `content_check()` (cross-file checks, no room argument); tests call `ContentValidator.check_resource()`. World-state switches are visual only (linted, D-123); map notes are `MapMarker.NOTE` (D-124).
  - Every runtime scan of a data folder goes through `DataDir.list` / `DataDir.list_scenes` (exported builds only list `.remap` files, K-M8-22).
  - Future-act flags are declared in `data/story/future_flags.tres`; only `data/endings` may read them (D-127). The Act I knowledge lint warns on Act II+ terms and on the name 'Rook' (D-132).
- **Endgame (M9):** read `CONTENT_PIPELINE.md` "Endgame content".
  - **Player text:** English source in data and code, `LOC_FIELDS` (+ `LOC_EXEMPT`) on every script with player text, translated at the edge with `Loc.t` / `Loc.f` (named `{placeholders}`) / `Loc.tn`; run `ExtractStrings -- --write` after changing player text and `-- --check` before committing (D-162). Logic never compares display strings.
  - **Sandboxed runs go through `Challenges`; never write `Game.state` in a run** (it is the run's sandbox; the profile is `Game.held_profile`, D-147). Any code that swaps `Game.state` around a room change must set `Game.suppress_leave_capture`.
  - Platform stores, records and ghosts live under `Platform.store_dir`; tests point it (and `SaveManager.save_dir`, `Playtest.dir`) at a temp dir and remove it: `test_zz_user_dir_clean` fails on files a test run writes to the real user:// paths and on leftovers in a suite's own `user://test_*` folders (only files modified during the run are judged; `logs/`, `shader_cache/` and `vulkan/` are the engine's).
  - Achievements never read Settings (D-144); accessibility never shames (§24, CrossRules X-8 forbidden words); assists are neutral record tags (D-149).
  - New top-level folders go into `ContentValidator.SCAN_DIRS` or `CrossRules.IGNORED_DIRS` (X-6); runtime folder scans only through `DataDir` (X-5); every EventBus signal is recorded by Playtest or listed in `UNRECORDED_SIGNALS` (X-3).
  - **Pitfall:** never put Backspace in `ui_cancel`: Godot 4.3's LineEdit/TextEdit take `ui_cancel` as "release focus", so Backspace could never delete text. Backspace is its own `ui_back` action; menus back out through `MenuScreen.cancel_pressed()` (D-158).
  - **Pitfall:** a script of a resource an autoload preloads must not name a class that names that autoload (e.g. `OnboardingConfig` -> `WorldMapIndex` -> `Game` -> preload `onboarding.tres`): the editor copes, exports die with SCRIPT ERRORs. Load such a class by path; `build.py --smoke` catches it.
  - **Pitfall:** `BuildInfo` (compiled by Settings, the second autoload) must not name `Game` as an identifier; reach later autoloads by path or node lookup.
