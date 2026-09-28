class_name RoomPresentation
extends Resource
## How a room looks and sounds, as ids only (presentation overhaul): the
## backdrop kind (ART_DIRECTION section 4 layer stack), the ambience bed and an
## optional stacked layer, the SFX reverb preset, the default footstep
## surface and the music district (SOUND_DIRECTION sections 2, 3, 6 and 7).
## Visual/audio only: nothing here touches collision, layout or routes.
## Ids, never res:// paths, so a missing asset is a quiet fallback in the
## consumer (backdrop: procedural skyline; bed: silence).

## e.g. &"uc_ward", &"ll_roof", &"relay_hub" (PresentationIndex.BACKDROP_KINDS).
@export var backdrop_kind: StringName = &""
## Ambience bed id (PresentationIndex.BED_IDS) or &"" for silence.
@export var ambience: StringName = &""
## A second loop stacked on the bed (e.g. Power Block's hum), or &"".
@export var ambience_layer: StringName = &""
## SFX reverb preset (PresentationIndex.REVERB_PRESETS) or &"" for dry.
@export var reverb: StringName = &""
## Default footstep surface (PresentationIndex.SURFACES) when no collider says otherwise.
@export var footstep_surface: StringName = &""
## Which district's music set plays here (PresentationIndex.MUSIC_DISTRICTS).
@export var music_district: StringName = &""
## Foreground silhouettes allowed (T03 REPAIR a). Off where ceiling hazards,
## flyers or the Collector eye use the top of the screen.
@export var foreground: bool = true


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if backdrop_kind != &"" and not PresentationIndex.BACKDROP_KINDS.has(backdrop_kind):
		out.append("unknown backdrop kind '%s'" % backdrop_kind)
	for bed in [ambience, ambience_layer]:
		if bed != &"" and not PresentationIndex.BED_IDS.has(bed):
			out.append("unknown ambience bed '%s'" % bed)
	if reverb != &"" and not PresentationIndex.REVERB_PRESETS.has(reverb):
		out.append("unknown reverb preset '%s'" % reverb)
	if footstep_surface != &"" and not PresentationIndex.SURFACES.has(footstep_surface):
		out.append("unknown footstep surface '%s'" % footstep_surface)
	if music_district != &"" and not PresentationIndex.MUSIC_DISTRICTS.has(music_district):
		out.append("unknown music district '%s'" % music_district)
	return out
