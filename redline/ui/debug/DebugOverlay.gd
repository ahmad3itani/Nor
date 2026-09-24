extends CanvasLayer
## Live telemetry (bible §38.8, §37.5): movement, combat, core and style, plus
## the world state in slice rooms (Scrap, Anchor, Circuits, quests, secrets).
## Renders at native resolution above the pixel viewport. Toggle: F1 / L3.

const FONT_SIZE := 5

var _player: Player
var _spawn_label: String = ""
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 100
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.05, 0.72)
	style.set_content_margin_all(2)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(2, 2)
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color("e6e2ee"))
	_label.add_theme_constant_override("line_spacing", 0)
	_panel.add_child(_label)
	visible = Settings.show_debug_overlay
	EventBus.player_spawned.connect(func(p: Node2D) -> void: _player = p as Player)
	EventBus.player_respawned.connect(_on_respawned)
	EventBus.settings_changed.connect(func() -> void: visible = Settings.show_debug_overlay)


func _on_respawned(_p: Node2D, spawn_id: StringName) -> void:
	_spawn_label = String(spawn_id)
	var room := SceneRouter.current_room as Room
	if room:
		var marker := room.active_spawn()
		if marker.label != "":
			_spawn_label = "%s - %s" % [spawn_id, marker.label]


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_toggle"):
		visible = not visible
		Settings.show_debug_overlay = visible
	if not visible:
		return
	_label.text = _build_text()


func _build_text() -> String:
	var lines: PackedStringArray = []
	var room := SceneRouter.current_room as Room
	lines.append("REDLINE %s   FPS %d   phys %.2fms   x%.2f   %dHz interp %s" % [
		room.room_name.to_upper() if room else "LAB", Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Engine.time_scale, Engine.physics_ticks_per_second,
		"ON" if get_tree().physics_interpolation else "off"])
	if _player == null or not is_instance_valid(_player):
		return "\n".join(lines)
	var p := _player
	var m := p.metrics
	lines.append("state  %s" % p.current_state_label())
	lines.append("vel    %6.1f, %6.1f   |v| %5.1f   top %5.1f" % [p.velocity.x, p.velocity.y, p.velocity.length(), m.top_speed])
	lines.append("ground %s   low %s   facing %s   iframes %s" % [
		_yn(p.is_on_floor()), _yn(p.is_low), "R" if p.facing > 0 else "L", _yn(p.invulnerable)])
	lines.append("coyote %.2f   jbuf %.2f   ebuf %.2f   ecd %.2f   airdodge %d" % [
		p.coyote_timer, p.jump_buffer_timer, p.evade_buffer_timer, p.evade_cooldown, p.air_dodges_left])
	lines.append("last jump  h %.1fpx   d %.1fpx   air %.2fs" % [m.last_jump_height, m.last_jump_distance, m.last_airtime])
	lines.append("count  jump %d  slide %d  dodge %d  dash %d" % [m.jumps, m.slides, m.dodges, m.dashes])
	lines.append("preset %s   dash %s   spawn %s" % [p.config.preset_name, "ON" if p.abilities.dash else "off", _spawn_label])
	var c := p.combat
	var atk := String(c.current_attack.id) if c.current_attack else "-"
	var w := c.ranged_weapon()
	lines.append("hp %d/%d  combo %d  atk %s  hitstop %.2f  %s %d  hang %d" % [
		c.health, c.config.max_health, c.combo_index, atk, p.hitstop_timer,
		w.id if w else "-", int(c.ammo.get(w.id, 0)) if w else 0, c.air_hang_left])
	lines.append("core %.1f %s [%s]  style %s %.0f" % [p.reactor.charge, "FLOW" if p.reactor.in_flow() else "safe",
		p.reactor.config.mode_name, p.style.meter.rank_name(), p.style.meter.points])
	if room and room.world_room:
		lines.append_array(_world_lines())
	lines.append("[F1] overlay [R] reset [Tab] station [F2] dash [F3] tune [F4] slowmo")
	lines.append("[F5] reload [F6] preset [F7] interp [F8] tick rate")
	lines.append("[F9] ranged [F10] enemies [F11] core mode [F12] switch lab")
	return "\n".join(lines)


## M3 world state: economy, respawn point, build, quest and secret progress.
func _world_lines() -> PackedStringArray:
	var st := Game.state
	var quests: PackedStringArray = []
	for q in Game.quests.active_quests():
		quests.append("%s:%d" % [q.id, q.current_stage()])
	var anchor := "-" if st.last_anchor_id == "" else "%s/%s" % [st.last_anchor_room.get_file().get_basename(), st.last_anchor_id]
	return PackedStringArray([
		"scrap %d banked + %d carried  drops %d   injectors %d   anchor %s" % [
			st.scrap_banked, st.scrap_unbanked, st.dropped_scrap.size(), _player.combat.injectors, anchor],
		"circuits %d/%d %s   shards %d   quests %s" % [
			Game.capacity_used(), Game.core_capacity(), ",".join(st.equipped_circuits), st.core_shards,
			",".join(quests) if not quests.is_empty() else "-"],
		"secrets %d/%d   fragments %d   flags %d   deaths %d   time %s" % [
			SliceStats.secrets_found(), SliceStats.totals()["secret_ids"].size(), st.memory_fragments.size(),
			st.flags.size(), st.deaths, SliceStats.format_time(st.play_time_sec)],
	])


func _yn(b: bool) -> String:
	return "Y" if b else "-"
