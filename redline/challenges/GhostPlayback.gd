class_name GhostPlayback
extends RefCounted
## Plays a GhostData back against the live run clock (M9 D2 §4.4). Playback
## is transform-based: the ghost never depends on enemies or bosses acting the
## same, so it stays valid when AI drifts, and it crosses rooms. Rewinding is
## free: the frame comes from the clock every tick.

var data: GhostData
## "pb" | "dev": the actor's tag and outline pattern.
var kind: String = "pb"


func _init(p_data: GhostData = null, p_kind: String = "pb") -> void:
	data = p_data
	kind = p_kind


## {room, x, y, state, flags, finished} at clock frame `f`; the ghost holds
## its last sample (with finished = true) once its run is over.
func frame_at(f: int) -> Dictionary:
	if data == null or data.sample_count() == 0:
		return {}
	var n := data.sample_count()
	var i := clampi(f, 0, n - 1)
	var s := data.sample(i)
	s["room"] = data.room_at(i)
	s["finished"] = f >= n - 1
	return s


## Live frames minus the ghost's frames at split `i`: positive = the live run
## is slower (▲ on the HUD), negative = faster (▼); 0 when unknown.
func delta_at_split(i: int, frames: int) -> int:
	if data == null or i < 0 or i >= data.splits.size():
		return 0
	return frames - data.splits[i]
