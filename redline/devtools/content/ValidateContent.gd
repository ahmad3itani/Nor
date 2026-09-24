extends Node
## Headless content check (bible §34):
##   godot --headless res://devtools/content/ValidateContent.tscn [-- --out=/abs/report.md]
## Prints the report; exit code 1 when there are errors (CI-friendly).


func _ready() -> void:
	var v := ContentValidator.new().run()
	var text := v.report()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var f := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			f.store_string(text)
			f.close()
	print(text)
	get_tree().quit(0 if v.ok() else 1)
