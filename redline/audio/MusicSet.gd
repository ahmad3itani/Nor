class_name MusicSet
extends Resource
## One district's full music tracks (SOUND_DIRECTION section 8, track mode),
## or the global default set when `district` is empty. Tracks are res://
## paths as Strings, not AudioStream references: MusicDirector loads them
## lazily and skips a path that does not exist, so a web or demo build can
## leave files out and fall back to the next set, then to the MusicSynth
## stems. An empty slot means "not here, ask the next set".

## PresentationIndex.MUSIC_DISTRICTS id (RoomPresentation.music_district), or
## "" for the default set every district falls back to.
@export var district: StringName = &""
@export_file("*.ogg") var title: String = ""
@export_file("*.ogg") var hub: String = ""
@export_file("*.ogg") var explore: String = ""
@export_file("*.ogg") var flow: String = ""
@export_file("*.ogg") var boss: String = ""
@export_file("*.ogg") var memory: String = ""
## Empty: AFTERMATH plays this set's explore track at `aftermath_gain`
## (never constant maximum intensity, bible section 28).
@export_file("*.ogg") var aftermath: String = ""
@export_range(0.0, 1.0) var aftermath_gain: float = 0.6
## The level of this set's tracks in dB (SOUND_DIRECTION sections 3 and 4:
## for music, mix_db is where the hierarchy lives). Tracks are normalised to
## -20 LUFS-I while the SFX sit near -25..-46 LUFS after their volume_db, so
## music at 0 dB would sit above tier 1-4 SFX. -13 = the manifest's -2 for
## every mus_* plus 11 dB of headroom, which puts EXPLORE (about -37 LUFS at
## the default sliders) under the tier-3 weapon sounds (about -33) and level
## with tier-4 movement. Chosen by measurement, not by ear: the listening
## pass (K-OV-1) tunes it.
@export_range(-40.0, 6.0) var mix_db: float = -13.0
## Per-slot trims on top of mix_db, slot name -> dB (e.g. flow and boss are
## the only dense music and sit higher; the title has no SFX to sit under).
@export var slot_db: Dictionary = {}
## Room scene path -> track path: per-boss themes without new states. Keyed
## by scene path, never by the (translatable) room name.
@export var boss_by_room: Dictionary = {}
## HUB growth: stem name (a MusicDirector.LAYERS entry) -> a free-time loop
## that replaces that synth stem over `hub` in track mode.
@export var extras: Dictionary = {}

## No player text: `title` is the title-screen track's path.
const LOC_EXEMPT := ["title"]
const SLOTS: Array[StringName] = [&"title", &"hub", &"explore", &"flow", &"boss", &"memory", &"aftermath"]


## The slot's path, or "" when this set has none.
func slot(name: StringName) -> String:
	if not SLOTS.has(name):
		return ""
	return str(get(name))


## Linear gain for a slot's track: mix_db plus the slot's trim.
func gain_for(slot_name: StringName) -> float:
	return db_to_linear(mix_db + float(slot_db.get(String(slot_name), slot_db.get(slot_name, 0.0))))


## Every path this set names (slots, bosses, extras), for tests and the
## build size check.
func all_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for s in SLOTS:
		if slot(s) != "":
			out.append(slot(s))
	for k: Variant in boss_by_room:
		out.append(str(boss_by_room[k]))
	for k: Variant in extras:
		out.append(str(extras[k]))
	return out
