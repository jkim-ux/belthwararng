extends SceneTree
## HWR-GRASS-001: capture the real village (main.tscn -> new game -> farm run victory -> enter village)
## with the grass tiles under the game camera. Same entry path as tests/shoot_spirit_village.gd, but only
## screenshots; writes reports/HWR-GRASS-001_village_*.png and a test save under user://test_saves/.
##   godot --path game -s tests/shoot_grass_village.gd

const TEST_SAVE := "user://test_saves/hwr_grass_shoot.json"
var out_dir := ProjectSettings.globalize_path("res://").path_join("../reports")
var g: Game
var view: VillageView
var data: CampaignData


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("HWR-GRASS-001_%s.png" % name)
	print("screenshot ", path, " err=", img.save_png(path))


func key(physical: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = physical
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame


func stand(cell: Vector2i) -> void:
	view.player_pos = (Vector2(cell) + Vector2(0.5, 0.5)) * VillageView.CELL
	g.campaign.sim.player_cell = cell
	view._update_camera(true)
	await process_frame


func _initialize() -> void:
	SaveStore.new(TEST_SAVE).delete_all()
	data = load(CampaignController.DATA_PATH)
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	g = scene.instantiate()
	root.add_child(g)
	await process_frame
	g.campaign = CampaignController.new(TEST_SAVE, data)
	g._start_new_game()
	var br := g.campaign.begin_run(&"ch1_farm")
	g.campaign.resolve_run(br.run_id, &"victory", {"chest_bonus": 30})
	g.show_map()
	await process_frame
	g.show_village(&"ch1_farm")
	await process_frame
	view = g.village_view
	view.manual_input = true
	await frames(6)
	var stage: VillageStage3D = view.stage
	if stage != null and stage.grass != null:
		print("village grass tiles: ", stage.grass.tile_count(), " multimeshes: ", stage.grass.multimesh_count())
	await shot("village_game_enter")
	await key(KEY_M)
	await shot("village_game_overview")
	await key(KEY_M)
	await stand(Vector2i(4, 4))
	await shot("village_game_stand_4_4")
	await stand(Vector2i(11, 9))
	await shot("village_game_stand_11_9")
	SaveStore.new(TEST_SAVE).delete_all()
	quit()
