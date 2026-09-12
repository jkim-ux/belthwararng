class_name VillageView
extends Node2D
## 마을 장면(HWR-005): 32×24 격자 위를 플레이어가 걷고, 마우스로 건물을 미리보기·배치·회전·이동하며,
## 주민을 배정한다. 상태 변경은 모두 CampaignController 의 village_* API(후보 상태 → 검증 → 저장)로 보낸다.
## 그림은 코드로 그린 도형이며 판정은 VillageSim 의 격자 규칙을 쓴다. 전투 입력(스킬 액션)은 읽지 않는다.
##
## 조작: 방향키/WASD 이동, E 인접 장애물·공사장·농장 작업(누르는 동안)/건물 선택, B 건설 목록, 마우스 이동·좌클릭 배치,
##       R 회전, 우클릭·Esc 취소, 수로는 드래그로 여러 칸, V 관개 보기, 출입구에서 E 지도로.

signal leave_requested

const CELL := VillageTemplate.CELL_PX
const MAP_W := VillageTemplate.WIDTH * CELL
const MAP_H := VillageTemplate.HEIGHT * CELL
const TOP_BAR := 44
const BOTTOM_BAR := 96
const PLAYER_SPEED := 220.0
const VIEW_W := 1280
const VIEW_H := 720

var campaign: CampaignController
var site_id: StringName
var site: SiteDef
var template: VillageTemplate
var data: CampaignData

var world: Node2D
var map_layer: Node2D
var actor_layer: Node2D
var preview_layer: Node2D
var hud: Control
var cam: Vector2 = Vector2.ZERO
var player_pos: Vector2 = Vector2.ZERO           ## 월드 px
var player_facing: int = 1
var anim_time: float = 0.0
var walk_grid: PackedByteArray = PackedByteArray()

## 모드: "free" / "place" / "canal" / "move"
var mode: String = "free"
var place_def: BuildingDef = null
var place_rot: int = 0
var moving_id: int = 0
var canal_cells: Array = []                       ## 드래그 중 수로 칸(Vector2i)
var canal_dragging: bool = false
var hover_cell: Vector2i = Vector2i(-1, -1)
var preview: Dictionary = {}                      ## 마지막 can_place 결과
var selected_building: int = 0
var show_water: bool = false
var build_list_open: bool = true
var message: String = ""
var message_time: float = 0.0
var event_log: Array[String] = []
var _hud_dirty: bool = true
var _pending_overlay: Control = null
var _help_open: bool = false
var manual_input: bool = false                    ## 테스트: 키 입력을 읽지 않는다
var input_move: Vector2 = Vector2.ZERO             ## 테스트용 이동 입력
var input_e_held: bool = false

# ------------------------------------------------------------------ 준비

func setup(p_campaign: CampaignController, p_site_id: StringName) -> void:
	campaign = p_campaign
	site_id = p_site_id
	data = campaign.data
	site = data.site(site_id)
	template = data.village_template(site_id)

func _ready() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	map_layer = Node2D.new()
	map_layer.name = "Map"
	map_layer.draw.connect(_draw_map)
	world.add_child(map_layer)
	actor_layer = Node2D.new()
	actor_layer.name = "Actors"
	actor_layer.draw.connect(_draw_actors)
	world.add_child(actor_layer)
	preview_layer = Node2D.new()
	preview_layer.name = "Preview"
	preview_layer.draw.connect(_draw_preview)
	world.add_child(preview_layer)
	player_pos = (Vector2(template.spawn) + Vector2(0.5, 0.5)) * CELL
	_build_hud()
	_refresh_walk_grid()
	_update_camera(true)
	_refresh_hud()
	map_layer.queue_redraw()

func vs() -> VillageState:
	return campaign.active_village_state()

func sim() -> VillageSim:
	return campaign.sim

func player_cell() -> Vector2i:
	return Vector2i(floori(player_pos.x / CELL), floori(player_pos.y / CELL))

func _refresh_walk_grid() -> void:
	if sim() != null and vs() != null:
		walk_grid = sim().blocked_grid(vs())

# ------------------------------------------------------------------ 매 프레임

func _process(delta: float) -> void:
	if campaign == null or not campaign.in_village():
		return
	anim_time += delta
	_handle_movement(delta)
	sim().player_cell = player_cell()
	# E 작업(누르는 동안): 인접 장애물 → 공사 현장 → 농장
	var e_held := input_e_held if manual_input else (Input.is_physical_key_pressed(KEY_E) and mode == "free")
	if e_held:
		sim().player_work = sim().interact_target(vs())
	else:
		sim().player_work = {}
	var events := campaign.village_tick(delta)
	if not events.is_empty():
		for ev in events:
			_log_event(ev)
		_refresh_walk_grid()
		map_layer.queue_redraw()
		_hud_dirty = true
	if campaign.has_pending() and _pending_overlay == null:
		_show_pending_overlay()
	elif not campaign.has_pending() and _pending_overlay != null:
		_pending_overlay.queue_free()
		_pending_overlay = null
		_hud_dirty = true
	if message_time > 0.0:
		message_time -= delta
		if message_time <= 0.0:
			message = ""
			_hud_dirty = true
	_update_camera(false)
	if mode != "free":
		_update_preview()
	actor_layer.queue_redraw()
	if _hud_dirty or fmod(anim_time, 0.5) < delta:
		_refresh_hud()

func _handle_movement(delta: float) -> void:
	var mv := input_move if manual_input else _read_move()
	if mv.length() > 1.0:
		mv = mv.normalized()
	if mv == Vector2.ZERO:
		return
	if mv.x != 0.0:
		player_facing = 1 if mv.x > 0.0 else -1
	var step := mv * PLAYER_SPEED * delta
	var nx := player_pos + Vector2(step.x, 0.0)
	if _pos_walkable(nx):
		player_pos = nx
	var ny := player_pos + Vector2(0.0, step.y)
	if _pos_walkable(ny):
		player_pos = ny

func _read_move() -> Vector2:
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down", 0.2)
	if _help_open or _pending_overlay != null:
		return Vector2.ZERO
	# WASD (마을 전용 물리 키. 전투 스킬 액션은 읽지 않는다)
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	return v

## 발 위치(반지름 12px)의 네 모서리 칸이 모두 통행 가능해야 한다.
func _pos_walkable(p: Vector2) -> bool:
	var r := 12.0
	for off: Vector2 in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		var q: Vector2 = p + off
		var c := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
		if VillageSim.grid_blocked(walk_grid, c):
			return false
	return true

