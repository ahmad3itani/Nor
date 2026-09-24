# REDLINE Known Issues

| # | Area | Issue | Severity | Notes |
|---|------|-------|----------|-------|
| K-1 | Validation | No human has played M1 yet. All checks so far are headless or scripted: 29 automated tests, a movement probe and a screenshot tour. How the game feels and how real input latency behaves are unverified. | High (process) | This is the M1 gate. See the report's checklist. |
| K-2 | Performance | FPS was only observed under software rendering (Mesa llvmpipe in a virtual display), at about 45–55 FPS. That number doesn't represent real GPUs. Physics costs about 1 ms per tick. | Medium | Verify on real hardware. |
| K-3 | Rendering | Physics runs at 60 Hz without interpolation, which may look juddery on 120/144 Hz displays. | Medium | Experiments in the report and D-011. |
| K-4 | Rendering | Camera and player positions aren't snapped to pixels (`snap_2d_transforms_to_pixel` is off). Sprites may shimmer by a subpixel once real art arrives. | Low | Revisit with sprites in M3. |
| K-5 | Movement | Slides are fully committed: you can't steer or brake, and slopes don't change slide speed. | Low | Design call after the playtest. |
| K-6 | Movement | Corner correction only applies to upward motion. There's no horizontal corner correction for dashes clipping ledge lips. | Low | Add it if playtesters snag on corners. |
| K-7 | Settings | Nothing saves settings yet (there's no menu). The overlay toggle changes the in-memory value only. | Low | Add with the settings menu. |
| K-8 | Input | Debug hotkeys F2, F4, F5 and F6 are keyboard-only. | Info | Dev tools only (D-006). |
| K-9 | UI | World-space station labels use the default font at 8 px and look soft. | Info | Placeholder. |
| K-10 | Tests | The class cache has to exist before tests run: `godot --headless --import` must run once on a fresh clone. | Info | Documented in the README. |
