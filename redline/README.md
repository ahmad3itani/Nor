# REDLINE

A high-speed 2D pixel-art action platformer set in the megacity of Veyra, built with Godot 4.
**Movement is life. Violence buys time. Curiosity reveals the truth.**

- Design source of truth: [`Docs/DESIGN_BIBLE.md`](Docs/DESIGN_BIBLE.md)
- Current milestone: **M8 Narrative Integration** (systems + Act I, D-105; [`Docs/M8_NARRATIVE_REPORT.md`](Docs/M8_NARRATIVE_REPORT.md), how-to: [`CONTENT_PIPELINE`](Docs/CONTENT_PIPELINE.md) "Story content"): skippable scripted sequences (the opening, boss intros, the Relay arrival, the Act I close), playable memory vignettes, NPC arcs, world-state changes and the endings framework (the four endings play only in the dev Ending theatre until Act V exists). Before that: **M7 District Production, batch 1** ([`Docs/M7_DISTRICT_REPORT.md`](Docs/M7_DISTRICT_REPORT.md), districts: [`DISTRICTS`](Docs/DISTRICTS.md)): Act I, the new **00 Undercity** opening and the completed **01 Lowlight**. Before that: **M6 Content Pipeline** ([`Docs/M6_CONTENT_PIPELINE_REPORT.md`](Docs/M6_CONTENT_PIPELINE_REPORT.md), how-to: [`CONTENT_PIPELINE`](Docs/CONTENT_PIPELINE.md)): validator, room templates, enemy modules, art pipeline, dev console. Before that: **M5 World Framework** ([`Docs/M5_WORLD_FRAMEWORK_REPORT.md`](Docs/M5_WORLD_FRAMEWORK_REPORT.md), [`ECONOMY`](Docs/ECONOMY.md)): map, transit, Nix, NPC/world state, economy audit. **M4 Validation:** the playtest tooling is built; the playtest itself needs external testers: see [`Docs/PLAYTEST_KIT.md`](Docs/PLAYTEST_KIT.md) and [`Docs/M4_VALIDATION_REPORT.md`](Docs/M4_VALIDATION_REPORT.md). The slice being tested: [`Docs/M3_VERTICAL_SLICE_REPORT.md`](Docs/M3_VERTICAL_SLICE_REPORT.md), [`Docs/M2_COMBAT_REPORT.md`](Docs/M2_COMBAT_REPORT.md) and [`Docs/M1_MOVEMENT_REPORT.md`](Docs/M1_MOVEMENT_REPORT.md).
- **All art and audio are placeholders** (D-026). Final assets must follow [`Docs/ART_BIBLE.md`](Docs/ART_BIBLE.md).
- Project logs: [`DECISIONS`](Docs/DECISIONS.md) · [`CHANGELOG`](Docs/CHANGELOG.md) · [`TODO`](Docs/TODO.md) · [`KNOWN_ISSUES`](Docs/KNOWN_ISSUES.md) · [`CIRCUITS`](Docs/CIRCUITS.md)

## Requirements
- Godot **4.3** or newer, the standard build (no .NET needed). No third-party addons.

## Run
Open `project.godot` in the Godot editor and press **F5**. The game boots to the title screen: **New Game** starts the Act I campaign unarmed in the Undercity (Wake), then the Relay and Lowlight up to Warden Krail. Debug builds also list **Slice (Relay start)**, the pre-M7 slice with the full kit. The Movement and Combat Labs are listed there too (**F12** cycles the labs). Controls are in the three reports, and **F1** shows the debug overlay.

## Test
```bash
godot --headless --import                                    # first run only: builds the script class cache
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn  # exit code 0 = all passed
```
`--fixed-fps 60` makes every frame exactly one physics tick. That keeps the movement tests deterministic and lets them run faster than real time.

