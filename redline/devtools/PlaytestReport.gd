extends Node
## Builds the M4 playtest report from collected session files (headless):
##   godot --headless res://devtools/PlaytestReport.tscn -- --in=/abs/sessions --out=/abs/report
## Defaults: --in=user://playtests  --out=user://playtest_report
## Writes REPORT.md plus one heatmap PNG per slice room.

const ROOM_DIR := "res://world/rooms/lowlight"


func _ready() -> void:
	var in_dir := Playtest.DIR
	var out_dir := "user://playtest_report"
	var title := "REDLINE playtest report"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--in="):
			in_dir = arg.trim_prefix("--in=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--title="):
			title = arg.trim_prefix("--title=")
	print("Playtest report: %s" % build(in_dir, out_dir, title))
	get_tree().quit()


## Returns a one-line summary (or an error) for the console.
static func build(in_dir: String, out_dir: String, title: String) -> String:
	var analyzer := PlaytestAnalyzer.new(Playtest.config)
	var n := analyzer.load_dir(in_dir)
	if n == 0:
		return "no session_*.json files in %s" % ProjectSettings.globalize_path(in_dir)
	DirAccess.make_dir_recursive_absolute(out_dir + "/heatmaps")
	var result := analyzer.analyze()
	var md := analyzer.render_markdown(result, title)
	md += "\n## Heatmaps\n\nGrey = geometry, orange = where players spent time, red × = deaths, orange dots = pit falls, yellow = reported moments.\n\n"
	for f in DirAccess.get_files_at(ROOM_DIR):
		if not f.ends_with(".tscn"):
			continue
		var img := analyzer.render_heatmap("%s/%s" % [ROOM_DIR, f])
		if img:
			var png := "heatmaps/%s.png" % f.get_basename()
			img.save_png("%s/%s" % [out_dir, png])
			md += "### %s\n![%s](%s)\n\n" % [f.get_basename(), f.get_basename(), png]
	var file := FileAccess.open(out_dir + "/REPORT.md", FileAccess.WRITE)
	file.store_string(md)
	file.close()
	return "%d sessions -> %s/REPORT.md (§44: %s)" % [n, ProjectSettings.globalize_path(out_dir),
		"PASS" if result["scorecard"]["pass"] else "not yet"]
