extends RedlineTestCase
## --tour=overhaul (presentation overhaul T10), headless, no rendering: the
## shot contract covers every backdrop kind the presentation data uses, each
## kind's room exists with its spawn, the --only parse, and the INSTANT rule.


func _used_kinds() -> Dictionary:
	var idx := load(PresentationIndex.PATH) as PresentationIndex
	var used := {}
	for d: Dictionary in [idx.rooms, idx.districts]:
		for k in d:
			var p := d[k] as RoomPresentation
			if p and p.backdrop_kind != &"":
				used[String(p.backdrop_kind)] = true
	return used


func test_covers_every_backdrop_kind_in_rooms_tres() -> void:
	var tour_kinds := OverhaulTour.kinds()
	var used := _used_kinds()
	check(used.size() >= 14, "rooms.tres uses the 14 kinds (%d)" % used.size())
	for k: String in used:
		check(tour_kinds.has(k), "the tour shoots backdrop kind %s" % k)
		check(OverhaulTour.shots("b").has(OverhaulTour.backdrop_shot(k)), "%s has a b-section shot" % k)
	for k in PresentationIndex.BACKDROP_KINDS:
		check(tour_kinds.has(String(k)), "the tour shoots declared kind %s" % k)
	var seen := {}
	for k in tour_kinds:
		check(not seen.has(k), "kind %s listed once" % k)
		seen[k] = true


func test_each_kind_room_has_that_kind_and_spawn() -> void:
	for r: Array in OverhaulTour.KIND_ROOMS:
		if String(r[0]) == "title":
			continue
		var path := String(r[1])
		check(ResourceLoader.exists(path), "%s: %s exists" % [r[0], path])
		if not ResourceLoader.exists(path):
			continue
		var p := PresentationIndex.for_room(path)
		check(p != null and String(p.backdrop_kind) == String(r[0]), "%s is a %s room" % [path.get_file(), r[0]])
		var probe := (load(path) as PackedScene).instantiate()
		var ids: Array[StringName] = []
		for m in probe.find_children("*", "SpawnMarker", true, false):
			ids.append((m as SpawnMarker).spawn_id)
		probe.free()
		check(ids.has(r[2]), "%s has spawn %s" % [path.get_file(), r[2]])


func test_shot_names_unique_and_prefixed() -> void:
	var seen := {}
	for s in OverhaulTour.SECTIONS:
		var list := OverhaulTour.shots(s)
		check(not list.is_empty(), "section %s has shots" % s)
		for n in list:
			check(n.begins_with("ov_%s_" % s), "%s is prefixed ov_%s_" % [n, s])
			check(not seen.has(n), "%s is unique" % n)
			seen[n] = true
	check(seen.size() <= 40, "a reviewable set (%d shots)" % seen.size())
	for v: Array in OverhaulTour.VARIANTS:
		for k: String in (v[1] as Dictionary):
			check(k in Settings, "variant %s sets a real setting (%s)" % [v[0], k])
	for f in OverhaulTour.VARIANT_FRAMES:
		check(f == "hit" or OverhaulTour.kinds().has(f), "variant frame %s is a kind or the hit" % f)


func test_every_section_has_a_method() -> void:
	var t := OverhaulTour.new(self)
	for s in OverhaulTour.SECTIONS:
		check(t.has_method("_section_" + s), "OverhaulTour._section_%s exists" % s)


func test_only_arg_parses() -> void:
	check(OverhaulTour.parse_only(PackedStringArray()) == OverhaulTour.SECTIONS, "no --only: every section")
	check(OverhaulTour.parse_only(PackedStringArray(["--out=/x", "--only=b,v"])) == PackedStringArray(["b", "v"]), "a subset")
	check(OverhaulTour.parse_only(PackedStringArray(["--only=u,x,u, c"])) == PackedStringArray(["u", "c"]), "unknown and repeated letters dropped")
	check(OverhaulTour.expected(PackedStringArray(["u"])) == OverhaulTour.UI_SHOTS, "expected() follows the selection")


func test_overhaul_forces_instant() -> void:
	var script := load("res://devtools/CaptureTour.gd") as GDScript
	check(int(script.call("tour_cinematic_mode", "overhaul", PackedStringArray())) == CinematicMode.Mode.INSTANT,
		"the overhaul tour runs INSTANT cinematics")
