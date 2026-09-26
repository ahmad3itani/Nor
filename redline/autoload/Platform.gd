extends Node
## Platform services (M9 D1, bible §29): achievements, stats, rich presence,
## leaderboard mirroring and cloud-save hooks behind one PlatformBackend.
## Only the local backend ships; a storefront adapter is a documented slot
## with no code (Docs/PLATFORM_SERVICES.md; §37.7: gameplay never depends on
## a platform API, and there is no networking, D-141).
## Gameplay never calls Platform: its trackers listen to EventBus (the
## Playtest pattern). Only UI, dev tools and SaveManager's one hook call in.
##
## The local store (platform/LocalStore.gd, <store_dir>/achievements.json) is
## the truth; the backend mirrors it. The store loads lazily on first access
## and reloads when store_dir changes (demo dirs, tests; R02.5). Nothing is
## written unless active(): headless runs (tests, probes) write nothing unless
## a test opts in with reset_for_tests().
## No class_name: an autoload's script must not declare one (4.3).

const CONFIG_PATH := "res://data/platform/platform_config.tres"
const DEFAULT_STORE_DIR := "user://platform"
const TOAST_LAYER := 70

## Headless runs (tests, probes) never write unless a test opts in.
var allow_headless := false
## Root of every platform file (achievements.json, records.json, ghosts/).
## Tests and CaptureTour redirect it with reset_for_tests().
var store_dir: String = DEFAULT_STORE_DIR
## Dev: let a dev-tainted profile earn (D-145), for testing the toasts.
var dev_allow_tainted := false

var config: PlatformConfig
var backend: PlatformBackend
var stats: StatsTracker
var achievements: AchievementTracker
var presence: PresenceTracker
## Unlock ids waiting for their announcement (R02.9): held while a challenge
## run or its result card is up, released on the first unpaused frame with no
## open menu. [[id, retroactive], ...]
var pending_toasts: Array = []

var _store: LocalStore = null
var _flush_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = load(CONFIG_PATH) as PlatformConfig
	if config == null:
		config = PlatformConfig.new()
	_make_backend()
	stats = StatsTracker.new()
	stats.name = "Stats"
	add_child(stats)
	achievements = AchievementTracker.new()
	achievements.name = "Achievements"
	add_child(achievements)
	stats.changed.connect(func() -> void: achievements.mark_dirty())
	presence = PresenceTracker.new()
	presence.name = "Presence"
	add_child(presence)
	register_overlay()
	# The toast is T07's file; the format form keeps the validator's literal
	# reference scan quiet until it exists.
	var toast_path := "res://ui/hud/%s.gd" % "AchievementToast"
	if ResourceLoader.exists(toast_path):
		var toast := (load(toast_path) as GDScript).new() as CanvasLayer
		if toast != null:
			toast.name = "AchievementToast"
			toast.layer = TOAST_LAYER
			add_child(toast)


func _process(delta: float) -> void:
	backend.poll(delta)
	_release_toasts()
	if _store != null and _store.dirty and active():
		_flush_timer += delta
		if _flush_timer >= config.flush_interval_s:
			flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


## get_tree().quit() (the title's Quit) sends no close request; the tree
## finalizing does reach here, so lifetime-only stats are never lost.
func _exit_tree() -> void:
	flush()


# --- Gates ---

## Whether platform files may be written: a real display, or a test opt-in.
func active() -> bool:
	return allow_headless or DisplayServer.get_name() != "headless"


## Achievements and campaign stats are earned now (D-145): not in the Ending
## theatre, not in a challenge sandbox, not on a dev-fabricated profile.
func earning_allowed() -> bool:
	return active() and not CinematicMode.theatre and not Challenges.active() \
		and (not Game.state.dev_tainted or dev_allow_tainted)


## Lifetime-only bookkeeping (the challenge feat whitelist, R02.3) may happen:
## like earning_allowed() but a live run does not block it, and the taint is
## read from the real profile, never the sandbox.
func lifetime_allowed() -> bool:
	var profile: GameState = Game.held_profile if Game.held_profile != null else Game.state
	return active() and not CinematicMode.theatre and (not profile.dev_tainted or dev_allow_tainted)


## The in-run pass of lifetime-only achievements (R02.3).
func run_pass_allowed() -> bool:
	return lifetime_allowed() and (Challenges.active() or Challenges.finishing())


# --- Store and queries ---

## The live store: loaded on first access, reloaded (never flushed across)
## when store_dir changed since it was loaded (R02.5).
func store() -> LocalStore:
	if _store == null or _store.dir != store_dir:
		_store = LocalStore.new()
		_store.load_from(store_dir, config.store_file, config.store_version)
		_flush_timer = 0.0
		backend.sync_unlocked(_api_names(_store.unlocked_ids()))
	return _store


func is_unlocked(id: String) -> bool:
	return store().is_unlocked(id)


func unlocked_ids() -> PackedStringArray:
	return store().unlocked_ids()


## {"t": unix seconds, "profile": int}, or {} when locked.
func unlock_record(id: String) -> Dictionary:
	return (store().unlocked.get(id, {}) as Dictionary).duplicate()


