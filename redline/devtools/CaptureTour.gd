extends Node
## Renders a scripted tour of the Movement Lab to PNGs for reports/PR review.
##   godot --fixed-fps 60 res://devtools/CaptureTour.tscn -- --out=/abs/dir
## Needs a real (or virtual, e.g. xvfb-run) display; headless has no renderer.

const MAIN := preload("res://Main.tscn")

var _out_dir := "user://captures"
var _input := ScriptedInputSource.new()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	add_child(MAIN.instantiate())
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out_dir, name])
	print("captured ", name)


func _goto(room: Room, spawn_id: StringName) -> void:
	for i in room.spawns.size():
		if room.spawns[i].spawn_id == spawn_id:
			room.active_spawn_index = i
	room.respawn()
	await _frames(20)


func _tour() -> void:
	await _frames(5)
	var room := SceneRouter.current_room as Room
	room.player.input_source = _input
	await _frames(20)
	await _shot("01_start")

	_input.move_x = 1
	await _frames(30)
	_input.press_jump()
	await _frames(18)
	await _shot("02_run_jump_apex")
	await _frames(40)
	_input.move_x = 0

	await _goto(room, &"slide")
	_input.move_x = 1
	await _frames(22)
	_input.down_held = true
	await _frames(14)
	await _shot("03_slide_into_tunnel")
	_input.down_held = false
	await _frames(40)
	_input.move_x = 0

	await _goto(room, &"gaps")
	_input.move_x = 1
	await _frames(20)
	_input.press_dodge()
	await _frames(6)
	await _shot("04_dodge_afterimages")
	_input.move_x = 0

	await _goto(room, &"drop")
	_input.move_x = -1
	await _frames(40)
	_input.move_x = 0
	await _frames(18)
	await _shot("05_falling_look_down")
	for i in 120:
		await _frames(1)
		if room.player.is_on_floor():
			break
	await _frames(4)
	await _shot("06_hard_landing_dust")

	await _goto(room, &"start")
	var panel := get_tree().root.find_child("TuningPanel", true, false) as CanvasLayer
	if panel:
		panel.visible = true
	_input.move_x = 1
	await _frames(25)
	_input.down_held = true
	await _frames(8)
	await _shot("07_tuning_panel_slide_dust")
	get_tree().quit()