func _update_camera(snap: bool) -> void:
	var view_h := VIEW_H - TOP_BAR - BOTTOM_BAR
	var target := player_pos - Vector2(VIEW_W / 2.0, TOP_BAR + view_h / 2.0)
	target.x = clampf(target.x, 0.0, maxf(0.0, MAP_W - VIEW_W))
	target.y = clampf(target.y, -TOP_BAR, maxf(-TOP_BAR, MAP_H - VIEW_H + BOTTOM_BAR))
	cam = target if snap else cam.lerp(target, 0.15)
	world.position = -cam.round()

func on_entrance() -> bool:
	return template.terrain_at(player_cell()) == "e"

# ------------------------------------------------------------------ 입력(마을 컨텍스트)

func _unhandled_input(event: InputEvent) -> void:
	if campaign == null or not campaign.in_village() or _pending_overlay != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		match k.physical_keycode:
			KEY_B:
				build_list_open = not build_list_open
				_hud_dirty = true
			KEY_R:
				if mode == "place" or mode == "move":
					var def := place_def if mode == "place" else sim().def_of(vs().building(moving_id))
					if def != null and def.rotatable:
						place_rot = (place_rot + 1) % 4
						_update_preview()
					else:
						_say("회전 불가 건물")
			KEY_V:
				show_water = not show_water
				map_layer.queue_redraw()
				_hud_dirty = true
			KEY_ESCAPE:
				if mode != "free":
					cancel_mode()
				elif _help_open:
					_help_open = false
					_hud_dirty = true
				elif selected_building != 0:
					select_building(0)
			KEY_E:
				if mode == "free" and not _help_open:
					if on_entrance():
						request_leave()
					else:
						_select_nearby()
		return
	if event is InputEventMouseMotion:
		hover_cell = _mouse_cell()
		if mode == "canal" and canal_dragging:
			_extend_canal_drag(hover_cell)
		if mode != "free":
			_update_preview()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		hover_cell = _mouse_cell()
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "free":
				cancel_mode()
			else:
				select_building(0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_press(hover_cell)
			else:
				_left_release(hover_cell)

func _mouse_cell() -> Vector2i:
	var p := world.get_local_mouse_position()
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func _left_press(cell: Vector2i) -> void:
	match mode:
		"place":
			confirm_place(cell)
		"move":
			confirm_move(cell)
		"canal":
			canal_dragging = true
			canal_cells = [cell]
			_update_preview()
		"free":
			_select_at(cell)

func _left_release(cell: Vector2i) -> void:
	if mode == "canal" and canal_dragging:
		_extend_canal_drag(cell)
		canal_dragging = false
		confirm_canals()

func _extend_canal_drag(cell: Vector2i) -> void:
	if canal_cells.is_empty():
		canal_cells = [cell]
		return
	var last: Vector2i = canal_cells[canal_cells.size() - 1]
	# 마지막 칸에서 목표 칸까지 축 우선으로 채운다(대각선 없음)
	var c := last
	while c != cell:
		if c.x != cell.x:
			c.x += signi(cell.x - c.x)
		else:
			c.y += signi(cell.y - c.y)
		if not canal_cells.has(c):
			canal_cells.append(c)

func _select_at(cell: Vector2i) -> void:
	var occ := sim().occupancy(vs())
	if occ.has(cell):
		select_building(int(occ[cell]))
	else:
		select_building(0)

func _select_nearby() -> void:
	var pc := player_cell()
	var occ := sim().occupancy(vs())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := pc + Vector2i(dx, dy)
			if occ.has(c):
				select_building(int(occ[c]))
				return
	select_building(0)

# ------------------------------------------------------------------ 모드 전환·확정

func begin_place(def: BuildingDef) -> void:
	if def == null:
		return
	mode = "canal" if def.kind == &"canal" else "place"
	place_def = def
	place_rot = 0
	moving_id = 0
	canal_cells = []
	canal_dragging = false
	selected_building = 0
	_update_preview()
	_hud_dirty = true

func begin_move(id: int) -> void:
	var b := vs().building(id)
	if b.is_empty():
		return
	var def := sim().def_of(b)
	if not def.movable:
		_say("이동할 수 없는 건물")
		return
	mode = "move"
	moving_id = id
	place_def = def
	place_rot = int(b.rot)
	_update_preview()
	_hud_dirty = true

func cancel_mode() -> void:
	mode = "free"
	place_def = null
	moving_id = 0
	canal_cells = []
	canal_dragging = false
	preview = {}
	preview_layer.queue_redraw()
	_hud_dirty = true

func select_building(id: int) -> void:
	selected_building = id if (id != 0 and vs().has_building(id)) else 0
	_hud_dirty = true
	map_layer.queue_redraw()

func _update_preview() -> void:
	if sim() == null:
		return
	match mode:
		"place":
			preview = campaign.village_can_place(place_def, hover_cell.x, hover_cell.y, place_rot)
		"move":
			preview = campaign.village_can_place(place_def, hover_cell.x, hover_cell.y, place_rot, moving_id)
		"canal":
			var cells: Array = canal_cells if not canal_cells.is_empty() else [hover_cell]
			preview = campaign.village_can_place_canals(cells)
		_:
			preview = {}
	preview_layer.queue_redraw()

func confirm_place(cell: Vector2i) -> void:
	var r := campaign.village_place(place_def.id, cell.x, cell.y, place_rot)
	if r.ok and r.saved:
		_say("%s 설치 (%s)" % [place_def.display_name, place_def.cost_text()])
		_after_change()
		if place_def.kind != &"road":
			cancel_mode()
		else:
			_update_preview()
	elif r.ok:
		_say("설치 저장 실패: %s" % r.reason)
	else:
		_say("설치 불가: %s" % r.reason)

func confirm_canals() -> void:
	if canal_cells.is_empty():
		return
	var r := campaign.village_place_canals(canal_cells)
	if r.ok and r.saved:
		_say("수로 %d칸 설치 (목재 %d)" % [r.ids.size(), r.ids.size()])
		_after_change()
	elif r.ok:
		_say("수로 저장 실패: %s" % r.reason)
	else:
		_say("수로 설치 불가: %s" % r.reason)
	canal_cells = []
	_update_preview()

func confirm_move(cell: Vector2i) -> void:
	var r := campaign.village_move(moving_id, cell.x, cell.y, place_rot)
	if r.ok and r.saved:
		_say("이동 완료")
		_after_change()
		cancel_mode()
	elif r.ok:
		_say("이동 저장 실패: %s" % r.reason)
	else:
		_say("이동 불가: %s" % r.reason)

func do_cancel_construction(id: int) -> void:
	var r := campaign.village_cancel(id)
	_say("공사 취소, 자원 반환" if r.ok and r.saved else "취소 불가: %s" % r.reason)
	if r.ok:
		select_building(0)
		_after_change()

func do_demolish(id: int) -> void:
	var r := campaign.village_demolish(id)
	_say("철거, 원재료 반환" if r.ok and r.saved else "철거 불가: %s" % r.reason)
	if r.ok:
		select_building(0)
		_after_change()

func do_assign(villager_id: int, building_id: int) -> void:
	var r := campaign.village_assign(villager_id, building_id)
	if r.ok and r.saved:
		_say("배정 변경" if building_id != 0 else "배정 해제")
	else:
		_say("배정 불가: %s" % r.reason)
	_after_change()

func request_leave() -> void:
	if mode != "free":
		cancel_mode()
	leave_requested.emit()

func _after_change() -> void:
	_refresh_walk_grid()
	map_layer.queue_redraw()
	_hud_dirty = true

func _say(text: String) -> void:
	message = text
	message_time = 3.5
	_hud_dirty = true

func _log_event(ev: Dictionary) -> void:
	var line := ""
	match String(ev.kind):
		"obstacle_cleared":
			var r := ""
			if int(ev.wood) > 0:
				r = " 목재 +%d" % int(ev.wood)
			elif int(ev.stone) > 0:
				r = " 석재 +%d" % int(ev.stone)
			line = "%s 제거%s" % [VillageTemplate.obstacle_name(String(ev.obstacle)), r]
		"construction_complete":
			var def := data.building(StringName(String(ev.def_id)))
			line = "%s 완공" % (def.display_name if def else String(ev.def_id))
			if int(ev.villagers) > 0:
				line += " — 주민 %d명 귀환" % int(ev.villagers)
			if def != null and def.management_on_complete > 0:
				line += " — 관리도 %d" % def.management_on_complete
			if def != null and def.facility_id != &"":
				line += " — 효과 적용(1회)"
		"harvest":
			line = "수확 식량 +%d" % int(ev.food)
		"production":
			var what := "목재" if String(ev.resource) == "wood" else ("석재" if String(ev.resource) == "stone" else "식량")
			line = "%s +%d%s" % [what, int(ev.amount), "" if int(ev.fed) == 1 else " (식사 없음, 절반)"]
	if line != "":
		event_log.append(line)
		if event_log.size() > 6:
			event_log.pop_front()
		_say(line)

# ------------------------------------------------------------------ 그리기: 지형·건물

const COL_GROUND := Color(0.56, 0.5, 0.34)
const COL_FERTILE := Color(0.42, 0.33, 0.2)
const COL_RIVER := Color(0.22, 0.45, 0.75)
const COL_CLIFF := Color(0.42, 0.4, 0.4)
const COL_PATH := Color(0.68, 0.6, 0.42)
const COL_FOREST := Color(0.16, 0.34, 0.16)
const COL_ROCK := Color(0.5, 0.48, 0.45)
const COL_DAM_SITE := Color(0.45, 0.55, 0.62)
const COL_REPAIR_SITE := Color(0.5, 0.42, 0.36)

func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * CELL, c.y * CELL, CELL, CELL)

