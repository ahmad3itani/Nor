class_name PlatformBackend
extends RefCounted
## The platform adapter interface (M9 D1 §6.1, D-141). Every method is a
## virtual no-op. The local store (LocalStore) is the truth; a backend only
## MIRRORS it (unlocks, stats, boards, presence) and never gates anything, so
## a backend that fails or is missing changes nothing about play (§37.7).
##
## Only LocalPlatformBackend ships. A storefront adapter would subclass this
## and be picked by PlatformBackends.create(); Docs/PLATFORM_SERVICES.md
## describes that slot. No networking may ever live under res://platform.


func backend_id() -> StringName:
	return &"none"


## False makes Platform fall back to the local backend.
func init() -> bool:
	return true


func shutdown() -> void:
	pass


## Called every frame by Platform._process (an adapter pumps callbacks here).
func poll(_delta: float) -> void:
	pass


# --- Achievements (mirror only) ---

func unlock(_api_name: String) -> void:
	pass


## Dev reset only.
func lock(_api_name: String) -> void:
	pass


## Pushes the local truth at store load, so an adapter catches up unlocks
## earned offline or before it existed.
func sync_unlocked(_api_names: PackedStringArray) -> void:
	pass


# --- Stats ---

func set_stat(_api_name: String, _value: float, _is_int: bool) -> void:
	pass


func store_stats() -> void:
	pass


func reset_all() -> void:
	pass


# --- Leaderboards (the local board is T04's RecordStore) ---

func submit_score(_board: String, _score: int, _meta: Dictionary) -> void:
	pass


## A backend's cached board; the local backend has none (RecordStore is read
## directly by the UI).
func top_scores(_board: String, _count: int) -> Array:
	return []


# --- Rich presence ---

func set_presence(_key: String, _text: String) -> void:
	pass


func clear_presence() -> void:
	pass


# --- Cloud saves ---

func cloud_enabled() -> bool:
	return false


## SaveManager wrote `path` (through Platform.notify_file_written).
func cloud_file_written(_path: String) -> void:
	pass
