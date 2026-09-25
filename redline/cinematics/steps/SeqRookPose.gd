class_name SeqRookPose
extends SequenceStep
## Crouches or stands Rook through the lock's input source (CrouchState; his
## body never moves, R1). A CROUCH needs a later STAND (validator).

enum Pose { STAND, CROUCH }

@export var pose: Pose = Pose.STAND


func finish(p: SequencePlayer) -> void:
	p.lock_source().down_held = pose == Pose.CROUCH


func locking_only() -> bool:
	return true
