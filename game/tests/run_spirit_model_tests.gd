extends SceneTree
## Imported rig, per-NPC pose isolation and live farming integration. Uses a test save only.
const SAVE := "user://test_saves/approved_spirit.json"
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(label)

func mesh_in(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var m := mesh_in(child)
		if m != null:
			return m
	return null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var a := SpiritActor3D.new()
	var b := SpiritActor3D.new()
	a.build(1, 0)
	b.build(2, 1)
	root.add_child(a)
	root.add_child(b)
	var mesh_a := mesh_in(a.model)
	var mesh_b := mesh_in(b.model)
	check(a.skeleton.get_bone_count() == 5, "Imported five-bone rig")
	check(mesh_a.mesh == mesh_b.mesh and a.skeleton != b.skeleton, "Shared mesh, independent skeletons")
	check(mesh_a.skin != null, "Geometry is bound to the skeleton")
	var triangles := 0
	for i in mesh_a.mesh.get_surface_count():
		triangles += mesh_a.mesh.surface_get_array_index_len(i) / 3
	check(triangles == 64000, "Runtime geometry budget is 64,000 triangles")
	var mat: StandardMaterial3D = mesh_a.mesh.surface_get_material(0)
	check(mat.albedo_texture != null and mat.normal_texture != null, "Color and feather normal textures imported")
	check(mat.albedo_texture.get_width() == 4096, "Original 4K color map retained")
	var untouched := b.skeleton.get_bone_pose_rotation(b.bone_wing_l)
	a.update_anim(0.75, "work", null)
	check(a.skeleton.get_bone_pose_rotation(a.bone_wing_l).angle_to(Quaternion.IDENTITY) > 0.2, "Work opens the skinned wings")
	check(b.skeleton.get_bone_pose_rotation(b.bone_wing_l).is_equal_approx(untouched), "Worker animation does not change another NPC")
	a.update_anim(0.1, "move", Vector3(2, 0, 0))
	check(a.body.position.y > SpiritActor3D.HOVER_Y, "Walking retains the hop")
	a.play_harvest()
	a.update_anim(0.15, "idle", null)
	check(a.harvest_t > 0 and a.body.position.y >= SpiritActor3D.HOVER_Y, "Harvest celebrates above the ground")
	a.free()
	b.free()
	SaveStore.new(SAVE).delete_all()
	SaveStore.new(SAVE + Game.VILLAGE_TEST_SUFFIX).delete_all()
	var game: Game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.campaign = CampaignController.new(SAVE)
	game.start_village_test()
	await process_frame
	check(game.current_screen == "village" and game.battle == null, "Actual game opens directly into the test village")
	var c := game.campaign
	var vs := c.active_village_state()
	var data := c.data
	var view := game.village_view
	check(view.stage.actor_nodes.size() == 3, "All three village NPCs use the imported actor")
	vs.add_building(data.building(&"well"), 6, 4, 0, true)
	vs.add_building(data.building(&"canal"), 5, 4, 0, true)
	var farm := vs.add_building(data.building(&"farm"), 2, 4, 0, true)
	var farmer: int = vs.sorted_villager_ids()[0]
	check(c.village_assign(farmer, farm).ok, "Farmer assignment still succeeds")
	vs = c.active_village_state()
	var saw_move := false
	var saw_work := false
	for i in 500:
		c.village_tick(VillageSim.TICK)
		vs = c.active_village_state()
		view.stage.sync_actors(vs, c.sim, VillageSim.TICK)
		var st: String = c.sim.work_status(vs, farmer).state
		saw_move = saw_move or st == "move"
		if st == "work":
			saw_work = true
			break
	check(saw_move and saw_work, "Live simulation moves the new model to the farm and starts work")
	for i in 8:
		c.village_tick(VillageSim.TICK)
		vs = c.active_village_state()
		view.stage.sync_actors(vs, c.sim, VillageSim.TICK)
	check(view.stage.wind_ribbons.has(farmer), "Working model emits the existing wind effect")
	vs.buildings[farm].progress = 24.0
	view._after_change()
	view._sync_stage(0.0)
	view._refresh_hud()
	var output := OS.get_environment("SPIRIT_CAPTURE_DIR")
	if output != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(output)
		view.set_process(false)
		view.overlay.queue_redraw()
		var actor: SpiritActor3D = view.stage.actor_nodes[farmer]
		view.stage.set_camera(actor.position.x + 4.0, false, true)
		await capture(output.path_join("spirit-village.jpg"))
		# Inspection camera only; normal village camera is not modified by this test.
		# Use the NPC on the open path so ripe crops do not hide the approved face.
		actor = view.stage.actor_nodes[vs.sorted_villager_ids()[1]]
		var cam := view.stage.camera
		cam.size = 1.8
		var target := actor.global_position + Vector3(0, 0.5, 0)
		cam.position = target + actor.global_basis.x * 5.5 + actor.global_basis.z * 2.0 + Vector3(0, 1.9, 0)
		cam.look_at(target)
		view.overlay.visible = false
		await capture(output.path_join("spirit-closeup.jpg"))
		for frame in 24:
			actor.update_anim(1.0 / 12.0, "work", null)
			await capture(output.path_join("motion_%02d.jpg" % frame))
	var food := c.state.food
	var harvested := false
	for i in 100:
		for event in c.village_tick(VillageSim.TICK):
			view._log_event(event)
			if event.kind == "harvest":
				harvested = true
		vs = c.active_village_state()
		view.stage.sync_actors(vs, c.sim, VillageSim.TICK)
		if harvested:
			break
	check(harvested and c.state.food > food, "New model does not interrupt actual food production")
	check(not FileAccess.file_exists(SAVE), "Test village leaves campaign save untouched")
	game.show_title()
	await process_frame
	game.free()
	SaveStore.new(SAVE).delete_all()
	SaveStore.new(SAVE + Game.VILLAGE_TEST_SUFFIX).delete_all()
	print("SPIRIT MODEL: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(path, 0.92)