## Dev tools
| Scene | Purpose |
|---|---|
| `devtools/MovementProbe.tscn` (headless) | Measures jump, slide, dodge and dash distances for every tuning preset |
| `devtools/CaptureTour.tscn` (needs a display, e.g. `xvfb-run`) | Scripted screenshot tour: `-- --out=/abs/dir [--tour=movement\|combat\|slice\|undercity\|ui\|story]` |
| `devtools/PerfProbe.tscn` (headless) | CPU cost per frame under fight load: `-- [--room=res://… --at=x:y,x:y]` (Combat Lab by default) |
| `devtools/RouteBot.gd` (used by `test_slice_routes`, `test_undercity_routes`, `test_lowlight_m7_routes`) | Plays a room with scripted input to prove its route is traversable |
| `devtools/content/ValidateContent.tscn` (headless) | Content + art validation (M8 adds the Story report: sequences, arcs, endings, memories, knowledge lint); exit code 1 on errors |
| `devtools/StoryTestKit.gd` (used by the M8 story tests and `--tour=story`) | Story helpers: flag sandbox, story-state presets, the Act I max state |
| ` (backquote) in game | Dev console: teleport, spawn, boss restart, unlock-all, inspector, hitboxes, perf graph; **Story…** pages (sequence, memory and ending theatres, story-state presets, arcs, sequence inspector) |
| `tools/roomgen/` (Python 3) | Room generators: `lowlight.py` (pre-M7 rooms), one `uc_*.py` / `ll_*.py` per M7 room, `fixtures_*.py` for test fixtures (`--check` for drift) |
| `devtools/PlaytestReport.tscn` (headless) | Builds the playtest report + heatmaps: `-- --in=<sessions dir> --out=<report dir>` |

## Layout
```
autoload/    EventBus, Settings, Game, SaveManager, AudioManager, SceneRouter, InputGlyphs, MusicDirector, Cinematics, Playtest
combat/      AttackData, ProjectileData, HitInfo, Hurtbox, Projectile, queries, layers
weapons/     WeaponData
circuits/    CircuitData (declarative stat modifiers)
progression/ GameState, ItemCatalog, shops, lore data, SliceStats
quests/      QuestData, QuestTracker (flag-derived)
dialogue/    NpcProfile, dialogue rules, NpcArc + ArcTracker (M8)
cinematics/  SequenceData, SequencePlayer, steps/, SkipGate, SpeakerTable, CinematicMode (M8)
story/       ActData, EndingData, EndingResolver, EndingDirector, FutureFlagSet, KnowledgeLint (M8)
interactables/ Interactable, pickups, caches, breakable walls, NPCs, repeaters, switches
bosses/      BossArena, Warden Krail, Collector Drone
audio/       MusicSynth (procedural stems)
playtest/    PlaytestSession, PlaytestConfig, PlaytestVariant, SurveyQuestion, PlaytestAnalyzer (M4)
player/      controller/ (Player, config, input, FSM), states/, combat/, reactor/, style/, animation/, abilities/
enemies/     base/ (Enemy, EnemyData, EnemyBehavior, EncounterDirector), modules/ (EnemyBrain + modules), variants/*.tscn
world/       rooms/ (Room, labs, undercity/*.tscn, lowlight/*.tscn), templates/ (room templates, metrics), map/ (world map data, fog, index), anchors/, transitions/, districts/, props/, hazards/ (spikes, scanners, chase), camera/, graybox/
data/        movement/, camera/, weapons/, enemies/, combat/, reactor/, style/, audio/, circuits/, shops/, npcs/, quests/, lore/, districts/, playtest/, world/, sequences/, memories/, arcs/, endings/, story/, dev/, catalog.tres
ui/          debug/ (overlay, tuning panel), hud/, menus/, dialogue/, map/, cinematic/, memory/
vfx/         dust, hit sparks, slash arcs, sprite sheets (SpriteSheetSpec, SpriteActor)
assets/      exported art (Art Bible §9; empty until final art)
tools/       roomgen (Python 3 room generator, dev only)
tests/       TestRunner + unit/test_*.gd + fixtures/
devtools/    lab controllers, movement probe, perf probe, capture tour, route bot, content/ validators, dev actions
Docs/        bible, Art Bible, M1–M8 reports, districts, content pipeline, playtest kit, Circuits, Economy, decision/changelog/todo/issue logs
```
Folders from the bible's architecture that later milestones will fill are kept with `.gitkeep`.