func _draw_map() -> void:
	var v := vs()
	if v == null:
		return
	var s := sim()
	var water: Dictionary = s.water if not s.water.is_empty() else s.compute_water(v)
	# 지형
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			var t := template.terrain_at(c)
			var col := COL_GROUND
			match t:
				"f": col = COL_FERTILE
				"~": col = COL_RIVER
				"#": col = COL_CLIFF
				"e", "p": col = COL_PATH
				"W": col = COL_FOREST
				"Q": col = COL_ROCK
				"d": col = COL_DAM_SITE
				"x": col = COL_REPAIR_SITE
			var r := _cell_rect(c)
			map_layer.draw_rect(r, col)
			if t == "f":
				map_layer.draw_rect(Rect2(r.position + Vector2(6, 6), Vector2(4, 4)), Color(0.5, 0.4, 0.26))
				map_layer.draw_rect(Rect2(r.position + Vector2(26, 30), Vector2(4, 4)), Color(0.5, 0.4, 0.26))
			elif t == "~":
				var off := fmod(anim_time * 20.0 + y * 7.0, CELL)
				map_layer.draw_line(r.position + Vector2(8, off), r.position + Vector2(24, off), Color(0.5, 0.7, 0.95, 0.5), 2.0)
			elif t == "W":
				map_layer.draw_colored_polygon(PackedVector2Array([r.position + Vector2(24, 6), r.position + Vector2(8, 40), r.position + Vector2(40, 40)]), Color(0.1, 0.45, 0.15))
			elif t == "Q":
				map_layer.draw_colored_polygon(PackedVector2Array([r.position + Vector2(8, 40), r.position + Vector2(20, 10), r.position + Vector2(34, 18), r.position + Vector2(42, 40)]), Color(0.62, 0.6, 0.58))
			elif t == "x":
				map_layer.draw_line(r.position + Vector2(6, 40), r.position + Vector2(40, 8), Color(0.3, 0.25, 0.2), 3.0)
				map_layer.draw_rect(Rect2(r.position + Vector2(10, 26), Vector2(14, 10)), Color(0.36, 0.3, 0.26))
			elif t == "d":
				map_layer.draw_line(r.position + Vector2(4, 24), r.position + Vector2(44, 24), Color(0.3, 0.4, 0.5), 2.0)
			elif t == "e":
				map_layer.draw_string(UiFont.FONT, r.position + Vector2(6, 30), "출구", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.15, 0.1))
			# 격자선
			map_layer.draw_rect(r, Color(0, 0, 0, 0.06), false, 1.0)
	# 장애물
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			if not s.has_obstacle(v, c):
				continue
			var r := _cell_rect(c)
			var ch := template.obstacle_at(c)
			match ch:
				"b":
					map_layer.draw_circle(r.position + Vector2(24, 28), 12, Color(0.3, 0.55, 0.25))
					map_layer.draw_circle(r.position + Vector2(16, 24), 8, Color(0.35, 0.6, 0.28))
				"t":
					map_layer.draw_rect(Rect2(r.position + Vector2(20, 26), Vector2(8, 18)), Color(0.4, 0.28, 0.15))
					map_layer.draw_circle(r.position + Vector2(24, 20), 14, Color(0.2, 0.5, 0.2))
				"r":
					map_layer.draw_colored_polygon(PackedVector2Array([r.position + Vector2(8, 40), r.position + Vector2(14, 16), r.position + Vector2(30, 10), r.position + Vector2(42, 38)]), Color(0.55, 0.55, 0.55))
			var w := float(v.clearing.get(VillageTemplate.obstacle_id(c), 0.0))
			if w > 0.0:
				var need := VillageTemplate.obstacle_work(ch)
				map_layer.draw_rect(Rect2(r.position + Vector2(6, 2), Vector2(36, 5)), Color(0, 0, 0, 0.5))
				map_layer.draw_rect(Rect2(r.position + Vector2(6, 2), Vector2(36 * clampf(w / need, 0.0, 1.0), 5)), Color(1.0, 0.85, 0.3))
	# 건물(수로·길 먼저, 본체 다음)
	var ids := v.sorted_building_ids()
	for id in ids:
		var b: Dictionary = v.buildings[id]
		var def := s.def_of(b)
		if def.kind == &"canal" or def.kind == &"road":
			_draw_building(b, def, water)
	for id in ids:
		var b: Dictionary = v.buildings[id]
		var def := s.def_of(b)
		if def.kind != &"canal" and def.kind != &"road":
			_draw_building(b, def, water)
	# 관개 보기
	if show_water:
		_draw_water_overlay(v, water)
	# 선택 표시
	if selected_building != 0 and v.has_building(selected_building):
		var b: Dictionary = v.buildings[selected_building]
		var def := s.def_of(b)
		var fp := def.footprint(int(b.rot))
		map_layer.draw_rect(Rect2(b.x * CELL, b.y * CELL, fp.x * CELL, fp.y * CELL), Color(1.0, 0.95, 0.5), false, 3.0)
		var door := s.work_cell(b)
		map_layer.draw_rect(_cell_rect(door).grow(-14), Color(1.0, 0.95, 0.5, 0.6), false, 2.0)

