class_name PlaytestSession
extends RefCounted
## One tester's run as plain JSON-able data: timestamped events, position
## samples per room (heatmaps, idle detection), frame-time histogram per room,
## input-device time, counters, and survey answers. The analyzer
## (PlaytestAnalyzer) only ever reads this format, never live game objects.

const SCHEMA := 1
## Frame-time histogram bucket upper edges (ms); the last bucket is open.
const BUCKETS: Array[float] = [8.4, 16.8, 20.0, 25.0, 33.4, 50.0, 100.0]

var data: Dictionary = {}


func _init(meta: Dictionary = {}) -> void:
	var hist: Array = []
	hist.resize(BUCKETS.size() + 1)
	hist.fill(0)
	data = {
		"schema": SCHEMA,
		"meta": meta,
		"events": [],
		"samples": {},
		"perf": {"histogram": hist, "rooms": {}, "spikes": []},
		"input": {"keyboard": 0.0, "pad": 0.0},
		"counters": {},
		"survey": {},
		"ended": "",
		"duration": 0.0,
	}


func add_event(t: float, type: String, room: String, pos: Vector2, extra: Dictionary = {}) -> Dictionary:
	var e := {"t": snappedf(t, 0.01), "type": type, "room": room, "x": roundi(pos.x), "y": roundi(pos.y)}
	e.merge(extra)
	(data["events"] as Array).append(e)
	return e


func add_sample(t: float, room: String, pos: Vector2) -> void:
	var samples: Dictionary = data["samples"]
	if not samples.has(room):
		samples[room] = []
	(samples[room] as Array).append([snappedf(t, 0.1), roundi(pos.x), roundi(pos.y)])


func add_frame(t: float, room: String, ms: float, spike_ms: float, max_spikes: int) -> void:
	var perf: Dictionary = data["perf"]
	var hist: Array = perf["histogram"]
	var b := BUCKETS.size()
	for i in BUCKETS.size():
		if ms <= BUCKETS[i]:
			b = i
			break
	hist[b] = int(hist[b]) + 1
	var rooms: Dictionary = perf["rooms"]
	if not rooms.has(room):
		rooms[room] = {"frames": 0, "total_ms": 0.0, "max_ms": 0.0, "spikes": 0}
	var r: Dictionary = rooms[room]
	r["frames"] = int(r["frames"]) + 1
	r["total_ms"] = float(r["total_ms"]) + ms
	r["max_ms"] = maxf(float(r["max_ms"]), ms)
	if ms > spike_ms:
		r["spikes"] = int(r["spikes"]) + 1
		var spikes: Array = perf["spikes"]
		if spikes.size() < max_spikes:
			spikes.append([snappedf(t, 0.01), room, snappedf(ms, 0.1)])


func count(key: String, amount: float = 1.0) -> void:
	var c: Dictionary = data["counters"]
	c[key] = float(c.get(key, 0.0)) + amount


func events_of(type: String) -> Array:
	return (data["events"] as Array).filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Atomic write (tmp + rename) so a crash mid-save keeps the previous file.
func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "", false))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


static func load_file(path: String) -> PlaytestSession:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or int((parsed as Dictionary).get("schema", 0)) != SCHEMA:
		return null
	var s := PlaytestSession.new()
	s.data = parsed
	return s
