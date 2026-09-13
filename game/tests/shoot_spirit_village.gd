extends SceneTree
## HWR-006 화면 확인용 재현 입력. 실제 Game 장면을 띄우고 루트 Viewport 로 마우스 이벤트를 보내 배치까지 진행한다.
## 스크린샷: xvfb-run -a -s "-screen 0 1280x720x24" godot --path game -s tests/shoot_spirit_village.gd
## 영상(약 20초): xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --fixed-fps 12 -s tests/shoot_spirit_village.gd -- --movie=/tmp/hwr006_frames
##       → python3 tools/pack_mjpeg_avi.py /tmp/hwr006_frames 12 reports/HWR-006_farm.avi
## 테스트 저장(user://test_saves/)만 쓰고 reports/HWR-006_*.png 를 저장한다. 사용자 저장은 건드리지 않는다.

const TEST_SAVE := "user://test_saves/hwr006_shoot.json"
var out_dir := ProjectSettings.globalize_path("res://").path_join("../reports")
var g: Game
var view: VillageView
var data: CampaignData
var movie := false

func shot(name: String) -> void:
	if movie:
		return
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("HWR-006_%s.png" % name)
	var err := img.save_png(path)
	print("screenshot ", path, " err=", err)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func c() -> CampaignController:
	return g.campaign

func vs() -> VillageState:
	return c().active_village_state()

# ------------------------------------------------------------------ 실제 입력

