class_name SfxSynth
extends RefCounted
## Renders an SfxDefinition to a 16-bit mono AudioStreamWAV.

const MIX_RATE := 22050


static func render(def: SfxDefinition, rng_seed: int = 1) -> AudioStream:
	if def.override_stream:
		return def.override_stream
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var count := maxi(int(def.duration * MIX_RATE), 1)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	var filtered := 0.0
	var ratio := def.freq_end / maxf(def.freq_start, 1.0)
	for i in count:
		var t := float(i) / count
		var freq := def.freq_start * pow(ratio, t)
		phase = fmod(phase + freq / MIX_RATE, 1.0)
		var s := _oscillate(def.wave, phase, rng)
		if def.noise_mix > 0.0:
			s = lerpf(s, rng.randf_range(-1.0, 1.0), def.noise_mix)
		filtered += (s - filtered) * def.tone
		# Linear attack, then a quadratic decay to silence: short, punchy blips.
		var time := float(i) / MIX_RATE
		var env := clampf(time / maxf(def.attack, 0.0001), 0.0, 1.0) * pow(1.0 - t, 2.0)
		data.encode_s16(i * 2, int(clampf(filtered * env, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _oscillate(wave: int, phase: float, rng: RandomNumberGenerator) -> float:
	match wave:
		SfxDefinition.Wave.SQUARE:
			return 0.6 if phase < 0.5 else -0.6
		SfxDefinition.Wave.TRIANGLE:
			return 4.0 * absf(phase - 0.5) - 1.0
		SfxDefinition.Wave.SINE:
			return sin(phase * TAU)
		_:
			return rng.randf_range(-1.0, 1.0)
