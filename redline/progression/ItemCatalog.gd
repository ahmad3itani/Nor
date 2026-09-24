class_name ItemCatalog
extends Resource
## Registry of every weapon and Circuit, so saves can store ids and systems
## can resolve them (bible §31: data-driven content, no hardcoded lists).

@export var weapons: Array[WeaponData] = []
@export var circuits: Array[Resource] = []


func weapon(id: String) -> WeaponData:
	for w in weapons:
		if String(w.id) == id:
			return w
	return null


func circuit(id: String) -> Resource:
	for c in circuits:
		if String(c.id) == id:
			return c
	return null


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for w in weapons:
		if seen.has(w.id):
			errors.append("duplicate weapon id %s" % w.id)
		seen[w.id] = true
	for c in circuits:
		if seen.has(c.id):
			errors.append("duplicate item id %s" % c.id)
		seen[c.id] = true
		if c.has_method("validate"):
			errors.append_array(c.validate())
	return errors
