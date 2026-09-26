class_name GhostData
extends RefCounted
## One recorded run (M9 D2 §4.2): a header plus 8 bytes per counted frame.
## Deliberately NOT a Resource: ghosts load from user://, and a tampered .tres
## could embed a script, so files are plain bytes (GhostCodec) and nothing in
## them is ever instanced.
##
## Sample layout (little-endian): i16 x, i16 y (room-local px), u8 state
## (GhostCodec.STATES index, 255 = unknown), u8 flags (bit0 facing right,
## bit1 low, bit2 invulnerable, bit3 in hitstop), u16 input bits.

const SAMPLE_SIZE := 8
const FLAG_RIGHT := 1
const FLAG_LOW := 2
const FLAG_INVULN := 4
const FLAG_HITSTOP := 8

var challenge: String = ""
var revision: int = 1
var build: String = ""
## Counted frames (== samples.size() / SAMPLE_SIZE once finished).
var frames: int = 0
## ChallengeData.Outcome of the run.
var result: int = 0
var profile: int = 0
## "pb" | "dev" | "dev_hand".
var kind: String = "pb"
## [{"room": path, "start": frame}] in order: which room each frame is in.
var segments: Array = []
## Frame count at each split.
var splits: PackedInt32Array = PackedInt32Array()
var date: String = ""
var samples: PackedByteArray = PackedByteArray()


func sample_count() -> int:
	return samples.size() / SAMPLE_SIZE


func add_sample(x: int, y: int, state: int, flags: int, input_bits: int) -> void:
	var at := samples.size()
	samples.resize(at + SAMPLE_SIZE)
	samples.encode_s16(at, clampi(x, -32768, 32767))
	samples.encode_s16(at + 2, clampi(y, -32768, 32767))
	samples.encode_u8(at + 4, clampi(state, 0, 255))
	samples.encode_u8(at + 5, flags & 0xFF)
	samples.encode_u16(at + 6, input_bits & 0xFFFF)


## {x, y, state, flags, input} of sample `i` (clamped into range); {} when empty.
func sample(i: int) -> Dictionary:
	var n := sample_count()
	if n == 0:
		return {}
	var at := clampi(i, 0, n - 1) * SAMPLE_SIZE
	return {"x": samples.decode_s16(at), "y": samples.decode_s16(at + 2), "state": samples.decode_u8(at + 4),
		"flags": samples.decode_u8(at + 5), "input": samples.decode_u16(at + 6)}


## The room path frame `f` was recorded in ("" when there is no segment).
func room_at(f: int) -> String:
	var room := ""
	for s: Dictionary in segments:
		if int(s.get("start", 0)) > f:
			break
		room = str(s.get("room", ""))
	return room


func header() -> Dictionary:
	return {"challenge": challenge, "revision": revision, "build": build, "frames": frames, "result": result,
		"profile": profile, "kind": kind, "segments": segments.duplicate(true), "splits": Array(splits), "date": date}


func apply_header(h: Dictionary) -> void:
	challenge = str(h.get("challenge", ""))
	revision = int(h.get("revision", 1))
	build = str(h.get("build", ""))
	frames = int(h.get("frames", 0))
	result = int(h.get("result", 0))
	profile = int(h.get("profile", 0))
	kind = str(h.get("kind", "pb"))
	segments = []
	for s: Variant in h.get("segments", []):
		if s is Dictionary:
			segments.append({"room": str((s as Dictionary).get("room", "")), "start": int((s as Dictionary).get("start", 0))})
	splits = PackedInt32Array()
	for v: Variant in h.get("splits", []):
		splits.append(int(v))
	date = str(h.get("date", ""))
