class_name CreditsData
extends Resource
## The credits roll every ending ends with (data/endings/credits.tres).
## Placeholder people until M10 (D-026 spirit: invent nobody). The ENGINE
## section is a licence requirement, not decoration: Godot's MIT notice must
## ship with any distributed build (K-E9), so validate() refuses to lose it.

const ENGINE_HEADING := "ENGINE"
const ENGINE_NAME := "Godot Engine"

@export var sections: Array[CreditsSection] = []
## Last line, held on screen while the roll ends.
@export var closing_line: String = ""


## The roll top to bottom: [{text, heading}], one blank row between sections
## and before the closing line.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in sections:
		if s == null:
			continue
		if not out.is_empty():
			out.append({"text": "", "heading": false})
		out.append({"text": s.heading, "heading": true})
		for l in s.lines:
			out.append({"text": l, "heading": false})
	if closing_line != "":
		out.append({"text": "", "heading": false})
		out.append({"text": closing_line, "heading": false})
	return out


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if sections.is_empty():
		errors.append("credits have no sections")
	var engine_ok := false
	for i in sections.size():
		var s := sections[i]
		if s == null:
			errors.append("credits section %d is empty" % i)
			continue
		if s.heading.strip_edges() == "":
			errors.append("credits section %d has no heading" % i)
		elif s.heading.length() > CreditsSection.HEADING_MAX:
			errors.append("credits heading '%s' is over %d chars" % [s.heading, CreditsSection.HEADING_MAX])
		if s.lines.is_empty():
			errors.append("credits section '%s' has no lines" % s.heading)
		for l in s.lines:
			if l.length() > CreditsSection.LINE_MAX:
				errors.append("credits line '%s' is over %d chars" % [l, CreditsSection.LINE_MAX])
		if s.heading == ENGINE_HEADING and Array(s.lines).any(func(l: String) -> bool: return l.contains(ENGINE_NAME)):
			engine_ok = true
	if not engine_ok:
		errors.append("credits need an %s section naming %s (licence notice)" % [ENGINE_HEADING, ENGINE_NAME])
	if closing_line.length() > CreditsSection.LINE_MAX:
		errors.append("closing line is over %d chars" % CreditsSection.LINE_MAX)
	return errors
