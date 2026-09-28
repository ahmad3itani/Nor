extends RedlineTestCase
## Presentation overhaul T08 (audio): SFX overrides with the synth fallback,
## priorities and voice stealing, the new ids, ambience beds and the drip
## emitter, footsteps per surface, the Ambience bus, and MusicDirector's track
## mode (headless: track choices only, no players).

const BANK_PATH := "res://data/audio/placeholder_sfx.tres"
const BEDS_PATH := "res://data/audio/ambience/beds.tres"
const LIBRARY_PATH := "res://data/audio/music/music_library.tres"
const PIT := "res://tests/fixtures/scaffold_pit.tscn"
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const SAVE_DIR := "user://test_audio_overhaul_saves"
const PLAYTEST_DIR := "user://test_audio_overhaul_playtests"
const NEW_IDS: Array[StringName] = [&"ui_confirm", &"ui_back", &"boss_defeat", &"secret_found",
	&"footstep_concrete", &"footstep_metal", &"footstep_water", &"footstep_wood", &"land_water"]
## Ids that must stay on the synth (INTEGRATION_NOTES 2.5).
const SYNTH_ONLY: Array[StringName] = [&"shoot_pistol", &"memory_beat", &"memory_tear", &"memory_detail",
	&"footstep_water", &"footstep_wood"]

var root: Node2D = null
var _saved_sfx: float
var _saved_amb: float


func before_each() -> void:
	_saved_sfx = Settings.sfx_volume
	_saved_amb = Settings.ambience_volume


func after_each() -> void:
	Settings.sfx_volume = _saved_sfx
	Settings.ambience_volume = _saved_amb
	AudioManager.apply_volume()
	AudioManager.load_bank(load(BANK_PATH) as SfxBank)
	AudioManager.stop_all()
	AudioManager.ambience.apply_presentation(null)
	if root != null:
		SceneRouter.current_room = null
		SceneRouter.current_room_path = ""
		SceneRouter.world_root = null
		root.queue_free()
		root = null
		Game.new_game()
		await physics_frames(2)
		SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
		Playtest.dir = Playtest.DIR
		AtomicJson.remove_tree(SAVE_DIR)
		AtomicJson.remove_tree(PLAYTEST_DIR)


## A world root with saves and playtest files in temp dirs (test_zz_user_dir_clean).
func _world() -> void:
	SaveManager.save_dir = SAVE_DIR
	Playtest.dir = PLAYTEST_DIR
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


# --- SFX bank ---------------------------------------------------------------

func test_every_bank_id_resolves_to_a_stream() -> void:
	var bank := load(BANK_PATH) as SfxBank
	var overridden := 0
	for def in bank.sounds:
		var s := AudioManager.stream_for(def.id)
		check(s != null, "%s has no stream" % def.id)
		check(def.override_stream == null, "%s: the bank stores paths, never streams" % def.id)
		if def.override_path != "":
			overridden += 1
			check(ResourceLoader.exists(def.override_path), "%s: override file %s exists" % [def.id, def.override_path])
			check(not (s is AudioStreamWAV), "%s must play its override" % def.id)
		else:
			check(s is AudioStreamWAV, "%s without an override must play the synth" % def.id)
		# The synth stays the fallback for every id: render always synthesises.
		check(SfxSynth.render(def) is AudioStreamWAV, "%s: render() must return the synth WAV" % def.id)
		check(def.duration > 0.0 and def.duration < 1.0, "%s: synth fallback under 1 s" % def.id)
		check(def.priority >= 1 and def.priority <= 5, "%s: priority tier %d" % [def.id, def.priority])
	check(overridden >= 45, "the phase-A assets are wired (%d overrides)" % overridden)
	for id in SYNTH_ONLY:
		check(_def(bank, id) != null and _def(bank, id).override_path == "", "%s stays on the synth" % id)


func test_randomizer_ids_and_ui_assets() -> void:
	var bank := load(BANK_PATH) as SfxBank
	for id: StringName in [&"jump", &"slash", &"hit", &"ui_tick", &"footstep_concrete", &"footstep_metal"]:
		check(AudioManager.stream_for(id) is AudioStreamRandomizer, "%s plays a randomizer of takes" % id)
	for id: StringName in [&"ui_confirm", &"ui_back", &"achievement"]:
		check(AudioManager.bus_for(id) == &"UI", "%s rides the UI bus" % id)
	check(AudioManager.bus_for(&"footstep_concrete") == &"SFX", "footsteps ride the SFX bus")
	check(AudioManager.stream_length(AudioManager.stream_for(&"jump")) > 0.05, "randomizer length is its longest take")


