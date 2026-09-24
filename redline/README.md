# REDLINE

A high-speed 2D pixel-art action platformer set in the megacity of Veyra, built with Godot 4.
**Movement is life. Violence buys time. Curiosity reveals the truth.**

- Design source of truth: [`Docs/DESIGN_BIBLE.md`](Docs/DESIGN_BIBLE.md)
- Current milestone: **M4 Validation**. The playtest tooling is built; the playtest itself needs external testers: see [`Docs/PLAYTEST_KIT.md`](Docs/PLAYTEST_KIT.md) and [`Docs/M4_VALIDATION_REPORT.md`](Docs/M4_VALIDATION_REPORT.md). The slice being tested: [`Docs/M3_VERTICAL_SLICE_REPORT.md`](Docs/M3_VERTICAL_SLICE_REPORT.md), [`Docs/M2_COMBAT_REPORT.md`](Docs/M2_COMBAT_REPORT.md) and [`Docs/M1_MOVEMENT_REPORT.md`](Docs/M1_MOVEMENT_REPORT.md).
- **All art and audio are placeholders** (D-026). Final assets must follow [`Docs/ART_BIBLE.md`](Docs/ART_BIBLE.md).
- Project logs: [`DECISIONS`](Docs/DECISIONS.md) · [`CHANGELOG`](Docs/CHANGELOG.md) · [`TODO`](Docs/TODO.md) · [`KNOWN_ISSUES`](Docs/KNOWN_ISSUES.md) · [`CIRCUITS`](Docs/CIRCUITS.md)

## Requirements
- Godot **4.3** or newer, the standard build (no .NET needed). No third-party addons.

## Run
Open `project.godot` in the Godot editor and press **F5**. The game boots to the title screen: **New Game** starts the vertical slice, and the Movement and Combat Labs are listed there too (**F12** cycles the labs). Controls are in the three reports, and **F1** shows the debug overlay.

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
| `devtools/CaptureTour.tscn` (needs a display, e.g. `xvfb-run`) | Scripted screenshot tour: `-- --out=/abs/dir [--tour=movement\|combat\|slice\|ui]` |
| `devtools/PerfProbe.tscn` (headless) | CPU cost per frame under fight load: `-- [--room=res://… --at=x:y,x:y]` (Combat Lab by default) |
| `devtools/RouteBot.gd` (used by `test_slice_routes`) | Plays a room with scripted input to prove its route is traversable |
| `devtools/PlaytestReport.tscn` (headless) | Builds the playtest report + heatmaps: `-- --in=<sessions dir> --out=<report dir>` |

## Layout
```
autoload/    EventBus, Settings, Game, SaveManager, AudioManager, SceneRouter, InputGlyphs, MusicDirector, Playtest
combat/      AttackData, ProjectileData, HitInfo, Hurtbox, Projectile, queries, layers
weapons/     WeaponData
circuits/    CircuitData (declarative stat modifiers)
progression/ GameState, ItemCatalog, shops, lore data, SliceStats
quests/      QuestData, QuestTracker (flag-derived)
dialogue/    NpcProfile, dialogue rules
interactables/ Interactable, pickups, caches, breakable walls, NPCs, repeaters, switches
bosses/      BossArena, Warden Krail
audio/       MusicSynth (procedural stems)
playtest/    PlaytestSession, PlaytestConfig, PlaytestVariant, SurveyQuestion, PlaytestAnalyzer (M4)
player/      controller/ (Player, config, input, FSM), states/, combat/, reactor/, style/, animation/, abilities/
enemies/     base/ (Enemy, EnemyData, EnemyBehavior, EncounterDirector), behaviors/, variants/*.tscn
world/       rooms/ (Room, labs, lowlight/*.tscn), anchors/, transitions/, districts/, props/, hazards/, camera/, graybox/
data/        movement/, camera/, weapons/, enemies/, combat/, reactor/, style/, audio/, circuits/, shops/, npcs/, quests/, lore/, districts/, playtest/, catalog.tres
ui/          debug/ (overlay, tuning panel), hud/, menus/, dialogue/
vfx/         dust, hit sparks, slash arcs
tests/       TestRunner + unit/test_*.gd + fixtures/
devtools/    lab controllers, movement probe, perf probe, capture tour, route bot
Docs/        bible, Art Bible, M1–M4 reports, playtest kit, Circuits, decision/changelog/todo/issue logs
```
Folders from the bible's architecture that later milestones will fill are kept with `.gitkeep`.
