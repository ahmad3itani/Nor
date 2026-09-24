class_name OnboardingConfig
extends Resource
## How a New Game begins (bible §42 onboarding, §23 Undercity). The campaign
## starts Rook unarmed in the Undercity with the Core readout hidden: he finds
## the blade, then the pistol, then learns what the Core is. Until the
## Undercity rooms land, `enforce` stays false and New Game is the legacy
## slice start (Relay, full kit), so nothing changes for old saves, tests or
## the capture tours. Game.START_ROOM stays the Relay either way.

## Off: New Game = the legacy slice start. On: the campaign start below.
@export var enforce: bool = false
## Where a campaign New Game drops Rook (the Undercity's Wake once it exists).
@export var campaign_start_room: String = "res://world/rooms/lowlight/Relay.tscn"
@export var campaign_start_entry: StringName = &"start"
## Weapons owned at the start (the campaign: none, both are found in play).
@export var start_owned_weapons: PackedStringArray = []
## Equipped slots at the start; "" leaves the slot empty.
@export var start_melee: String = ""
@export var start_ranged: String = ""
## Flags set on a campaign New Game. core_hud_hidden keeps the Core bar off
## the HUD until the first Flow Zone introduces it.
@export var start_flags: Dictionary = {"core_hud_hidden": true}
## Title-screen subtitle under the tagline.
@export var title_subtitle: String = "vertical slice  —  Lowlight"


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ResourceLoader.exists(campaign_start_room):
		errors.append("onboarding start room %s does not exist" % campaign_start_room)
	var catalog := load("res://data/catalog.tres") as ItemCatalog
	var listed := Array(start_owned_weapons)
	for id in [start_melee, start_ranged]:
		if id != "":
			listed.append(id)
			# An equipped weapon the profile does not own could never be re-equipped.
			if not start_owned_weapons.has(id):
				errors.append("onboarding equips %s without owning it" % id)
	for id: String in listed:
		if catalog.weapon(id) == null:
			errors.append("onboarding weapon %s is not in the item catalog" % id)
	return errors