func test_missing_override_falls_back_to_synth() -> void:
	# The real failure: the shipped bank text with one row pointing at a file
	# that is not there (a stripped build or a removed asset). The bank must
	# still load (no [ext_resource] to a missing file), that id plays the
	# synth and every other id keeps its asset.
	var text := FileAccess.get_file_as_string(BANK_PATH)
	var gone := 'override_path = "res://assets/audio/sfx/%s.ogg"' % "t08_not_there"
	var edited := text.replace('override_path = "res://assets/audio/sfx/dash.ogg"', gone)
	check(edited != text, "the bank has a dash override row to break")
	var dir := "user://test_audio_bank"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/bank.tres"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(edited)
	f.close()
	var bank := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SfxBank
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir)
	check(bank != null, "a bank with a missing override file still loads")
	if bank == null:
		return
	AudioManager.load_bank(bank)
	check(AudioManager.stream_for(&"dash") is AudioStreamWAV, "the missing override falls back to the synth")
	check(AudioManager.stream_for(&"dodge") is AudioStreamOggVorbis, "other ids keep their files")
	check(AudioManager.stream_for(&"jump") is AudioStreamRandomizer, "randomizer ids keep their takes")
	# An in-memory stream still wins (tools and tests).
	var real := SfxDefinition.new()
	real.id = &"t08_real"
	real.override_stream = load("res://assets/audio/sfx/dash.ogg") as AudioStream
	var b2 := SfxBank.new()
	b2.sounds = [real]
	AudioManager.load_bank(b2)
	check(AudioManager.stream_for(&"t08_real") is AudioStreamOggVorbis, "a present override plays the file")


func test_new_ids_exist() -> void:
	for id in NEW_IDS:
		check(AudioManager.has_sfx(id), "missing sfx %s" % id)
	for s in PresentationIndex.SURFACES:
		check(AudioManager.has_sfx(FootstepDirector.sfx_id(s)), "no footstep for surface %s" % s)
	var bank := load(BANK_PATH) as SfxBank
	check(_def(bank, &"player_hurt").priority == 1 and _def(bank, &"enemy_telegraph").priority == 1, "tier 1: hurt, telegraph")
	check(_def(bank, &"scrap_pickup").priority == 5, "tier 5: pickups")
	check(_def(bank, &"footstep_concrete").volume_db <= -18.0, "footsteps are the quietest gameplay sound")


func test_voice_stealing_keeps_priority() -> void:
	var vip := SfxDefinition.new()
	vip.id = &"t08_vip"
	vip.duration = 0.9
	vip.priority = 1
	var spam := SfxDefinition.new()
	spam.id = &"t08_spam"
	spam.duration = 0.5
	spam.priority = 5
	var mid := SfxDefinition.new()
	mid.id = &"t08_mid"
	mid.duration = 0.5
	mid.priority = 3
	var bank := SfxBank.new()
	bank.sounds = [vip, spam, mid]
	AudioManager.load_bank(bank)
	AudioManager.stop_all()
	AudioManager.play_sfx(&"t08_vip")
	for i in AudioManager.VOICES * 3:
		AudioManager.play_sfx(&"t08_spam")
	var busy := AudioManager.busy_ids()
	check(busy.has(&"t08_vip"), "a priority-1 sound survives priority-5 spam")
	check(busy.size() == AudioManager.VOICES, "spam fills the other voices (%d busy)" % busy.size())
	# A more important sound takes a spam voice; spam never takes it back.
	AudioManager.play_sfx(&"t08_mid")
	for i in AudioManager.VOICES * 2:
		AudioManager.play_sfx(&"t08_spam")
	busy = AudioManager.busy_ids()
	check(busy.has(&"t08_mid") and busy.has(&"t08_vip"), "spam does not steal more important voices: %s" % [busy])
	# All voices held by tier 1: a tier-5 sound is dropped, not played.
	AudioManager.stop_all()
	for i in AudioManager.VOICES:
		AudioManager.play_sfx(&"t08_vip")
	AudioManager.play_sfx(&"t08_spam")
	check(not AudioManager.busy_ids().has(&"t08_spam"), "a tier-5 sound never cuts a tier-1 voice")


