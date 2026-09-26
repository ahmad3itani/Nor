class_name ProfileSandbox
extends RefCounted
## The whole-state sandbox a challenge runs in (D-147). begin() swaps
## Game.state and Game.abilities for a sandbox and keeps the profile objects
## by reference in Game.held_profile, so Game.save_game() keeps writing the
## untouched profile while the run owns Game.state (an Anchor rest or a quit
## can never save the sandbox). restore() puts the same objects back.
##
## Unlike FlagSandbox (flags and play time only, D-128), everything is swapped:
## a run changes health, map bits, visited rooms, deaths and flags.
## Profile play time does not include run time: Game._process adds to the
## sandbox, which is discarded (D2 §3.4.5).
##
## Only Challenges uses it, and it swaps between rooms with
## Game.suppress_leave_capture set, so no room ever writes its player into the
## wrong state (R04.11/R04.24).

var profile: GameState
var profile_abilities: PlayerAbilities
## The live sandbox (replace_sandbox swaps it on restarts).
var sandbox: GameState
var sandbox_abilities: PlayerAbilities


## Swaps in the sandbox. Refused (null) while another sandbox holds a profile:
## restarts use replace_sandbox so the held profile is never a sandbox.
## emit_reset = false swaps silently (between rooms; Challenges emits
## game_state_reset once the new room is in).
static func begin(sandbox_state: GameState, p_sandbox_abilities: PlayerAbilities, emit_reset: bool = true) -> ProfileSandbox:
	if Game.held_profile != null:
		push_error("ProfileSandbox.begin: a profile is already held (restart with replace_sandbox)")
		return null
	var sb := ProfileSandbox.new()
	sb.profile = Game.state
	sb.profile_abilities = Game.abilities
	sb.sandbox = sandbox_state
	sb.sandbox_abilities = p_sandbox_abilities
	Game.held_profile = sb.profile
	Game.state = sandbox_state
	Game.abilities = p_sandbox_abilities
	if emit_reset:
		EventBus.game_state_reset.emit()
	return sb


## A fresh kit state for a restart; the held profile is never touched.
func replace_sandbox(sandbox_state: GameState, p_sandbox_abilities: PlayerAbilities) -> void:
	sandbox = sandbox_state
	sandbox_abilities = p_sandbox_abilities
	if Game.held_profile == profile:
		Game.state = sandbox_state
		Game.abilities = p_sandbox_abilities


## Puts the profile back. When a New Game or load replaced Game.state inside
## the run, it only lets go of the held profile: one profile's data is never
## written into another (the FlagSandbox guard).
func restore(emit_reset: bool = true) -> void:
	if Game.state != sandbox and Game.state != profile:
		push_warning("ProfileSandbox.restore: Game.state was replaced during the run; not restoring")
		if Game.held_profile == profile:
			Game.held_profile = null
		return
	Game.state = profile
	Game.abilities = profile_abilities
	Game.held_profile = null
	Game._session_entry_room = ""
	Game._session_entry_id = &""
	if emit_reset:
		EventBus.game_state_reset.emit()


## The sandbox GameState for a run (D2 §2.2), built off-line: flags go into
## the new state's dictionary, never through Game.set_flag, so nothing fires
## while the source room is still in the tree.
static func kit_state(kit: ChallengeKit, ch: ChallengeData, profile_state: GameState) -> GameState:
	var s := GameState.new()
	if kit == null:
		kit = ChallengeKit.new()
	if kit.use_profile_loadout and profile_state:
		# Deep Rig: the profile's kit, never its progress.
		s.owned_weapons.assign(profile_state.owned_weapons)
		s.melee_weapon = profile_state.melee_weapon
		s.ranged_weapon = profile_state.ranged_weapon
		s.owned_circuits.assign(profile_state.owned_circuits)
		s.equipped_circuits.assign(profile_state.equipped_circuits)
		s.core_shards = profile_state.core_shards
		s.abilities = profile_state.abilities.duplicate()
	elif kit.campaign_start:
		var ob := Game.onboarding
		s.owned_weapons.assign(ob.start_owned_weapons)
		s.melee_weapon = ob.start_melee
		s.ranged_weapon = ob.start_ranged
		for f: String in ob.start_flags:
			s.flags[f] = ob.start_flags[f]
	else:
		var owned: Array[String] = []
		for w in [kit.melee, kit.ranged] + Array(kit.owned_weapons):
			if String(w) != "" and not owned.has(String(w)):
				owned.append(String(w))
		s.owned_weapons = owned
		s.melee_weapon = kit.melee
		s.ranged_weapon = kit.ranged
		s.owned_circuits.assign(kit.circuits)
		s.equipped_circuits.assign(kit.circuits)
		s.core_shards = kit.core_shards
		for a in kit.abilities:
			s.abilities[a] = true
	for f in kit.set_flags:
		s.flags[f] = true
	for f in kit.clear_flags:
		s.flags[f] = false
	for f: String in kit.int_flags:
		s.flags[f] = int(kit.int_flags[f])
	if kit.core_hud_hidden:
		s.flags["core_hud_hidden"] = true
	# Rematches skip the long intro (the short retry intro still plays inside
	# every attempt), and the first-Flow tip never interrupts a run.
	if ch:
		if ch.group == ChallengeData.Group.BOSS_REMATCH and ch.boss_id != "":
			s.flags["%s_intro_seen" % ch.boss_id] = true
		s.last_entry_room = ch.start_room
		s.last_entry_id = String(ch.start_entry)
	s.flags["hint_first_flow"] = true
	return s


static func kit_abilities(state: GameState) -> PlayerAbilities:
	var a := PlayerAbilities.new()
	for key: String in state.abilities:
		if key in a:
			a.set(key, bool(state.abilities[key]))
	return a
