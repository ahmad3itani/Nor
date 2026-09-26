class_name AchievementDevActions
extends RefCounted
## Dev console helpers for achievements (M9 D1 §4.8, T07). Debug builds only
## (the dev console never opens in a release export); every entry point is
## gated on DevActions.available(). Nothing here is player-facing, so the
## text is English only.
##
## Unlocks are machine-wide (D-143), so these act on the platform store, not
## on the profile: a dev unlock does not taint the profile. The store only
## changes while Platform.active() (a real display, or a test opt-in).

## Reset needs a second press (the first one arms it), like SkipGate; any
## other row disarms it.
static var reset_armed: bool = false


## [id, "[x] title", unlocked] for every achievement, in menu order.
static func rows() -> Array:
	var out: Array = []
	for a in AchievementLibrary.all():
		var done := Platform.is_unlocked(a.id)
		out.append([a.id, "[%s] %s" % ["x" if done else " ", a.title], done])
	return out


static func toggle(id: String) -> bool:
	reset_armed = false
	if not DevActions.available():
		return false
	if Platform.is_unlocked(id):
		Platform.dev_lock(id)
	else:
		Platform.dev_unlock(id)
	return Platform.is_unlocked(id)


static func unlock_all() -> int:
	reset_armed = false
	if not DevActions.available():
		return 0
	var n := 0
	for a in AchievementLibrary.all():
		if not Platform.is_unlocked(a.id):
			Platform.dev_unlock(a.id)
			n += 1
	return n


## First press arms, the second clears every unlock and lifetime stat.
## Returns true when it actually reset.
static func reset_pressed() -> bool:
	if not DevActions.available():
		return false
	if not reset_armed:
		reset_armed = true
		return false
	reset_armed = false
	Platform.dev_reset_all()
	var toast := toast_node()
	if toast:
		toast.clear()
	return true


## Re-evaluates every locked achievement now (as a load would, retroactive).
static func evaluate_now() -> void:
	reset_armed = false
	if DevActions.available():
		Platform.achievements.mark_dirty(true)


static func set_dev_earn(on: bool) -> void:
	reset_armed = false
	if DevActions.available():
		Platform.dev_allow_tainted = on
		Platform.achievements.mark_dirty()


## Shows a toast for `id` (the first achievement when empty) without writing
## the store or announcing an unlock.
static func test_toast(id: String = "") -> bool:
	reset_armed = false
	var toast := toast_node()
	if toast == null or not DevActions.available():
		return false
	if id == "":
		var all := AchievementLibrary.all()
		if all.is_empty():
			return false
		id = all[0].id
	toast.enqueue(id)
	return true


static func toast_node() -> AchievementToast:
	return Platform.get_node_or_null("AchievementToast") as AchievementToast


## "backend: local · store: <path> · presence: <text> · 3/30 unlocked".
static func summary() -> String:
	return "backend: %s · store: %s · presence: %s · %d/%d unlocked%s" % [Platform.backend.backend_id(),
		ProjectSettings.globalize_path(Platform.store_dir), Platform.presence_text(), Platform.unlocked_ids().size(),
		AchievementLibrary.count(), "" if Platform.active() else " · platform off"]
