# REDLINE Known Issues

| # | Area | Issue | Severity | Notes |
|---|------|-------|----------|-------|
| K-1 | Validation | No human has played M1, M2 or the M3 slice yet. All checks so far are headless or scripted: 130 automated tests, a route bot, a movement probe, a performance probe and screenshot tours. How the game feels and how real input latency behaves are unverified. | High (process) | This is the M1/M2/M3 gate. See the reports' checklists. |
| K-2 | Performance | FPS was only observed under software rendering (Mesa llvmpipe in a virtual display), at about 45–55 FPS. That number doesn't represent real GPUs. CPU cost is measured headless by wall time per frame: about 0.6–0.9 ms idle, and under Combat Lab fight load 2.2 ms on average, 4.9 ms at p99 and 11 ms at worst (`devtools/PerfProbe.tscn`), against a 16.7 ms budget. **Correction:** the earlier "1.5 ms / 3.7 ms physics" figures came from `Performance.TIME_PHYSICS_PROCESS`, which is unreliable in fixed-fps headless runs. | Medium | Verify on real hardware, including GPU cost. |
| K-3 | Rendering | Physics runs at 60 Hz without interpolation by default, which may look juddery on 120/144 Hz displays. The F7 (interpolation) and F8 (120 Hz) toggles exist, but nobody has checked them on a high-refresh screen. Whether `Camera2D` is interpolated in 4.3 without jitter is also unverified. | Medium | Experiments in the report and D-011. |
| K-4 | Rendering | Camera and player positions aren't snapped to pixels (`snap_2d_transforms_to_pixel` is off). Sprites may shimmer by a subpixel once real art arrives. | Low | Revisit with sprites in M3. |
| K-5 | Movement | Slides are fully committed: you can't steer or brake, and slopes don't change slide speed. | Low | Design call after the playtest. |
| K-6 | Movement | Corner correction only applies to upward motion. There's no horizontal corner correction for dashes clipping ledge lips. | Low | Add it if playtesters snag on corners. |
| K-7 | Settings | ~~Nothing saves settings.~~ Fixed in M3: the settings menu saves. Input rebinding still doesn't exist. | Low | Rebinding is in TODO. |
| K-8 | Input | Debug hotkeys F2–F12 (and the mouse-driven tuning panel) are keyboard-only. | Info | Dev tools only (D-006). |
| K-9 | UI | World-space station labels use the default font at 8 px and look soft. | Info | Placeholder. |
| K-10 | Tests | The class cache has to exist before tests run: `godot --headless --import` must run once on a fresh clone. | Info | Documented in the README. |
| K-11 | Audio | The SFX are synthesized placeholder blips: good enough to judge timing, not tone. The mix levels haven't been tuned on speakers. | Info | Real sounds replace them through `override_stream`. |
| K-12 | Tools | Tuning panel sliders use each property's export range, or 0–3× its current value. To go beyond that range, edit the `.tres` file. Collision sizes aren't on the panel because they need `apply_config`. | Info | By design. |
| K-13 | Tools | Saving from the panel while the default preset is active rewrites `data/movement/default_movement.tres`. Commit only the tuning changes you mean to keep. | Info | Revert (or `git checkout`) undoes it. |
| K-14 | Combat | The numbers (damage, hitstop, telegraphs, core drain) haven't been felt by a person. | High (process) | M2 gate. |
| K-15 | Combat | Enemies pass through Rook, and Rook can stand inside them (D-024). | Low | Design call after the playtest. |
| K-16 | Combat | No parry or executions yet. Heal injectors and an elite (Enforcer) arrived in M3. | Info | Later milestones. |
| K-17 | Tools | The F3 tuning panel covers movement only. Combat data is edited in `.tres` files; F5 reloads movement only, so restart to pick up weapon/enemy edits. | Low | Follow-up in TODO. |
| K-18 | Engine | In Godot 4.3, calling a method on a freed *typed* reference crashes the engine instead of raising an error. Code must check `is_instance_valid` before touching any object that might have been freed (projectile shooters, credited attackers). | Medium | See CLAUDE.md conventions. |
| K-19 | Audio | Quitting while a sound is playing reports one leaked `AudioStreamPlaybackWAV`. It's harmless, even though voices are stopped in `_exit_tree`. | Info | Engine-side. |
| K-20 | Performance | Spawning enemies and first-use effects cause one 11 ms frame. There's no pooling yet. | Low | Pool if it shows up on real hardware. |
| K-21 | Lab | Combat Lab station labels and the debug overlay overlap on some views. F1 hides the overlay. | Info | Placeholder layout. |
| K-22 | Art/Audio | **Everything is placeholder** (D-026): rectangles, props, a procedural skyline, synthesized SFX and music. Bible M3 asks for production quality; that has to come from artists and composers, following `ART_BIBLE.md`. | High (process) | Human decision in TODO. |
| K-23 | Content | The slice may be shorter than the bible's 15–25 min: pure bot traversal takes ≈ 2 min. Real play time is unmeasured. | Medium | Measure in the playtest (end card), then decide on D-028 options. |
| K-24 | Movement | A slide-jump beats a run-jump by only about 8–15 px, and only when it's timed at the lip. A late slide does worse than a run-jump. The Neon Roofs gap is a teaching gap, not a gate (D-036). | Medium | Tuning call after the playtest. |
| K-25 | Audio | The music stems are rendered at startup on a worker thread (1.3 s of CPU on the 4-core build container). Music fades in once they're ready. Headless runs skip it, so no automated test hears the final mix. | Low | Real stems replace it (Art Bible §10). |
| K-26 | World | There's no map, fast travel or objective markers (D-033). The only shortcut is the Bell Tower lift back to the Relay. | Medium | M5 scope. Watch the "did you get lost?" answers. |
| K-27 | World | Dying again before you recover a Scrap cache loses the older cache (D-031). This is intended, but it can feel harsh. The Settings toggle turns Scrap loss off. | Info | Design confirmation wanted. |
| K-28 | Tools | `RouteBot` proves that rooms are *traversable* with enemies disabled. It doesn't prove they're fun or fair with enemies on, and it doesn't fight the boss (boss behavior has its own tests). | Info | By design. Humans judge fights. |
| K-29 | UI | Menus and hints use the default font at native resolution. There's no pixel font or final UI art yet. Long hint strings can wrap near the screen edges on narrow aspect ratios (only 16:9 has been checked). | Low | UI art pass. |
| K-30 | Playtest | Frame times are wall-clock per rendered frame, including vsync waits. On a 60 Hz display the average reads ~16.7 ms even with headroom. Use the spike counts and the 33 ms+ buckets as the stutter signal. | Info | By design; documented in the report. |
| K-31 | Playtest | Idle-span detection can't tell reading or thinking from being lost. | Info | Cross-check with moments and facilitator notes. |
| K-32 | Playtest | The first frames after a room load include one-off loading spikes (e.g. one 55 ms frame entering the Warden Tower in a bot run). | Low | Repeated spikes are the problem; singles on entry are expected. |
| K-33 | Playtest | A crash keeps the session up to the last autosave (every 20 s, and on every death). | Info | `autosave_interval` in `PlaytestConfig`. |
| K-34 | Playtest | No exported build is committed: `export_presets.cfg` stays gitignored, and export templates must be installed in the editor. | Info | Steps in `PLAYTEST_KIT.md` §2. |
| K-35 | Map | The map redraws every explored cell and geometry piece each frame. Fine for 7 rooms; with many districts it should be cached. | Low | TODO. |
| K-36 | Map | The cursor pans freely; it doesn't snap to rooms or icons. At the widest zoom, small icons overlap. | Low | Human check. |
| K-37 | Map | The labs have no map (the map is world rooms only). | Info | By design. |
| K-38 | Transit | Travel starts only from an Anchor menu, not from the map (D-047). | Low | Design call. |
| K-39 | Tools | The slice's room `.tscn` files were produced by a Python generator that isn't committed. The scenes are the source of truth and editable in Godot, but bulk layout edits are manual until M6 tooling. | Medium | M6 content pipeline. |

