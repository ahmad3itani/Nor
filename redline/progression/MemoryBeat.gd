class_name MemoryBeat
extends Resource
## One line of a memory vignette (M8, bible §18). A beat waits for the player
## (PLAY) or its auto time (AUTO); nothing in a memory runs on a clock the
## player cannot stop, because the world is paused behind it.

## "" = narration (italic, no label); else an UPPERCASE role label of at most
## 16 characters (bible §24 speaker labels). Never a name: memories introduce
## no names in Act I.
@export var speaker: String = ""
## At most 110 characters, so one beat fits the subtitle box at every size.
@export_multiline var text: String = ""
## The view centre auto-pans here when the beat starts (-1 = stay). Must lie
## in [240, tableau_width - 240] and never within detail_radius of the detail.
@export var view_x: float = -1.0
## 0..1 density of the neutral static crawling in from the frame edges.
@export var burn: float = 0.0
## A tap is ignored before this, so the press that opened the memory (or a
## mash) never skims a line.
@export var min_seconds: float = 0.5
## Optional one-shot SfxBank id played when the beat starts.
@export var sfx: StringName = &""
