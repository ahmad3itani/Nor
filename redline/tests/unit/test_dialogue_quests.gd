extends RedlineTestCase
## M3.3: NPC dialogue rules, the dialogue box, quest flow and rewards.

var ORR: NpcProfile


func before_each() -> void:
	Game.new_game()
	ORR = load("res://data/npcs/orr.tres")


func after_each() -> void:
	get_tree().paused = false
	Game.new_game()


func test_npc_profiles_validate() -> void:
	for f in DirAccess.get_files_at("res://data/npcs"):
		if f.ends_with(".tres"):
			var p: NpcProfile = load("res://data/npcs/" + f)
			check(p.validate().is_empty(), "%s: %s" % [f, ", ".join(p.validate())])


func test_quests_validate() -> void:
	check(Game.quests.quests.size() >= 1, "no quests loaded")
	for q in Game.quests.quests:
		check(q.validate().is_empty(), "%s: %s" % [q.id, ", ".join(q.validate())])


func test_orr_lines_follow_quest_state() -> void:
	check(ORR.pick_dialogue().id == "orr_intro", "fresh game should get the intro")
	Game.apply_dialogue(ORR.pick_dialogue())
	check(ORR.pick_dialogue().id == "orr_waiting", "after intro Orr should wait")
	for f in ["repeater_market", "repeater_stack", "repeater_bell"]:
		Game.set_flag(f)
	check(ORR.pick_dialogue().id == "orr_report", "all repeaters should unlock the report")
	Game.apply_dialogue(ORR.pick_dialogue())
	check(ORR.pick_dialogue().id == "orr_after", "after completion Orr should move on")


func test_dead_air_completes_once_and_pays() -> void:
	var q: QuestData = load("res://data/quests/dead_air.tres")
	Game.set_flag(q.start_flag)
	check(q.current_stage() == 0, "should start at stage 0")
	Game.set_flag("repeater_market")
	check(q.stage_progress(0) == Vector2i(1, 3), "progress should be 1/3")
	Game.set_flag("repeater_stack")
	Game.set_flag("repeater_bell")
	check(q.current_stage() == 1, "should advance to the report stage")
	var scrap_before := Game.state.total_scrap()
	Game.set_flag("dead_air_reported")
	check(Game.has_flag(q.complete_flag), "quest not completed")
	check(Game.state.total_scrap() == scrap_before + q.reward_scrap, "scrap reward not paid")
	check(Game.state.owned_circuits.has(q.reward_circuit), "circuit reward not granted")
	Game.quests.evaluate()
	check(Game.state.total_scrap() == scrap_before + q.reward_scrap, "reward paid twice")


func test_dialogue_box_pauses_and_applies_effects() -> void:
	var box: CanvasLayer = load("res://ui/dialogue/DialogueBox.gd").new()
	add_child(box)
	var d: DialogueData = ORR.rules[ORR.rules.size() - 1].dialogue
	box.open(d, "Orr")
	check(get_tree().paused, "dialogue should pause the game")
	check(not Game.has_flag("quest_dead_air_started"), "effects applied before the end")
	for i in d.lines.size():
		box.advance()
	check(not get_tree().paused, "closing should unpause")
	check(Game.has_flag("quest_dead_air_started"), "finish effects not applied")
	box.queue_free()


func test_repeater_sets_flag_and_locks() -> void:
	var r := SignalRepeater.new()
	r.flag_id = "repeater_market"
	add_child(r)
	check(r.can_interact(null), "fresh repeater should be usable")
	r.interact(null)
	check(Game.has_flag("repeater_market") and not r.can_interact(null), "repeater did not set/lock")
	r.queue_free()


## M7/D1: both Undercity radios share orr_radio.tres, and either may be
## skipped, so every rule has to read right as the first thing heard. Forward
## campaign players (Pulse Blade in hand) get the lift-shaft call; a legacy
## save that walked down from the Relay gets the legacy or location-neutral
## call instead, never lines about a lift shaft it is not standing at.
func test_orr_radio_rules() -> void:
	var radio: NpcProfile = load("res://data/npcs/orr_radio.tres")
	# Forward campaign at FirstPursuit: lift-shaft call, then the reminder.
	Game.start_campaign()
	Game.set_flag("got_pulse_blade")
	check(radio.pick_dialogue().id == "orr_radio_shaft", "blade holder should get the lift-shaft call")
	Game.apply_dialogue(radio.pick_dialogue())
	check(Game.has_flag("met_orr_radio"), "the first call should set met_orr_radio")
	check(radio.pick_dialogue().id == "orr_radio_waiting", "after the call the radio should repeat the route")
	# Boss killed without ever using a radio: the after-call stands alone.
	Game.start_campaign()
	Game.set_flag("got_pulse_blade")
	Game.set_flag("collector_drone_defeated")
	check(radio.pick_dialogue().id == "orr_radio_after", "after the boss the EscapeTunnel radio should congratulate")
	Game.apply_dialogue(radio.pick_dialogue())
	check(Game.has_flag("orr_radio_after") and Game.has_flag("met_orr_radio"), "after-call should set both flags")
	check(radio.pick_dialogue().id == "orr_radio_climb", "after-call should be one-shot")
	# Legacy save that met Orr at the Relay: no second introduction.
	Game.new_game()
	Game.set_flag("met_orr")
	check(radio.pick_dialogue().id == "orr_radio_legacy", "legacy met_orr should get the crew-band line")
	Game.apply_dialogue(radio.pick_dialogue())
	check(radio.pick_dialogue().id == "orr_radio_waiting", "legacy call should lead to the reminder")
	# Legacy save without met_orr or the blade (EscapeTunnel from above).
	Game.new_game()
	var d := radio.pick_dialogue()
	check(d.id == "orr_radio_first", "fallback should be the location-neutral call, got %s" % d.id)
	for l in d.lines:
		check(not l.text.contains("lift shaft") and not l.text.contains("That eye was"), "fallback mentions FirstPursuit: %s" % l.text)
	Game.apply_dialogue(d)
	check(Game.has_flag("met_orr_radio"), "fallback should set met_orr_radio")
	check(radio.pick_dialogue().id == "orr_radio_waiting", "fallback should lead to the reminder")
