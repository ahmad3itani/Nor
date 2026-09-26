class_name AchievementData
extends Resource
## One achievement (M9 D1 §3.1, bible §29). Rewards play, never grind (§2.9,
## D-146) and never reads Settings (§24, D-144): an assist player can earn
## every one. Unlocked when ALL `conditions` hold (Game.check_condition
## grammar, D-119: no AND/OR, a rule lists several conditions) AND the stat
## target is met. Unlocks are global and retroactive (D-143).
##
## Text is English source, translated at display (D-162). api_name is a
## platform API name, not a translation key.

const LOC_FIELDS := {"title": 32, "description": 90, "hint_when_hidden": 90}
const LOC_EXEMPT := ["id", "api_name"]
## Descriptions longer than this wrap to a third line in the toast/menu.
const DESCRIPTION_WARN := 72

enum Category { STORY, EXPLORATION, PEOPLE, MASTERY }
enum Scope { LIFETIME, PROFILE }

## snake_case; equals the file basename.
@export var id: String = ""
@export var title: String = ""
## Shown when unlocked, or always when not hidden.
@export_multiline var description: String = ""
## Locked text reads the hidden line plus hint_when_hidden.
@export var hidden: bool = false
## Optional non-spoiler nudge for a hidden achievement.
@export var hint_when_hidden: String = ""
@export var category: Category = Category.STORY
## Display order (unique across achievements, AchievementRules).
@export var sort: int = 0
## The act whose content earns it (future-flag guard, AchievementRules).
@export var act: int = 1
## Every entry must hold (Game.check_condition). Empty = stat only.
@export var conditions: PackedStringArray = []
## Optional stat threshold: value >= stat_target (MIN stats: 0 < value <=
## stat_target).
@export var stat_id: StringName = &""
@export var stat_target: float = 0.0
@export var stat_scope: Scope = Scope.LIFETIME
## Completion achievements: the count:<metric>:N condition must equal the live
## SliceStats total (AchievementRules), so content changes never strand them.
@export var completion: bool = false
## Spoiler guard (R02.6/R07.3): until this Game.check_condition expression
## holds, the menu row shows "???" and the category only. "" = always shown.
@export var reveal_when: String = ""
## Platform API name ([A-Z0-9_], <= 128). "" = "ACH_" + id.to_upper().
@export var api_name: String = ""
## Placeholder art slot (D-026): null draws a category glyph.
@export var icon: Texture2D


func api() -> String:
	return api_name if api_name != "" else "ACH_" + id.to_upper()


## Reads only machine-wide stats: no flag, no profile stat. Such achievements
## are evaluated during challenge runs too (R02.3), because the lifetime
## whitelist is the only thing a run can change.
func lifetime_only() -> bool:
	return conditions.is_empty() and stat_id != &"" and stat_scope == Scope.LIFETIME


## (current, target) for a progress readout; ZERO when not a stat achievement.
func progress(profile_stats: Dictionary, lifetime: Dictionary) -> Vector2:
	if stat_id == &"":
		return Vector2.ZERO
	var src := lifetime if stat_scope == Scope.LIFETIME else profile_stats
	return Vector2(minf(float(src.get(String(stat_id), 0.0)), stat_target), stat_target)


## Local rules (D1 §5 items 1, 3, 4 and the reveal_when grammar).
func validate() -> PackedStringArray:
	var e := PackedStringArray()
	if RegEx.create_from_string("^[a-z0-9_]+$").search(id) == null:
		e.append("achievement id '%s' must be snake_case" % id)
	elif resource_path != "" and resource_path.get_file().get_basename() != id:
		e.append("achievement id '%s' must equal its file name" % id)
	if title.strip_edges() == "" or title.length() > int(LOC_FIELDS["title"]):
		e.append("%s: title must be 1..%d chars" % [id, LOC_FIELDS["title"]])
	if description.strip_edges() == "" or description.length() > int(LOC_FIELDS["description"]):
		e.append("%s: description must be 1..%d chars" % [id, LOC_FIELDS["description"]])
	if hint_when_hidden.length() > int(LOC_FIELDS["hint_when_hidden"]):
		e.append("%s: hint_when_hidden is over %d chars" % [id, LOC_FIELDS["hint_when_hidden"]])
	if conditions.is_empty() and stat_id == &"":
		e.append("%s: needs a condition or a stat_id" % id)
	if stat_id != &"" and stat_target <= 0.0:
		e.append("%s: stat_target must be > 0" % id)
	if stat_id == &"" and stat_target != 0.0:
		e.append("%s: stat_target without a stat_id" % id)
	if hidden and title.strip_edges() != "" and hint_when_hidden.to_lower().contains(title.to_lower()):
		e.append("%s: hint_when_hidden spoils the title" % id)
	if reveal_when != "" and not ContentValidator.is_valid_condition(reveal_when):
		e.append("%s: reveal_when '%s' is not a valid condition" % [id, reveal_when])
	return e


## Flag reads, so a typo'd flag is an error ("required by ... but nothing
## sets it"). reveal_when is a read too.
func content_flags() -> Dictionary:
	var conds: Array = Array(conditions)
	if reveal_when != "":
		conds.append(reveal_when)
	return {"produces": [], "consumes": [], "conditions": conds}


func content_check() -> PackedStringArray:
	var e := PackedStringArray()
	for c in conditions:
		if c.strip_edges() == "" or not ContentValidator.is_valid_condition(c):
			e.append("%s: condition '%s' is not valid" % [id, c])
	if description.length() > DESCRIPTION_WARN:
		e.append("WARN: %s: description is over %d chars (wraps to a third line)" % [id, DESCRIPTION_WARN])
	return e