func _building_color(def: BuildingDef) -> Color:
	match def.kind:
		&"farm": return Color(0.5, 0.36, 0.2)
		&"well": return Color(0.6, 0.6, 0.65)
		&"dam": return Color(0.35, 0.38, 0.45)
		&"lumber": return Color(0.55, 0.38, 0.2)
		&"quarry": return Color(0.55, 0.52, 0.5)
		&"house": return Color(0.7, 0.5, 0.35)
		&"repair": return Color(0.62, 0.55, 0.42)
		&"facility": return Color(0.55, 0.3, 0.3)
	return Color(0.6, 0.6, 0.6)

func _draw_building(b: Dictionary, def: BuildingDef, water: Dictionary) -> void:
	var s := sim()
	var fp := def.footprint(int(b.rot))
	var rect := Rect2(b.x * CELL, b.y * CELL, fp.x * CELL, fp.y * CELL)
	var under: bool = b.state == "construction"
	var wet_cells: Dictionary = water.get("cell_component", {})
	var comps: Array = water.get("components", [])
	if def.kind == &"canal":
		var c := Vector2i(b.x, b.y)
		var wet := false
		if wet_cells.has(c):
			var comp: Dictionary = comps[wet_cells[c]]
			wet = int(comp.capacity) > 0
		var col := Color(0.25, 0.5, 0.85) if wet else Color(0.45, 0.5, 0.58)
		if under:
			col = Color(0.5, 0.45, 0.35)
		map_layer.draw_rect(rect.grow(-10), col)
		# 상하좌우 이웃 수로/수원과 이어진 모습
		for d in VillageSim.DIRS:
			var n: Vector2i = c + d
			if wet_cells.has(n) and not under:
				var from := rect.get_center()
				map_layer.draw_line(from, from + Vector2(d) * (CELL / 2.0), col, CELL - 20)
		if wet and not under:
			var off := fmod(anim_time * 30.0, 16.0)
			map_layer.draw_line(rect.position + Vector2(14, 14 + off), rect.position + Vector2(34, 14 + off), Color(0.6, 0.8, 1.0, 0.8), 2.0)
		_draw_construction(b, def, rect)
		return
	if def.kind == &"road":
		map_layer.draw_rect(rect.grow(-4), Color(0.75, 0.66, 0.5))
		return
	if def.kind == &"farm":
		map_layer.draw_rect(rect.grow(-2), Color(0.45, 0.3, 0.16) if not under else Color(0.5, 0.42, 0.3))
		if not under:
			var stage := VillageSim.growth_stage(b, def)
			var watered := s.is_farm_watered(int(b.id))
			for row in 3:
				for colm in 3:
					var p := rect.position + Vector2(colm * CELL + 24, row * CELL + 36)
					map_layer.draw_line(rect.position + Vector2(6, row * CELL + 38), rect.position + Vector2(fp.x * CELL - 6, row * CELL + 38), Color(0.35, 0.22, 0.12), 3.0)
					if stage >= 1:
						var h := 10.0 if stage == 1 else 24.0
						var gc := Color(0.45, 0.8, 0.3) if stage == 1 else Color(0.85, 0.75, 0.25)
						map_layer.draw_line(p, p - Vector2(0, h), Color(0.3, 0.6, 0.2), 3.0)
						map_layer.draw_circle(p - Vector2(0, h), 5 if stage == 1 else 7, gc)
					elif float(b.progress) > 0.0 or watered:
						map_layer.draw_circle(p - Vector2(0, 4), 3, Color(0.5, 0.75, 0.35))
			# 물방울: 공급 파랑 / 부족 빨강
			var drop := rect.position + Vector2(rect.size.x - 16, 16)
			map_layer.draw_circle(drop, 8, Color(0.3, 0.6, 1.0) if watered else Color(0.9, 0.3, 0.3))
			map_layer.draw_colored_polygon(PackedVector2Array([drop + Vector2(-6, -4), drop + Vector2(6, -4), drop + Vector2(0, -14)]), Color(0.3, 0.6, 1.0) if watered else Color(0.9, 0.3, 0.3))
			if not watered:
				var reason := "물 공급 필요"
				var finfo: Dictionary = water.get("farms", {}).get(int(b.id), {})
				if not finfo.is_empty() and not (finfo.touching as Array).is_empty():
					reason = "용수 부족"
				map_layer.draw_string(UiFont.FONT, rect.position + Vector2(6, 16), reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.7))
			# 성장 바
			var frac := clampf(float(b.progress) / def.cycle_seconds, 0.0, 1.0)
			map_layer.draw_rect(Rect2(rect.position + Vector2(6, rect.size.y - 10), Vector2(rect.size.x - 12, 6)), Color(0, 0, 0, 0.5))
			map_layer.draw_rect(Rect2(rect.position + Vector2(6, rect.size.y - 10), Vector2((rect.size.x - 12) * frac, 6)), Color(0.6, 0.9, 0.4))
		_draw_construction(b, def, rect)
		return
	# 일반 건물 본체
	var base := _building_color(def)
	if under:
		base = base.darkened(0.35)
	map_layer.draw_rect(rect.grow(-3), base)
	map_layer.draw_rect(rect.grow(-3), Color(0.15, 0.1, 0.08), false, 2.0)
	match def.kind:
		&"well":
			map_layer.draw_circle(rect.get_center(), 22, Color(0.35, 0.35, 0.38))
			map_layer.draw_circle(rect.get_center(), 14, Color(0.25, 0.5, 0.85) if not under else Color(0.3, 0.3, 0.3))
		&"dam":
			map_layer.draw_rect(Rect2(rect.position + Vector2(6, rect.size.y * 0.4), Vector2(rect.size.x - 12, 14)), Color(0.25, 0.25, 0.3))
			if not under:
				map_layer.draw_rect(Rect2(rect.position + Vector2(6, 6), Vector2(rect.size.x - 12, rect.size.y * 0.4 - 6)), Color(0.3, 0.55, 0.85, 0.8))
				var outlet := _cell_rect(template.dam_outlet)
				map_layer.draw_rect(outlet.grow(-12), Color(0.25, 0.5, 0.85))
		&"house":
			map_layer.draw_colored_polygon(PackedVector2Array([rect.position + Vector2(4, rect.size.y * 0.45), rect.position + Vector2(rect.size.x / 2.0, 6), rect.position + Vector2(rect.size.x - 4, rect.size.y * 0.45)]), Color(0.5, 0.25, 0.18) if not under else Color(0.4, 0.3, 0.25))
			map_layer.draw_rect(Rect2(rect.position + Vector2(rect.size.x / 2.0 - 8, rect.size.y - 28), Vector2(16, 24)), Color(0.3, 0.2, 0.12))
		&"lumber":
			map_layer.draw_rect(Rect2(rect.position + Vector2(10, rect.size.y - 34), Vector2(rect.size.x - 20, 12)), Color(0.4, 0.26, 0.12))
			map_layer.draw_rect(Rect2(rect.position + Vector2(14, rect.size.y - 48), Vector2(rect.size.x - 28, 12)), Color(0.45, 0.3, 0.14))
		&"quarry":
			map_layer.draw_colored_polygon(PackedVector2Array([rect.position + Vector2(12, rect.size.y - 12), rect.position + Vector2(rect.size.x / 2.0, 14), rect.position + Vector2(rect.size.x - 12, rect.size.y - 12)]), Color(0.7, 0.68, 0.66))
		&"repair":
			map_layer.draw_line(rect.position + Vector2(10, rect.size.y / 2.0), rect.position + Vector2(rect.size.x - 10, rect.size.y / 2.0), Color(0.8, 0.7, 0.5), 8.0)
		&"facility":
			map_layer.draw_rect(Rect2(rect.position + Vector2(rect.size.x / 2.0 - 3, 8), Vector2(6, rect.size.y - 16)), Color(0.9, 0.85, 0.7))
	map_layer.draw_string(UiFont.FONT, rect.position + Vector2(6, 16), def.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.95))
	# 문(작업 위치)
	if def.needs_door:
		var door := sim().work_cell(b)
		var dr := _cell_rect(door)
		map_layer.draw_rect(Rect2(dr.get_center() - Vector2(6, 6), Vector2(12, 12)), Color(0.9, 0.85, 0.6, 0.7))
	# 생산 진행
	if not under and def.is_producer():
		var frac := clampf(float(b.progress) / def.cycle_seconds, 0.0, 1.0)
		map_layer.draw_rect(Rect2(rect.position + Vector2(6, rect.size.y - 10), Vector2(rect.size.x - 12, 6)), Color(0, 0, 0, 0.5))
		map_layer.draw_rect(Rect2(rect.position + Vector2(6, rect.size.y - 10), Vector2((rect.size.x - 12) * frac, 6)), Color(0.95, 0.8, 0.4))
		if int(b.fed) == 0:
			map_layer.draw_string(UiFont.FONT, rect.position + Vector2(6, rect.size.y - 14), "식사 없음", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.6))
	_draw_construction(b, def, rect)