func test_stingers_wired_through_eventbus() -> void:
	var wired := {}
	for sig: StringName in [&"boss_defeated", &"secret_found"]:
		for c: Dictionary in EventBus.get_signal_connection_list(sig):
			if (c["callable"] as Callable).get_object() == AudioManager:
				wired[sig] = true
	check(wired.has(&"boss_defeated"), "boss_defeated plays boss_defeat")
	check(wired.has(&"secret_found"), "secret_found plays secret_found")


# --- buses ------------------------------------------------------------------

func test_ambience_bus_follows_sfx_times_ambience_volume() -> void:
	var idx := AudioServer.get_bus_index(&"Ambience")
	check(idx >= 0, "Ambience bus exists")
	Settings.sfx_volume = 0.5
	Settings.ambience_volume = 0.4
	AudioManager.apply_volume()
	check_near(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.2, 0.002, "Ambience = sfx x ambience")
	Settings.sfx_volume = 1.0
	Settings.ambience_volume = 0.8
	AudioManager.apply_volume()
	check_near(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.8, 0.002, "Ambience follows the sliders back")
	var fx := AudioServer.get_bus_index(&"AmbienceFx")
	check(fx >= 0 and AudioServer.get_bus_send(fx) == &"Ambience", "the drip bus sends into Ambience")
	var music := AudioServer.get_bus_index(&"Music")
	var duck: AudioEffectCompressor = null
	for i in AudioServer.get_bus_effect_count(music):
		if AudioServer.get_bus_effect(music, i) is AudioEffectCompressor:
			duck = AudioServer.get_bus_effect(music, i)
	check(duck != null and duck.sidechain == &"SFX" and duck.ratio <= 3.0, "music ducks mildly under SFX")
	# AudioServer runs buses from the highest index down: SFX must come after
	# Music so the sidechain reads the post-fader SFX (Effects at 0 = no pump).
	check(AudioServer.get_bus_index(&"SFX") > music, "SFX is processed (faded) before Music reads it")


func test_room_reverb_presets_reach_the_sfx_bus() -> void:
	var sfx := AudioServer.get_bus_index(&"SFX")
	var rv: AudioEffectReverb = null
	for i in AudioServer.get_bus_effect_count(sfx):
		if AudioServer.get_bus_effect(sfx, i) is AudioEffectReverb:
			rv = AudioServer.get_bus_effect(sfx, i)
	check(rv != null, "the SFX bus has one reverb")
	if rv == null:
		return
	for preset: StringName in PresentationIndex.REVERB_PRESETS:
		check(AudioManager.REVERB_TABLE.has(preset), "reverb table covers %s" % preset)
	AudioManager.set_reverb(&"tunnel")
	check_near(rv.room_size, 0.8, 0.001, "tunnel room size")
	check_near(rv.wet, 0.2, 0.001, "tunnel wet")
	check_near(rv.dry, 1.0, 0.001, "dry stays at 1")
	var pres := PresentationIndex.for_room("res://world/rooms/lowlight/NeonRoofs.tscn")
	check(pres != null and pres.reverb == &"roof", "Neon Roofs uses the roof preset")
	AudioManager.set_reverb(pres.reverb)
	check_near(rv.wet, 0.03, 0.001, "roof wet")
	AudioManager.set_reverb(&"")
	check_near(rv.wet, 0.0, 0.001, "no preset plays dry")
	check(AudioManager.reverb_preset == &"", "dry preset recorded")


func test_ambience_keeps_playing_through_pause() -> void:
	var amb := AudioManager.ambience
	check(amb.process_mode == Node.PROCESS_MODE_ALWAYS, "beds are not stream-paused by a paused tree")
	check(amb.emitter.can_process(), "the drip emitter inherits it")
	get_tree().paused = true
	for i in 3:
		await get_tree().process_frame
	var muffled := AudioManager.ambience_muffled()
	get_tree().paused = false
	for i in 3:
		await get_tree().process_frame
	check(muffled, "the Ambience bus is low-passed while paused")
	check(not AudioManager.ambience_muffled(), "and open again after")
	check(amb.emitter.stream == null or amb.emitter.play_once(), "the Ambience preview drip plays")


