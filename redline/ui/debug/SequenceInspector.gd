class_name SequenceInspector
extends CanvasLayer
## Sequence debug view (M8, A5 §4.3, bible §37.5 "debug visibility"). Dev
## only, toggled from DevConsole > Story > "Sequence inspector". Top-right,
## above the debug overlay (layer 101), native resolution like PerfGraph.
##
## While a sequence plays: its id, view, mode and clock against the nominal
## length; a window of steps around the current one, where every step that
## will not play says why ("[skip: <reason>]", the most common authoring
## bug: a wrong only_when or views); the skip hold bar from the player's
## SkipGate; and the flags the scene sets. When idle: the last finished
## sequence (skipped, seconds, step reached) from sequence_finished.
## Reads only (Cinematics.current, step_started, sequence_finished).

const FONT_SIZE := 7
const WIDTH := 200.0
## Steps listed around the current one (the rest are summarised as "…").
const STEP_WINDOW := 7
const BAR_CELLS := 6

var _panel: PanelContainer
var _label: Label
## Last finished sequence: {id, skipped, seconds, step_index, step_count}.
var _last: Dictionary = {}
## Clock at which each step of the current play started (index -> seconds).
var _step_clock: Dictionary = {}


func _ready() -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "SequenceInspector"
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.05, 0.8)
	style.set_content_margin_all(2)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color("e6e2ee"))
	_label.add_theme_constant_override("line_spacing", 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_label.custom_minimum_size = Vector2(WIDTH - 4.0, 0)
	_panel.add_child(_label)
	Cinematics.step_started.connect(_on_step)
	EventBus.sequence_finished.connect(_on_finished)
	_place()


func _exit_tree() -> void:
	if Cinematics.step_started.is_connected(_on_step):
		Cinematics.step_started.disconnect(_on_step)
	if EventBus.sequence_finished.is_connected(_on_finished):
		EventBus.sequence_finished.disconnect(_on_finished)


func _place() -> void:
	var view := get_viewport().get_visible_rect().size if get_viewport() else Vector2(480, 270)
	_panel.position = Vector2(view.x - WIDTH - 2.0, 2.0)


func _process(_delta: float) -> void:
	_place()
	_label.text = build_text()


func _on_step(index: int, _label_text: String) -> void:
	if index == 0:
		_step_clock.clear()
	var p := Cinematics.current
	_step_clock[index] = p.clock() if is_instance_valid(p) else 0.0


func _on_finished(id: String, skipped: bool, seconds: float, step_index: int, step_count: int, _nominal: float) -> void:
	_last = {"id": id, "skipped": skipped, "seconds": seconds, "step_index": step_index, "step_count": step_count}


## Why `s` will not play in this view, or "" when it will.
static func ineligible_reason(s: SequenceStep, first_view: bool) -> String:
	if s == null:
		return "empty step"
	if not s.plays_in_view(first_view):
		return "first view only" if s.views == 1 else "repeat view only"
	if s.only_when != "" and not Game.check_condition(s.only_when):
		return s.only_when
	return ""


func build_text() -> String:
	var lines := PackedStringArray()
	var p := Cinematics.current
	if not Cinematics.is_playing():
		if _last.is_empty():
			lines.append("SEQ idle")
		else:
			lines.append("SEQ idle · last %s" % _last["id"])
			lines.append(" %s  %.1f s  step %s" % ["skipped" if _last["skipped"] else "finished", _last["seconds"],
				"aborted" if int(_last["step_index"]) < 0 else "%d/%d" % [int(_last["step_index"]) + 1, _last["step_count"]]])
		return "\n".join(lines)
	var seq := p.seq
	lines.append("SEQ %s  %s  %s  %.1f / %.1f s" % [seq.id, "first" if p.first_view else "repeat",
		CinematicMode.Mode.keys()[CinematicMode.current()], p.clock(), seq.nominal_seconds(p.first_view)])
	var n := seq.steps.size()
	var start := clampi(p.index - 2, 0, maxi(n - STEP_WINDOW, 0))
	var end := mini(start + STEP_WINDOW, n)
	if start > 0:
		lines.append("   …")
	for i in range(start, end):
		lines.append(step_line(seq.steps[i], i, p))
	if end < n:
		lines.append("   … %d more" % (n - end))
	if p.gate:
		var hold := SkipGate.HOLD_SECONDS if p.first_view else SkipGate.REPEAT_HOLD_SECONDS
		var ratio := p.gate.progress_ratio()
		var cells := int(round(ratio * BAR_CELLS))
		lines.append("skip hold %s %.2f / %.2f" % ["█".repeat(cells) + "░".repeat(BAR_CELLS - cells), ratio * hold, hold])
	else:
		lines.append("skip: none (unlocked play)")
	lines.append("lock %s hud %s letterbox %s" % [_mark(p.locking), _mark(p.locking and seq.hide_hud), _mark(p.locking and seq.letterbox)])
	var produces: Array = seq.content_flags().get("produces", [])
	lines.append("flags set: %s (at end)" % ", ".join(PackedStringArray(produces)))
	return "\n".join(lines)


## " ▸ 3 SeqLine  label  3.1 s" or "   4 SeqLine  [skip: !flag:x]".
func step_line(s: SequenceStep, i: int, p: SequencePlayer) -> String:
	var cursor := "▸" if i == p.index else " "
	var why := ineligible_reason(s, p.first_view)
	if s == null:
		return " %s %d  [skip: empty step]" % [cursor, i]
	var title := "%s%s" % [s.kind(), "" if s.label == "" else "  " + s.label]
	if why != "":
		return " %s %d %s  [skip: %s]" % [cursor, i, title, why]
	var t := "%.1f s" % s.nominal_seconds()
	if i == p.index and _step_clock.has(i):
		t = "%.1f / %s" % [p.clock() - float(_step_clock[i]), t]
	return " %s %d %s  %s%s" % [cursor, i, title, t, "" if s.blocking else " ∥"]


func _mark(b: bool) -> String:
	return "✓" if b else "✗"
