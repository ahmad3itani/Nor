# REDLINE Known Issues

| # | Area | Issue | Severity | Notes |
|---|------|-------|----------|-------|
| K-1 | Validation | No human has played M1 yet. All checks so far are headless or scripted: 37 automated tests, a movement probe and a screenshot tour. How the game feels and how real input latency behaves are unverified. | High (process) | This is the M1 gate. See the report's checklist. |
| K-2 | Performance | FPS was only observed under software rendering (Mesa llvmpipe in a virtual display), at about 45–55 FPS. That number doesn't represent real GPUs. Headless physics costs 1.5 ms per tick on average and 3.7 ms at worst during repeated slides with dust and audio, against a 16.7 ms budget. | Medium | Verify on real hardware. |
| K-3 | Rendering | Physics runs at 60 Hz without interpolation by default, which may look juddery on 120/144 Hz displays. The F7 (interpolation) and F8 (120 Hz) toggles exist, but nobody has checked them on a high-refresh screen. Whether `Camera2D` is interpolated in 4.3 without jitter is also unverified. | Medium | Experiments in the report and D-011. |
| K-4 | Rendering | Camera and player positions aren't snapped to pixels (`snap_2d_transforms_to_pixel` is off). Sprites may shimmer by a subpixel once real art arrives. | Low | Revisit with sprites in M3. |
| K-5 | Movement | Slides are fully committed: you can't steer or brake, and slopes don't change slide speed. | Low | Design call after the playtest. |
| K-6 | Movement | Corner correction only applies to upward motion. There's no horizontal corner correction for dashes clipping ledge lips. | Low | Add it if playtesters snag on corners. |
| K-7 | Settings | Nothing saves settings yet (there's no menu). The overlay toggle changes the in-memory value only. | Low | Add with the settings menu. |
| K-8 | Input | Debug hotkeys F2–F8 (and the mouse-driven tuning panel) are keyboard-only. | Info | Dev tools only (D-006). |
| K-9 | UI | World-space station labels use the default font at 8 px and look soft. | Info | Placeholder. |
| K-10 | Tests | The class cache has to exist before tests run: `godot --headless --import` must run once on a fresh clone. | Info | Documented in the README. |
| K-11 | Audio | The SFX are synthesized placeholder blips: good enough to judge timing, not tone. The mix levels haven't been tuned on speakers. | Info | Real sounds replace them through `override_stream`. |
| K-12 | Tools | Tuning panel sliders use each property's export range, or 0–3× its current value. To go beyond that range, edit the `.tres` file. Collision sizes aren't on the panel because they need `apply_config`. | Info | By design. |
| K-13 | Tools | Saving from the panel while the default preset is active rewrites `data/movement/default_movement.tres`. Commit only the tuning changes you mean to keep. | Info | Revert (or `git checkout`) undoes it. |