func _draw_construction(b: Dictionary, def: BuildingDef, rect: Rect2) -> void:
	if b.state != "construction":
		return
	# 자재 더미·기초 + 공사 진행 바
	map_layer.draw_rect(rect.grow(-3), Color(1, 0.9, 0.5, 0.9), false, 2.0)
	var n := 0
	while n * 16.0 < rect.size.x + rect.size.y:
		var start := rect.position + Vector2(minf(n * 16.0, rect.size.x), maxf(0.0, n * 16.0 - rect.size.x))
		var end := rect.position + Vector2(maxf(0.0, n * 16.0 - rect.size.y), minf(n * 16.0, rect.size.y))
		map_layer.draw_line(start, end, Color(1, 0.9, 0.5, 0.25), 1.0)
		n += 1
	map_layer.draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(14, 10)), Color(0.45, 0.3, 0.15))
	map_layer.draw_rect(Rect2(rect.position + Vector2(8, 0), Vector2(14, 8)), Color(0.5, 0.35, 0.18))
	var frac := clampf(float(b.work_done) / maxf(def.work_required, 0.001), 0.0, 1.0)
	map_layer.draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 12), Vector2(rect.size.x - 8, 8)), Color(0, 0, 0, 0.6))
	map_layer.draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 12), Vector2((rect.size.x - 8) * frac, 8)), Color(1.0, 0.75, 0.3))
	map_layer.draw_string(UiFont.FONT, rect.position + Vector2(rect.size.x / 2.0 - 20, rect.size.y / 2.0 + 4), "공사 %d%%" % int(frac * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.9))