func test_water_landing_uses_land_water() -> void:
	var fb_script := load("res://player/animation/PlayerFeedback.gd") as GDScript
	var fb: Node = fb_script.new()
	check(fb.get(&"sfx_land_water") == &"land_water", "a water landing id exists")
	check(AudioManager.has_sfx(&"land_water"), "and the bank plays it")
	fb.free()


# --- ambience ---------------------------------------------------------------

func test_beds_cover_every_planned_bed_and_loop() -> void:
	var bank := load(BEDS_PATH) as AmbienceBank
	check(bank != null and bank.validate().is_empty(), "beds.tres validates: %s" % [bank.validate() if bank else []])
	for bed in PresentationIndex.BED_IDS:
		check(bank.paths.has(bed), "beds.tres has no entry for %s" % bed)
	var shipped := 0
	for bed: Variant in bank.paths:
		var p := str(bank.paths[bed])
		if p == "":
			continue
		shipped += 1
		var s := load(p) as AudioStreamOggVorbis
		check(s != null and s.loop, "%s must exist and loop" % p)
	check(shipped >= 5, "the five phase-A beds are mapped (%d)" % shipped)
	check(ResourceLoader.exists(bank.drip_path) and load(bank.drip_path) is AudioStreamRandomizer, "the drip emitter has its takes")


func test_ambience_same_bed_does_not_restart() -> void:
	var amb := AudioManager.ambience
	amb.apply_presentation(null)
	var wake := PresentationIndex.for_room("res://world/rooms/undercity/Wake.tscn")
	var ruin := PresentationIndex.for_room("res://world/rooms/undercity/MedicalRuin.tscn")
	amb.apply_presentation(wake)
	var starts := amb.starts
	check(amb.current[0] == &"amb_undercity_ward", "Wake plays the ward bed (%s)" % amb.current[0])
	amb.apply_presentation(ruin)
	check(amb.starts == starts, "the same bed across rooms does not restart")
	check(amb.emitter.is_active(), "the Undercity drips")
	# District fallback: a room without its own entry gets its district's bed.
	var fallback := PresentationIndex.for_room("res://tests/fixtures/none.tscn", "Lowlight")
	amb.apply_presentation(fallback)
	check(amb.current[0] == &"amb_lowlight_street", "district default bed (%s)" % amb.current[0])
	check(amb.starts == starts + 1, "a new bed starts once")
	check(not amb.emitter.is_active(), "no drips on the street")
	amb.apply_presentation(PresentationIndex.for_room("res://world/rooms/lowlight/ApartmentStack.tscn"))
	check(amb.current[0] == &"amb_lowlight_interior" and amb.emitter.is_active(), "Lowlight interiors drip")
	# Silence: the Deep Rig (no bed yet), unmapped rooms, a planned bed with no file.
	amb.apply_presentation(PresentationIndex.for_room("res://tests/fixtures/none.tscn", "Deep Rig"))
	check(amb.current[0] == &"" and not amb.emitter.is_active(), "the Deep Rig is silent")
	var planned := RoomPresentation.new()
	planned.ambience = &"amb_lowlight_power"
	amb.apply_presentation(planned)
	check(amb.current[0] == &"", "a bed without a file is silence")
	amb.apply_presentation(null)
	check(amb.current[0] == &"" and amb.current[1] == &"", "no presentation, no bed")


func test_ambient_emitter_uses_its_own_rng() -> void:
	var e := AmbientEmitter.new()
	add_child(e)
	e.configure(load("res://assets/audio/ambience/amb_drip.tres") as AudioStream, Vector2(4, 11), -18.0, 3.0, 0.6)
	var before := randi()
	seed(1234)
	var expected := randi()
	seed(1234)
	e.set_active(true)
	var fired := 0
	for i in 60 * 30:
		if e.step(1.0 / 60.0):
			fired += 1
	check(randi() == expected, "the emitter never touches the global RNG")
	check(fired >= 2 and fired <= 8, "a drip every 4-11 s: %d in 30 s" % fired)
	e.set_active(false)
	check(not e.step(20.0), "inactive emitters stay quiet")
	e.queue_free()
	seed(before)