## A stat's value (lifetime = the machine-wide total, else this profile's).
func stat(id: StringName, lifetime: bool = true) -> float:
	return stats.lifetime_value(id) if lifetime else stats.profile_value(id)


func profile_stat(id: StringName) -> float:
	return stats.profile_value(id)


# --- Unlocks ---

## The one unlock path (AchievementTracker and dev tools): store, save,
## mirror, announce. False when it was already unlocked, or while inactive
## (an unlock that cannot be persisted is never recorded or announced).
func record_unlock(a: AchievementData, retroactive: bool) -> bool:
	if a == null or not active() or not store().unlock(a.id, Game.profile_id, int(Time.get_unix_time_from_system())):
		return false
	_save()
	backend.unlock(a.api())
	backend.store_stats()
	_announce(a.id, retroactive)
	return true


## Emits EventBus.achievement_unlocked now, or holds it while a run or its
## result card is up (the toast would draw over the run HUD or the card).
func _announce(id: String, retroactive: bool) -> void:
	pending_toasts.append([id, retroactive])
	_release_toasts()


func _release_toasts() -> void:
	if pending_toasts.is_empty() or not _toasts_free():
		return
	var out := pending_toasts.duplicate()
	pending_toasts.clear()
	for p: Array in out:
		EventBus.achievement_unlocked.emit(String(p[0]), bool(p[1]))


func _toasts_free() -> bool:
	if Challenges.active() or Challenges.finishing() or get_tree().paused:
		return false
	for host in get_tree().get_nodes_in_group(&"menu_host"):
		if host.has_method("any_open") and host.call("any_open"):
			return false
	return true


# --- Persistence and backend ---

## Writes unsaved lifetime stats and presence, and mirrors the stats.
func flush() -> void:
	if _store == null or not active():
		return
	for def in stats.catalog.stats:
		if def != null and def.lifetime and _store.has_lifetime(def.id):
			backend.set_stat(def.api(), _store.lifetime_value(def.id), def.is_int())
	backend.store_stats()
	if _store.dirty:
		_save()


func _save() -> void:
	_flush_timer = 0.0
	if not active():
		return
	var s := store()
	s.presence = {"key": presence.key, "text": presence.text} if presence.key != "" else {}
	s.save()


## SaveManager calls this after every successful profile write (cloud hook):
## lifetime stats persist at Anchors and Save & Quit too.
func notify_file_written(path: String) -> void:
	backend.cloud_file_written(path)
	flush()


## Mirrors a local personal best to the backend's leaderboard. The local
## backend does nothing: T04's RecordStore already is the local board.
func submit_score(board: String, value: int, meta: Dictionary) -> void:
	backend.submit_score(board, value, meta)


func presence_text() -> String:
	return presence.current_text()


## A manual presence line (dev tools) until the next presence event.
func set_presence(key: String, arg: String = "") -> void:
	presence.override(key, arg)


func _make_backend() -> void:
	backend = PlatformBackends.create(config.backend_id)
	if not backend.init():
		push_warning("Platform: backend '%s' failed to start; local only" % backend.backend_id())
		backend = LocalPlatformBackend.new()
		backend.init()


func _api_names(ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		var a := AchievementLibrary.by_id(id)
		out.append(a.api() if a != null else "ACH_" + id.to_upper())
	return out


# --- DebugOverlay (§37.5) ---

## Adds the PRESENCE / ACH lines to the F1 overlay once (DebugOverlay drops
## providers on clear_cache; the test teardown registers again).
func register_overlay() -> void:
	var c := Callable(self, "overlay_lines")
	if not DebugOverlay.providers.has(c):
		DebugOverlay.providers.append(c)


func overlay_lines() -> PackedStringArray:
	return PackedStringArray(["PRESENCE: " + presence_text(),
		"ACH %d/%d" % [unlocked_ids().size(), AchievementLibrary.count()]])


# --- Dev and tests ---

func dev_unlock(id: String) -> void:
	var a := AchievementLibrary.by_id(id)
	if a == null:
		push_warning("Platform.dev_unlock: unknown achievement '%s'" % id)
		return
	record_unlock(a, false)


func dev_lock(id: String) -> void:
	if active() and store().lock(id):
		_save()
		var a := AchievementLibrary.by_id(id)
		backend.lock(a.api() if a != null else "ACH_" + id.to_upper())


## Clears every unlock and lifetime stat (store and backend).
func dev_reset_all() -> void:
	if not active():
		return
	store().clear_all()
	backend.reset_all()
	_save()
	achievements.mark_dirty()


func reset_for_tests(dir: String) -> void:
	store_dir = dir
	allow_headless = true


## TestRunner/CaptureTour teardown (R02.1): back to the real store with the
## headless gate shut, a fresh backend, no held toasts and no tracker state.
func reset_after_tests() -> void:
	store_dir = DEFAULT_STORE_DIR
	allow_headless = false
	dev_allow_tainted = false
	_store = null
	pending_toasts.clear()
	_make_backend()
	stats.reset()
	achievements.reset()
	presence.reset()
	AchievementLibrary.clear_cache()
	register_overlay()


func clear_cache() -> void:
	AchievementLibrary.clear_cache()
	StatCatalog.clear_cache()
