class_name AtomicJson
extends RefCounted
## The one atomic JSON writer (M9, bible §29). SaveManager and every M9 store
## (platform achievements, challenge records) write through here, so a crash
## mid-write never destroys the last good file anywhere in user://.
##
## Contract (unchanged from SaveManager.save_profile since M0):
## write <file>.tmp, move the previous <file> to <file>.bak, then rename the
## tmp into place. read() falls back to <file>.bak when the primary file is
## missing or unreadable.


## Writes `data` as JSON (tab-indented by default). Creates the directory.
static func write(path: String, data: Variant, indent: String = "\t") -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var tmp_path := path + ".tmp"
	var bak_path := path + ".bak"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, indent))
	f.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		err = DirAccess.rename_absolute(path, bak_path)
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp_path, path)


## The Dictionary stored at `path`, or its backup's when the primary is
## unreadable (with a warning); {} when neither parses as a Dictionary.
static func read(path: String) -> Dictionary:
	var data := _read_dict(path)
	if data.is_empty():
		data = _read_dict(path + ".bak")
		if not data.is_empty():
			push_warning("AtomicJson: %s unreadable, recovered from backup" % path)
	return data


## Deletes a user:// directory and everything under it (tour and test store
## sandboxes). Refuses anything outside user:// so a bad path can never touch
## the project. A missing directory is a no-op.
static func remove_tree(dir: String) -> void:
	if not dir.begins_with("user://"):
		push_error("AtomicJson.remove_tree: refusing %s (user:// only)" % dir)
		return
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		remove_tree("%s/%s" % [dir, sub])
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, f])
	DirAccess.remove_absolute(dir)


static func _read_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
