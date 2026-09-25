class_name MemoryShape
extends Resource
## A placeholder tableau primitive for memory vignettes (D-026: no final art;
## a later art pass swaps shapes for sprite layers). Drawn procedurally by
## ui/memory/MemoryTableauView.gd in three tones of memory blue.

enum Kind { RECT, POLY, FIGURE, HAND, LAMP, RAIN, BARS, SCRIBBLE, RAILING }
## FIGURE only. Figures are blocky silhouettes (no portraits yet, §39).
enum Pose { STAND, LIE, SIT, REACH }

@export var kind: Kind = Kind.RECT
## Tableau space, bottom-centre origin like room decor (x 0..tableau_width,
## y 0..270 in screen rows).
@export var pos: Vector2 = Vector2.ZERO
@export var size: Vector2 = Vector2(16, 16)
## POLY only, relative to pos.
@export var points: PackedVector2Array = PackedVector2Array()
@export var pose: Pose = Pose.STAND
@export var facing: int = 1
## 0 dark, 1 mid, 2 bright (shades of memory blue).
@export var tone: int = 1
## Visible from this beat index...
@export var from_beat: int = 0
## ...through this one (-1 = to the end).
@export var to_beat: int = -1
## Gentle alpha pulse; frozen under Settings.flash_reduction.
@export var flicker: bool = false
## Filled with red static that never resolves in Act I (a face, a
## signature): an unexplained redaction, the only red in a memory (D-115).
@export var redacted: bool = false


func visible_at(beat: int) -> bool:
	return beat >= from_beat and (to_beat < 0 or beat <= to_beat)
