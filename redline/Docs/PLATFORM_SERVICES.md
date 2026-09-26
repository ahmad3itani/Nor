# Platform services (M9)

REDLINE's achievements, stats, rich presence, leaderboard mirroring and cloud-save hooks sit behind one `Platform` autoload and one `PlatformBackend` interface. **Only the local backend ships.** There is no storefront SDK, no GodotSteam and no networking anywhere (D-141, bible §37.7: gameplay never depends on a platform API). A storefront adapter is a documented slot (below), to be built only after a human decision.

## Layout

| Path | Role |
|---|---|
| `autoload/Platform.gd` | Public API, gates, lazy store, pending-toast queue, DebugOverlay lines. Loads after `Cinematics`, before `Challenges` and `Playtest`. |
| `platform/PlatformBackend.gd` | Interface: every method a virtual no-op. |
| `platform/LocalPlatformBackend.gd` | The shipped backend. Mirrors nothing (the local store is the truth); keeps presence in memory. |
| `platform/PlatformBackends.gd` | Factory. `&"local"` only; any other id warns and plays on local. |
| `platform/LocalStore.gd` | `achievements.json` (below), through `progression/AtomicJson.gd`. |
| `platform/StatsTracker.gd` | Stat bookkeeping and feat detectors (EventBus listener). |
| `platform/AchievementTracker.gd` | Unlock evaluation (EventBus listener). |
| `platform/PresenceTracker.gd` | Rich-presence status. |
| `platform/AchievementData.gd`, `AchievementLibrary.gd` | One achievement; the sorted, cached list of `data/achievements/*.tres`. |
| `platform/StatDef.gd`, `StatCatalog.gd` | Stat definitions (`data/platform/stats.tres`). |
| `platform/PresenceTable.gd` | Presence lines (`data/platform/presence.tres`). |
| `platform/PlatformConfig.gd` | `data/platform/platform_config.tres`: backend id, store file, toast timing, close-call margin, flush interval, menu rows, grind cap. |
| `devtools/content/rules/PlatformRules.gd` | Validator rules PL-11, PL-12, PL-14. |

Gameplay never calls `Platform`. The trackers only listen to EventBus (the Playtest pattern). The only callers are UI, dev tools and SaveManager's cloud hook, so deleting the trackers changes nothing about play.

## API (`Platform`)

