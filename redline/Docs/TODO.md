# REDLINE TODO

## Now: M1 gate (humans)
- [ ] Playtest the Movement Lab with keyboard **and** a controller (Xbox or PlayStation layout). Use the checklist in `M1_MOVEMENT_REPORT.md`.
- [ ] Confirm or overrule the flagged decisions D-001, D-005 and D-009 in `DECISIONS.md`.
- [ ] Verify a stable 60 FPS on real hardware, at 60 Hz and at 120/144 Hz monitor refresh rates.
- [ ] Pick a default tuning preset, or ask for a blend of presets, after the playtest.
- [ ] Decide whether to move `redline/` to its own repository (D-001).

## M1 polish candidates (only if the playtest asks for them)
- [x] Physics interpolation experiment (Godot 4.3's 2D interpolation), or 120 Hz physics ticks. Toggles are on F7 and F8. **A human still needs to judge them on a 120/144 Hz display.**
- [ ] Let slides gain or lose speed on slopes.
- [ ] Footstep sounds for running (left out so far to avoid noise before the playtest).
- [ ] An optional brake or steer during a slide. It's fully committed right now.
- [x] An in-game tuning panel (F3).
- [x] Placeholder SFX for jump, land, slide, dodge and dash (synthesized from data).
- [x] Dust VFX for jump, land, slide and dash.
- [ ] Hard-landing roll when holding a direction (needs a design call).
- [ ] World-label font: a pixel font instead of the default font at 8 px.

## Framework (pulled forward only when needed)
- [ ] Rebinding UI. Persist remaps through `Settings` (bible §24).
- [ ] Controller glyph switching and hot-plug handling.
- [ ] A settings menu that calls `Settings.save_settings()`. Nothing saves settings yet.
- [ ] `AccessibilityConfig` resource once a menu exists.

## Do NOT start until M1 is signed off
- M2 Combat Lab: Pulse Blade, pistol, Scattergun, three enemies, hitstop, reactor prototype, style prototype.
