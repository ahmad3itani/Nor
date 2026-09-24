# REDLINE

A high-speed 2D pixel-art action platformer set in the megacity of Veyra, built with Godot 4.
**Movement is life. Violence buys time. Curiosity reveals the truth.**

- Design source of truth: [`Docs/DESIGN_BIBLE.md`](Docs/DESIGN_BIBLE.md)
- Current milestone: **M1 Movement Lab**, waiting on a human playtest. See [`Docs/M1_MOVEMENT_REPORT.md`](Docs/M1_MOVEMENT_REPORT.md).
- Project logs: [`DECISIONS`](Docs/DECISIONS.md) · [`CHANGELOG`](Docs/CHANGELOG.md) · [`TODO`](Docs/TODO.md) · [`KNOWN_ISSUES`](Docs/KNOWN_ISSUES.md)

## Requirements
- Godot **4.3** or newer, the standard build (no .NET needed). No third-party addons.

## Run
Open `project.godot` in the Godot editor and press **F5**. The game boots into the Movement Lab. The controls are listed in the M1 report, and **F1** shows the debug overlay.

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
| `devtools/CaptureTour.tscn` (needs a display, e.g. `xvfb-run`) | Scripted screenshot tour: `-- --out=/abs/dir` |

## Layout
```
autoload/    EventBus, Settings, Game, SaveManager, AudioManager, SceneRouter
player/      controller/ (Player, config, input, FSM), states/, animation/, abilities/
world/       rooms/ (Room, SpawnMarker, MovementLab), camera/, graybox/
data/        movement/*.tres tuning presets, camera/*.tres
ui/debug/    DebugOverlay
tests/       TestRunner + unit/test_*.gd
devtools/    lab hotkeys, probe, capture tour
Docs/        bible, report, decision/changelog/todo/issue logs
```
Empty folders from the bible's architecture (enemies/, weapons/, circuits/, …) are kept with `.gitkeep` for later milestones.
