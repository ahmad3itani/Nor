class_name RunClock
extends RefCounted
## The challenge run clock (M9 D2 §3.6): counted physics frames, not seconds.
## Challenges ticks it once per physics tick while running and not
## SceneRouter.transitioning; a paused tree runs no physics, so menus and
## dialogue pauses never count. Hitstop counts (it is gameplay). Transitions
## never count: loadless by construction and immune to the tween/render-rate
## coupling of fades, so runs are deterministic under --fixed-fps 60.

const FPS := 60

var frames: int = 0
var running: bool = false
## Frame count at each split, in order.
var splits: PackedInt32Array = PackedInt32Array()


func start() -> void:
	running = true


func stop() -> void:
	running = false


func reset() -> void:
	frames = 0
	running = false
	splits = PackedInt32Array()


## +1 only while running.
func tick() -> void:
	if running:
		frames += 1


## Appends and returns the current frame count.
func split() -> int:
	splits.append(frames)
	return frames


func seconds() -> float:
	return float(frames) / FPS


## "m:ss.cc" (centiseconds = frames × 100 / 60, truncated).
static func format(f: int) -> String:
	var cs := maxi(f, 0) * 100 / FPS
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]


## A split delta, "+1.10" / "-0.42" (seconds.centiseconds; minutes past 60 s).
static func format_delta(f: int) -> String:
	var sign := "+" if f >= 0 else "-"
	var cs := absi(f) * 100 / FPS
	if cs >= 6000:
		return "%s%d:%02d.%02d" % [sign, cs / 6000, (cs / 100) % 60, cs % 100]
	return "%s%d.%02d" % [sign, cs / 100, cs % 100]
