class_name KnowledgeLint
extends Resource
## The act knowledge lint (D-132): a guard for "never answer Act II+
## questions" (bible §18). Text a player can see in this act must not use a
## term a later act introduces or answers (Project REDLINE, the Architect, The
## Null, what the Pulse is, the research behind the resistance, and the name
## D-109 still has open). ContentValidator.validate_story() scans the act's
## shown text with it and reports WARNINGS only: a word can be innocent, and
## the reviewer decides. data/story/knowledge_lint.tres holds the Act I list.

const PATH := "res://data/story/knowledge_lint.tres"

## The act whose shown text is scanned (memory scenes and standing lines of
## other acts are skipped).
@export var act: int = 1
## Case-insensitive substrings ("stores memor" catches memory/memories).
@export var forbidden: PackedStringArray = []
## Files under these folders are never scanned (ending text is only reachable
## through the dev theatre; theatre_only sequences are exempt too).
@export var exempt_dirs: PackedStringArray = []


## The forbidden terms found in `text`, in list order (case-insensitive).
func hits(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var low := text.to_lower()
	for term in forbidden:
		if term != "" and low.contains(term.to_lower()):
			out.append(term)
	return out


func is_exempt(path: String) -> bool:
	for d in exempt_dirs:
		if d != "" and path.begins_with(d.trim_suffix("/") + "/"):
			return true
	return false


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if act < 1 or act > 5:
		errors.append("knowledge lint: act %d is not 1..5" % act)
	if forbidden.is_empty():
		errors.append("knowledge lint: no forbidden terms")
	var seen := {}
	for term in forbidden:
		if term.strip_edges() == "":
			errors.append("knowledge lint: empty forbidden term")
		elif seen.has(term.to_lower()):
			errors.append("knowledge lint: '%s' listed twice" % term)
		seen[term.to_lower()] = true
	for d in exempt_dirs:
		if not d.begins_with("res://"):
			errors.append("knowledge lint: exempt dir '%s' is not a res:// path" % d)
	return errors