# --- footsteps --------------------------------------------------------------

func test_footstep_surface_resolution_order() -> void:
	check(FootstepDirector.resolve_surface(&"metal", &"water") == &"metal", "collider metadata wins")
	check(FootstepDirector.resolve_surface(&"", &"water") == &"water", "then the room default")
	check(FootstepDirector.resolve_surface(&"", &"") == &"concrete", "then concrete")
	var alley := PresentationIndex.for_room("res://world/rooms/lowlight/FloodedAlley.tscn")
	check(alley != null and alley.footstep_surface == &"water", "Flooded Alley walks on water")


func test_footsteps_play_while_running_and_read_metadata() -> void:
	_world()
	SceneRouter.goto_room(PIT, &"start")
	await physics_frames(10)
	var room := SceneRouter.current_room as Room
	var p := room.player
	var fs := AudioManager.footsteps
	var input := ScriptedInputSource.new()
	p.input_source = input
	var steps := fs.steps
	input.move_x = 1
	await physics_frames(30)
	input.move_x = 0
	check(fs.steps > steps, "running plays footsteps (%d)" % (fs.steps - steps))
	check(fs.last_surface == &"concrete", "a fixture without presentation walks on concrete (%s)" % fs.last_surface)
	# Metadata on the floor collider wins (visual-only: no layer or shape change).
	var floor_body: Object = null
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i)
		if c.get_normal().y < -0.5:
			floor_body = c.get_collider()
	check(floor_body != null, "the player stands on a floor body")
	if floor_body != null:
		floor_body.set_meta(&"surface", "metal")
		var steps2 := fs.steps
		input.move_x = -1
		await physics_frames(20)
		input.move_x = 0
		check(fs.steps > steps2 and fs.last_surface == &"metal", "collider metadata picks metal (%s)" % fs.last_surface)
		floor_body.remove_meta(&"surface")
	# Standing still plays nothing.
	await physics_frames(10)
	var still := fs.steps
	await physics_frames(30)
	check(fs.steps == still, "no steps while idle")


func test_room_change_sets_the_bed() -> void:
	_world()
	SceneRouter.goto_room(PIT, &"start")
	await physics_frames(5)
	check(AudioManager.ambience.current[0] == &"", "a test fixture is silent")
	SceneRouter.goto_room(RELAY)
	await physics_frames(5)
	check(AudioManager.ambience.current[0] == &"amb_relay_hub", "the Relay plays its bed (%s)" % AudioManager.ambience.current[0])
	check(AudioManager.footsteps._room_surface == &"concrete", "the Relay's steps are concrete until wood lands")


# --- music ------------------------------------------------------------------

func test_music_library_paths_exist_and_loop() -> void:
	var lib := load(LIBRARY_PATH) as MusicLibrary
	check(lib != null and lib.validate().is_empty(), "music_library validates: %s" % [lib.validate() if lib else []])
	for s in lib.sets:
		for p in s.all_paths():
			var st := load(p) as AudioStreamOggVorbis
			check(st != null and st.loop, "%s must exist and loop" % p)
		for k: Variant in s.extras:
			check(MusicDirector.LAYERS.has(StringName(str(k))), "extras key %s is a stem" % k)
		for k: Variant in s.boss_by_room:
			check(ResourceLoader.exists(str(k)), "boss_by_room key %s is a room" % k)


