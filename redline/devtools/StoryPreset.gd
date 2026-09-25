class_name StoryPreset
extends Resource
## One Act I story state for dev tools, tests and captures (data/dev/
## story_presets.tres). Lists are cumulative: a preset holds every flag and
## ability of the presets before it, so any single preset reads on its own.
## Dev data only: it declares no content_flags (it never consumes anything
## in play).

@export var id: String = ""
@export var label: String = ""
@export var flags: PackedStringArray = []
@export var abilities: PackedStringArray = []
