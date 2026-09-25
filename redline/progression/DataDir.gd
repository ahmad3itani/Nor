class_name DataDir
extends RefCounted
## Directory scans that also work in an exported build. There DirAccess lists
## "x.tres.remap" / "x.tscn.remap" instead of the source files, while load()
## still takes the source path. Every runtime scan of a data or room folder
## goes through here (same rule as quests/QuestTracker.gd:_ready), so an
## exported playtest build sees the same content as the editor.


## "x.<ext>" or "x.<ext>.remap" -> "x.<ext>" (the name to load); anything
## else -> "".
static func load_name(file: String, ext: String = "tres") -> String:
	var name := file.trim_suffix(".remap")
	return name if name.get_extension() == ext and name.get_basename() != "" else ""


## Sorted, de-duplicated load paths of every .tres (or .tres.remap) directly
## in dir (not recursive).
static func list(dir: String) -> PackedStringArray:
	return _list(dir, "tres")


## Same rule for room scenes: "dir/x.tscn" for every .tscn / .tscn.remap.
static func list_scenes(dir: String) -> PackedStringArray:
	return _list(dir, "tscn")


static func _list(dir: String, ext: String) -> PackedStringArray:
	var seen := {}
	for f in DirAccess.get_files_at(dir):
		var n := load_name(f, ext)
		if n != "":
			seen["%s/%s" % [dir, n]] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out
