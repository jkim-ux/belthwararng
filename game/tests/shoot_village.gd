extends SceneTree
## HWR-005 화면 확인용 재현 입력. 실행(가상 화면): xvfb-run -a -s "-screen 0 1280x720x24" godot --path game -s tests/shoot_village.gd
## 테스트 저장(user://test_saves/)만 쓰고 reports/HWR-005_*.png 를 저장한다. 사용자 저장은 건드리지 않는다.

const TEST_SAVE := "user://test_saves/hwr005_shoot.json"
var out_dir := ProjectSettings.globalize_path("res://").path_join("../reports")
var g: Game
var view: VillageView

func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("HWR-005_%s.png" % name)
	var err := img.save_png(path)
	print("screenshot ", path, " err=", err)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func c() -> CampaignController:
	return g.campaign

func vs() -> VillageState:
	return c().active_village_state()

## 플레이어를 칸에 세우고 E 작업을 경제 틱으로 진행한다(소프트웨어 렌더가 느려 실시간 대신 컨트롤러 틱 사용, 규칙은 동일).
func hold_e_at(cell: Vector2i, seconds: float) -> void:
	view.player_pos = (Vector2(cell) + Vector2(0.5, 0.5)) * VillageView.CELL
	c().sim.player_cell = cell
	c().sim.player_work = c().sim.interact_target(vs())
	for i in int(seconds / VillageSim.TICK):
		var ev := c().village_tick(VillageSim.TICK)
		for e in ev:
			view._log_event(e)
	c().sim.player_work = {}
	view._after_change()
	await process_frame

## 실제 조작처럼 걸을 수 있는 이웃 칸에 서서 E 를 누른다(장애물 위에는 설 수 없다).
func clear_cells(cells: Array) -> void:
	for cell in cells:
		var cc: Vector2i = cell
		var ch := view.template.obstacle_at(cc)
		var stand := Vector2i(-1, -1)
		for d in VillageSim.DIRS:
			var n: Vector2i = cc + d
			if c().sim.is_walkable(vs(), n):
				c().sim.player_cell = n
				var tgt := c().sim.interact_target(vs())
				if not tgt.is_empty() and tgt.kind == "obstacle" and tgt.cell == cc:
					stand = n
					break
		if stand.x < 0:
			print("no stand cell for ", cc)
			continue
		await hold_e_at(stand, VillageTemplate.obstacle_work(ch) + 0.3)

func build(def_id: StringName, x: int, y: int) -> int:
	view.player_pos = (Vector2(view.template.spawn) + Vector2(0.5, 0.5)) * VillageView.CELL
	await process_frame
	var r := c().village_place(def_id, x, y, 0)
	if not r.ok:
		print("place failed ", def_id, " ", r.reason)
		return 0
	var def := c().data.building(def_id)
	var door := c().sim.work_cell(vs().building(r.id))
	await hold_e_at(door, def.work_required / VillageSim.PLAYER_BUILD_RATE + 0.4)
	return r.id

