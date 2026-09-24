# REDLINE Known Issues

| # | Area | Issue | Severity | Notes |
|---|------|-------|----------|-------|
| K-1 | Validation | No human has played M1 or M2 yet. All checks so far are headless or scripted: 71 automated tests, a movement probe, a performance probe and screenshot tours. How the game feels and how real input latency behaves are unverified. | High (process) | This is the M1/M2 gate. See both reports' checklists. |
| K-2 | Performance | FPS was only observed under software rendering (Mesa llvmpipe in a virtual display), at about 45–55 FPS. That number doesn't represent real GPUs. CPU cost is measured headless by wall time per frame: about 0.6–0.9 ms idle, and under Combat Lab fight load 2.2 ms on average, 4.9 ms at p99 and 11 ms at worst (`devtools/PerfProbe.tscn`), against a 16.7 ms budget. **Correction:** the earlier "1.5 ms / 3.7 ms physics" figures came from `Performance.TIME_PHYSICS_PROCESS`, which is unreliable in fixed-fps headless runs. | Medium | Verify on real hardware, including GPU cost. |
| K-3 | Rendering | Physics runs at 60 Hz without interpolation by default, which may look juddery on 120/144 Hz displays. The F7 (interpolation) and F8 (120 Hz) toggles exist, but nobody has checked them on a high-refresh screen. Whether `Camera2D` is interpolated in 4.3 without jitter is also unverified. | Medium | Experiments in the report and D-011. |
| K-4 | Rendering | Camera and player positions aren't snapped to pixels (`snap_2d_transforms_to_pixel` is off). Sprites may shimmer by a subpixel once real art arrives. | Low | Revisit with sprites in M3. |
| K-5 | Movement | Slides are fully committed: you can't steer or brake, and slopes don't change slide speed. | Low | Design call after the playtest. |
| K-6 | Movement | Corner correction only applies to upward motion. There's no horizontal corner correction for dashes clipping ledge lips. | Low | Add it if playtesters snag on corners. |
| K-7 | Settings | Nothing saves settings yet (there's no menu). The overlay toggle changes the in-memory value only. | Low | Add with the settings menu. |
| K-8 | Input | Debug hotkeys F2–F12 (and the mouse-driven tuning panel) are keyboard-only. | Info | Dev tools only (D-006). |
| K-9 | UI | World-space station labels use the default font at 8 px and look soft. | Info | Placeholder. |
| K-10 | Tests | The class cache has to exist before tests run: `godot --headless --import` must run once on a fresh clone. | Info | Documented in the README. |
| K-11 | Audio | The SFX are synthesized placeholder blips: good enough to judge timing, not tone. The mix levels haven't been tuned on speakers. | Info | Real sounds replace them through `override_stream`. |
| K-12 | Tools | Tuning panel sliders use each property's export range, or 0–3× its current value. To go beyond that range, edit the `.tres` file. Collision sizes aren't on the panel because they need `apply_config`. | Info | By design. |
| K-13 | Tools | Saving from the panel while the default preset is active rewrites `data/movement/default_movement.tres`. Commit only the tuning changes you mean to keep. | Info | Revert (or `git checkout`) undoes it. |
| K-14 | Combat | The numbers (damage, hitstop, telegraphs, core drain) haven't been felt by a person. | High (process) | M2 gate. |
| K-15 | Combat | Enemies pass through Rook, and Rook can stand inside them (D-024). | Low | Design call after the playtest. |
| K-16 | Combat | No parry, heal injectors, executions or elites yet. | Info | Later milestones. |
| K-17 | Tools | The F3 tuning panel covers movement only. Combat data is edited in `.tres` files; F5 reloads movement only, so restart to pick up weapon/enemy edits. | Low | Follow-up in TODO. |
| K-18 | Engine | In Godot 4.3, calling a method on a freed *typed* reference crashes the engine instead of raising an error. Code must check `is_instance_valid` before touching any object that might have been freed (projectile shooters, credited attackers). | Medium | See CLAUDE.md conventions. |
| K-19 | Audio | Quitting while a sound is playing reports one leaked `AudioStreamPlaybackWAV`. It's harmless, even though voices are stopped in `_exit_tree`. | Info | Engine-side. |
| K-20 | Performance | Spawning enemies and first-use effects cause one 11 ms frame. There's no pooling yet. | Low | Pool if it shows up on real hardware. |
| K-21 | Lab | Combat Lab station labels and the debug overlay overlap on some views. F1 hides the overlay. | Info | Placeholder layout. |
