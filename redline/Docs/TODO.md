# REDLINE TODO

## Now: run the M4 playtest (humans)
- [ ] Recruit 5–8 external testers (2+ on a controller, 1+ non-dev machine) and run sessions as described in `PLAYTEST_KIT.md`.
- [ ] Collect the `session_*.json` files and note sheets, then run `devtools/PlaytestReport.tscn`.
- [ ] Confirm or overrule D-038 to D-041 (especially D-039 recording default and D-041 §44 thresholds).
- [ ] Send the report and notes back. Next: data-driven changes per failing §44 line, then a second round.
- [ ] Pick the slide-jump arm from the variant comparison and moments (D-036/D-042).

## M4 follow-ups (after the first round)
- [ ] Switch recording default off for any public/demo build (D-039).
- [ ] Add the next experiment arm only after D-036 is decided (D-042).
- [ ] If testers quit early, record a lighter "exit survey" on quit to title.

## M3 gate, the §44 vertical-slice test (humans; run it with the M4 kit)
- [ ] External playtesters play New Game → end card. Use the checklist in `M3_VERTICAL_SLICE_REPORT.md` §6 and record the end-card time and deaths.
- [ ] Confirm or overrule the flagged decisions D-026 (placeholder art/audio), D-027, D-028 (6 of 10 rooms), D-033 (no map) and D-036 (slide-jump strength) in `DECISIONS.md`.
- [ ] Decide who produces the production art and audio, and whether §44 runs on placeholders (D-026).
- [ ] If the slice runs short of ~15 min, pick the next rooms: Power Block and Rainline Chase are the recommended ones (D-028).
- [ ] The M1 and M2 gates below are still open. The slice exercises both labs' systems, so one playtest can cover all three.
- [ ] Do **not** start M4+ until the slice passes §44.

## M3 follow-ups (only if the playtest asks for them)
- [ ] Slide-jump strength (`slide_jump_bonus` / `slide_jump_height_ratio`, D-036).
- [ ] More Lowlight rooms (D-028), and more Circuits toward the 60–80 target.
- [ ] Saved loadout presets (bible §11) once there are enough Circuits to need them.
- [ ] Map and fast travel (M5 scope, D-033), and Nix, if playtesters get lost.
- [ ] Parry and executions (bible §8): not started.
- [ ] Rebinding UI (bible §24). Settings now save, but there's no remapping yet.
- [ ] A pixel font for world labels and hints.

## M2 gate (humans), covering M1 too
- [ ] Playtest the Combat Lab with keyboard **and** a controller. Use the checklist in `M2_COMBAT_REPORT.md`.
- [ ] Confirm or overrule the flagged decisions D-016, D-018 and D-022 in `DECISIONS.md`.
- [ ] Judge core pressure (F11 modes) and the style rank's legibility.
- [x] ~~Do not start M3 until both labs pass the playtest.~~ M3 was started on request, before the M1/M2 playtest.

## M2 follow-ups (only if the playtest asks for them)
- [ ] A combat tuning panel: extend the F3 panel to the active weapon's `AttackData`.
- [ ] Enemy body blocking or a "shove" (D-024).
- [ ] Pool projectiles and particles if profiling on real hardware shows spikes. The 11 ms max happens on respawn.
- [ ] Parry (bible §8, midgame) and executions. Healing injectors and an elite (Enforcer) arrived in M3.
- [ ] Use `score_multiplier` once challenge scoring exists (M9).

## M1 gate (humans)
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
- [x] Controller glyph switching (`InputGlyphs`, M3). Hot-plug handling is untested.
- [x] A settings menu that calls `Settings.save_settings()` (M3).
- [ ] `AccessibilityConfig` resource once a menu exists.

## Do NOT start until the slice passes §44
- M4 Validation changes, M5 World Framework (map, fast travel, more NPCs), M6 content pipeline, and district production. Bible §44: "If these fail, fix the core instead of producing more content."
