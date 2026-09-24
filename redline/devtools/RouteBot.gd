class_name RouteBot
extends RefCounted
## Plays a room with scripted input to prove its route is traversable with
## the real movement physics (bible §34 "traversal validation"). Steps:
##   ["run", x]                     run until at x
##   ["jump", x]                    jump (held), steer to x, until landed
##   ["runjump", edge, x]           run to edge, jump, steer to x, land
##   ["slidejump", edge, x, lead?]  run, slide `lead` px before edge (14), jump at edge
##   ["dodgejump", edge, x]         run, dodge near edge, jump mid-dodge
##   ["dashjump", edge, x]          same with Dash (needs the unlock)
##   ["slide", x]                   run then hold down until at x (tunnels)
##   ["interact"] / ["attack", n] / ["heavy", n] / ["wait", frames]
##   ["exit", dir]                  move in dir until the room changes
##   ["shoot", n, aim]              fire the ranged weapon n times, 24 frames
##                                  apart; aim "fwd", "up" or "diag" (up+facing)
##   ["dodge", x]                   run toward x, dodge; ok if on the floor after
##   ["dodgejump_airdodge", edge, x, delay_frames]
##                                  dodge-jump, then air-dodge on the first
##                                  airborne frame >= delay_frames that the
##                                  dodge cooldown allows (~18 frames after
##                                  the ground dodge ends); fails if no air
##                                  dodge fired, else lands near x

var tree: SceneTree
var player: Player
var input: ScriptedInputSource
var log: PackedStringArray = []
var failure: String = ""
## Set when the player node vanished outside an "exit" step (death respawn,
## unexpected room change). The bot rebinds to the new player and fails.
var lost_player: bool = false
var _expect_exit: bool = false


func _init(p_tree: SceneTree, p_player: Player) -> void:
	tree = p_tree
	bind(p_player)


func bind(p_player: Player) -> void:
	player = p_player
	input = ScriptedInputSource.new()
	player.input_source = input


func _frame() -> void:
	await tree.physics_frame
	if is_instance_valid(player):
		return
	if not _expect_exit:
		lost_player = true
	# Never touch the freed body: wait for the next room's player and rebind.
	for f in 240:
		var room := SceneRouter.current_room as Room
		if room != null and is_instance_valid(room.player) and not SceneRouter.transitioning:
			bind(room.player)
			return
		await tree.physics_frame


func _dx(x: float) -> float:
	return x - player.global_position.x


func _steer(x: float, tolerance: float = 3.0) -> void:
	var dx := _dx(x)
	input.move_x = 0 if absf(dx) < tolerance else int(signf(dx))


## Runs every step; returns false and fills `failure` on the first failed step.
func run(steps: Array) -> bool:
	for i in steps.size():
		var step: Array = steps[i]
		var ok: bool = await _do(step)
		input.move_x = 0
		input.down_held = false
		input.release_jump()
		if lost_player:
			failure = "step %d %s: player lost (died or left the room); now in %s" % [i, step, SceneRouter.current_room.name if SceneRouter.current_room else "nothing"]
			return false
		if not ok:
			failure = "step %d %s failed at %s (state %s)" % [i, step, player.global_position.round(), player.current_state_id()]
			return false
		log.append("%s -> %s" % [step, player.global_position.round()])
	return true


func _do(step: Array) -> bool:
	match String(step[0]):
		"run":
			return await _run_to(float(step[1]))
		"jump":
			return await _jump_to(float(step[1]))
		"runjump":
			if not await _run_to(float(step[1]), 2.0, true):
				return false
			return await _jump_to(float(step[2]))
		"slidejump":
			return await _technique_jump(float(step[1]), float(step[2]), &"slide", float(step[3]) if step.size() > 3 else 14.0)
		"dodgejump", "dashjump":
			return await _technique_jump(float(step[1]), float(step[2]), &"dodge")
		"slide":
			return await _slide_to(float(step[1]))
		"interact":
			input.press_interact()
			for f in 12:
				await _frame()
			return true
		"attack", "heavy":
			for n in int(step[1]):
				if step[0] == "attack":
					input.press_light()
				else:
					input.press_heavy()
				for f in 22:
					await _frame()
			return true
		"wait":
			for f in int(step[1]):
				await _frame()
			return true
		"shoot":
			var aim := String(step[2]) if step.size() > 2 else "fwd"
			input.up_held = aim == "up" or aim == "diag"
			if aim == "diag":
				input.move_x = player.facing
			for n in int(step[1]):
				input.press_ranged()
				for f in 24:
					await _frame()
					if lost_player:
						_release_aim()
						return false
			_release_aim()
			return true
		"dodge":
			if not await _run_to(float(step[1]), 2.0, true):
				return false
			input.press_dodge()
			# The run keeps its momentum into the dodge, then stops: the next
			# step starts from rest rather than inheriting a held direction.
			for f in 16:
				await _frame()
				if lost_player:
					input.move_x = 0
					return false
			input.move_x = 0
			return player.is_on_floor()
		"dodgejump_airdodge":
			return await _technique_jump(float(step[1]), float(step[2]), &"dodge", 14.0, int(step[3]))
		"exit":
			var room := SceneRouter.current_room
			input.move_x = int(step[1])
			_expect_exit = true
			for f in 240:
				await _frame()
				if SceneRouter.current_room != room and not SceneRouter.transitioning:
					bind((SceneRouter.current_room as Room).player)
					_expect_exit = false
					return true
			_expect_exit = false
			return false
	return false


