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
## A real asset (OGG or AudioStreamRandomizer) that replaces the synth when
## set; AudioManager falls back to the synth parameters above when it is null
## (a missing file leaves it null), so the placeholder always stays playable.
@export var override_stream: AudioStream
## Mix tier (SOUND_DIRECTION section 3): 1 is never masked (hurt, telegraph,
## critical heartbeat), 5 is pickup chatter. When every voice is busy a new
## sound takes the least important, oldest voice, never a more important one.
@export_range(1, 5) var priority: int = 3
