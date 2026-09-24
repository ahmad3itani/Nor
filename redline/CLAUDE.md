# CLAUDE.md: REDLINE (Godot project)

`redline/` is a standalone Godot 4.3 game project. It is unrelated to the Nor Next.js app in the parent directory.

## Before any change
- Read `Docs/DESIGN_BIBLE.md` and follow its §37 rules. The most important ones:
  - Don't implement future milestones unless asked.
  - Tuning and content belong in Resources (`data/`), not in code.
  - Keep keyboard and controller parity.
  - Commit in small logical units.
  - Flag conflicts with the bible in `Docs/DECISIONS.md` instead of silently changing the design.
- Current state: M0 and M1 are done. **Work is stopped for human playtesting. Do not start M2 (combat) unless the user asks.**
- Keep `Docs/DECISIONS.md`, `CHANGELOG.md`, `TODO.md` and `KNOWN_ISSUES.md` up to date.

## Commands (run inside `redline/`)
```bash
godot --headless --import                                          # once per fresh clone (class cache)
godot --headless --fixed-fps 60 res://tests/TestRunner.tscn        # all tests; must pass before pushing
godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn  # movement metrics per preset
xvfb-run -a godot --fixed-fps 60 --rendering-driver opengl3 res://devtools/CaptureTour.tscn -- --out=/abs/dir
```

## Conventions
- GDScript uses static typing and tabs. Comments explain design intent, not syntax.
- Movement: `Player.gd` is the motor (timers, stance, physics helpers), and `player/states/*.gd` holds one mode each. States read `PlayerInputFrame`, never `Input`.
- New tests go in `tests/unit/test_*.gd` and extend `RedlineTestCase`, using `check()` and `check_near()`. Use `ScriptedInputSource` to drive the player.
- EventBus signals must be explicit and typed. Never add a generic event channel.
