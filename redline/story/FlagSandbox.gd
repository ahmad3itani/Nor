class_name FlagSandbox
extends RefCounted
## Dev/test flag sandbox (D-128). begin() snapshots the profile's flags and
## play time; the returned Callable puts them back and emits game_state_reset
## so switches, NPC posts, quests, arcs and the HUD re-read the profile. The
## Ending theatre plays inside one, so a dev replay never marks the profile.
##
## Only flags, play time and the dev taint (M9, D-145) are covered: a theatre ending locks input and
## Rook ignores hits, so nothing else can change during one (K-E6).

## How many sandboxes were opened (tests prove a real ending play takes none).
static var begin_count: int = 0


static func begin() -> Callable:
	begin_count += 1
	var flags: Dictionary = Game.state.flags.duplicate(true)
	var play_time: float = Game.state.play_time_sec
	var tainted: bool = Game.state.dev_tainted
	var state := Game.state
	return func() -> void:
		# A new game or load inside the sandbox replaced the state: never
		# write an old profile's flags into a different one.
		if Game.state != state:
			return
		Game.state.flags = flags.duplicate(true)
		Game.state.play_time_sec = play_time
		Game.state.dev_tainted = tainted
		EventBus.game_state_reset.emit()


## The "did everything in Act I" profile (dev/test helper; T09's
## StoryTestKit.act1_max_state delegates here). Stronger than any single
## playthrough: every flag any data can produce is set, except future flags.
## Order matters (4.3 raises on int == bool inside Game.set_flag's compare,
## and a later bool pass would overwrite a counter with true):
## 1. the act1_complete story preset;
## 2. bool true for every produced flag that is not a counter and does not
##    already hold a number;
## 3. the counters last: memories_remembered, every arc_<npc>_stage at its
##    Act I top, every mem_seen_<scene>, and every shop upgrade at least 1.
##
## M9: the profile is dev-tainted (no achievements, D-145), and M9 system
## flags are never written by the produced-flag loop: ng_* and demo_*, every
## null_* flag, and every flag only challenge data produces. null_open still
## ends up true, derived from act1_complete by the preset (D-154).
static func apply_act1_max_state() -> void:
	Game.state.dev_tainted = true
	StoryPresets.apply("act1_complete")
	var ints := _int_flags()
	var future := FutureFlagSet.shared()
	var v := ContentValidator.new().run(true)
	var produced := v.produced
	for f: String in produced:
		if future.has_flag(f) or ints.has(f) or f.begins_with("talks_") or _m9_system_flag(f, v):
			continue
		var cur: Variant = Game.state.flags.get(f)
		if typeof(cur) == TYPE_INT or typeof(cur) == TYPE_FLOAT:
			continue
		Game.set_flag(f, true)
	for s in MemoryLibrary.all_scenes():
		Game.set_flag(MemoryLibrary.flag_seen(s.id), true)
	Game.set_flag(MemoryLibrary.REMEMBERED_FLAG, MemoryLibrary.all_scenes().size())
	if Game.arcs:
		for a in Game.arcs.arcs:
			Game.set_flag(a.index_flag(), a.stages.size())
	# A quest reward can store `true` in a shop counter (chart_lowlight's
	# reward_flags map_lens); counters end as ints >= 1 here.
	for f in _upgrade_flags():
		var cur: Variant = Game.state.flags.get(f)
		if (typeof(cur) != TYPE_INT and typeof(cur) != TYPE_FLOAT) or Game.flag_int(f) < 1:
			Game.set_flag(f, maxi(Game.flag_int(f), 1))


## M9 system flags the Act I max state never sets itself.
static func _m9_system_flag(f: String, v: ContentValidator) -> bool:
	if f.begins_with("ng_") or f.begins_with("demo_") or f.begins_with("null_"):
		return true
	var paths: Array = v.producers.get(f, [])
	return not paths.is_empty() and paths.all(func(p: String) -> bool: return p.begins_with("res://data/challenges/"))


## Flags that hold numbers: memories_remembered, arc_<npc>_stage and every
## ShopItem.upgrade_flag (ShopMenu stores flag_int + 1). talks_* counters are
## matched by prefix.
static func _int_flags() -> Dictionary:
	var out := {MemoryLibrary.REMEMBERED_FLAG: true}
	if Game.arcs:
		for a in Game.arcs.arcs:
			out[a.index_flag()] = true
	for f in _upgrade_flags():
		out[f] = true
	return out


static func _upgrade_flags() -> PackedStringArray:
	var out := PackedStringArray()
	for path in DataDir.list("res://data/shops"):
		var shop := load(path) as ShopData
		if shop == null:
			continue
		for item in shop.items:
			if item != null and item.upgrade_flag != "" and not out.has(item.upgrade_flag):
				out.append(item.upgrade_flag)
	return out
