extends MenuScreen
## "Report a moment" (M4): testers flag confusion, unfair hits, control
## problems or bugs *where they happen*, instead of trying to remember them
## after the session. Step 1 picks a tag (controller-friendly); step 2 adds
## an optional typed note (keyboard) or saves straight away.

var _tag: String = ""
var _note: LineEdit


func open_menu() -> void:
	_tag = ""
	super.open_menu()
	focus_index(0)


func rebuild() -> void:
	clear_body()
	add_label("REPORT A MOMENT", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	if _tag == "":
		add_label("What just happened? This is saved with where you are right now.", UiTheme.MUTED)
		for tag in Playtest.config.moment_tags:
			add_button(tag, _pick.bind(tag))
		add_button("Cancel", close_menu)
		return
	add_label("Tag: %s" % _tag)
	add_button("Save without a note", _save)
	add_label("Or type a note and press Enter:", UiTheme.MUTED)
	_note = LineEdit.new()
	_note.placeholder_text = "optional note"
	_note.custom_minimum_size = Vector2(320, 0)
	_note.text_submitted.connect(func(_t: String) -> void: _save())
	_body.add_child(_note)
	add_button("Back", func() -> void:
		_tag = ""
		rebuild()
		focus_index(0))


func _pick(tag: String) -> void:
	_tag = tag
	rebuild()
	focus_index(0)


func _save() -> void:
	var note := _note.text.strip_edges() if is_instance_valid(_note) else ""
	Playtest.report_moment(_tag, note)
	EventBus.hint_requested.emit("Moment saved. Thanks!", 1.5)
	close_menu()
