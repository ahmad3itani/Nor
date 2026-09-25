class_name SeqLine
extends SequenceStep
## One subtitle line, typed at 70 cps and held for its auto time
## clamp(1.0 + 0.065 * len, 2.0, 7.0) x the Subtitle speed setting (about
## 15 cps readable after the typing; budgets use x1.0). speaker_id: an
## NpcProfile.npc_id, a SpeakerTable id, or "" = narration (italic, no
## label). Tap/advance pacing lives in SequencePlayer.pace_line().

const CPS := 70.0
const MAX_CHARS := 120

@export var speaker_id: String = ""
@export_multiline var text: String = ""
## 0 = auto time.
@export var seconds: float = 0.0
## Waits for a tap (PLAY) instead of its clock; theatre-only sequences only.
@export var hold_for_input: bool = false
@export var blip: StringName = &""


static func auto_seconds(t: String) -> float:
	return clampf(1.0 + 0.065 * t.length(), 2.0, 7.0)


func run(p: SequencePlayer) -> void:
	var ov := p.overlay()
	var who := SpeakerTable.lookup(speaker_id)
	if is_instance_valid(ov):
		ov.show_line(who.get("label", speaker_id), who.get("color", Color.WHITE), text, who.get("narration", false))
	if blip != &"":
		AudioManager.play_sfx(blip)
	await p.pace_line(text.length(), nominal_seconds() * SubtitleStyle.time_scale(), hold_for_input)
	finish(p)


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


func nominal_seconds() -> float:
	return seconds if seconds > 0.0 else auto_seconds(text)
