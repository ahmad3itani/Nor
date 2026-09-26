class_name GhostCodec
extends RefCounted
## The one ghost file format, *.ghost (M9 D2 §4.2), for personal-best ghosts
## in user:// and shipped developer ghosts in res://data/challenges/ghosts:
##
##   magic "RLGH" | u16 format=1 | u32 header_len | header JSON (UTF-8)
##   | u32 raw_len | deflate(samples)            (little-endian)
##
## Written with store_buffer and read with get_buffer: never store_var/get_var
## with objects and never a .tres from user:// (a tampered Resource could
## embed a script). Loading validates the magic, the format, header_len <=
## 64 KiB, raw_len == frames × 8 and frames <= MAX_FRAMES; a bad file is
## ignored with a warning.

const MAGIC := "RLGH"
const FORMAT := 1
const MAX_HEADER := 65536
## 30 minutes at 60 fps. Longer runs still count; they just save no ghost.
const MAX_FRAMES := 108000
## Player state ids (Player._register_states) -> sample byte; unknown = 255.
const STATES: Array[StringName] = [&"idle", &"run", &"crouch", &"slide", &"air", &"dodge", &"dash", &"melee", &"hurt", &"heal"]
const UNKNOWN_STATE := 255


static func state_index(id: StringName) -> int:
	var i := STATES.find(id)
	return i if i >= 0 else UNKNOWN_STATE


static func state_id(index: int) -> StringName:
	return STATES[index] if index >= 0 and index < STATES.size() else &""


## Input bits: move_x in bits 0-1 (0/1/2 = -1/0/+1), then down, up,
## jump_pressed, jump_held, dodge, light, heavy, ranged, interact, heal.
static func encode_input(f: PlayerInputFrame) -> int:
	if f == null:
		return 1
	var bits := clampi(f.move_x, -1, 1) + 1
	var flags := [f.down_held, f.up_held, f.jump_pressed, f.jump_held, f.dodge_pressed, f.light_pressed,
		f.heavy_pressed, f.ranged_pressed, f.interact_pressed, f.heal_pressed]
	for i in flags.size():
		if flags[i]:
			bits |= 1 << (i + 2)
	return bits


static func decode_input(bits: int) -> PlayerInputFrame:
	var f := PlayerInputFrame.new()
	f.move_x = (bits & 3) - 1
	f.down_held = bits & (1 << 2) != 0
	f.up_held = bits & (1 << 3) != 0
	f.jump_pressed = bits & (1 << 4) != 0
	f.jump_held = bits & (1 << 5) != 0
	f.dodge_pressed = bits & (1 << 6) != 0
	f.light_pressed = bits & (1 << 7) != 0
	f.heavy_pressed = bits & (1 << 8) != 0
	f.ranged_pressed = bits & (1 << 9) != 0
	f.interact_pressed = bits & (1 << 10) != 0
	f.heal_pressed = bits & (1 << 11) != 0
	f.move = Vector2(f.move_x, 1.0 if f.down_held else (-1.0 if f.up_held else 0.0))
	return f


static func encode(g: GhostData) -> PackedByteArray:
	var header := JSON.stringify(g.header()).to_utf8_buffer()
	var raw := g.samples
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_data(MAGIC.to_ascii_buffer())
	buf.put_u16(FORMAT)
	buf.put_u32(header.size())
	buf.put_data(header)
	buf.put_u32(raw.size())
	buf.put_data(raw.compress(FileAccess.COMPRESSION_DEFLATE) if raw.size() > 0 else PackedByteArray())
	return buf.data_array


## The ghost in `bytes`, or null (with a warning naming `what`) when invalid.
static func decode(bytes: PackedByteArray, what: String = "ghost") -> GhostData:
	if bytes.size() < 14 or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return _bad(what, "bad magic")
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes
	buf.seek(4)
	if buf.get_u16() != FORMAT:
		return _bad(what, "unknown format")
	var header_len := buf.get_u32()
	if header_len <= 0 or header_len > MAX_HEADER or buf.get_position() + header_len + 4 > bytes.size():
		return _bad(what, "bad header length")
	var header_bytes := bytes.slice(buf.get_position(), buf.get_position() + header_len)
	buf.seek(buf.get_position() + header_len)
	var parsed: Variant = JSON.parse_string(header_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return _bad(what, "header is not a JSON object")
	var g := GhostData.new()
	g.apply_header(parsed)
	if g.frames < 0 or g.frames > MAX_FRAMES:
		return _bad(what, "frame count %d outside 0..%d" % [g.frames, MAX_FRAMES])
	var raw_len := buf.get_u32()
	if raw_len != g.frames * GhostData.SAMPLE_SIZE:
		return _bad(what, "raw length %d != frames × 8" % raw_len)
	var packed := bytes.slice(buf.get_position())
	if raw_len > 0:
		if packed.is_empty():
			return _bad(what, "truncated samples")
		var raw := packed.decompress(raw_len, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() != raw_len:
			return _bad(what, "truncated samples")
		g.samples = raw
	return g


static func save(path: String, g: GhostData) -> Error:
	if g == null or g.frames > MAX_FRAMES or g.sample_count() != g.frames:
		return ERR_INVALID_DATA
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(encode(g))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Reads a .ghost file (user:// or res://); null when missing or invalid.
static func load_file(path: String) -> GhostData:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return decode(FileAccess.get_file_as_bytes(path), path)


static func _bad(what: String, why: String) -> GhostData:
	push_warning("GhostCodec: ignoring %s (%s)" % [what, why])
	return null
