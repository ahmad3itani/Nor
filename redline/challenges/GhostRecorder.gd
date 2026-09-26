class_name GhostRecorder
extends RefCounted
## Records the live run as a ghost (M9 D2 §4.3): one sample per COUNTED
## frame, with exactly the clock's gating (so transition frames, which depend
## on the render rate, never enter a ghost), and a new segment whenever the
## sampled room changes. Recording past MAX_FRAMES just stops: the run still
## counts, it saves no ghost.

var data: GhostData = null
var _room: String = ""
var _overflow: bool = false


func begin(ch: ChallengeData, profile: int, kind: String = "pb") -> void:
	data = GhostData.new()
	data.challenge = ch.id if ch else ""
	data.revision = ch.revision if ch else 1
	data.build = BuildInfo.version()
	data.profile = profile
	data.kind = kind
	_room = ""
	_overflow = false


func recording() -> bool:
	return data != null


## One counted frame. `room_path` is the loaded room; the position is stored
## room-local, rounded to 1 px.
func sample(player: Player, room: Node2D, room_path: String) -> void:
	if data == null or player == null or not is_instance_valid(player):
		return
	if data.sample_count() >= GhostCodec.MAX_FRAMES:
		_overflow = true
		return
	var n := data.sample_count()
	if room_path != _room:
		_room = room_path
		data.segments.append({"room": room_path, "start": n})
	var origin := room.global_position if room and is_instance_valid(room) else Vector2.ZERO
	var local := player.global_position - origin
	var flags := 0
	if player.facing > 0:
		flags |= GhostData.FLAG_RIGHT
	if player.is_low:
		flags |= GhostData.FLAG_LOW
	if player.invulnerable:
		flags |= GhostData.FLAG_INVULN
	if player.hitstop_timer > 0.0:
		flags |= GhostData.FLAG_HITSTOP
	data.add_sample(roundi(local.x), roundi(local.y), GhostCodec.state_index(player.current_state_id()), flags,
		GhostCodec.encode_input(player.last_input))


## Marks a split at the current sample count.
func split() -> void:
	if data:
		data.splits.append(data.sample_count())


## The finished ghost, or null when there is nothing (or too much) to keep.
func finish(result: int) -> GhostData:
	if data == null or _overflow or data.sample_count() == 0:
		data = null
		return null
	var g := data
	g.frames = g.sample_count()
	g.result = result
	g.date = Time.get_datetime_string_from_system()
	data = null
	return g


func discard() -> void:
	data = null
	_room = ""
	_overflow = false
