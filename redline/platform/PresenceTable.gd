class_name PresenceTable
extends Resource
## Rich-presence lines (M9 D1 §3.5), data/platform/presence.tres. One field per
## presence key, so a storefront adapter can map each key 1:1 to a token
## (Docs/PLATFORM_SERVICES.md). English source with named placeholders:
## {district}, {room}, {boss}, {name}; translated at display (D-162).

const LOC_FIELDS := {"title": 40, "room": 40, "boss": 40, "memory": 40, "cinematic": 40, "act_done": 40,
	"lab": 40, "challenge": 40}
## Every presence key, in priority-free declaration order.
const KEYS: PackedStringArray = ["title", "room", "boss", "memory", "cinematic", "act_done", "lab", "challenge"]
## The placeholders each key may use (anything else is a validation error).
const PLACEHOLDERS := {"title": [], "room": ["district", "room"], "boss": ["boss"], "memory": [], "cinematic": [],
	"act_done": ["room"], "lab": ["room"], "challenge": ["name"]}

@export var title: String = "In the menus"
@export var room: String = "{district} — {room}"
@export var boss: String = "Fighting {boss}"
@export var memory: String = "Remembering"
@export var cinematic: String = "Watching"
@export var act_done: String = "Act I complete — {room}"
@export var lab: String = "In the {room}"
@export var challenge: String = "Challenge — {name}"


## The source line of `key` ("" for an unknown key).
func source(key: String) -> String:
	return String(get(key)) if KEYS.has(key) else ""


## The display line: translated, then placeholders filled.
func text(key: String, args: Dictionary = {}) -> String:
	var src := source(key)
	return Loc.f(src, args) if src != "" else ""


func validate() -> PackedStringArray:
	var e := PackedStringArray()
	var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for key: String in KEYS:
		var src := source(key)
		if src.strip_edges() == "":
			e.append("presence '%s' is empty" % key)
			continue
		if src.length() > int(LOC_FIELDS[key]):
			e.append("presence '%s' is over %d chars" % [key, LOC_FIELDS[key]])
		for m in re.search_all(src):
			if not (PLACEHOLDERS[key] as Array).has(m.get_string(1)):
				e.append("presence '%s' uses unknown placeholder {%s}" % [key, m.get_string(1)])
	return e
