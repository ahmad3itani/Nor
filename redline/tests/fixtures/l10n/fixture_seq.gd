extends Resource
## LOC_FIELDS fixture: a container whose text lives in sub-resources only,
## plus choices with nested replies and a dictionary of names.

const LOC_FIELDS := {"names": 24, "labels": 16}
const LOC_EXEMPT := ["id"]

@export var id: String = ""
@export var steps: Array[Resource] = []
@export var choices: Array[Resource] = []
@export var names: Dictionary = {}
@export var labels: PackedStringArray = []
