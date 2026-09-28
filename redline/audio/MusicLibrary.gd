class_name MusicLibrary
extends Resource
## Every MusicSet (data/audio/music/music_library.tres). MusicDirector asks
## the room's district set first, then the default set (district ""), then
## falls back to the synth stems.

@export var sets: Array[MusicSet] = []


func set_for(district: StringName) -> MusicSet:
	for s in sets:
		if s != null and s.district == district:
			return s
	return null


## The sets to ask, most specific first: the district's, then the default.
func chain(district: StringName) -> Array[MusicSet]:
	var out: Array[MusicSet] = []
	if district != &"":
		var own := set_for(district)
		if own != null:
			out.append(own)
	var def := set_for(&"")
	if def != null:
		out.append(def)
	return out


## ContentValidator resource protocol: every path loads, loops, and every
## extras key is a MusicDirector stem.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for s in sets:
		if s == null:
			out.append("empty music set")
			continue
		if seen.has(s.district):
			out.append("two music sets for district '%s'" % s.district)
		seen[s.district] = true
		for p in s.all_paths():
			if not ResourceLoader.exists(p):
				out.append("music set '%s': missing track %s" % [s.district, p])
		for k: Variant in s.boss_by_room:
			if not ResourceLoader.exists(str(k)):
				out.append("music set '%s': boss_by_room names no room %s" % [s.district, k])
		for k: Variant in s.extras:
			# MusicDirector.LAYERS, spelled out: a resource script must not name an autoload.
			if not (StringName(str(k)) in [&"pad", &"bass", &"drums", &"arp", &"lead"]):
				out.append("music set '%s': extras key '%s' is not a stem" % [s.district, k])
	return out
