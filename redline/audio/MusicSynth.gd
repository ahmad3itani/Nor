class_name MusicSynth
extends RefCounted
## Renders placeholder music stems (bible §28: dynamic states, recurring
## motifs). All stems share tempo and length so they loop in sync and the
## director only has to fade layers. Replace with composed stems later.

const RATE := 16000
const BPM := 96.0
const BEATS := 16
## Am - F - Dm - E : Lowlight's noir progression (the recurring motif).
const CHORDS := [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]
const LEAD := [69, 72, 71, 69, 65, 64, 62, 64, 69, 72, 76, 74, 72, 71, 68, 64]


static func length_seconds() -> float:
	return BEATS * 60.0 / BPM


static func midi_hz(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


static func render(layer: StringName) -> AudioStreamWAV:
	var count := int(length_seconds() * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var beat_len := 60.0 / BPM
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		var beat := t / beat_len
		var bar := int(beat / 4.0) % 4
		var chord: Array = CHORDS[bar]
		var s := 0.0
		match layer:
			&"pad":
				for n in chord:
					var f := midi_hz(float(n) - 12.0)
					s += _tri(f * t) * 0.18 + _tri(f * 1.004 * t) * 0.12
				var bar_t := fmod(beat, 4.0) / 4.0
				s *= clampf(bar_t * 6.0, 0.0, 1.0) * clampf((1.0 - bar_t) * 6.0, 0.35, 1.0)
				lp += (s - lp) * 0.08
				s = lp
			&"bass":
				var step := fmod(beat * 2.0, 1.0)
				var f := midi_hz(float(chord[0]) - 24.0)
				s = (1.0 if fmod(f * t, 1.0) < 0.5 else -1.0) * 0.35 * exp(-step * 5.0)
				lp += (s - lp) * 0.12
				s = lp
			&"drums":
				var b := fmod(beat, 1.0)
				var in_bar := int(beat) % 4
				if in_bar == 0 or in_bar == 2:
					s += sin(TAU * (50.0 + 90.0 * exp(-b * 30.0)) * b * beat_len) * exp(-b * 9.0) * 0.8
				if in_bar == 1 or in_bar == 3:
					s += rng.randf_range(-1, 1) * exp(-b * 18.0) * 0.35
				var h := fmod(beat * 2.0, 1.0)
				s += rng.randf_range(-1, 1) * exp(-h * 60.0) * 0.12
			&"arp":
				var step16 := int(beat * 4.0)
				var n: int = chord[step16 % 3] + (12 if (step16 / 3) % 2 == 0 else 24)
				var st := fmod(beat * 4.0, 1.0)
				s = (sin(TAU * midi_hz(n) * t) * 0.6 + _tri(midi_hz(n) * t) * 0.4) * exp(-st * 6.0) * 0.22
			&"lead":
				var note: int = LEAD[int(beat) % LEAD.size()]
				var vib := sin(TAU * 5.0 * t) * 0.004
				var f := midi_hz(note) * (1.0 + vib)
				var st := fmod(beat, 1.0)
				s = (1.0 if fmod(f * t, 1.0) < 0.3 else -1.0) * 0.16 * clampf(st * 20.0, 0.0, 1.0) * (1.0 - st * 0.5)
				lp += (s - lp) * 0.2
				s = lp
		buf[i] = s
	# Short crossfade so the loop point never clicks.
	var fade := int(0.02 * RATE)
	for i in fade:
		var a := float(i) / fade
		buf[count - fade + i] = lerpf(buf[count - fade + i], buf[i], a)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = count
	return wav


static func _tri(phase: float) -> float:
	return 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
