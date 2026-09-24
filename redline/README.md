# REDLINE

A high-speed 2D pixel-art action platformer set in the megacity of Veyra, built with Godot 4.
**Movement is life. Violence buys time. Curiosity reveals the truth.**

- Design source of truth: [`Docs/DESIGN_BIBLE.md`](Docs/DESIGN_BIBLE.md)
- Current milestone: **M2 Combat Lab**, waiting on a human playtest along with M1. See [`Docs/M2_COMBAT_REPORT.md`](Docs/M2_COMBAT_REPORT.md) and [`Docs/M1_MOVEMENT_REPORT.md`](Docs/M1_MOVEMENT_REPORT.md).
- Project logs: [`DECISIONS`](Docs/DECISIONS.md) · [`CHANGELOG`](Docs/CHANGELOG.md) · [`TODO`](Docs/TODO.md) · [`KNOWN_ISSUES`](Docs/KNOWN_ISSUES.md)

## Requirements
- Godot **4.3** or newer, the standard build (no .NET needed). No third-party addons.

## Run
Open `project.godot` in the Godot editor and press **F5**. The game boots into the **Combat Lab**, and **F12** switches to the Movement Lab. The controls are listed in both reports, and **F1** shows the debug overlay.

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
| `devtools/CaptureTour.tscn` (needs a display, e.g. `xvfb-run`) | Scripted screenshot tour: `-- --out=/abs/dir [--tour=combat]` |
| `devtools/PerfProbe.tscn` (headless) | CPU cost per frame in the Combat Lab under fight load |

## Layout
```
autoload/    EventBus, Settings, Game, SaveManager, AudioManager, SceneRouter
combat/      AttackData, ProjectileData, HitInfo, Hurtbox, Projectile, queries, layers
weapons/     WeaponData
player/      controller/ (Player, config, input, FSM), states/, combat/, reactor/, style/, animation/, abilities/
enemies/     base/ (Enemy, EnemyData, EnemyBehavior, EncounterDirector), behaviors/, variants/*.tscn
world/       rooms/ (Room, labs, FlowZone, EnemySpawner, SpawnMarker), hazards/, camera/, graybox/
data/        movement/, camera/, weapons/, enemies/, combat/, reactor/, style/, audio/ (.tres)
ui/          debug/ (overlay, tuning panel), hud/
vfx/         dust, hit sparks, slash arcs
tests/       TestRunner + unit/test_*.gd
devtools/    lab hotkeys, movement probe, perf probe, capture tour
Docs/        bible, M1/M2 reports, decision/changelog/todo/issue logs
```
Empty folders from the bible's architecture (circuits/, quests/, dialogue/, bosses/, …) are kept with `.gitkeep` for later milestones.