func mouse_move(px: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	root.push_input(ev)
	await process_frame

func mouse_button(px: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = px
	ev.global_position = px
	ev.button_index = button
	ev.pressed = pressed
	root.push_input(ev)
	await process_frame

func click(px: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await mouse_move(px)
	await mouse_button(px, true, button)
	await mouse_button(px, false, button)

func key(physical: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = true
	root.push_input(ev)
	await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = physical
	up.pressed = false
	root.push_input(up)
	await process_frame

func build_button_px(def_id: String) -> Vector2:
	var b: Button = view.build_buttons[def_id].button
	return b.get_global_rect().get_center()

## 플레이어를 칸에 세우고 카메라를 맞춘다(실제 조작에서는 걸어가는 부분).
func stand(cell: Vector2i) -> void:
	view.player_pos = (Vector2(cell) + Vector2(0.5, 0.5)) * VillageView.CELL
	c().sim.player_cell = cell
	view._update_camera(true)
	await process_frame

## 경제 시간을 컨트롤러 틱으로 진행한다(소프트웨어 렌더가 느려 실시간 대신, 규칙은 같다). 화면은 다음 프레임에 같은 상태를 그린다.
func advance(seconds: float) -> void:
	for i in int(round(seconds / VillageSim.TICK)):
		var ev := c().village_tick(VillageSim.TICK)
		for e in ev:
			view._log_event(e)
	view._after_change()
	await process_frame

func wait_arrival(vid: int, max_s: float = 40.0) -> bool:
	for i in int(max_s / VillageSim.TICK):
		c().village_tick(VillageSim.TICK)
		if c().sim.actors[vid].arrived:
			view._after_change()
			await process_frame
			return true
	return false

## 정돈 부탁 → 정령 도착 → 완료까지(실제 규칙: 덤불 1·나무 2·바위 3초)
func clear_with_spirit(cell: Vector2i, shot_name: String = "") -> void:
	var r := c().village_request_clear(VillageTemplate.obstacle_id(cell))
	if not r.ok:
		print("request fail ", cell, " ", r.reason)
		return
	await wait_arrival(int(r.villager))
	if shot_name != "":
		await frames(25)   # 모으기 0.2초 이후 바람이 보이도록 실제 프레임 진행
		await shot(shot_name)
	var guard := 0
	while c().sim.has_obstacle(vs(), cell) and guard < 100:
		for e in c().village_tick(VillageSim.TICK):
			view._log_event(e)
		guard += 1
	view._after_change()
	await process_frame

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--movie="):
			movie = true
			movie_dir = a.trim_prefix("--movie=")
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
	if movie:
		await run_movie()
	else:
		await run_shots()
	quit()

# ------------------------------------------------------------------ 스크린샷 순서

func run_shots() -> void:
	await frames(6)
	await shot("side_view_enter")
	await key(KEY_M)
	await shot("overview")
	await key(KEY_M)
	# 동쪽 위 들판으로 이동(카메라 추적) → 장애물 선택 패널
	await stand(Vector2i(24, 4))
	await click(view.cell_to_root_px(Vector2i(23, 3)))
	await shot("obstacle_panel")
	# 정령에게 정돈 부탁(E) → 걸어가서 바람으로 치우는 모습 (바위 3초: (25,5) 에 서면 인접 대상이 (24,5) 바위)
	await click(Vector2(600, 300), MOUSE_BUTTON_RIGHT)
	await stand(Vector2i(25, 5))
	await key(KEY_E)
	var first_req := VillageTemplate.obstacle_id(Vector2i(24, 5))
	await wait_arrival(vs().worker_of_obstacle(first_req))
	await frames(12)
	await shot("spirit_clearing_wind")
	await advance(3.5)
	# 농장 자리 3×3 (21..23, 3..5) 바깥부터 정돈
	for cell in [Vector2i(23, 3), Vector2i(23, 4), Vector2i(23, 5), Vector2i(22, 3), Vector2i(22, 4), Vector2i(22, 5), Vector2i(21, 3), Vector2i(21, 4), Vector2i(21, 5)]:
		if c().sim.has_obstacle(vs(), cell):
			await clear_with_spirit(cell)
	await advance(8.0)   # 정령들이 시작 칸으로 돌아갈 시간
	# 실제 마우스로 농장 배치: 건설 버튼 → 불가 칸(강) → 유효 칸 클릭
	await stand(Vector2i(24, 4))
	await click(build_button_px("farm"))
	await mouse_move(view.cell_to_root_px(Vector2i(27, 6)))
	await shot("preview_invalid")
	await mouse_move(view.cell_to_root_px(Vector2i(21, 3)))
	await shot("preview_valid_farm")
	await mouse_button(view.cell_to_root_px(Vector2i(21, 3)), true)
	await mouse_button(view.cell_to_root_px(Vector2i(21, 3)), false)
	print("farm placed by real click: ", vs().count_of_def(&"farm"), " msg=", view.message)
	await shot("placed_by_click")
	var fid := 0
	for id in vs().sorted_building_ids():
		if vs().buildings[id].def_id == "farm":
			fid = id
	if fid == 0:
		print("farm placement failed")
		return
	# 공사: 정령 배정(패널) → 도착 → 바람으로 짓는 중
	var v1: int = vs().first_idle_villager()
	view.do_assign(v1, fid)
	await wait_arrival(v1)
	await frames(25)
	await shot("construction_wind")
	await advance(6.5)
	# 우물(24,3): 실제 클릭 배치 → 정령 공사
	await click(build_button_px("well"))
	await mouse_move(view.cell_to_root_px(Vector2i(24, 2)))
	await mouse_button(view.cell_to_root_px(Vector2i(24, 2)), true)
	await mouse_button(view.cell_to_root_px(Vector2i(24, 2)), false)
	var wid := 0
	for id in vs().sorted_building_ids():
		if vs().buildings[id].def_id == "well":
			wid = id
	if wid != 0:
		var v2: int = vs().first_idle_villager()
		view.do_assign(v2, wid)
		await wait_arrival(v2)
		await advance(6.5)
	# 농부 배정 → 도착 → 바람 농사(씨앗) → 성장 → 수확
	view.do_assign(v1, fid)
	await wait_arrival(v1)
	await stand(Vector2i(25, 6))
	await frames(25)
	await shot("farmer_wind_stage0")
	await key(KEY_V)
	await shot("water_overlay")
	await key(KEY_V)
	await advance(10.5)
	await frames(6)
	await shot("crop_stage1")
	await advance(10.0)
	await frames(6)
	await shot("crop_stage2")
	await advance(9.6)
	await frames(4)
	await shot("harvest")
	# 선택 패널(농장) + 가림 완화: 주택을 플레이어 앞에 두고 뒤에 서기
	await click(view.cell_to_root_px(Vector2i(22, 4)))
	await shot("farm_panel")
	await click(Vector2(600, 300), MOUSE_BUTTON_RIGHT)
	await stand(Vector2i(26, 9))
	await click(build_button_px("house"))
	await mouse_move(view.cell_to_root_px(Vector2i(24, 6)))
	await mouse_button(view.cell_to_root_px(Vector2i(24, 6)), true)
	await mouse_button(view.cell_to_root_px(Vector2i(24, 6)), false)
	print("house placed: ", vs().count_of_def(&"house"), " msg=", view.message)
	await stand(Vector2i(25, 5))
	await frames(3)
	await shot("occlusion_fade")
	await key(KEY_M)
	await shot("overview_built")
	await key(KEY_M)
	view._help_open = true
	view._refresh_hud()
	await shot("help")
	view._help_open = false
	print("done. buildings=", vs().buildings.size(), " food=", c().state.food, " wood=", c().state.wood)

# ------------------------------------------------------------------ 영상: 이동 + 바람 농사 + 수확 (약 20초, 실제 프레임)
## 실행: xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --fixed-fps 12 -s tests/shoot_spirit_village.gd -- --movie=<프레임 저장 폴더>
## 각 프레임을 640×360 JPEG 로 저장하고, tools/pack_mjpeg_avi.py 로 reports/HWR-006_farm.avi(MJPEG) 를 만든다.

var movie_dir := ""
var movie_frame := 0

func capture_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	img.save_jpg(movie_dir.path_join("frame_%04d.jpg" % movie_frame), 0.62)
	movie_frame += 1

func run_movie() -> void:
	# 준비: 3×3 정돈, 농장·우물 완공, 농부 배정(컨트롤러 틱). 이후는 실제 프레임으로 진행한다.
	for cell in [Vector2i(23, 3), Vector2i(23, 4), Vector2i(23, 5), Vector2i(22, 3), Vector2i(22, 4), Vector2i(22, 5), Vector2i(21, 3), Vector2i(21, 4), Vector2i(21, 5), Vector2i(24, 5)]:
		if c().sim.has_obstacle(vs(), cell):
			await clear_with_spirit(cell)
	for i in 100:   # 정령들이 시작 칸으로 돌아갈 시간(서 있는 칸에는 설치 불가)
		c().village_tick(VillageSim.TICK)
	c().sim.player_cell = Vector2i(15, 21)
	var fr := c().village_place(&"farm", 21, 3, 0)
	var wr := c().village_place(&"well", 24, 2, 0)
	print("movie setup: farm ", fr.ok, " ", fr.reason, " / well ", wr.ok, " ", wr.reason)
	for id in [fr.id, wr.id]:
		if id == 0:
			continue
		var v: int = vs().first_idle_villager()
		c().village_assign(v, id)
		await wait_arrival(v)
		for i in 62:
			c().village_tick(VillageSim.TICK)
		c().village_assign(v, 0)
	var farmer: int = vs().first_idle_villager()
	c().village_assign(farmer, fr.id)
	await wait_arrival(farmer)
	for i in 120:   # 성장 12초 진행: 영상 안에서 수확이 보이도록
		c().village_tick(VillageSim.TICK)
	c().sim.wander_enabled = true
	view._after_change()
	await stand(Vector2i(19, 9))
	# 실제 프레임: 걷기(가로로 길게, 앞뒤로도) → 밭 옆에서 정령 바람 농사 지켜보기 → 수확
	var plan := [[Vector2(1, 0), 2.0], [Vector2(0, 1), 0.7], [Vector2(-1, 0), 2.5], [Vector2(0, -1), 0.9], [Vector2(1, 0), 2.6], [Vector2(0, 0), 3.0], [Vector2(0, -1), 0.6], [Vector2(0, 0), 8.5]]
	var elapsed := 0.0
	for step in plan:
		view.input_move = step[0]
		var t := 0.0
		while t < float(step[1]):
			await capture_frame()
			var dt := root.get_process_delta_time()
			t += dt
			elapsed += dt
	view.input_move = Vector2.ZERO
	print("movie frames ", movie_frame, " elapsed ", elapsed, " food=", c().state.food, " farm progress=", vs().building(fr.id).progress)
