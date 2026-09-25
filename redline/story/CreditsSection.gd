class_name CreditsSection
extends Resource
## One heading of the credits roll and the names under it.

const HEADING_MAX := 40
const LINE_MAX := 48

@export var heading: String = ""
@export var lines: PackedStringArray = []
