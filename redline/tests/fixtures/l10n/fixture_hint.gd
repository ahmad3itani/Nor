extends Area2D
## LOC_FIELDS fixture for the scene scan: a hint trigger. _ready counts, so
## the test can prove the extractor never instantiates the scene.

const LOC_FIELDS := {"text": 110}
const LOC_EXEMPT := ["hint_id"]

static var ready_count: int = 0

@export var hint_id: String = "fixture"
@export var text: String = "Default hint text"


func _ready() -> void:
	ready_count += 1