func test_track_for_every_state_and_district() -> void:
	var S := MusicDirector.State
	var mus := "res://assets/audio/music/%s.ogg"
	var expect := {
		"undercity": {S.TITLE: "mus_title", S.HUB: "mus_relay", S.EXPLORE: "mus_undercity_explore",
			S.FLOW: "mus_flow", S.BOSS: "mus_boss", S.AFTERMATH: "mus_undercity_explore", S.MEMORY: "", S.SILENT: ""},
		"lowlight": {S.EXPLORE: "mus_lowlight_explore", S.AFTERMATH: "mus_lowlight_explore", S.BOSS: "mus_boss", S.MEMORY: ""},
		"relay": {S.HUB: "mus_relay", S.EXPLORE: "", S.AFTERMATH: "", S.FLOW: "mus_flow"},
		"deep_rig": {S.EXPLORE: "", S.FLOW: "mus_flow", S.BOSS: "mus_boss", S.MEMORY: ""},
		"title": {S.TITLE: "mus_title", S.EXPLORE: ""},
		"": {S.TITLE: "mus_title", S.EXPLORE: "", S.MEMORY: ""},
	}
	check(expect.size() == 6, "six district rows")
	for d: String in expect:
		var rows: Dictionary = expect[d]
		for st: int in rows:
			var want: String = rows[st]
			var got := MusicDirector._track_for(st, StringName(d), "")
			var want_path := mus % want if want != "" else ""
			check(str(got["path"]) == want_path, "%s state %d: want '%s', got '%s'" % [d, st, want_path, got["path"]])
	# Every State maps without error, in every district the index names.
	for d in PresentationIndex.MUSIC_DISTRICTS:
		for st: int in S.values():
			var got := MusicDirector._track_for(st, d, "")
			check(got.has("path") and got.has("gain"), "%s/%d returns a track record" % [d, st])
	var after := MusicDirector._track_for(S.AFTERMATH, &"undercity", "")
	var boss := float(MusicDirector._track_for(S.BOSS, &"lowlight", "")["gain"])
	var explore := float(MusicDirector._track_for(S.EXPLORE, &"lowlight", "")["gain"])
	check_near(float(after["gain"]), explore * 0.6, 0.001, "aftermath plays the explore track lower")
	# SOUND_DIRECTION section 3: music is the lowest tier; boss sits above explore.
	check(explore < db_to_linear(-8.0), "explore music sits well under 0 dB (%.3f)" % explore)
	check(boss > explore and boss < 1.0, "boss louder than explore, still under unity (%.3f)" % boss)


func test_track_mode_details() -> void:
	var S := MusicDirector.State
	check_near(MusicDirector._fade_time(S.EXPLORE, S.BOSS), 0.6, 0.001, "-> BOSS 0.6 s")
	check_near(MusicDirector._fade_time(S.EXPLORE, S.FLOW), 1.0, 0.001, "-> FLOW 1.0 s")
	check_near(MusicDirector._fade_time(S.FLOW, S.EXPLORE), 3.0, 0.001, "FLOW -> EXPLORE 3.0 s")
	check_near(MusicDirector._fade_time(S.BOSS, S.AFTERMATH), 2.5, 0.001, "-> AFTERMATH 2.5 s")
	check_near(MusicDirector._fade_time(S.EXPLORE, S.MEMORY), 1.2, 0.001, "-> MEMORY 1.2 s")
	check_near(MusicDirector._fade_time(S.TITLE, S.HUB), 2.0, 0.001, "else 2.0 s")
	# The Relay keeps only the arrhythmic growth stems over its track.
	Game.set_flag("dead_air_complete", true)
	Game.set_flag("warden_krail_defeated", true)
	Game.set_flag("act1_complete", true)
	var mix := MusicDirector._track_stem_mix(S.HUB)
	check(mix == {&"lead": 0.2}, "track-mode hub stems: lead only, got %s" % mix)
	check(MusicDirector._track_stem_mix(S.EXPLORE).is_empty(), "stems silent under an explore track")
	check(MusicDirector._mix_for(S.HUB).has(&"arp"), "stem mode keeps the full growth")
	Game.new_game()
	for stem in MusicDirector.TRACK_HUB_STEMS:
		check(MusicDirector.LAYERS.has(stem), "%s is a stem" % stem)


func test_stems_render_once_off_the_main_thread() -> void:
	check(MusicDirector._stem_requests <= 1, "stems are requested at most once (%d)" % MusicDirector._stem_requests)
	check(MusicDirector._main_thread_renders == 0, "stems never render on the main thread")
	if DisplayServer.get_name() == "headless":
		check(MusicDirector._stem_requests == 0 and MusicDirector._decks.is_empty(), "headless: no render, no decks")
		check(AudioManager.ambience._players[0] == null and AudioManager.ambience._players[1] == null, "headless: no ambience players")


func _def(bank: SfxBank, id: StringName) -> SfxDefinition:
	for d in bank.sounds:
		if d.id == id:
			return d
	return null