| Member | Meaning |
|---|---|
| `allow_headless`, `store_dir`, `dev_allow_tainted` | Headless opt-in; the root of every platform file (default `user://platform`); the dev override for tainted profiles. |
| `config`, `backend`, `stats`, `achievements`, `presence` | The config resource, the backend and the three child trackers. |
| `active()` | Files may be written: `allow_headless` or a real display. |
| `earning_allowed()` | `active()`, not `CinematicMode.theatre`, not `Challenges.active()`, and not a dev-tainted profile (unless `dev_allow_tainted`), D-145. |
| `lifetime_allowed()`, `run_pass_allowed()` | The challenge feat whitelist and the in-run pass (below). Theatre blocks them only outside a run (the Ending): a challenge run keeps theatre on until its restore, which comes after `challenge_finished`. |
| `store()` | The lazy `LocalStore`. |
| `is_unlocked(id)`, `unlocked_ids()`, `unlock_record(id)` | Unlock state; a record is `{t: unix seconds, profile: int}`. |
| `stat(id, lifetime = true)`, `profile_stat(id)` | Lifetime or this profile's value. During a run the profile value reads the held profile, never the sandbox. |
| `record_unlock(a, retroactive)` | The one unlock path: store, save, `backend.unlock`, `backend.store_stats`, announce. |
| `pending_toasts` | Unlocks waiting to be announced (see "Announcing"). |
| `flush()` | Writes unsaved lifetime stats and mirrors every lifetime stat to the backend. Runs every `flush_interval_s`, on every profile save, after every finished challenge run, on a window close request and when the autoload leaves the tree (so `get_tree().quit()` from the title's Quit loses nothing). |
| `notify_file_written(path)` | SaveManager's hook after each successful profile write: `backend.cloud_file_written(path)`, then `flush()`. |
| `submit_score(board, value, meta)` | Mirrors a personal best to the backend. Local: no-op, because T04's `RecordStore` (`records.json`) already is the local board. |
| `presence_text()`, `set_presence(key, arg = "")` | The live status line; a manual status until the next presence event. |
| `register_overlay()`, `overlay_lines()` | F1 DebugOverlay lines `PRESENCE: …` and `ACH n/m` (§37.5). |
| `dev_unlock(id)`, `dev_lock(id)`, `dev_reset_all()` | Dev tools. The reset clears unlocks and lifetime stats (store and backend). Like `record_unlock`, they do nothing while inactive: an unlock that cannot be saved is never recorded or announced. |
| `reset_for_tests(dir)`, `reset_after_tests()`, `clear_cache()` | Test and tour seams (TestRunner and CaptureTour call them). |

Achievement unlocks are announced on `EventBus.achievement_unlocked(achievement_id, retroactive)`. There is no Platform-local signal. The toast (`ui/hud/AchievementToast.gd`, T07) is instantiated by Platform as a child CanvasLayer on layer 70 when the script exists, and listens to EventBus.

## Store format

`<store_dir>/achievements.json`, written atomically (`.tmp` → previous file to `.bak` → rename). An unreadable primary recovers from `.bak`.

```json
{
  "store_version": 1,
  "unlocked": { "krail_down": { "t": 1790000000, "profile": 1 } },
  "lifetime": { "kills": 142, "perfect_dodges": 31, "best_style_rank": 6, "boss_time_warden_krail": 83.4, "play_time": 20411.2 },
  "presence": { "key": "room", "text": "Lowlight — Market Run" }
}
```

- The store is **global to the machine user** (D-143). Unlocks record the earning profile. Deleting a profile never deletes achievements; only an explicit dev reset does.
- Sections a build does not know are kept and written back. A newer `store_version` is kept with a warning.
- Challenge records are not here. They live in `<store_dir>/records.json` (T04's RecordStore), and personal-best ghosts live in `<store_dir>/ghosts/`.
- Per-profile stat values live in `GameState.stats` (an optional key, no schema bump, D-087/D-090).
- **Lazy loading (R02.5):** the store loads on first access, not in `_ready`, and remembers the dir it came from. If `store_dir` changed since then (demo user dirs, tests), the next access first writes a dirty in-memory copy to its own dir (when `active()`), then reloads from the new dir. `reset_for_tests()` does the same before it swaps. Nothing is ever written to the new dir by the swap.

## Headless gating

Nothing under `store_dir` is written unless `active()`. Headless runs (the test suite, probes, route bots) are inactive by default, so they never touch `user://platform`, and nothing is earned either (`earning_allowed()` needs `active()`). A test opts in with `Platform.reset_for_tests("user://<temp>")`. `TestRunner` calls `reset_after_tests()` after every test (store dir, headless gate, dev override, backend, held toasts, tracker state and the achievement cache). CaptureTour redirects the store to `user://tour_sandbox/platform` and turns toasts off.

## Stats

`data/platform/stats.tres` lists every stat: kind (COUNTER, MAX, MIN, DERIVED), format (int, time, rank), scopes (lifetime, profile), whether the Records page lists it, and an API name (`STAT_<ID>` by default).

- Campaign stats count only while `earning_allowed()` and the current room is a world room (labs respawn dummies, and a lab is not the game).
- `kills` counts player kills of non-boss enemies. `kills_environmental` and `kills_aerial` are the tagged subsets.
- Boss detectors: `boss_started` opens a fight by `BossArena.id_of`. Any `player_damaged` spoils the no-hit. `player_died` and `room_leaving` close every fight, so a clean retry after a death still counts. `boss_defeated` records `boss_time_<id>` (MIN, unpaused physics seconds) and, when clean, `boss_nohit_<id>`.
- `act1_clear_time` is recorded when `act1_complete` is set in play. `Game.load_game`'s derivation sets the flag without `flag_changed`, so loading an old save is never a clear.
- `deaths` is kept for the playtest and per-profile records but is never listed on the Records page (`shown = false`, §24 never shame).
- DERIVED stats (`memory_details_found`, `anchors_rested`, `secrets_found`, plus the profile side of `play_time` and `deaths`) are computed from the profile (`StatsTracker.DERIVED_IDS`, checked by PL-12).

### Challenge runs (D-145 as amended by R02.3)

While `Challenges.active()` nothing counts, except this whitelist, applied to the **lifetime** store only when `challenge_finished` reports outcome FINISHED:

| Run | Lifetime stat |
|---|---|
| `br_collector_nohit` | `boss_nohit_collector_drone` +1 |
| `br_krail_nohit` | `boss_nohit_warden_krail` +1 |
| `br_krail`, `br_krail_nohit` with a Grid Clamp stagger in the run | `clamp_boss_staggers` +1 |
| `tt_rainline` with no catch | `chase_clean` +1 |
| `pit_style` | `best_style_rank` (max) |
| any run with medal ≥ 2 (Silver or better) | `challenge_silver_medals` +1 |

The sandbox profile is never counted, and a dev-tainted held profile counts nothing.

## Achievements

`AchievementTracker` re-evaluates every locked achievement once per dirty frame. Flags, collectibles, secrets, bosses, Circuits, weapons, memories, arc stages and stat changes mark it dirty.

- All `conditions` must hold (`Game.check_condition`, no AND/OR, D-119), and the stat rule must be met (MIN stats: `0 < value <= target`).
- **Retroactive (D-143):** `game_state_reset` (load, new game, the Challenges restore) re-evaluates with `retroactive = true`, so an old save earns what it already did. Only the first full pass after the reset is retroactive; an in-run pass (lifetime-only achievements) keeps the mark for the full pass after the restore.
- A pass blocked by `earning_allowed()` keeps the dirty mark and runs once earning is allowed again.
- **In runs (R02.3):** achievements that read only lifetime stats (no conditions, lifetime scope) are evaluated during a run too. Everything else waits for the restore.
- `reveal_when` (a condition, empty = always) is a spoiler guard for the menu (T07). The validator treats it as a flag read.

### Announcing

`record_unlock` queues `[id, retroactive]` in `Platform.pending_toasts` and releases it at once when no run is live, no result card is pending (`Challenges.finishing()`), the tree is not paused and no MenuHost screen is open. Otherwise the queue is released on the first free frame (R02.9). The toast itself holds further while a scene locks input (T07).

### Excluded achievements

The Act I set (30 files in `data/achievements/`, T07) leaves these out on purpose. The validator rules that keep them out are `AchievementRules` PL-6, PL-9 and PL-10.

- **Die N times, kill N enemies:** grind (§2.9, D-146) or shame (§24). Deaths are not even listed on the Records page.
- **Anything that needs currency loss or a Core mode** (e.g. "finish with currency loss on", "clear in Redline Challenge mode"): it would shut out assist players (D-144). Difficulty-tagged goals belong to Challenges and their local boards.
- **Recover a dropped cache:** impossible with `currency_loss` off (D-144).
- **Speed goals** (e.g. "finish Act I in under 45 minutes"): they need §44 timing data. The `act1_clear_time` stat is recorded now; a goal can become a time trial or a later achievement with a measured threshold.
- **Ending achievements:** the endings are unreachable until Act V (D-105). The data slot exists, and PL-9 blocks any achievement that reads a future flag while Act I is the last built act.

## Rich presence

`PresenceTracker` derives one status, in priority order: a manual `set_presence` (until the next event), a challenge run (`challenge`, with `Challenges.current_title()`), a memory (`memory`), a scripted scene (`cinematic`), a boss fight (`boss`), a world room (`room`, or `act_done` once Act I is complete), a lab (`lab`), otherwise the menus (`title`). The lines live in `data/platform/presence.tres` with named placeholders (`{district}`, `{room}`, `{boss}`, `{name}`) and are translated at display. Changes are pushed to `backend.set_presence(key, text)`. Locally that only feeds the DebugOverlay line.

## Validator rules

| Id | Rule |
|---|---|
| PL-11 | Every `boss_nohit_*` / `boss_time_*` stat suffix is the `boss_id` of a BossArena in a district room (from the room pass), and the stat has `reveal_when = "flag:<boss_id>_intro_seen"`, so the Records page names no boss before the meeting (`StatDef.revealed(value)`: shown, and a value above 0 or the condition holds). |
| PL-12 | StatDef ids are unique. API names are unique and match `^[A-Z0-9_]{1,128}$`. DERIVED stats are in `StatsTracker.DERIVED_IDS`. |
| PL-14 | No network classes or storefront calls in code under `res://platform/` or in `autoload/Platform.gd`: `Steam.`, `HTTPRequest`, `HTTPClient`, `StreamPeerTCP`, `PacketPeerUDP`, `WebSocket(Peer)`, `ENet(MultiplayerPeer)`, `Engine.get_singleton("Steam")`. Comments are stripped first (everything from the first `#` outside a string), so notes like this page's may name those APIs. |

Achievement-file rules PL-1..PL-10 and the PL-13 report table are T07's `AchievementRules`. The project-wide network ban is CrossRules X-4 (T14).

## No networking (D-141)

REDLINE makes no network calls. Telemetry (`Playtest`) is local only, achievements and records are local files, and the backend interface has no transport. PL-14 and `test_platform_services::test_no_network_or_steam_symbols_in_platform` keep this mechanical for the platform layer.

## Storefront adapter slot (documented, not implemented)

This section is for a future human decision. It is not M9 work.

- **Dependency (§37.9):** the GodotSteam GDExtension for Godot 4.3, added as a documented dependency, plus a `steam` export feature tag. The factory would return a `SteamPlatformBackend` only when `OS.has_feature("steam")` and the singleton exists. It returns `LocalPlatformBackend` otherwise and whenever `init()` fails. **Verify GodotSteam names at adoption:** function names differ between GodotSteam versions, and this design does not pin them.
- **Achievements:** `unlock(api_name)` sets the achievement and stores stats. `AchievementData.api()` is the API name (`ACH_<ID>` by default). `sync_unlocked()` runs when the store loads, so unlocks earned offline or before the adapter existed are replayed.
- **Stats:** `set_stat(api_name, value, is_int)` by `StatDef.api()`. Stats are configured per stat on the partner site (for example "increment only", "min/max"). MIN stats are uploaded as they are, or skipped with only a leaderboard carrying them.
- **Leaderboards:** `submit_score(board, score, meta)` would find or create the board and upload with "keep best". Uploads are asynchronous and never gate anything. The local board stays `RecordStore`.
- **Rich presence:** `set_presence(key, text)` would map each PresenceTable key 1:1 to a `steam_display` token `#Status_<key>`, with a localization file on the partner site.
- **Cloud saves:** prefer **Auto-Cloud (no code)** with root `user://` and these paths: `saves/profile_*.json`, `saves/*.bak` and `platform/**`. Exclude `settings.cfg` (machine-specific) and `playtests/` (local telemetry, never cloud). `cloud_file_written(path)` stays a no-op unless the Remote Storage API is chosen instead.
- **Art:** each API name needs 64×64 locked and unlocked images. This is an M10 asset task (D-026: none now). `AchievementData.icon` is the in-game slot.
- **Overlay/Deck:** pausing when the overlay opens would come through a backend signal. It is not designed further (M10 Steam Deck validation).
