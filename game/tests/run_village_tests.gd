extends SceneTree
## HWR-006 compact village: real input, production, layout migration, overflow and atomic saves.
## Run: godot --headless --path game -s tests/run_village_tests.gd
const SAVE := "user://test_saves/compact_village.json"
var data: CampaignData
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(label)

func fresh(site: StringName = &"ch1_farm") -> CampaignController:
	var c := CampaignController.new(SAVE, data)
	c.state = CampaignState.new_game(data)
	c.state.sites[String(site)].liberated = true
	c.state.sites[String(site)].management = 60
	c.state.currency = 1000
	c.state.wood = 1000
	c.state.stone = 1000
	c.state.food = 100
	c.enter_village(site)
	c.sim.wander_enabled = false
	return c

func finish(c: CampaignController, id: int) -> void:
	var v := c.active_village_state()
	var vid: int = v.sorted_villager_ids()[0]
	check(c.village_assign(vid, id).ok, "assign construction")
	for i in 500:
		c.village_tick(0.1)
		if c.active_village_state().building(id).state == "complete":
			break
	check(c.active_village_state().building(id).state == "complete", "construction completes after arrival")
	c.village_assign(vid, 0)

func _initialize() -> void:
	data = load(CampaignController.DATA_PATH)
	await process_frame
	check(VillageTemplate.WIDTH == 16 and VillageTemplate.HEIGHT == 12, "quarter area")
	for site in [&"ch1_farm", &"ch1_store"]:
		var c := fresh(site)
		var v := c.active_village_state()
		var t := c.sim.template
		check(t.validate().is_empty(), "template valid: " + String(site))
		check(t.all_obstacles().is_empty(), "no clearing prerequisites")
		check(c.sim.check_paths(v, [], 0, t.spawn).ok, "entrance, repair, dam and work zones reachable")
		for def in data.buildings_for_site(site):
			var found := false
			for y in VillageTemplate.HEIGHT:
				for x in VillageTemplate.WIDTH:
					if c.village_can_place(def, x, y, 0).ok:
						found = true
						break
				if found:
					break
			check(found, "each facility can be placed: %s/%s" % [site, def.id])
		check(t.terrain_at(Vector2i(2, 4)) == "." and c.village_can_place(data.building(&"farm"), 2, 4, 0).ok, "farm on ordinary land")
		check(not c.village_can_place(data.building(&"farm"), 14, 9, 0).ok, "outside compact boundary rejected")
		check(not c.village_can_place(data.building(&"farm"), 6, 8, 0).ok, "reserved path remains protected")
	await test_production()
	test_migration()
	await test_input_and_background()
	SaveStore.new(SAVE).delete_all()
	SaveStore.new(SAVE + Game.VILLAGE_TEST_SUFFIX).delete_all()
	for suffix in [".large-village.bak", ".v1.bak"]:
		if FileAccess.file_exists(SAVE + suffix):
			DirAccess.remove_absolute(SAVE + suffix)
	print("COMPACT VILLAGE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func test_production() -> void:
	var c := fresh()
	var r := c.village_place(&"well", 2, 1, 0)
	check(r.ok and r.saved, "well placement saves")
	if not r.ok: return
	finish(c, int(r.id))
	c.sim.actors.clear()
	r = c.village_place_canals([Vector2i(2, 3), Vector2i(3, 3)])
	check(r.ok and r.saved, "canal batch placement")
	if not r.ok: return
	for id in r.ids:
		finish(c, int(id))
	c.sim.actors.clear()
	r = c.village_place(&"farm", 2, 4, 0)
	check(r.ok and r.saved, "regular-land farm saves")
	if not r.ok: return
	var farm_id := int(r.id)
	finish(c, farm_id)
	var vid: int = c.active_village_state().sorted_villager_ids()[0]
	c.village_assign(vid, farm_id)
	var food_before := c.state.food
	var harvests := 0
	for i in 400:
		for ev in c.village_tick(0.1):
			if ev.kind == "harvest": harvests += 1
	check(harvests == 1 and c.state.food == food_before + 6, "watered farm produces exactly one harvest")
	c.leave_village()
	var loaded := CampaignController.new(SAVE, data)
	check(loaded.continue_game().ok and loaded.state.food == c.state.food, "production persists on reload")

func test_migration() -> void:
	var c := fresh()
	var v := c.active_village_state()
	v.layout_version = 0
	var ids := []
	for i in 32:
		var id := v.add_building(data.building(&"farm"), 2 + (i % 8) * 3, 3 + (i / 8) * 3, 0, true)
		v.buildings[id].progress = 13.4
		ids.append(id)
	var house := v.add_building(data.building(&"house"), 25, 19, 0, true)
	v.buildings[house].house_returned = true
	var repair := v.add_building(data.building(&"repair"), 15, 10, 0, true)
	var training := v.add_building(data.building(&"training"), 7, 8, 0, true)
	c.state.sites.ch1_farm.repaired = true
	c.state.facilities.training_ground = true
	var raw := c.state.to_dict()
	raw.villages.ch1_farm.erase("layout_version")
	var money := c.state.currency
	var wood := c.state.wood
	var next_id := v.next_id
	check(c.store.write(raw) == OK, "write legacy fixture")
	var old_bytes := FileAccess.get_file_as_string(SAVE)
	var loaded := CampaignController.new(SAVE, data)
	check(loaded.continue_game().ok, "legacy migration loads")
	v = loaded.state.village(&"ch1_farm")
	check(v.layout_version == 1 and v.buildings.size() + v.stored_buildings.size() == 35, "all buildings preserved including overflow")
	check(not v.stored_buildings.is_empty() and not v.previous_layout.is_empty(), "overflow and original layout retained")
	check(v.next_id == next_id and loaded.state.currency == money and loaded.state.wood == wood, "no IDs, funds or resources granted during migration")
	check(v.buildings.has(repair) and v.buildings.has(training) and loaded.state.has_facility(&"training_ground"), "repair and training remain functional")
	check(FileAccess.get_file_as_string(SAVE + ".large-village.bak") == old_bytes, "exact original save backup")
	for b in v.buildings.values() + v.stored_buildings.values():
		if b.def_id == "farm": check(is_equal_approx(float(b.progress), 13.4), "farm progress preserved")
	var errors := []
	var roundtrip := CampaignState.from_dict(JSON.parse_string(JSON.stringify(loaded.state.to_dict())), data, errors)
	check(errors.is_empty() and not roundtrip.layout_migrated and roundtrip.village(&"ch1_farm").stored_buildings.size() == v.stored_buildings.size(), "reload is idempotent")
	loaded.enter_village(&"ch1_farm")
	loaded.sim.actors.clear()
	var freed := Vector2i(-1, -1)
	var deployed_id := 0
	for id in v.buildings:
		if v.buildings[id].def_id == "farm":
			freed = Vector2i(v.buildings[id].x, v.buildings[id].y)
			deployed_id = int(id)
			break
	check(deployed_id != 0, "migration places farms")
	if deployed_id != 0:
		# Free one footprint to exercise the same placement path used by the menu.
		loaded.state.village(&"ch1_farm").remove_building(deployed_id)
		var stored_id := loaded.state.village(&"ch1_farm").stored_id_for(&"farm")
		loaded.store.fail_next_write = true
		var rr := loaded.village_place(&"farm", freed.x, freed.y, 0)
		check(rr.ok and not rr.saved and loaded.state.village(&"ch1_farm").stored_buildings.has(stored_id), "failed restore save leaves stored item intact")
		loaded.retry_pending()
		var restored := loaded.state.village(&"ch1_farm").building(stored_id)
		check(not restored.is_empty() and restored.state == "complete" and is_equal_approx(float(restored.progress), 13.4), "free restore retains original ID, completion and progress")
		check(loaded.state.currency == money and loaded.state.wood == wood, "restore retry charges no resources")
	# Migration failure also keeps the old bytes and retries without repeating the transfer.
	c.store.write(raw)
	old_bytes = FileAccess.get_file_as_string(SAVE)
	var failing := CampaignController.new(SAVE, data)
	failing.store.fail_next_write = true
	check(failing.continue_game().ok and failing.has_pending(), "migration write failure offers retry")
	check(FileAccess.get_file_as_string(SAVE) == old_bytes, "migration failure preserves source")
	failing.retry_pending()
	check(not failing.has_pending() and failing.state.village(&"ch1_farm").layout_version == 1, "migration retry succeeds")

func click_at(px: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = px
	motion.global_position = px
	root.push_input(motion)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = px
		ev.global_position = px
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame

func test_input_and_background() -> void:
	root.size = Vector2i(1280, 720)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	g.campaign = CampaignController.new(SAVE, data)
	var original := FileAccess.get_file_as_string(SAVE)
	g.start_village_test()
	await process_frame
	check(g.current_screen == "village" and g.village_view.test_mode, "direct village test, no combat")
	var view := g.village_view
	view.manual_input = true
	g.campaign.sim.wander_enabled = false
	var stage := view.stage
	check(stage.camera.size == 8.5 and stage.camera.rotation_degrees.x < -19, "closer side-view camera")
	check(stage.backdrop_root.has_node("DistantHills") and stage.backdrop_root.has_node("GardenGrove") and stage.backdrop_root.has_node("GardenFence"), "3D scenery attached to live game stage")
	for overview in [false, true]:
		view.overview = overview
		view._update_camera(true)
		await process_frame
		var mismatches := 0
		var visible := 0
		for y in VillageTemplate.HEIGHT:
			for x in VillageTemplate.WIDTH:
				var cell := Vector2i(x, y)
				var px := stage.ground_to_screen(Vector2(cell) + Vector2(0.5, 0.5))
				if Rect2(Vector2.ZERO, stage.viewport_size()).has_point(px):
					visible += 1
					if stage.screen_to_cell(px) != cell: mismatches += 1
		check(mismatches == 0 and visible > 60, "camera projection/input round trip")
	view.overview = false
	view._update_camera(true)
	await click_at(view.build_buttons.farm.button.get_global_rect().get_center())
	check(view.mode == "place" and view.place_def.id == &"farm", "actual farm menu click")
	var wood := g.campaign.state.wood
	await click_at(view.cell_to_root_px(Vector2i(5, 4)))
	check(g.campaign.active_village_state().count_of_def(&"farm") == 1 and g.campaign.state.wood == wood - 10, "actual ground click places farm once")
	check(FileAccess.get_file_as_string(SAVE) == original, "test entry leaves normal save untouched")
	# Export the actual scene geometry and camera for visual review with an external mesh renderer.
	var export_dir := OS.get_environment("COMPACT_PREVIEW_DIR")
	if export_dir != "":
		var state := GLTFState.new()
		var doc := GLTFDocument.new()
		var err := doc.append_from_scene(stage, state)
		if err == OK: err = doc.write_to_filesystem(state, export_dir.path_join("compact_village.glb"))
		check(err == OK, "actual game stage GLB export")
		var f := FileAccess.open(export_dir.path_join("camera.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"position": [stage.camera.position.x, stage.camera.position.y, stage.camera.position.z], "pitch": VillageStage3D.PITCH_DEG, "size": stage.camera.size, "aspect": stage.viewport_size().aspect()}))
		f.close()
	g.queue_free()
	await process_frame
