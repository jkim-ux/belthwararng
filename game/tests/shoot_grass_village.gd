extends SceneTree
## HWR-GRASS-001 R3: capture the real village (main.tscn -> new game -> farm run victory -> enter village)
## under the game camera, with a representative state placed through the real placement rules:
## path/grass boundary, forest trees, a well, a farm, two road cells, the fence row and the spirits.
## Writes reports/HWR-GRASS-001_R3_<tag>_*.png and reports/HWR-GRASS-001_R3_<tag>_perf.json (real frame
## times of the whole village incl. spirits, buildings and UI). Same script for the before/after pair:
##   godot --path game -s tests/shoot_grass_village.gd -- --tag before
##   godot --path game -s tests/shoot_grass_village.gd -- --tag after
## Test state lives in user://test_saves/hwr_grass_shoot.json and is deleted at the end.

const TEST_SAVE := "user://test_saves/hwr_grass_shoot.json"
const WARMUP := 30
const SAMPLE := 240
var out_dir := ProjectSettings.globalize_path("res://").path_join("../reports")
var tag := "after"
var movie_dir := ""
var movie_frame := 0
var g: Game
var view: VillageView
var data: CampaignData
var perf: Array = []


func c() -> CampaignController:
	return g.campaign


func vs() -> VillageState:
	return c().state.village(c().active_village)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("HWR-GRASS-001_R3_%s_%s.png" % [tag, name])
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
	c().sim.player_cell = cell
	view._update_camera(true)
	await process_frame


func wait_arrival(vid: int, max_s: float = 40.0) -> bool:
	for i in int(max_s / VillageSim.TICK):
		c().village_tick(VillageSim.TICK)
		if c().sim.actors[vid].arrived:
			view._after_change()
			await process_frame
			return true
	return false


## Place a building with the real rules and let a spirit finish it (real construction ticks).
func place_and_finish(def_id: StringName, x: int, y: int, rot: int) -> int:
	var r := c().village_place(def_id, x, y, rot)
	print("place %s at %d,%d: ok=%s reason=%s" % [def_id, x, y, r.ok, r.reason])
	if not r.ok:
		return 0
	var id: int = r.id
	if String(vs().buildings[id].state) == "complete":
		return id
	var v: int = vs().first_idle_villager()
	if v == 0:
		print("no idle spirit for construction")
		return id
	c().village_assign(v, id)
	if await wait_arrival(v):
		for i in 80:
			c().village_tick(VillageSim.TICK)
			if String(vs().buildings[id].state) == "complete":
				break
	c().village_assign(v, 0)
	for i in 40:   # let the spirit walk back before the capture
		c().village_tick(VillageSim.TICK)
	view._after_change()
	await process_frame
	print("%s state=%s" % [def_id, vs().buildings[id].state])
	return id


## Real-time walk (right, pause, left) captured frame by frame at 640x360 for a short clip.
func walk_clip() -> void:
	var plan := [[Vector2(1, 0), 2.2], [Vector2(0, 0), 0.8], [Vector2(-1, 0), 2.2], [Vector2(0, 0), 0.6]]
	for step in plan:
		view.input_move = step[0]
		var t := 0.0
		while t < float(step[1]):
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
			img.save_jpg(movie_dir.path_join("frame_%04d.jpg" % movie_frame), 0.7)
			movie_frame += 1
			t += get_root().get_process_delta_time()
	view.input_move = Vector2.ZERO
	print("movie frames ", movie_frame)


func measure(name: String) -> void:
	var prev := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await frames(WARMUP)
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in SAMPLE:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	DisplayServer.window_set_vsync_mode(prev)
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= maxf(times.size(), 1.0)
	var s := {
		"name": name, "frame_ms_avg": snappedf(avg, 0.01), "frame_ms_p95": snappedf(times[int(floor((times.size() - 1) * 0.95))], 0.01),
		"frame_samples": times.size(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buildings": vs().buildings.size(), "villagers": vs().villagers.size(),
	}
	perf.append(s)
	print("perf %-22s %6.2f ms avg  %6.2f ms p95  draw %4d  prims %9d  objects %4d  vram %.1f MB" % [name, s.frame_ms_avg, s.frame_ms_p95, s.draw_calls, s.primitives, s.objects, s.video_mem_mb])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--tag" and i + 1 < args.size():
			tag = args[i + 1]
		if args[i] == "--movie" and i + 1 < args.size():
			movie_dir = args[i + 1]
			DirAccess.make_dir_recursive_absolute(movie_dir)
	SaveStore.new(TEST_SAVE).delete_all()
	data = load(CampaignController.DATA_PATH)
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	g = scene.instantiate()
	root.add_child(g)
	await process_frame
	g.campaign = CampaignController.new(TEST_SAVE, data)
	g._start_new_game()
	var br := c().begin_run(&"ch1_farm")
	c().resolve_run(br.run_id, &"victory", {"chest_bonus": 30})
	g.show_map()
	await process_frame
	g.show_village(&"ch1_farm")
	await process_frame
	view = g.village_view
	view.manual_input = true
	await frames(6)
	print("renderer ", RenderingServer.get_current_rendering_method(), " gpu ", RenderingServer.get_video_adapter_name(), " window ", DisplayServer.window_get_size(), " tag ", tag)
	var stage: VillageStage3D = view.stage
	var clumps: Variant = stage.get("clumps")
	if clumps != null:
		print("village clumps: ", clumps.clump_count(), " multimeshes: ", clumps.multimesh_count())
	var old_grass: Variant = stage.get("grass")
	if old_grass != null:
		print("village grass tiles: ", old_grass.tile_count(), " multimeshes: ", old_grass.multimesh_count())
	# 1. plain entry / overview
	await shot("enter")
	await key(KEY_M)
	await shot("overview")
	await key(KEY_M)
	await measure("enter_no_buildings")
	# 2. representative state: well, farm, two road cells next to the path (real placement + construction)
	for i in 40:
		c().village_tick(VillageSim.TICK)
	c().sim.player_cell = Vector2i(3, 9)
	var well := await place_and_finish(&"well", 5, 4, 0)
	var farm := await place_and_finish(&"farm", 2, 5, 0)
	var road_a := await place_and_finish(&"road", 5, 7, 0)
	var road_b := await place_and_finish(&"road", 6, 7, 0)
	await stand(Vector2i(3, 9))
	await shot("stand_3_9")
	await measure("stand_3_9")
	if movie_dir != "":
		await walk_clip()
	await stand(Vector2i(11, 9))
	await shot("stand_11_9")
	await key(KEY_M)
	await shot("overview_built")
	await key(KEY_M)
	# 3. demolish the roads and the well: the grass must come back exactly where it was
	for id in [road_a, road_b, well]:
		if id != 0:
			var r := c().village_demolish(id)
			print("demolish ", id, " ok=", r.ok, " ", r.reason)
	view._after_change()
	await stand(Vector2i(3, 9))
	await shot("stand_3_9_demolished")
	print("farm id ", farm, " buildings left ", vs().buildings.size())
	var f := FileAccess.open(out_dir.path_join("HWR-GRASS-001_R3_%s_perf.json" % tag), FileAccess.WRITE)
	f.store_string(JSON.stringify({"tag": tag, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string, "window": [1280, 720], "results": perf}, "  "))
	f.close()
	SaveStore.new(TEST_SAVE).delete_all()
	quit()