func _draw_water_overlay(v: VillageState, water: Dictionary) -> void:
	var comps: Array = water.get("components", [])
	var cell_comp: Dictionary = water.get("cell_component", {})
	var colors := [Color(0.3, 0.7, 1.0), Color(0.4, 1.0, 0.9), Color(0.7, 0.6, 1.0), Color(1.0, 0.8, 0.4)]
	for c in cell_comp.keys():
		var idx: int = cell_comp[c]
		var comp: Dictionary = comps[idx]
		var col: Color = colors[idx % colors.size()] if int(comp.capacity) > 0 else Color(0.6, 0.6, 0.6)
		map_layer.draw_rect(_cell_rect(c).grow(-4), Color(col.r, col.g, col.b, 0.35))
		map_layer.draw_rect(_cell_rect(c).grow(-4), col, false, 2.0)
	var farms: Dictionary = water.get("farms", {})
	for fid in farms.keys():
		var info: Dictionary = farms[fid]
		var b: Dictionary = v.buildings[fid]
		var center := Vector2(b.x * CELL + 1.5 * CELL, b.y * CELL + 1.5 * CELL)
		if int(info.component) >= 0:
			var comp: Dictionary = comps[int(info.component)]
			var col: Color = colors[int(info.component) % colors.size()]
			for sid in comp.sources:
				var sb: Dictionary = v.buildings[sid]
				var sdef := sim().def_of(sb)
				var sfp := sdef.footprint(int(sb.rot))
				var sc := Vector2(sb.x * CELL + sfp.x * CELL / 2.0, sb.y * CELL + sfp.y * CELL / 2.0)
				map_layer.draw_line(sc, center, col, 3.0)
	for i in comps.size():
		var comp: Dictionary = comps[i]
		if comp.sources.is_empty():
			continue
		var sb: Dictionary = v.buildings[comp.sources[0]]
		map_layer.draw_string(UiFont.FONT, Vector2(sb.x * CELL, sb.y * CELL - 4), "공급 %d/%d" % [int(comp.used), int(comp.capacity)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.95, 1.0))

# ------------------------------------------------------------------ 그리기: 배우·미리보기

func _draw_person(layer: Node2D, p: Vector2, body: Color, head: Color, working: bool, facing: int, scale_: float = 1.0) -> void:
	var bob := sin(anim_time * 10.0) * 2.0 if working else 0.0
	layer.draw_rect(Rect2(p + Vector2(-7 * scale_, -26 * scale_ + bob), Vector2(14 * scale_, 22 * scale_)), body)
	layer.draw_circle(p + Vector2(0, -32 * scale_ + bob), 7 * scale_, head)
	if working:
		var arm := p + Vector2(facing * 10 * scale_, -20 * scale_ + bob)
		layer.draw_line(arm, arm + Vector2(facing * 10, -6 + sin(anim_time * 12.0) * 8.0), Color(0.6, 0.45, 0.3), 3.0)

func _draw_actors() -> void:
	var v := vs()
	if v == null:
		return
	var s := sim()
	# 주민
	for id in v.sorted_villager_ids():
		if not s.actors.has(id):
			continue
		var a: Dictionary = s.actors[id]
		var vl: Dictionary = v.villagers[id]
		var p: Vector2 = Vector2(a.pos) * CELL
		var working: bool = bool(a.arrived) and vl.job_building != 0
		_draw_person(actor_layer, p, Color(0.35, 0.5, 0.7), Color(0.95, 0.85, 0.7), working, 1, 0.85)
		var job := ""
		match String(vl.job_kind):
			"build": job = "공사"
			"farm": job = "농사"
			"lumber": job = "벌목"
			"quarry": job = "채석"
		var label := String(vl.name) + ("" if job == "" else " · " + job + ("" if working else " (이동)"))
		actor_layer.draw_string(UiFont.FONT, p + Vector2(-20, -40), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))
		if working and vl.job_kind != "build":
			# 짧은 운반 동작: 작업 중 손에 든 꾸러미
			actor_layer.draw_rect(Rect2(p + Vector2(8, -18 + sin(anim_time * 10.0) * 2.0), Vector2(8, 6)), Color(0.9, 0.8, 0.4))
	# 플레이어
	var pw := not s.player_work.is_empty()
	_draw_person(actor_layer, player_pos, Color(0.75, 0.2, 0.2), Color(0.98, 0.88, 0.75), pw, player_facing, 1.0)
	actor_layer.draw_string(UiFont.FONT, player_pos + Vector2(-16, -44), "사무라이", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.95, 0.8))
	# 상호작용 안내
	if mode == "free":
		var tgt := s.interact_target(v)
		var hint := ""
		if on_entrance():
			hint = "E: 지도로 나가기"
		elif not tgt.is_empty():
			if tgt.kind == "obstacle":
				var ch := template.obstacle_at(tgt.cell)
				var reward := VillageTemplate.obstacle_reward(ch)
				var rt := ""
				if int(reward.wood) > 0:
					rt = " (목재 +%d)" % int(reward.wood)
				elif int(reward.stone) > 0:
					rt = " (석재 +%d)" % int(reward.stone)
				hint = "E 누르기: %s 정리 %.0f초%s" % [VillageTemplate.obstacle_name(ch), VillageTemplate.obstacle_work(ch), rt]
			else:
				var b := v.building(int(tgt.id))
				hint = "E 누르기: 공사 작업 (초당 5)" if b.state == "construction" else "E 누르기: 직접 농사 (초당 1)"
		if hint != "":
			var w := hint.length() * 9.0 + 16
			actor_layer.draw_rect(Rect2(player_pos + Vector2(-w / 2.0, 8), Vector2(w, 20)), Color(0, 0, 0, 0.6))
			actor_layer.draw_string(UiFont.FONT, player_pos + Vector2(-w / 2.0 + 8, 23), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.9))

