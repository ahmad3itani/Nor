class_name WaveSet
extends Resource
## A Pulse Pit wave list (M9 D2 §2.3), run by the room's WaveDirector when a
## challenge names it in ChallengeData.waves. Waves advance on a thinned
## field (alive <= next_when_alive_at_most) or after next_after_s, so a
## stalled wave never stalls the run. A non-looping set finishes the run when
## its last wave is cleared; a looping one repeats from loop_from with more
## enemies per loop until Rook falls (the Redline endurance run).

const LOC_FIELDS := {}

## STYLE: the run's style score (T04's default, Challenges.session.style_score).
## ENDURANCE: (seconds × score_per_second + kills × score_per_kill + waves
## cleared × score_per_wave) × the live Core's ReactorConfig.score_multiplier.
enum ScoreMode { STYLE, ENDURANCE }

@export var entries: Array[WaveEntry] = []
@export var score_mode: ScoreMode = ScoreMode.STYLE
## The next wave starts once every entry of this one spawned and at most
## this many of the director's enemies are alive.
@export var next_when_alive_at_most: int = 1
## ... or this long after the wave started, whatever is alive.
@export var next_after_s: float = 20.0
## Spawns wait while this many of the director's enemies are alive.
@export var max_alive: int = 5
## 0-based wave index the set loops back to after its last wave; -1 = stop.
@export var loop_from: int = -1
## Added to every entry's count per completed loop.
@export var loop_count_bonus: int = 1
@export var score_per_second: float = 10.0
@export var score_per_kill: float = 50.0
@export var score_per_wave: float = 200.0


func wave_count() -> int:
	var n := 0
	for e in entries:
		if e:
			n = maxi(n, e.wave)
	return n


## Entries of wave `w` (1-based), in authored order.
func wave_entries(w: int) -> Array[WaveEntry]:
	var out: Array[WaveEntry] = []
	for e in entries:
		if e and e.wave == w:
			out.append(e)
	return out


func loops() -> bool:
	return loop_from >= 0


## The endurance score (pure: the tests are table-driven).
func endurance_score(seconds: float, kills: int, waves_cleared: int, multiplier: float) -> int:
	var base := seconds * score_per_second + kills * score_per_kill + waves_cleared * score_per_wave
	return maxi(0, roundi(base * multiplier))


## Every spawn point index an entry names (NU-6 checks them against the room).
func spawn_points() -> PackedInt32Array:
	var out := PackedInt32Array()
	for e in entries:
		if e == null:
			continue
		for i in e.spawn_points:
			if not out.has(i):
				out.append(i)
	out.sort()
	return out


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if entries.is_empty():
		out.append("wave set has no entries")
	var n := wave_count()
	for w in range(1, n + 1):
		if wave_entries(w).is_empty():
			out.append("wave set skips wave %d (waves must be 1..%d)" % [w, n])
	for e in entries:
		if e == null:
			out.append("wave set has an empty entry")
			continue
		out.append_array(e.validate())
	if loop_from < -1 or loop_from >= maxi(n, 1):
		out.append("wave set loop_from %d must be -1 or a wave index 0..%d" % [loop_from, n - 1])
	if loops() and loop_count_bonus < 0:
		out.append("wave set loop_count_bonus must be >= 0")
	if next_when_alive_at_most < 0 or max_alive < 1:
		out.append("wave set needs next_when_alive_at_most >= 0 and max_alive >= 1")
	if next_after_s <= 0.0:
		out.append("wave set next_after_s must be > 0")
	if score_per_second < 0.0 or score_per_kill < 0.0 or score_per_wave < 0.0:
		out.append("wave set scores must be >= 0")
	return out
