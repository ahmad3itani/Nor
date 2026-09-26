extends Resource
## LOC_FIELDS fixture: a spoken line (text limited, speaker id exempt).

const LOC_FIELDS := {"text": 20}
const LOC_EXEMPT := ["speaker_id"]

@export var speaker_id: String = ""
@export var text: String = ""