func _draw_preview() -> void:
	if mode == "free" or preview.is_empty():
		return
	var ok: bool = preview.ok
	var col := Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.3, 0.3, 0.45)
	var line := Color(0.3, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.3)
	var cells: Array = preview.get("cells", [])
	for c in cells:
		var cc: Vector2i = c
		preview_layer.draw_rect(_cell_rect(cc), col)
		preview_layer.draw_rect(_cell_rect(cc), line, false, 2.0)
	if mode == "move" and moving_id != 0 and vs().has_building(moving_id):
		var b := vs().building(moving_id)
		var def := sim().def_of(b)
		var fp := def.footprint(int(b.rot))
		preview_layer.draw_rect(Rect2(b.x * CELL, b.y * CELL, fp.x * CELL, fp.y * CELL), Color(1, 1, 1, 0.5), false, 2.0)
	var door: Vector2i = preview.get("door", Vector2i(-1, -1))
	if mode != "canal" and place_def != null and place_def.needs_door and door.x >= 0:
		preview_layer.draw_rect(_cell_rect(door).grow(-14), Color(1.0, 0.95, 0.5, 0.9), false, 2.0)
		preview_layer.draw_string(UiFont.FONT, Vector2(door.x * CELL + 8, door.y * CELL + 30), "문", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.8))
	if cells.is_empty():
		return
	var first: Vector2i = cells[0]
	var text := ("✓ " + ("설치" if mode != "move" else "이동")) if ok else ("× " + String(preview.reason))
	if mode == "canal":
		text += "  수로 %d칸 · 목재 %d" % [cells.size(), int(preview.get("cost_wood", 0))]
	elif place_def != null and mode == "place":
		text += "  " + place_def.display_name + " · " + place_def.cost_text() + (" · R 회전" if place_def.rotatable else "")
		if place_def.needs_water:
			text += " · 물 공급 필요"
	var pos := Vector2(first.x * CELL, first.y * CELL - 22)
	var w := text.length() * 9.5 + 16
	preview_layer.draw_rect(Rect2(pos, Vector2(w, 20)), Color(0, 0, 0, 0.7))
	preview_layer.draw_string(UiFont.FONT, pos + Vector2(8, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, line)

# ------------------------------------------------------------------ HUD

var top_bar: PanelContainer
var top_label: Label
var msg_label: Label
var bottom_bar: PanelContainer
var bottom_box: HBoxContainer
var side_panel: PanelContainer
var side_box: VBoxContainer
var help_panel: PanelContainer
var log_label: Label

func _style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0.75, 0.62, 0.35)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	return sb

func _lbl(text: String, size: int = 14, color: Color = Color(0.95, 0.93, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _btn(text: String, on_pressed: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(on_pressed)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _build_hud() -> void:
	hud = Control.new()
	hud.name = "HUD"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.size = Vector2(VIEW_W, VIEW_H)
	add_child(hud)
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", _style(Color(0.09, 0.08, 0.11, 0.92)))
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(VIEW_W, TOP_BAR)
	hud.add_child(top_bar)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 14)
	top_bar.add_child(th)
	top_label = _lbl("", 16, Color(1.0, 0.92, 0.6))
	top_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(top_label)
	msg_label = _lbl("", 14, Color(0.8, 0.95, 0.8))
	msg_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(msg_label)
	th.add_child(_btn("관개 보기 (V)", func(): show_water = not show_water; map_layer.queue_redraw(); _hud_dirty = true))
	th.add_child(_btn("도움말", func(): _help_open = not _help_open; _hud_dirty = true))
	th.add_child(_btn("지도로", request_leave))
	bottom_bar = PanelContainer.new()
	bottom_bar.add_theme_stylebox_override("panel", _style(Color(0.09, 0.08, 0.11, 0.92)))
	bottom_bar.position = Vector2(0, VIEW_H - BOTTOM_BAR)
	bottom_bar.size = Vector2(VIEW_W, BOTTOM_BAR)
	hud.add_child(bottom_bar)
	bottom_box = HBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 6)
	bottom_bar.add_child(bottom_box)
	side_panel = PanelContainer.new()
	side_panel.add_theme_stylebox_override("panel", _style(Color(0.09, 0.08, 0.11, 0.94)))
	side_panel.position = Vector2(VIEW_W - 320, TOP_BAR + 8)
	side_panel.size = Vector2(312, 360)
	side_panel.visible = false
	hud.add_child(side_panel)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 4)
	side_panel.add_child(side_box)
	log_label = _lbl("", 12, Color(0.85, 0.85, 0.8))
	log_label.position = Vector2(8, TOP_BAR + 6)
	log_label.size = Vector2(420, 100)
	hud.add_child(log_label)
	help_panel = PanelContainer.new()
	help_panel.add_theme_stylebox_override("panel", _style(Color(0.09, 0.08, 0.11, 0.96)))
	help_panel.position = Vector2(240, 120)
	help_panel.size = Vector2(800, 400)
	help_panel.visible = false
	hud.add_child(help_panel)
	var hv := VBoxContainer.new()
	help_panel.add_child(hv)
	hv.add_child(_lbl("마을 조작", 20, Color(1.0, 0.9, 0.65)))
	hv.add_child(_lbl("방향키/WASD 이동 · E 인접한 덤불/나무/바위 정리(누르는 동안 진행, 놓아도 진행량 유지) · E 공사 현장에서 작업(초당 5) · E 농장에서 직접 농사", 14))
	hv.add_child(_lbl("B 건설 목록 열기/닫기 · 목록에서 건물 선택 → 마우스로 반투명 미리보기 → 좌클릭 확정 · R 회전 · 우클릭/Esc 취소", 14))
	hv.add_child(_lbl("수로: 드래그해서 여러 칸을 한 번에(전부 설치 또는 전부 취소) · 길: 연속 설치", 14))
	hv.add_child(_lbl("건물 클릭 → 오른쪽 패널에서 주민 배정 / 이동 / 공사 취소(자원 100% 반환) / 철거(원재료 반환) · V 관개 보기", 14))
	hv.add_child(_lbl("농장은 3×3 비옥한 개간지. 우물(용량 2)·보(용량 4)의 물이 수로를 타고 상하좌우로 닿아야 자란다. 30초 농사에 식량 6.", 14))
	hv.add_child(_lbl("벌목소/채석장은 20초 주기. 주기 시작에 식량 1이 있으면 먹고 정상 생산, 없으면 절반. 주택 완공 시 주민 2명 귀환(최대 2채).", 14))
	hv.add_child(_lbl("경로 복구 현장(군자금 40)을 완공하면 관리도 60. 훈련장/보급창은 관리도 60에서 건설·완공해야 효과가 난다.", 14))
	hv.add_child(_lbl("경제 시간은 지금 들어와 있는 이 마을에서만 흐른다. 지도·전투·다른 마을·앱을 닫은 동안에는 생산과 공사가 멈춘다.", 14, Color(1.0, 0.85, 0.6)))
	hv.add_child(_btn("닫기 (Esc)", func(): _help_open = false; _hud_dirty = true))

