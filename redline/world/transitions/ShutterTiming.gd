class_name ShutterTiming
extends Resource
## Countdown of one PowerShutter (M7 Lowlight Grid, D-071). Seconds. The
## numbers are tuned against the recorded kinematics (run 150 px/s, a slide
## covers 92 px, crawl 55 px/s): `open` is the standing run, and the `slot`
## is the late, low escape (crawling past a 16 px shutter takes 0.51 s).

## Fully open after a breaker hit (WARN is the tail end of it).
@export var open: float = 3.2
## The last seconds of `open`: faster ticks, amber lamps.
@export var warn: float = 1.0
## The shutter lowers from open down to the 24 px slot.
@export var drop: float = 0.25
## Only a low (sliding or crouched) Rook fits under it now.
@export var slot: float = 0.6
## The slot closes; red lamps.
@export var seal: float = 0.15


## Seconds from the breaker hit until the shutter is closed again.
func cycle() -> float:
	return open + drop + slot + seal


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if open < 2.0:
		errors.append("shutter timing: open must be >= 2.0 s (got %.2f)" % open)
	if warn <= 0.0 or warn >= open:
		errors.append("shutter timing: warn must be > 0 and < open")
	if slot < 0.55:
		errors.append("shutter timing: slot must be >= 0.55 s (a crawl past 16 px takes 0.51 s)")
	if drop <= 0.0 or seal <= 0.0:
		errors.append("shutter timing: drop and seal must be > 0")
	return errors
