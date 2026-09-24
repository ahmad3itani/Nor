extends Node
## Combat Lab dev hotkeys (bible §34), alongside MovementLabController.
##   F9  cycle ranged weapon (Pistol / Scattergun)
##   F10 respawn every enemy
##   F11 cycle Redline Core mode (Normal / Assist / Challenge)

@onready var room: Room = get_parent()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_cycle_ranged"):
		room.player.combat.cycle_ranged()
	if Input.is_action_just_pressed("debug_reset_enemies"):
		for spawner in get_tree().get_nodes_in_group(&"enemy_spawners"):
			(spawner as EnemySpawner).spawn()
	if Input.is_action_just_pressed("debug_cycle_reactor"):
		Settings.reactor_mode = (Settings.reactor_mode + 1) % room.player.reactor.configs.size()
		room.player.reactor.apply_mode(Settings.reactor_mode)