func _refresh_hud() -> void:
	_hud_dirty = false
	var st := campaign.state
	var v := vs()
	if v == null:
		return
	top_label.text = "%s   군자금 %d · 목재 %d · 석재 %d · 식량 %d   주민 %d/%d (빈손 %d)   관리도 %d" % [site.display_name, st.currency, st.wood, st.stone, st.food, v.villagers.size(), VillageState.MAX_VILLAGERS, v.free_villager_count(), st.management(site_id)]
	msg_label.text = message
	log_label.text = "\n".join(event_log)
	help_panel.visible = _help_open
	# 건설 목록
	for c in bottom_box.get_children():
		c.queue_free()
	bottom_bar.visible = build_list_open
	if build_list_open:
		var lead := _lbl("건설 (B)", 14, Color(1.0, 0.9, 0.65))
		lead.autowrap_mode = TextServer.AUTOWRAP_OFF
		bottom_box.add_child(lead)
		for def in data.buildings_for_site(site_id):
			var item := VBoxContainer.new()
			item.add_theme_constant_override("separation", 2)
			var icon := ColorRect.new()
			icon.color = _building_color(def) if def.kind != &"canal" else Color(0.25, 0.5, 0.85)
			icon.custom_minimum_size = Vector2(96, 14)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			item.add_child(icon)
			var enabled := true
			var note := ""
			if def.requires_management > 0 and st.management(site_id) < def.requires_management:
				enabled = false
				note = "관리도 %d" % def.requires_management
			elif def.max_per_village > 0 and v.count_of_def(def.id) >= def.max_per_village:
				enabled = false
				note = "최대 %d" % def.max_per_village
			var b := _btn("%s %d×%d" % [def.display_name, def.size.x, def.size.y], func(): begin_place(def), enabled)
			b.custom_minimum_size = Vector2(96, 30)
			if mode != "free" and place_def == def and moving_id == 0:
				b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
			item.add_child(b)
			var cost := _lbl(note if note != "" else def.cost_text(), 11, Color(0.8, 0.8, 0.75) if note == "" else Color(0.9, 0.6, 0.5))
			cost.autowrap_mode = TextServer.AUTOWRAP_OFF
			cost.custom_minimum_size = Vector2(96, 0)
			item.add_child(cost)
			bottom_box.add_child(item)
	# 선택 패널
	for c in side_box.get_children():
		c.queue_free()
	if selected_building != 0 and v.has_building(selected_building):
		side_panel.visible = true
		var b := v.building(selected_building)
		var def := sim().def_of(b)
		side_box.add_child(_lbl("%s #%d" % [def.display_name, int(b.id)], 18, Color(1.0, 0.9, 0.65)))
		side_box.add_child(_lbl(def.description, 12, Color(0.8, 0.8, 0.75)))
		if b.state == "construction":
			side_box.add_child(_lbl("공사 %.0f / %.0f (플레이어 E 초당 5, 주민 초당 1)" % [float(b.work_done), def.work_required], 13))
		else:
			var line := "완공"
			if def.kind == &"farm":
				var stage := VillageSim.growth_stage(b, def)
				line = "농사 %.0f / %.0f초 · %s · %s" % [float(b.progress), def.cycle_seconds, ["파종", "성장", "수확 직전"][stage], "물 공급됨" if sim().is_farm_watered(int(b.id)) else "물 없음"]
			elif def.is_producer():
				line = "생산 %.0f / %.0f초 · %s" % [float(b.progress), def.cycle_seconds, ["식사 없음(절반)", "정상"][maxi(int(b.fed), 0)] if int(b.fed) >= 0 else "대기"]
			elif def.water_capacity > 0:
				line = "수원 용량 %d" % def.water_capacity
			side_box.add_child(_lbl(line, 13))
		var kind := sim().job_kind_for(b)
		if kind != "":
			var worker := v.worker_of(int(b.id))
			side_box.add_child(_lbl("주민 배정 (%s) — 현재: %s" % [{"build": "공사", "farm": "농사", "lumber": "벌목", "quarry": "채석"}[kind], (String(v.villager(worker).name) if worker != 0 else "없음")], 13, Color(0.8, 0.9, 1.0)))
			var grid := GridContainer.new()
			grid.columns = 2
			for vid in v.sorted_villager_ids():
				var vl: Dictionary = v.villagers[vid]
				var status := "빈손" if vl.job_building == 0 else ("이 건물" if vl.job_building == int(b.id) else "다른 작업")
				var bid := int(b.id)
				grid.add_child(_btn("%s (%s)" % [String(vl.name), status], func(): do_assign(vid, bid), vl.job_building != bid))
			side_box.add_child(grid)
			if worker != 0:
				var wid := worker
				side_box.add_child(_btn("배정 해제", func(): do_assign(wid, 0)))
		var acts := HBoxContainer.new()
		var bid2 := int(b.id)
		if def.movable:
			acts.add_child(_btn("이동", func(): begin_move(bid2)))
		if b.state == "construction":
			acts.add_child(_btn("공사 취소 (100% 반환)", func(): do_cancel_construction(bid2)))
		elif def.demolishable:
			acts.add_child(_btn("철거 (원재료 반환)", func(): do_demolish(bid2)))
		acts.add_child(_btn("닫기", func(): select_building(0)))
		side_box.add_child(acts)
	else:
		side_panel.visible = false

func _show_pending_overlay() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.12, 0.08, 0.08, 0.97)))
	p.position = Vector2(340, 240)
	p.size = Vector2(600, 200)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_lbl("⚠ 저장 실패", 20, Color(1.0, 0.6, 0.5)))
	var reason := String(campaign.pending.result.get("reason", "")) if not campaign.pending.is_empty() else ""
	v.add_child(_lbl("마을 시간과 추가 변경을 멈췄다. %s" % reason, 14))
	v.add_child(_lbl("재시도는 같은 결과를 다시 저장한다(생산물·주민·비용을 다시 계산하지 않음).", 13, Color(0.8, 0.8, 0.75)))
	v.add_child(_btn("저장 재시도", func():
		var r := campaign.retry_pending()
		_say("저장 성공" if r.saved else "재시도 실패: %s" % r.reason)
		_after_change()))
	v.add_child(_btn("이전 저장으로 (이번 변경 미반영)", func():
		campaign.discard_pending()
		_say("이전 저장으로 돌아갔다.")
		_after_change()))
	hud.add_child(p)
	_pending_overlay = p
	_hud_dirty = true
