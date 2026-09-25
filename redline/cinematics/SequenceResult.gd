class_name SequenceResult
extends RefCounted
## What one Cinematics.play() ended with. Every caller checks refused and
## aborted() before acting on completion: an aborted scene (room left, Save &
## Quit, test teardown) ran none of its remaining effects and replays later.

## The player skipped (hold, press twice, PauseMenu "Skip scene").
var skipped: bool = false
## Resolved in INSTANT mode (same call, no frame passed).
var instant: bool = false
## Not played: another locking sequence owns Cinematics, or no sequence.
var refused: bool = false
## Real seconds it ran (0 in INSTANT).
var seconds: float = 0.0
## Step it ended on; -1 = aborted.
var step_index: int = 0


func aborted() -> bool:
	return step_index == -1
