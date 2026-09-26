extends MenuScreen
## The adaptive-assist card (bible §23 "suggests, never silently changes",
## §24, D4 §10.2). AssistAdvisor opens it (menu id assist_suggest) with the
## context in ctx: {context, title, cause, deaths, text, keys, values}.
##
##   WARDEN KRAIL
##   Learning a fight takes a few tries. If you'd like, these options can help.
##   They never lock anything, and you can change them any time in Settings.
##     Damage assist: Bosses: reduced  —  Turn on    (applies that one key)
##     Respawn at room entrance: On  —  Turn on
##     Open all assists…                             (Settings, Assists page)
##     Not now                                       (focused first)
##     Don't suggest again                           (reversible in Settings)
##
## Nothing is on until the player picks it, and "Not now" has focus, so a
## mashed confirm changes nothing (D-154). A confirm (or cancel) only counts
## once the card is armed like DialogueBox.confirm_armed (R11.11): the arm
## time has passed in real time and every confirm-like action has been seen
## released since the card opened, so a jump held through the respawn never
## answers it. Every answer emits assist_suggestion_answered. The wording says
## what happened, never who the option is for (§24 never shame).

## Player text: Loc literals here, the rule body line is AssistRule data and
## the row labels are SettingDef data.
const LOC_FIELDS := {}
const LOC_EXEMPT := []
## Presses that must be seen released before a confirm counts.
const ARM_ACTIONS: Array[StringName] = [&"ui_accept", &"jump", &"attack_light", &"attack_heavy", &"interact"]

## Real ms at open (tests move it back to skip the arm time).
var opened_ms: int = 0
var _released: Dictionary = {}
## Keys applied from this card (the row then reads "On").
var _applied: Dictionary = {}


func open_menu() -> void:
	opened_ms = Time.get_ticks_msec()
	_released.clear()
	_applied.clear()
	super.open_menu()
	focus_index(not_now_index())


func _process(_delta: float) -> void:
	if not visible:
		return
	for a in ARM_ACTIONS:
		if InputMap.has_action(a) and not Input.is_action_pressed(a):
			_released[a] = true
	# Cancel behaves like "Not now", with the same arming (never a stray press).
	if Engine.get_process_frames() != _opened_frame and cancel_pressed() and armed():
		not_now()


## True once a fresh press may answer (R11.11).
func armed() -> bool:
	var arm_ms := int(CinematicMode.config().choice_arm_seconds * 1000.0)
	if Time.get_ticks_msec() - opened_ms < maxi(arm_ms, 400):
		return false
	for a in ARM_ACTIONS:
		if InputMap.has_action(a) and not _released.has(a):
			return false
	return true


func rebuild() -> void:
	clear_body()
	var title := str(ctx.get("title", ""))
	if title != "":
		add_label(Loc.upper(title), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	var body := str(ctx.get("text", ""))
	add_label((Loc.t(body) + " " if body != "" else "") + Loc.t("If you'd like, these options can help."))
	add_label(Loc.t("They never lock anything, and you can change them any time in Settings."), UiTheme.MUTED)
	var keys: PackedStringArray = ctx.get("keys", PackedStringArray())
	var values: Array = ctx.get("values", [])
	for i in keys.size():
		if i < values.size():
			add_button(row_text(keys[i], values[i]), _apply.bind(keys[i], values[i]))
	add_button(Loc.t("Open all assists…"), _open_settings)
	add_button(Loc.t("Not now"), not_now)
	add_button(Loc.t("Don't suggest again"), dont_suggest_again)


## "Damage assist: Bosses: reduced  —  Turn on", or "…  —  On" once applied.
func row_text(key: String, value: Variant) -> String:
	var d := Settings.settings_catalog().def(StringName(key)) if Settings.settings_catalog() else null
	var label := Loc.t(d.label) if d else key
	var shown := Loc.t(d.value_text(value)) if d else str(value)
	if _applied.has(key):
		return Loc.f("{setting}: {value}  —  On", {"setting": label, "value": shown})
	return Loc.f("{setting}: {value}  —  Turn on", {"setting": label, "value": shown})


## Button index of "Not now" (after the offered rows and "Open all assists…").
func not_now_index() -> int:
	return (ctx.get("keys", PackedStringArray()) as PackedStringArray).size() + 1


func _context() -> String:
	return str(ctx.get("context", ""))


## Turns one offered setting on (only this key), saves, and keeps the card
## open so the player can take another or leave.
func _apply(key: String, value: Variant) -> void:
	if not armed() or _applied.has(key):
		return
	Settings.set(key, value)
	if key == "reactor_mode":
		var room := SceneRouter.current_room as Room
		if room and is_instance_valid(room.player):
			room.player.reactor.apply_mode(Settings.reactor_mode)
	Settings.save_settings()
	EventBus.settings_changed.emit()
	_applied[key] = true
	AudioManager.play_sfx(&"ui_tick")
	EventBus.assist_suggestion_answered.emit(_context(), &"applied", key)
	var keep := focused_index()
	rebuild()
	focus_index(keep)


func _open_settings() -> void:
	if not armed():
		return
	EventBus.assist_suggestion_answered.emit(_context(), &"opened_settings", "")
	close_menu()
	MenuHost.context = {"page": &"assists"}
	EventBus.menu_requested.emit(&"settings")
	MenuHost.context = {}


## "Not now": closes; the advisor's cooldown starts (armed presses only).
func not_now() -> void:
	if not armed():
		return
	EventBus.assist_suggestion_answered.emit(_context(), &"later", "")
	close_menu()


## Turns suggestions off (Settings > Assists turns them back on).
func dont_suggest_again() -> void:
	if not armed():
		return
	Settings.assist_suggestions = false
	Settings.save_settings()
	EventBus.settings_changed.emit()
	EventBus.assist_suggestion_answered.emit(_context(), &"never", "assist_suggestions")
	close_menu()
