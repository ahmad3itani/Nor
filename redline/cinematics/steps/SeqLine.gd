class_name SeqLine
extends SequenceStep
## One subtitle line, typed at CinematicConfig.type_cps (70) and held for its
## auto time CinematicConfig.line_seconds(len) = clamp(1.0 + 0.065 * len, 2.0,
## 7.0) x the Subtitle speed setting (about 15 cps readable after the typing;
## budgets use x1.0). speaker_id: an
## NpcProfile.npc_id, a SpeakerTable id, or "" = narration (italic, no
## label). Tap/advance pacing lives in SequencePlayer.pace_line().

const MAX_CHARS := 120

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"text": MAX_CHARS}

@export var speaker_id: String = ""
@export_multiline var text: String = ""
## 0 = auto time.
@export var seconds: float = 0.0
## Waits for a tap (PLAY) instead of its clock; theatre-only sequences only.
@export var hold_for_input: bool = false
@export var blip: StringName = &""


static func auto_seconds(t: String) -> float:
	return CinematicMode.config().line_seconds(t.length())


func run(p: SequencePlayer) -> void:
	var ov := p.overlay()
	var who := SpeakerTable.lookup(speaker_id)
	if is_instance_valid(ov):
		# The overlay keeps the source and translates at draw (D-162).
		ov.show_line(who.get("label", speaker_id), who.get("color", Color.WHITE), text, who.get("narration", false))
	if blip != &"":
		AudioManager.play_sfx(blip)
	var shown := Loc.t(text)
	await p.pace_line(shown.length(), displayed_seconds(shown) * SubtitleStyle.time_scale(), hold_for_input)
	# No finish() on abort (R3-1): the overlay may show a newer play's line.
	if not p.aborted(): finish(p)


func finish(p: SequencePlayer) -> void:
	var ov := p.overlay()
	if is_instance_valid(ov):
		ov.clear_line()


func validate(v: SequenceValidation) -> PackedStringArray:
	var out := PackedStringArray()
	if not SpeakerTable.exists(speaker_id):
		out.append("unknown speaker '%s'" % speaker_id)
	if text.strip_edges() == "":
		out.append("empty line")
	elif text.length() > MAX_CHARS:
		out.append("line is %d chars (max %d)" % [text.length(), MAX_CHARS])
	if hold_for_input and not v.seq.theatre_only:
		out.append("hold_for_input is for theatre-only sequences")
	if blip != &"" and not AudioManager.has_sfx(blip):
		out.append("unknown blip sfx '%s'" % blip)
	return out


## The D-135 budget time: always the English source (validators, budgets).
func nominal_seconds() -> float:
	return seconds if seconds > 0.0 else auto_seconds(text)


## D-164: the time a reader gets for the line as displayed (`shown` is the
## translated text) times the locale's reading scale. In English this is
## nominal_seconds() exactly, so every sequence timing stays byte-stable.
func displayed_seconds(shown: String) -> float:
	var base := seconds if seconds > 0.0 else auto_seconds(shown)
	return base * Loc.info().reading_scale
