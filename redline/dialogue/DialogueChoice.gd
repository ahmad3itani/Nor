class_name DialogueChoice
extends Resource
## A deliberate answer at the end of a conversation (bible §19 "meaningful
## choice"). The label is the only thing Rook says in Act I (D-109 FLAG), so
## it stays terse; the reply is the NPC's answer, played before the box
## closes. Effects apply on close with the rest of the dialogue
## (Game.apply_dialogue(d, choice)), so a reply skipped by mashing still
## records the answer.

@export var id: String = ""
## Rook's words (<= 28 chars so 2-3 options fit under the last line).
@export var label: String = ""
## Non-empty and disjoint from the sibling choices' flags (DialogueData.validate).
@export var set_flags: PackedStringArray = []
## Optional NPC answer, shown with the same typing and advance rules.
@export var reply: Array[DialogueLine] = []
