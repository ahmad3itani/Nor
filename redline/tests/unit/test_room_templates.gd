extends RedlineTestCase
## M6 room pipeline: recorded traversal metrics stay in sync with the real
## movement, and templates built from them do what they promise (proven by
## RouteBot with the real player physics).

const PLAYER_SCENE := preload("res://player/Player.tscn")

var world: Node2D


func after_each() -> void:
	if is_instance_valid(world):
		world.queue_free()
	await physics_frames(2)


func test_recorded_metrics_match_current_movement() -> void:
	var stored: TraversalMetrics = load(RoomTemplate.METRICS_PATH)
	var fresh := await TrajectoryRecorder.record(self, load("res://data/movement/default_movement.tres"))
	for t in TraversalMetrics.TECHNIQUES:
		check_near(fresh.reach(t), stored.reach(t), 1.5, "%s reach changed: re-run MovementProbe -- --write-metrics" % t)
		check_near(fresh.peak(t), stored.peak(t), 1.5, "%s peak changed: re-run MovementProbe -- --write-metrics" % t)
	check(stored.reach("slide_jump") > stored.reach("run_jump") and stored.reach("dodge_jump") > stored.reach("slide_jump"), "technique order broken")


## A world with a GapChallenge at x=0 and a player on the near lip; the bot
## runs `step` and the result says whether Rook ended on the far side.
func _attempt(gap_technique: String, step: Array) -> Dictionary:
	world = Node2D.new()
	add_child(world)
	var gap := GapChallenge.new()
	gap.technique = gap_technique
	world.add_child(gap)
	gap.build()
	var p: Player = PLAYER_SCENE.instantiate()
	p.config = load("res://data/movement/default_movement.tres")
	p.abilities = PlayerAbilities.new()
	world.add_child(p)
	p.respawn(Vector2(-140, -2))
	await physics_frames(5)
	var bot := RouteBot.new(get_tree(), p)
	var target := gap.gap_width() + 40.0
	await bot.run([[step[0], 2.0, target] + step.slice(1)])
	var pos := p.global_position
	return {"far": pos.y < 1.0 and pos.x > gap.gap_width(), "pos": pos, "gap": gap.gap_width(), "leak": gap.leaks_to()}


func test_slide_gap_clears_with_slide_jump() -> void:
	var r := await _attempt("slide_jump", ["slidejump"])
	check(r["far"], "slide-jump should clear the %d px slide gap (ended at %s)" % [r["gap"], r["pos"]])


func test_slide_gap_stops_a_run_jump_into_the_well() -> void:
	var r := await _attempt("slide_jump", ["runjump"])
	check(not r["far"], "a run-jump from the lip should fall short of the %d px gap" % r["gap"])
	check(Rect2(-6, 100, float(r["gap"]) + 12.0, 100).has_point(r["pos"]), "a miss should land in the catch well (at %s)" % r["pos"])


func test_dodge_gap_clears_with_dodge_jump() -> void:
	var r := await _attempt("dodge_jump", ["dodgejump"])
	check(r["leak"] == "", "dodge gap should be a real gate, leaks to %s" % r["leak"])
	check(r["far"], "dodge-jump should clear the %d px gap (ended at %s)" % [r["gap"], r["pos"]])


func test_dodge_gap_stops_a_slide_jump() -> void:
	var r := await _attempt("dodge_jump", ["slidejump"])
	check(not r["far"], "a slide-jump should not clear the %d px dodge gap" % r["gap"])


func test_climb_steps_are_climbable_and_warn_when_too_tall() -> void:
	world = Node2D.new()
	add_child(world)
	var floor_block := GrayboxBlock.new()
	floor_block.position = Vector2(-200, 0)
	floor_block.size = Vector2(600, 64)
	world.add_child(floor_block)
	var steps := ClimbSteps.new()
	world.add_child(steps)
	steps.build()
	check(steps._get_configuration_warnings().is_empty(), "48 px steps should be fine")
	var p: Player = PLAYER_SCENE.instantiate()
	p.config = load("res://data/movement/default_movement.tres")
	p.abilities = PlayerAbilities.new()
	world.add_child(p)
	p.respawn(Vector2(30, -2))
	await physics_frames(5)
	var bot := RouteBot.new(get_tree(), p)
	var route: Array = []
	for pos in steps.step_positions():
		route.append(["jump", pos.x + steps.step_width * 0.5])
	check(await bot.run(route), "climb failed: %s" % bot.failure)
	check_near(p.global_position.y, -steps.step_rise * steps.steps, 2.0, "should stand on the top step")
	steps.step_rise = 60.0
	check(not steps._get_configuration_warnings().is_empty(), "60 px steps must warn (jump peaks at ~56)")


func test_doorway_places_exit_and_spawn_consistently() -> void:
	var d := Doorway.new()
	d.side = -1
	d.entry_id = &"from_test"
	d.target_room = "res://world/rooms/lowlight/Relay.tscn"
	d.target_entry = &"from_alley"
	d.build()
	var exit := d.get_node("Exit") as RoomExit
	var spawn := d.get_node("Spawn_from_test") as SpawnMarker
	check(exit.position == Vector2(-16, -96) and exit.target_entry == &"from_alley", "exit placement wrong")
	check(spawn.position == Vector2(36, 0) and spawn.facing == 1, "spawn should be inside, facing in")
	d.free()


## A template saved without baked children (as a script would write it)
## still has geometry in game and for the tools that read scenes.
func test_unbaked_template_expands_for_tools_and_runtime() -> void:
	var root := Node2D.new()
	var gap := GapChallenge.new()
	gap.technique = "run_jump"
	root.add_child(gap)
	check(gap.get_child_count() == 0, "starts unbaked")
	RoomTemplate.expand_all(root)
	check(root.find_children("*", "GrayboxBlock", true, false).size() >= 2, "expand_all should build the geometry")
	root.free()
	var g2 := GapChallenge.new()
	add_child(g2)
	check(g2.find_children("*", "GrayboxBlock", true, false).size() >= 2, "runtime _ready should build an unbaked template")
	g2.queue_free()
