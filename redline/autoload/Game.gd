extends Node
## Session-level game state that is not yet owned by a save profile.
##
## In M1 this only tracks which traversal abilities are unlocked, because the
## Movement Lab lets testers toggle Dash on/off to compare it with Dodge.

var abilities: PlayerAbilities = PlayerAbilities.new()


func set_ability(ability: StringName, unlocked: bool) -> void:
	if not ability in abilities:
		push_error("Unknown ability: %s" % ability)
		return
	abilities.set(ability, unlocked)