func _initialize() -> void:
	SaveStore.new(TEST_SAVE).delete_all()
	var data: CampaignData = load(CampaignController.DATA_PATH)
	var scene: PackedScene = load("res://scenes/main.tscn")
	g = scene.instantiate()
	root.add_child(g)
	await process_frame
	g.campaign = CampaignController.new(TEST_SAVE, data)
	g._start_new_game()
	var br := c().begin_run(&"ch1_farm")
	c().resolve_run(br.run_id, &"victory", {"chest_bonus": 30})
	g.show_map()
	await shot("map")
	g.show_village(&"ch1_farm")
	await process_frame
	view = g.village_view
	view.manual_input = true
	await frames(5)
	await shot("village_enter")
	view.overview = true
	view._update_camera(true)
	await shot("village_overview")
	view.overview = false
	view._update_camera(true)
	# 배치 불가 미리보기(강 위)
	view.player_pos = Vector2(24.5, 9.5) * VillageView.CELL
	view._update_camera(true)
	view.begin_place(data.building(&"well"))
	view.hover_cell = Vector2i(28, 7)
	view._update_preview()
	await shot("preview_invalid_river")
	view.hover_cell = Vector2i(21, 6)
	view._update_preview()
	await shot("preview_invalid_obstacle")
	view.cancel_mode()
	# 개간: 바위 (24,5) → 농장 3×3 (21..23, 3..5) 동쪽 열부터
	await clear_cells([Vector2i(24, 5)])
	var cells := []
	for x in [23, 22, 21]:
		for y in range(3, 6):
			cells.append(Vector2i(x, y))
	await clear_cells(cells.slice(0, 4))
	await shot("clearing")
	await clear_cells(cells.slice(4))
	# 농장 미리보기(유효) → 설치 → 공사 중 화면 (플레이어는 개간지 동쪽 지면 (24,3) 에 선다)
	view.player_pos = Vector2(24.5, 3.5) * VillageView.CELL
	c().sim.player_cell = Vector2i(24, 3)
	view.begin_place(data.building(&"farm"))
	view.hover_cell = Vector2i(21, 3)
	view._update_preview()
	await shot("preview_valid_farm")
	view.confirm_place(Vector2i(21, 3))
	print("step: farm placed ", vs().buildings.size(), " ", view.message, " t=", Time.get_ticks_msec() / 1000.0)
	if vs().buildings.is_empty():
		quit(1)
		return
	var fid: int = vs().sorted_building_ids()[0]
	var vid: int = vs().sorted_villager_ids()[0]
	view.do_assign(vid, fid)
	print("step: assigned t=", Time.get_ticks_msec() / 1000.0)
	await hold_e_at(Vector2i(24, 4), 3.0)
	print("step: held t=", Time.get_ticks_msec() / 1000.0)
	view.select_building(fid)
	await frames(2)
	await shot("construction_farm_panel")
	view.select_building(0)
	await hold_e_at(Vector2i(24, 4), 4.0)
	# 우물 (24,7) + 수로 (24,6),(24,5)
	var wid := await build(&"well", 24, 7)
	view.begin_place(data.building(&"canal"))
	view._left_press(Vector2i(24, 6))
	view._extend_canal_drag(Vector2i(24, 5))
	view.hover_cell = Vector2i(24, 5)
	view._update_preview()
	await shot("canal_drag")
	view._left_release(Vector2i(24, 5))
	view.cancel_mode()
	for id in vs().sorted_building_ids():
		var b: Dictionary = vs().buildings[id]
		if b.def_id == "canal":
			await hold_e_at(Vector2i(b.x, b.y), 1.4)
	# 농부 배정 → 도착 → 성장
	view.do_assign(vid, fid)
	view.player_pos = Vector2(24.5, 3.5) * VillageView.CELL
	c().sim.player_cell = Vector2i(24, 3)
	for i in 200:
		if c().sim.actors[vid].arrived:
			break
		c().village_tick(VillageSim.TICK)
	view._after_change()
	await frames(3)
	await shot("farmer_working_stage0")
	view.show_water = true
	view.map_layer.queue_redraw()
	await shot("water_overlay")
	view.show_water = false
	view.map_layer.queue_redraw()
	# 성장 단계 2까지 시간 진행 (실시간 대기 대신 컨트롤러 틱을 직접 진행: 화면은 같은 상태를 그린다)
	for i in 110:
		c().village_tick(VillageSim.TICK)
	view.map_layer.queue_redraw()
	await shot("crop_stage1")
	for i in 100:
		c().village_tick(VillageSim.TICK)
	view.map_layer.queue_redraw()
	await shot("crop_stage2")
	var ev: Array = []
	for i in 110:
		ev.append_array(c().village_tick(VillageSim.TICK))
	for e in ev:
		view._log_event(e)
	view.map_layer.queue_redraw()
	view._refresh_hud()
	await shot("harvest")
	# 벌목소 + 주민 배정, 복구 현장 공사
	var lid := await build(&"lumber", 2, 12)
	var v2: int = vs().sorted_villager_ids()[1]
	view.do_assign(v2, lid)
	var rid := 0
	var rr := c().village_place(&"repair", 15, 10, 0)
	if rr.ok:
		rid = rr.id
		var v3: int = vs().sorted_villager_ids()[2]
		view.do_assign(v3, rid)
	view.player_pos = Vector2(6.5, 12.5) * VillageView.CELL
	c().sim.player_cell = Vector2i(6, 12)
	for i in 200:
		if c().sim.actors[v2].arrived:
			break
		c().village_tick(VillageSim.TICK)
	view._after_change()
	await frames(3)
	view.select_building(lid)
	await frames(2)
	await shot("lumber_worker_panel")
	view.select_building(0)
	view.overview = true
	view._update_camera(true)
	await shot("village_overview_built")
	# 저장 실패 오버레이
	view.overview = false
	view._update_camera(true)
	c().store.fail_next_write = true
	view.begin_place(data.building(&"house"))
	view.confirm_place(Vector2i(6, 2))
	await frames(3)
	await shot("save_failed")
	c().retry_pending()
	await frames(2)
	view._help_open = true
	view._refresh_hud()
	await shot("help")
	view._help_open = false
	SaveStore.new(TEST_SAVE).delete_all()
	quit(0)
