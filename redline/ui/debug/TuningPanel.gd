extends CanvasLayer
## Live movement tuning (M1 polish): one slider per numeric export of the
## active PlayerMovementConfig, generated from the resource's property list so
## new tuning values appear automatically. Edits apply on the next physics tick.
## Save writes the preset .tres (editor runs) or a copy in user://tuning/.
## Toggle: F3. Mouse-driven on purpose: sliders never take keyboard focus, so
## movement keys keep controlling Rook while the panel is open.

const FONT_SIZE := 5
const PANEL_WIDTH := 172.0
## Collision sizes need apply_config() and strings aren't tunable by slider.
const SKIP := ["preset_name", "standing_size", "low_size"]

var config: PlayerMovementConfig
var sliders: Dictionary = {}  # property name -> HSlider

var _panel: PanelContainer
var _rows: VBoxContainer
var _title: Label
var _status: Label
var _player: Player
var _pending_group: String = ""
var _grabber: ImageTexture


func _ready() -> void:
	layer = 101
	_build_shell()
	visible = false
	EventBus.player_spawned.connect(func(p: Node2D) -> void:
		_player = p as Player
		bind_config(_player.config))
	EventBus.movement_config_changed.connect(func(c: Resource) -> void: bind_config(c as PlayerMovementConfig))


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_tuning_panel"):
		visible = not visible
	# Hot reload/preset swaps replace the resource; follow the player's live one.
	if _player and is_instance_valid(_player) and _player.config != config:
		bind_config(_player.config)


func bind_config(new_config: PlayerMovementConfig) -> void:
	config = new_config
	sliders.clear()
	for child in _rows.get_children():
		child.queue_free()
	if config == null:
		return
	_title.text = "TUNING  %s" % config.preset_name
	for prop in config.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_GROUP:
			# Emitted lazily so groups with no sliders (e.g. Resource's own) vanish.
			_pending_group = String(prop["name"])
			continue
		if not (usage & PROPERTY_USAGE_EDITOR) or prop["name"] in SKIP:
			continue
		var type: int = prop["type"]
		if type == TYPE_FLOAT or type == TYPE_INT:
			_add_slider_row(prop)
	_status.text = ""


func _add_group_label(text: String) -> void:
	var l := _label(text.to_upper(), Color("e8283c"))
	_rows.add_child(l)


func _add_slider_row(prop: Dictionary) -> void:
	if _pending_group != "":
		_add_group_label(_pending_group)
		_pending_group = ""
	var prop_name: String = prop["name"]
	var is_int: bool = prop["type"] == TYPE_INT
	var value: float = float(config.get(prop_name))
	var bounds := _range_for(prop, value, is_int)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var name_label := _label(prop_name, Color("c9c3d6"))
	name_label.custom_minimum_size.x = 84
	name_label.clip_text = true
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(52, 5)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.add_theme_icon_override("grabber", _grabber)
	slider.add_theme_icon_override("grabber_highlight", _grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e8283c")
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = bounds.z
	slider.value = value
	row.add_child(slider)

	var value_label := _label(_fmt(value, is_int), Color.WHITE)
	value_label.custom_minimum_size.x = 30
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		config.set(prop_name, int(v) if is_int else v)
		value_label.text = _fmt(v, is_int)
		_status.text = "unsaved changes")
	sliders[prop_name] = slider
	_rows.add_child(row)


## Uses @export_range hints when present; otherwise 0 .. 3x the current value,
## which covers "half as much" to "much more" experiments.
func _range_for(prop: Dictionary, value: float, is_int: bool) -> Vector3:
	if prop["hint"] == PROPERTY_HINT_RANGE:
		var parts := String(prop["hint_string"]).split(",")
		var step := float(parts[2]) if parts.size() > 2 else (1.0 if is_int else 0.01)
		return Vector3(float(parts[0]), float(parts[1]), step)
	var top := maxf(absf(value) * 3.0, 1.0)
	if is_int:
		return Vector3(0.0, ceilf(top), 1.0)
	var step := 0.001 if top <= 1.0 else (0.01 if top <= 10.0 else 1.0)
	return Vector3(0.0, top, step)


func _fmt(v: float, is_int: bool) -> String:
	if is_int:
		return str(int(v))
	return "%.3f" % v if absf(v) < 10.0 else "%.0f" % v


func save_config() -> String:
	var path := String(config.resource_path)
	if path.is_empty():
		path = String(config.get_meta(&"source_path", ""))
	if path.is_empty():
		path = "res://data/movement/%s.tres" % config.preset_name.validate_filename()
	# res:// is read-only in exported builds; keep a copy in user:// instead.
	if not OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute("user://tuning")
		path = "user://tuning/%s" % path.get_file()
	var err := ResourceSaver.save(config, path)
	_status.text = ("saved %s" % path) if err == OK else ("save failed (%d)" % err)
	return path if err == OK else ""


func _build_shell() -> void:
	# Default theme grabbers are 16px: huge at this canvas scale. Use a 3x5 knob.
	var img := Image.create(3, 5, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_grabber = ImageTexture.create_from_image(img)
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color(1, 1, 1, 0.1)
	button_style.set_content_margin_all(1)
	button_style.content_margin_left = 3
	button_style.content_margin_right = 3
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.05, 0.85)
	style.set_content_margin_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH - 2
	_panel.offset_right = -2
	_panel.offset_top = 2
	_panel.offset_bottom = -2
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_panel.add_child(v)
	_title = _label("TUNING", Color.WHITE)
	v.add_child(_title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	for spec in [["Save", save_config], ["Revert", _on_revert], ["Close", func() -> void: visible = false]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", FONT_SIZE)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, button_style)
		b.pressed.connect(spec[1])
		buttons.add_child(b)
	v.add_child(buttons)
	_status = _label("", Color("ff9a3c"))
	v.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 0)
	scroll.add_child(_rows)


func _on_revert() -> void:
	EventBus.movement_config_reload_requested.emit()
	_status.text = "reverted to disk"


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 0)
	return l
