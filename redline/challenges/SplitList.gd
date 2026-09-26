class_name SplitList
extends Resource
## The campaign's split list (M9 D2 §2.4, T08's data/challenges/splits/
## act1_campaign.tres). Order matters: a split reached out of order is
## recorded with no delta.

## The split that ends the campaign run: its IGT posts the campaign best.
const END_SPLIT := "act1_end"

@export var splits: Array[SplitDef] = []
## R04.17: also a display-only split per world room, on the first entry this
## profile makes into it ("room:<Basename>").
@export var auto_room_splits: bool = false


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var ids := {}
	for s in splits:
		if s == null:
			out.append("split list has an empty entry")
			continue
		out.append_array(s.validate())
		if ids.has(s.id):
			out.append("split id '%s' is used twice" % s.id)
		ids[s.id] = true
	return out


## Resource content protocol: the split conditions read flags.
func content_flags() -> Dictionary:
	var conds: Array = []
	for s in splits:
		if s != null and s.when != "":
			conds.append(s.when)
	return {"conditions": conds}


func index_of(id: String) -> int:
	for i in splits.size():
		if splits[i] != null and splits[i].id == id:
			return i
	return -1
