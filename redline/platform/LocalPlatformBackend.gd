class_name LocalPlatformBackend
extends PlatformBackend
## The only shipped backend (D-141). Unlocks and lifetime stats already live in
## LocalStore and personal bests in RecordStore, so mirroring them is a no-op.
## Presence is kept in memory for the DebugOverlay line (§37.5).

var presence_key: String = ""
var presence_text: String = ""


func backend_id() -> StringName:
	return &"local"


func set_presence(key: String, text: String) -> void:
	presence_key = key
	presence_text = text


func clear_presence() -> void:
	presence_key = ""
	presence_text = ""
