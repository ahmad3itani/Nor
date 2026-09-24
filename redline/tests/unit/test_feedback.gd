extends RedlineTestCase
## Placeholder SFX data and the player feedback wiring (M1 polish).

const BANK_PATH := "res://data/audio/placeholder_sfx.tres"


func test_bank_ids_unique_and_render() -> void:
	var bank := load(BANK_PATH) as SfxBank
	check(bank != null and bank.sounds.size() > 0, "bank missing or empty")
	var seen := {}
	for def in bank.sounds:
		check(not seen.has(def.id), "duplicate sfx id %s" % def.id)
		seen[def.id] = true
		check(def.duration > 0.0 and def.duration < 1.0, "%s duration out of range" % def.id)
		var wav := SfxSynth.render(def) as AudioStreamWAV
		check(wav != null and wav.data.size() == int(def.duration * SfxSynth.MIX_RATE) * 2,
			"%s rendered wrong length" % def.id)


func test_render_is_not_silent_and_does_not_clip() -> void:
	var def := SfxDefinition.new()
	def.duration = 0.1
	def.freq_start = 300.0
	def.freq_end = 600.0
	var wav := SfxSynth.render(def) as AudioStreamWAV
	var peak := 0
	for i in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	check(peak > 3000, "rendered sound is (nearly) silent: peak %d" % peak)
	check(peak <= 32000, "rendered sound clips: peak %d" % peak)


func test_every_feedback_sound_exists_in_bank() -> void:
	var player: Player = preload("res://player/Player.tscn").instantiate()
	player.abilities = PlayerAbilities.new()
	add_child(player)
	var feedback := player.get_node("Feedback")
	for id in feedback.sound_ids():
		check(AudioManager.has_sfx(id), "PlayerFeedback requests unknown sfx '%s'" % id)
	player.queue_free()
	await physics_frames(1)
