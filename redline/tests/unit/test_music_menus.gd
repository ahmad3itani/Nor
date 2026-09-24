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
			"res://ui/menus/SettingsMenu.gd", "res://ui/menus/SliceEndMenu.gd"]:
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
	check(int(t["fragments"]) == 3, "expected 3 memory fragments in the slice, found %d" % t["fragments"])
	check(int(t["core_shards"]) >= 2, "expected >= 2 core shards")
	check((t["secret_ids"] as Array).size() >= 8, "expected >= 8 secrets/discoveries")
