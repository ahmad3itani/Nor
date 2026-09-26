class_name NgPlusDevActions
extends RefCounted
## Dev console helpers for New Game+ and the remix (M9 D3 §3.12). Debug
## builds only (the dev console never opens in a release export). Actions
## that fabricate progress set dev_tainted (D-145), so a dev-made NG+ never
## earns achievements; restoring a real archive does not.


## NG+ right now from the live profile. A profile that has not closed Act I
## gets act1_complete fabricated first (and is tainted). Saves go wherever
## SaveManager.save_dir points (tests use a temp dir). Returns begin()'s answer.
static func start_now(remix: bool, keep_dash: bool = true) -> bool:
	if not NewGamePlus.can_begin(Game.state.to_dict()):
		Game.state.dev_tainted = true
		Game.set_flag("act1_complete")
	return NewGamePlus.begin({"from": "", "remix": remix, "keep_dash": keep_dash})


## Flips the remix option of the live profile; the next room load applies
## it. An option, not progress: no taint.
static func toggle_remix() -> bool:
	var f := NewGamePlus.config().remix_flag
	Game.set_flag(f, not Game.has_flag(f))
	return Game.has_flag(f)


## "Force remix": every room applies its remix whatever the flags say (this
## session only; the test teardown's cache reset puts it back).
static func toggle_force() -> bool:
	RemixLibrary.force_active = not RemixLibrary.force_active
	return RemixLibrary.force_active


## One line per remix file plus the ops of the current room, for the page
## and the log.
static func remix_report() -> String:
	var lines := PackedStringArray()
	var here := SceneRouter.current_room_path
	var r := RemixLibrary.for_room(here) if here != "" else null
	if r != null:
		lines.append("%s: %d ops applied on load (%s)" % [here.get_file().get_basename(), int(RemixLibrary.last_applied.get(here, 0)),
			"active" if (r.is_active() or RemixLibrary.force_active) else "off"])
		for op in r.ops:
			if op != null:
				lines.append("  " + op.describe())
	else:
		lines.append("%s: no remix" % (here.get_file().get_basename() if here != "" else "no room"))
	lines.append("%d remix files; cycle %d, remix %s, early Dash %s" % [RemixLibrary.all_paths().size(), NewGamePlus.cycle(),
		"on" if NewGamePlus.remix_on() else "off", "on" if NewGamePlus.keep_dash_on() else "off"])
	return "\n".join(lines)


static func print_remix_report() -> String:
	var text := remix_report()
	print("REMIX_REPORT\n" + text)
	return text


## Archived cycles of the live profile on disk: [[cycle, path], ...].
static func archives() -> Array:
	var out: Array = []
	var prefix := "profile_%d.cycle" % Game.profile_id
	for f in DirAccess.get_files_at(SaveManager.save_dir):
		if f.begins_with(prefix) and f.ends_with(".json") and f.get_slice(".", 1).trim_prefix("cycle").is_valid_int():
			out.append([int(f.get_slice(".", 1).trim_prefix("cycle")), "%s/%s" % [SaveManager.save_dir, f]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


## Puts an archived cycle back as the live save and loads it (dev only,
## R09.5: players have no restore in M9). The replaced save is archived as
## "restored<N>" first, so nothing is lost.
static func restore_archive(cycle: int) -> bool:
	var path := "%s/profile_%d.cycle%d.json" % [SaveManager.save_dir, Game.profile_id, cycle]
	var data := AtomicJson.read(path)
	if data.is_empty():
		return false
	SaveManager.archive_profile(Game.profile_id, "restored%d" % cycle)
	if SaveManager.save_profile(Game.profile_id, SaveManager.migrate(data)) != OK:
		return false
	return Game.load_game(Game.profile_id)