func _run_to(x: float, tolerance: float = 3.0, keep_speed: bool = false) -> bool:
	var last := player.global_position.x
	var stuck := 0
	for f in 900:
		var dx := _dx(x)
		if absf(dx) <= tolerance or (keep_speed and signf(dx) != signf(player.velocity.x) and absf(player.velocity.x) > 10.0):
			return true
		input.move_x = int(signf(dx))
		await _frame()
		if lost_player:
			return false
		stuck = stuck + 1 if absf(player.global_position.x - last) < 0.2 and player.is_on_floor() else 0
		last = player.global_position.x
		if stuck > 45:
			return false
	return false


## "shoot" releases everything on every exit, so aim never leaks into the
## next step (or the respawned player).
func _release_aim() -> void:
	input.up_held = false
	input.move_x = 0


func _jump_to(x: float, air_dodge_after: int = 0) -> bool:
	input.press_jump()
	var airborne := false
	var air_frames := 0
	var air_dodged := false
	for f in 240:
		_steer(x)
		await _frame()
		if lost_player:
			return false
		# Hold jump until landing, like a player going for distance: holding
		# through the apex keeps the apex-hang gravity (bible §5 feel tech).
		if not player.is_on_floor():
			airborne = true
			air_frames += 1
			# Keep pressing from the requested frame until the dodge state is
			# entered: the ground dodge's cooldown (0.3 s) can swallow an
			# early single press, and a step that silently skips the air
			# dodge would prove nothing.
			if air_dodge_after > 0 and not air_dodged and air_frames >= air_dodge_after:
				if player.current_state_id() == &"dodge":
					air_dodged = true
				else:
					input.press_dodge()
		elif airborne:
			# Let horizontal speed settle so the next step starts clean.
			for g in 4:
				_steer(x)
				await _frame()
				if lost_player:
					return false
			if air_dodge_after > 0 and not air_dodged:
				return false
			return absf(_dx(x)) < 40.0
	return false


## air_dodge_after > 0 adds an air dodge that many airborne frames into the
## jump (M7 dodge-jump + air-dodge teaching gaps).
func _technique_jump(edge: float, x: float, kind: StringName, slide_lead: float = 14.0, air_dodge_after: int = 0) -> bool:
	var dir := signf(x - player.global_position.x)
	input.move_x = int(dir)
	for f in 900:
		await _frame()
		if lost_player:
			return false
		var to_edge := (edge - player.global_position.x) * dir
		# Slide at the lip: friction bleeds ~4 px/s per frame, so a slide-jump
		# only out-ranges a run-jump when the jump comes 2-4 frames into it.
		if kind == &"slide" and to_edge < slide_lead and player.current_state_id() != &"slide":
			input.down_held = true
		# Dodge so its jump-cancel window (0.08 s, ~22 px) opens at the lip,
		# then jump as the centre crosses the edge.
		if kind == &"dodge" and to_edge < 26.0:
			input.press_dodge()
			for g in 14:
				await _frame()
				if lost_player:
					return false
				if g >= 4 and (edge - player.global_position.x) * dir < 2.0:
					break
			input.down_held = false
			return await _jump_to(x, air_dodge_after)
		# Jump at the very edge (centre just past it, feet still on the ground).
		if to_edge < 1.0:
			input.down_held = false
			return await _jump_to(x)
	return false


func _slide_to(x: float) -> bool:
	var dir := signf(x - player.global_position.x)
	input.move_x = int(dir)
	for f in 900:
		await _frame()
		if lost_player:
			return false
		if absf(player.velocity.x) > 120.0:
			input.down_held = true
		if (x - player.global_position.x) * dir <= 0.0:
			input.down_held = false
			for g in 10:
				await _frame()
				if lost_player:
					return false
			return player.is_on_floor()
	return false
