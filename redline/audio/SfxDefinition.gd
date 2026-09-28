class_name SfxDefinition
extends Resource
## A placeholder sound described as data and synthesized at load time.
## Lets M1 have readable audio feedback (bible §28: jump/land/dash must be
## audible) without committing temporary binary assets. A real AudioStream
## replaces it through `override_stream` (presentation overhaul).

enum Wave { SQUARE, TRIANGLE, SINE, NOISE }

@export var id: StringName
@export var wave: Wave = Wave.SQUARE
@export var duration: float = 0.1
## Pitch sweeps exponentially from start to end over the duration.
@export var freq_start: float = 440.0
@export var freq_end: float = 440.0
## Blend of white noise into the tone (0 = pure tone).
@export_range(0.0, 1.0) var noise_mix: float = 0.0
## One-pole low-pass on the result: 1 = bright, 0.05 = muffled thump.
@export_range(0.01, 1.0) var tone: float = 1.0
@export var attack: float = 0.004
@export var volume_db: float = -8.0
## Random +/- pitch per play so repeats don't sound machine-gunned.
@export_range(0.0, 0.5) var pitch_jitter: float = 0.05
## Minimum seconds between plays of this sound (stops slide/land spam).
@export var cooldown: float = 0.0
## The real asset (an OGG or an AudioStreamRandomizer .tres of takes) that
## replaces the synth, as a res:// path string. A path, not an ext_resource:
## in Godot 4.3 one missing [ext_resource] makes the whole bank .tres fail to
## load, which would silence every id. AudioManager loads it lazily behind
## ResourceLoader.exists and falls back to the synth parameters above when the
## file is missing or fails to load, so removing or excluding a file needs no
## code or data change.
@export_file("*.ogg", "*.tres", "*.wav") var override_path: String = ""
## An in-memory override (tests, tools); wins over override_path when set.
## Not exported, so it is never saved in the bank (see above).
var override_stream: AudioStream
## Mix tier (SOUND_DIRECTION section 3): 1 is never masked (hurt, telegraph,
## critical heartbeat), 5 is pickup chatter. When every voice is busy a new
## sound takes the least important, oldest voice, never a more important one.
@export_range(1, 5) var priority: int = 3
