# REDLINE TODO

## Now: humans
- [ ] The M4 playtest (`PLAYTEST_KIT.md`) is still the gate before M7 batch 2 (Ironworks and later, bible §44). Export playtest builds as **release** so the dev console is off (D-059).
- [ ] **Decide which build the playtest uses (D-068):** the Act I campaign (New Game from the Undercity, about 20–37 min before the Relay) or the old slice (Relay start, debug builds only, K-58).
- [ ] Confirm or overrule the M7 flags: D-061 (M7 before §44), D-062 (Undercity opening, unarmed start), D-063 (pre-Anchor entry respawn), D-068, D-072 (scanners respect i-frames), D-073 (one chase system), D-074 (Rainline G3 slide-jump), D-075 (Smuggler Route order), D-076 (Iko moves to the Relay), D-079 (Collector = first mini-boss), D-082 (shards/secrets/fragments), D-083 (pacing), D-085 (Challenge FZ3), D-087/D-090 (no schema bump), D-093 (air swings hang only on hit), D-101 (the Undercity combines after its boss), D-102 (the Undercity is linear).
- [ ] Try the M6 editor tools in Godot: drop `GapChallenge`, `ClimbSteps`, `Doorway` and `JumpArcPreview` into a room and check the baking, rebuilds and warnings (K-40).
- [ ] Confirm or overrule D-053 (M6 before §44) and D-056 (Python generator as a dev dependency).

## M7 batch 1 follow-ups (Undercity + Lowlight)
- [ ] Playtest checks: the Undercity timeline against §42 (K-45); whether the Collector eye still threatens (K-54); the Collector's fight length (K-56); Rainline G3 catches (K-44); air juggling after D-093; heads bumping under Power Block's shaft lips (D-098).
- [ ] If the median Relay arrival is under ~25 min: deepen Medical Ruin and First Pursuit (D-083).
- [ ] Widen `test_tunnel_dash_shard_negative_sweep` like the Smuggler/alley sweeps (every air-dodge frame, late take-offs); lower the ledge if it leaks (K-48).
- [ ] `PowerShutter`: report low passes against the slot clock, so S4b stops reading as a close call (K-52, D-099).
- [ ] `test_pb_b3_reach` could add a Hot Wire case now that the circuit exists (D5a landed after Power Block).
- [ ] `DevActions` grant-kit sets `injector_upgrades` but not `injector_upgrades_bootleg`, so the debug kit lacks Iko's charge.
- [ ] RouteBot: a stationary diagonal aim for multi-shot volleys (K-57).
- [ ] Escape Tunnel pistol lesson: widen the diagonal hit band and sweep it in a test (K-61).
- [ ] Power Block: a respawn near the L0 entrance (K-62).
- [ ] Chase, scanner, clamp and tracker numbers still in code: move them to their data resources (K-63).
- [ ] **Boss Assist** (M9): an Assist-mode option for bosses (slower telegraphs or more pips), announced, never silent (§23).
- [ ] **`timing_assist` setting** (not built, D-073): an announced option that scales pursuer speed and shutter clocks. §23 forbids silent difficulty changes.
- [ ] **Rising-flood pursuer** (deferred): a second `PursuerData` style for a later district.
- [ ] Deferred mechanics, build them when a room needs one (D-078): PowerJunction, LaserGrid, SecurityCamera, AlarmSystem, MovingPlatform, CollapsingPlatform (also CoreConduit, RadioTerminal, the OnboardingValidator, the Shaft Sentinel mini-boss, RouteBot `await`).
- [ ] Final art: banner lettering, the chest-clamp chairs, a bracket for Orr's Escape Tunnel radio (K-53); check the Undercity sea-green against healing green (K-46) and the seepage rain (K-47).
- [ ] Sinks before enemies: the next district needs new stock before any new respawning enemy (K-49).
- [x] Iko's shop stock (D5a), the Undercity intros and The Way Up (D4), the economy audit (D5b), the full Undercity and Lowlight walks (D6), final chart thresholds (D8b).

## M6 follow-ups
- [ ] More modules as enemies need them (patrol, dive, group spacing, retreat: bible §32).
- [ ] An enemy journal (bible §16) fed by EnemyData and kill counters.
- [ ] Room metadata editor dock and camera zones (bible §34, not yet needed).

## M4 playtest (humans, now covers M5 too)
- [ ] Run the playtest (`PLAYTEST_KIT.md`). Also watch whether testers open the map, where, and whether pins and transit get used.
- [ ] Confirm or overrule D-044 (M5 before §44), D-047 (transit gating), D-049 (economy targets) and D-051 (View button).

## M5 follow-ups
- [ ] Cache the map drawing into a texture once there are many districts (K-35).
- [ ] Travel from the map screen, if D-047 says so.
- [x] Room-authoring tooling committed in M6 (`tools/roomgen`, templates).
- [ ] Saved Circuit loadout presets (bible §11), once there are more Circuits.

## M4 playtest (humans)
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
- [ ] External playtesters play the build chosen in D-068 (New Game is now the Undercity campaign; the old Relay-start slice is the debug-only "Slice (Relay start)" entry) → end card. Use the checklist in `M3_VERTICAL_SLICE_REPORT.md` §6 and record the end-card time and deaths.
- [ ] Confirm or overrule the flagged decisions D-026 (placeholder art/audio), D-027, D-028 (6 of 10 rooms), D-033 (no map) and D-036 (slide-jump strength) in `DECISIONS.md`.
- [ ] Decide who produces the production art and audio, and whether §44 runs on placeholders (D-026).
- [x] ~~If the slice runs short of ~15 min, pick the next rooms: Power Block and Rainline Chase (D-028).~~ Built in M7 batch 1, with Security Station and the Smuggler Route.
- [ ] The M1 and M2 gates below are still open. The slice exercises both labs' systems, so one playtest can cover all three.
- [ ] Do **not** start M4+ until the slice passes §44.

## M3 follow-ups (only if the playtest asks for them)
- [ ] Slide-jump strength (`slide_jump_bonus` / `slide_jump_height_ratio`, D-036).
- [x] ~~More Lowlight rooms (D-028)~~: Lowlight is complete since M7 batch 1.
- [ ] More Circuits toward the 60–80 target.
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
- M7 batch 2+ (Ironworks and later districts). Bible §44: "If these fail, fix the core instead of producing more content." M5, M6 and M7 batch 1 were built on request before the playtest (D-044, D-053, D-061).
