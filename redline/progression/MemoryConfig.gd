class_name MemoryConfig
extends Resource
## Tuning and player-facing text for memory vignettes and the journal
## gallery (bible §37.3: content lives in data; data/memories/memory_config.tres).

@export_group("Pacing")
## Vignettes per Anchor rest. 1 keeps the first rest before the Collector
## short (D-112); extras wait for the next rest with more_waiting_hint.
@export var max_per_rest: int = 1
## "MEMORY" + title card before the first beat.
@export var title_seconds: float = 1.0
## The closing tear after the last beat.
@export var tear_seconds: float = 0.6
## Beat text types out at this rate; a tap completes it first.
@export var chars_per_second: float = 70.0
## AUTO mode: a beat lasts base + chars * per_char seconds (/ auto_speed).
@export var auto_advance_base: float = 2.5
@export var auto_advance_per_char: float = 0.05
@export var letterbox_px: int = 24

@export_group("Look")
## Player pan speed (px/s) and the ease of automatic pans.
@export var pan_speed: float = 90.0
@export var pan_ease: float = 6.0
## The detail counts while |detail_x - view centre| <= detail_radius...
@export var detail_radius: float = 40.0
## ...for this long without a break.
@export var detail_dwell: float = 0.8
## How long the found detail line stays up (or until the next beat).
@export var detail_show_seconds: float = 4.0

@export_group("Text")
@export var title_label: String = "MEMORY"
## HUD fragment card body (CombatHud) when memories play at Anchors / when
## they do not (Settings.memories_at_anchors off).
@export var card_body_anchor: String = "Rest at an Anchor to remember."
@export var card_body_journal: String = "Open the Journal to remember."
## HUD hint after a rest that left memories pending (max_per_rest cap).
@export var more_waiting_hint: String = "Another memory is waiting."
## Journal main page.
@export var remembered_line: String = "Fragments remembered %d / %d"
@export var gallery_button: String = "Memories…"
@export var empty_text: String = "No memories recovered."
## Journal gallery.
@export var gallery_title: String = "MEMORIES  —  ACT %s"
@export var act_names: PackedStringArray = PackedStringArray(["I", "II", "III", "IV", "V"])
@export var pending_hint: String = "— rest at an Anchor to remember"
@export var detail_line: String = "Detail: %s"
@export var detail_unfound_text: String = "Something else was there."
@export var back_label: String = "Back"
## Timeline strip glyphs: remembered, recovered but not remembered, not yet
## recovered, and the gap between memories (the strip never shows a total).
@export var glyph_seen: String = "◆"
@export var glyph_pending: String = "◇"
@export var glyph_locked: String = "·"
@export var glyph_gap: String = "?"
## Vignette pause panel (bible §24 pause during scenes).
@export var pause_title: String = "PAUSED"
@export var pause_resume: String = "Resume"
@export var pause_skip: String = "Skip memory"
@export var pause_size: String = "Subtitle size: %s"
@export var size_names: PackedStringArray = PackedStringArray(["Small", "Medium", "Large"])


func act_name(act: int) -> String:
	return act_names[act - 1] if act >= 1 and act <= act_names.size() else str(act)


func validate() -> PackedStringArray:
	var e := PackedStringArray()
	if max_per_rest < 1:
		e.append("max_per_rest must be >= 1")
	if title_seconds < 0.0 or tear_seconds < 0.0:
		e.append("title/tear seconds must be >= 0")
	if chars_per_second <= 0.0 or pan_speed <= 0.0 or pan_ease <= 0.0:
		e.append("chars_per_second, pan_speed and pan_ease must be > 0")
	if detail_radius <= 0.0 or detail_dwell <= 0.0:
		e.append("detail_radius and detail_dwell must be > 0")
	if size_names.size() != 3:
		e.append("size_names needs Small/Medium/Large (3 entries)")
	for s in [title_label, card_body_anchor, card_body_journal, more_waiting_hint, remembered_line,
			gallery_button, empty_text, gallery_title, pending_hint, detail_line, detail_unfound_text,
			back_label, glyph_seen, glyph_pending, glyph_locked, glyph_gap, pause_title, pause_resume,
			pause_skip, pause_size]:
		if (s as String).strip_edges() == "":
			e.append("memory config has an empty text field")
			break
	return e
