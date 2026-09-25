extends RedlineTestCase
## M3.7: music stems, music state selection, every referenced SFX exists,
## title/pause/journal/settings/slice-end menus open cleanly.


func test_music_stems_loop_and_are_audible() -> void:
	var t0 := Time.get_ticks_msec()
	for layer in MusicDirector.LAYERS:
		var wav := MusicSynth.render(layer)
		check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s does not loop" % layer)
		var peak := 0
		for i in range(0, wav.data.size(), 64):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		check(peak > 1500, "%s is (nearly) silent: peak %d" % [layer, peak])
	var ms := Time.get_ticks_msec() - t0
	print("  music synthesis: %d ms for %d stems" % [ms, MusicDirector.LAYERS.size()])
	check(ms < 8000, "music synthesis too slow for a background thread (%d ms)" % ms)


func test_every_data_sfx_exists() -> void:
	var ids: Array[StringName] = []
	for dir in ["res://data/weapons", "res://data/enemies"]:
		for f in DirAccess.get_files_at(dir):
			var res := load("%s/%s" % [dir, f])
			var attacks: Array = []
			if res is WeaponData:
				attacks = (res as WeaponData).all_attacks()
			elif res is EnemyData:
				for a in (res as EnemyData).attacks:
					var x: AttackData = a
					while x:
						attacks.append(x)
						x = x.follow_up
			for a in attacks:
				for id in [a.swing_sfx, a.hit_sfx]:
					if id != &"" and not ids.has(id):
						ids.append(id)
			if res is WeaponData:
				ids.append((res as WeaponData).fire_sfx)
	for id in ids:
		check(AudioManager.has_sfx(id), "data references unknown sfx '%s'" % id)


func test_menus_open_and_close() -> void:
	Game.new_game()
	for path in ["res://ui/menus/PauseMenu.gd", "res://ui/menus/JournalMenu.gd",
			"res://ui/menus/SettingsMenu.gd", "res://ui/menus/SliceEndMenu.gd",
			"res://ui/menus/MomentMenu.gd", "res://ui/menus/SurveyMenu.gd"]:
		var m: MenuScreen = load(path).new()
		add_child(m)
		m.open_menu()
		check(m.is_open() and get_tree().paused, "%s did not open/pause" % path.get_file())
		m.close_menu()
		check(not get_tree().paused, "%s did not unpause" % path.get_file())
		m.queue_free()
	var title: MenuScreen = load("res://ui/menus/TitleMenu.gd").new()
	add_child(title)
	title.open_menu()
	check(title.is_open() and not get_tree().paused, "title should open without pausing")
	title.queue_free()


func test_slice_totals_count_content() -> void:
	var t := SliceStats.totals()
	# Every M7 room has landed: mf_lowlight_01..04 and mf_undercity_01.
	var fragments := int(t["fragments"])
	check(fragments == 5, "expected exactly 5 memory fragments in Act I, found %d" % fragments)
	var lore_files := 0
	for f in DirAccess.get_files_at("res://data/lore"):
		if f.begins_with("mf_") and f.ends_with(".tres"):
			lore_files += 1
	check(fragments <= lore_files, "%d fragments placed but only %d mf_*.tres lore files" % [fragments, lore_files])
	var seen := {}
	for path in SliceStats.room_paths():
		var inst := (load(path) as PackedScene).instantiate()
		for n in inst.find_children("*", "Collectible", true, false):
			var c := n as Collectible
			if c.kind != Collectible.Kind.MEMORY_FRAGMENT:
				continue
			var lore := c.fragment.resource_path if c.fragment else ""
			check(lore.begins_with("res://data/lore/"), "%s: fragment %s has no data/lore resource" % [path.get_file(), c.persist_id])
			check(not seen.has(lore), "lore %s placed twice (%s and %s)" % [lore, seen.get(lore, ""), path.get_file()])
			seen[lore] = path.get_file()
		inst.free()
	check(int(t["core_shards"]) >= 2, "expected >= 2 core shards")
	check((t["secret_ids"] as Array).size() >= 8, "expected >= 8 secrets/discoveries")
