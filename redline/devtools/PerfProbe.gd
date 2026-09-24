extends Node
## Headless CPU cost probe for the Combat Lab under fight load.
##   godot --headless --fixed-fps 60 res://devtools/PerfProbe.tscn
## Measures wall time per frame (with --fixed-fps, frames run back to back,
## so wall time = total CPU work per tick). Note: Performance.TIME_PHYSICS_PROCESS
## is unreliable in this mode and must not be quoted. No GPU cost included.

@export var frames_per_arena: int = 600
@export var arenas: Array[Vector2] = [Vector2(730, -2), Vector2(1500, -2), Vector2(2000, -2)]


func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.start_room = "res://world/rooms/CombatLab.tscn"
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await get_tree().physics_frame
	var room := SceneRouter.current_room as Room
	var input := ScriptedInputSource.new()
	room.player.input_source = input
	# Keep the player alive so the whole run is spent fighting.
	room.player.combat.config = room.player.combat.config.duplicate()
	room.player.combat.config.max_health = 999
	var frame_ms: Array[float] = []
	var last := Time.get_ticks_usec()
	for arena in arenas:
		room.player.respawn(arena)
		for f in frames_per_arena:
			if f % 20 == 0:
				input.press_light()
			if f % 45 == 0:
				input.press_ranged()
			if f % 90 == 0:
				input.press_jump()
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			frame_ms.append((now - last) / 1000.0)
			last = now
	frame_ms.sort()
	var total := 0.0
	for v in frame_ms:
		total += v
	print("Combat Lab fight load (headless CPU): avg %.2f ms  p95 %.2f ms  p99 %.2f ms  max %.2f ms  over %d frames" % [
		total / frame_ms.size(), frame_ms[int(frame_ms.size() * 0.95)], frame_ms[int(frame_ms.size() * 0.99)],
		frame_ms[frame_ms.size() - 1], frame_ms.size()])
	get_tree().quit()
