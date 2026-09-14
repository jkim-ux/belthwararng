class_name VillageView
extends Node2D
## 마을 장면(HWR-005 → HWR-006): 16×12 논리 격자 위를 플레이어가 걷고, 마우스로 건물을 미리보기·배치·회전·이동하며,
## 정령(주민)에게 밭 정돈·공사·농사·생산을 부탁한다. 상태 변경은 모두 CampaignController 의 village_* API(후보 상태 → 검증 → 저장)로 보낸다.
## 표시는 SubViewport 안의 VillageStage3D(낮은 측면 카툰 3D)가 맡고, 이 노드는 입력·HUD·2D 라벨 오버레이만 관리한다.
## 판정(점유·문·통행·작업)은 VillageSim 의 격자 규칙을 쓴다. 전투 입력(스킬 액션)은 읽지 않는다.
##
## 조작: 방향키/WASD 이동(화면 가로 약 300px/s, 깊이 약 105px/s), E 인접 장애물 정돈 부탁 / 건물 선택 / 출입구에서 지도로,
##       B 건설 목록, 마우스 이동·좌클릭 배치, R 회전, 우클릭·Esc 취소, 수로는 드래그로 여러 칸, V 관개 보기, M 전체 보기.
## 마우스 → 칸: 루트 Viewport 위치 → 표시 TextureRect 안 위치 → SubViewport 픽셀 → Camera3D 레이 → 바닥 평면 → 칸(VillageStage3D.screen_to_cell).

signal leave_requested

const CELL := VillageTemplate.CELL_PX
const MAP_W := VillageTemplate.WIDTH * CELL
const MAP_H := VillageTemplate.HEIGHT * CELL
const TOP_BAR := 44
const BOTTOM_BAR := 96
const VIEW_W := 1280
const VIEW_H := 720
const STAGE_H := VIEW_H - TOP_BAR - BOTTOM_BAR
## 화면 기준 이동 속도(px/s): 가로 / 깊이. 논리 칸 속도로 환산해 쓴다(대각선은 정규화, 통행 판정은 논리 격자).
const SCREEN_SPEED := Vector2(300.0, 105.0)

var campaign: CampaignController
var site_id: StringName
var site: SiteDef
var template: VillageTemplate
var data: CampaignData

var sub_viewport: SubViewport
var stage: VillageStage3D
var stage_rect: TextureRect
var overlay: Control
var hud: Control
var player_pos: Vector2 = Vector2.ZERO           ## 논리 px(48px = 1칸). 3D 표시는 칸 단위로 변환한다
var player_facing: int = 1
var player_moving: bool = false
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
var selected_obstacle: String = ""                ## 선택한 장애물 ID(정돈 부탁 패널)
var _pick_last: Array = []                        ## 마지막 클릭에서 겹친 건물 목록(순환 선택)
var _pick_index: int = 0
var show_water: bool = false
var overview: bool = false                        ## 전체 마을 보기(각도 유지, 줌만)
var build_list_open: bool = true
var message: String = ""
var message_time: float = 0.0
var event_log: Array[String] = []
var _hud_dirty: bool = true
var _pending_overlay: Control = null
var _help_open: bool = false
var _side_sig: String = ""
var manual_input: bool = false                    ## 테스트: 키 입력을 읽지 않는다
var test_mode: bool = false                       ## 시작 화면의 별도 저장 테스트 마을
var input_move: Vector2 = Vector2.ZERO             ## 테스트용 이동 입력
var _last_mouse: Vector2 = Vector2(-1, -1)        ## 마지막 마우스 이벤트 위치(루트 Viewport 좌표, 창 크기 변환 반영)

# ------------------------------------------------------------------ 준비

func setup(p_campaign: CampaignController, p_site_id: StringName) -> void:
	campaign = p_campaign
	site_id = p_site_id
	data = campaign.data
	site = data.site(site_id)
	template = data.village_template(site_id)

func _ready() -> void:
	# 표시: SubViewport(3D) → TextureRect(입력 통과). 입력은 이 노드가 한 번만 해석한다(자동 전달 없음).
	sub_viewport = SubViewport.new()
	sub_viewport.name = "Stage"
	sub_viewport.size = Vector2i(VIEW_W, STAGE_H)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.handle_input_locally = false
	sub_viewport.gui_disable_input = true
	add_child(sub_viewport)
	stage = VillageStage3D.new()
	stage.name = "Stage3D"
	sub_viewport.add_child(stage)
	stage.setup(template, data)
	stage_rect = TextureRect.new()
	stage_rect.name = "StageView"
	stage_rect.texture = sub_viewport.get_texture()
	stage_rect.position = Vector2(0, TOP_BAR)
	stage_rect.size = Vector2(VIEW_W, STAGE_H)
	stage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage_rect)
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.position = Vector2(0, TOP_BAR)
	overlay.size = Vector2(VIEW_W, STAGE_H)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	player_pos = (Vector2(template.spawn) + Vector2(0.5, 0.5)) * CELL
	_build_hud()
	if not vs().stored_buildings.is_empty():
		message = "보관된 건물 %d개 — 건설 목록에서 무료 재배치" % vs().stored_buildings.size()
	_refresh_walk_grid()
	_update_camera(true)
	_sync_stage(0.0)
	_refresh_hud()

func vs() -> VillageState:
	return campaign.active_village_state()

func sim() -> VillageSim:
	return campaign.sim

func player_cell() -> Vector2i:
	return Vector2i(floori(player_pos.x / CELL), floori(player_pos.y / CELL))

func player_cell_pos() -> Vector2:
	return player_pos / CELL

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
	var events := campaign.village_tick(delta)
	if not events.is_empty():
		for ev in events:
			_log_event(ev)
		_refresh_walk_grid()
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
	_sync_stage(delta)
	overlay.queue_redraw()
	if _hud_dirty or fmod(anim_time, 0.5) < delta:
		_refresh_hud()

## 화면 속도 → 논리 칸 속도. 축마다 다르게 환산하되 입력 벡터는 먼저 정규화한다(대각선 과속 없음).
func _logic_speed() -> Vector2:
	var cpp := stage.cells_per_pixel()
	return Vector2(SCREEN_SPEED.x * cpp.x, SCREEN_SPEED.y * cpp.y) * CELL

func _handle_movement(delta: float) -> void:
	var mv := input_move if manual_input else _read_move()
	if mv.length() > 1.0:
		mv = mv.normalized()
	player_moving = mv != Vector2.ZERO
	if mv == Vector2.ZERO:
		return
	if mv.x != 0.0:
		player_facing = 1 if mv.x > 0.0 else -1
	var sp := _logic_speed()
	var step := Vector2(mv.x * sp.x, mv.y * sp.y) * delta
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
	stage.set_camera(player_cell_pos().x * VillageStage3D.CELL_W, overview, snap)

func on_entrance() -> bool:
	return template.terrain_at(player_cell()) == "e"

# ------------------------------------------------------------------ 표시 동기화

func _sync_stage(delta: float) -> void:
	var v := vs()
	var s := sim()
	if v == null or s == null:
		return
	var water: Dictionary = s.water if not s.water.is_empty() else s.compute_water(v)
	stage.sync_obstacles(v, s)
	stage.sync_buildings(v, s, water)
	stage.sync_actors(v, s, delta)
	stage.set_player(player_cell_pos(), player_facing, player_moving, delta)
	var target := s.interact_target(v) if mode == "free" else {}
	var ob_cell := VillageSim.obstacle_cell_of(selected_obstacle) if selected_obstacle != "" else Vector2i(-1, -1)
	stage.sync_selection(v, s, selected_building, ob_cell, target)
	if mode == "free":
		stage.sync_preview(null, -1, -1, 0, {}, water, mode, [])
	else:
		stage.sync_preview(place_def, hover_cell.x, hover_cell.y, place_rot, preview, water, mode, canal_cells)
	stage.sync_water_overlay(show_water, v, s, water)
	stage.set_faded(_occluders(v, s, target))
	stage.update_fx(delta)

## 가림 완화: 조작 대상(플레이어·E 대상·미리보기 칸)을 화면에서 덮는 앞쪽 건물만 옅게 한다. 전체를 항상 위에 그리지 않는다.
func _occluders(v: VillageState, s: VillageSim, target: Dictionary) -> Array:
	var points: Array = []      # [{px: Vector2, depth: float}]
	var pq := player_cell_pos()
	points.append({"px": stage.ground_to_screen(pq, 0.6), "depth": pq.y})
	if not target.is_empty():
		var tc: Vector2i = target.cell if target.kind == "obstacle" else Vector2i(-1, -1)
		if tc.x >= 0:
			points.append({"px": stage.ground_to_screen(Vector2(tc) + Vector2(0.5, 0.5), 0.4), "depth": float(tc.y) + 0.5})
	if mode != "free" and hover_cell.x >= 0:
		points.append({"px": stage.ground_to_screen(Vector2(hover_cell) + Vector2(0.5, 0.5), 0.3), "depth": float(hover_cell.y) + 0.5})
	var out := []
	for id in v.sorted_building_ids():
		var b: Dictionary = v.buildings[id]
		var def := s.def_of(b)
		if def.walkable or def.kind == &"road":
			continue
		var front := float(int(b.y) + def.footprint(int(b.rot)).y)
		var rect := stage.building_screen_rect(b, def)
		for p in points:
			if front > float(p.depth) + 0.01 and rect.has_point(p.px):
				out.append(id)
				break
	return out

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
				_hud_dirty = true
			KEY_M:
				overview = not overview
				_update_camera(true)
				_hud_dirty = true
			KEY_ESCAPE:
				if mode != "free":
					cancel_mode()
				elif _help_open:
					_help_open = false
					_hud_dirty = true
				elif selected_building != 0 or selected_obstacle != "":
					select_building(0)
			KEY_E:
				if mode == "free" and not _help_open:
					press_e()
		return
	if event is InputEventMouseMotion:
		_last_mouse = (event as InputEventMouseMotion).position
		hover_cell = _mouse_cell()
		if mode == "canal" and canal_dragging:
			_extend_canal_drag(hover_cell)
		if mode != "free":
			_update_preview()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_last_mouse = mb.position
		hover_cell = _mouse_cell()
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "free":
				cancel_mode()
			else:
				select_building(0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_press(hover_cell, _mouse_stage_px())
			else:
				_left_release(hover_cell)

## E: 출입구면 지도로, 인접 장애물이면 정돈 부탁, 인접 건물이면 선택
func press_e() -> void:
	if on_entrance():
		request_leave()
		return
	var tgt := sim().interact_target(vs())
	if tgt.is_empty():
		select_building(0)
		return
	if tgt.kind == "obstacle":
		do_request_clear(String(tgt.id))
	else:
		select_building(int(tgt.id))

## 루트 Viewport 마우스 위치(이벤트 position: 창 크기 변환이 반영된 1280×720 좌표) → 표시 영역(SubViewport) 픽셀. 영역 밖이면 (-1,-1).
func _mouse_stage_px() -> Vector2:
	var m := _last_mouse if _last_mouse.x >= 0.0 else get_viewport().get_mouse_position()
	var p := m - stage_rect.position
	if p.x < 0.0 or p.y < 0.0 or p.x > stage_rect.size.x or p.y > stage_rect.size.y:
		return Vector2(-1, -1)
	return p

func _mouse_cell() -> Vector2i:
	var px := _mouse_stage_px()
	if px.x < 0.0:
		return Vector2i(-1, -1)
	return stage.screen_to_cell(px)

## 표시 픽셀 → 칸(테스트·재현용 공개 함수)
func stage_px_to_cell(px: Vector2) -> Vector2i:
	return stage.screen_to_cell(px)

## 칸 가운데 → 루트 Viewport 픽셀(테스트·재현용). 표시 영역 오프셋을 더한다.
func cell_to_root_px(c: Vector2i) -> Vector2:
	return stage.ground_to_screen(Vector2(c) + Vector2(0.5, 0.5)) + stage_rect.position

func _left_press(cell: Vector2i, px: Vector2 = Vector2(-1, -1)) -> void:
	match mode:
		"place":
			if cell.x >= 0:
				confirm_place(cell)
			else:
				_say("설치 불가: 마을 밖")
		"move":
			if cell.x >= 0:
				confirm_move(cell)
		"canal":
			if cell.x >= 0:
				canal_dragging = true
				canal_cells = [cell]
				_update_preview()
		"free":
			_select_at(cell, px)

func _left_release(cell: Vector2i) -> void:
	if mode == "canal" and canal_dragging:
		if cell.x >= 0:
			_extend_canal_drag(cell)
		canal_dragging = false
		confirm_canals()

func _extend_canal_drag(cell: Vector2i) -> void:
	if cell.x < 0:
		return
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

## 자유 모드 클릭: 보이는 건물 메시(화면 영역)로 ID 를 찾고, 겹치면 같은 자리를 다시 눌러 뒤쪽 건물로 순환한다.
## 건물이 없으면 바닥 칸의 장애물을 선택한다.
func _select_at(cell: Vector2i, px: Vector2) -> void:
	var hits: Array = stage.pick_buildings(px, vs(), sim()) if px.x >= 0.0 else []
	if hits.is_empty() and cell.x >= 0:
		var occ := sim().occupancy(vs())
		if occ.has(cell):
			hits = [int(occ[cell])]
	if not hits.is_empty():
		if hits == _pick_last and hits.size() > 1:
			_pick_index = (_pick_index + 1) % hits.size()
		else:
			_pick_index = 0
		_pick_last = hits
		select_building(int(hits[_pick_index]))
		if hits.size() > 1:
			_say("겹친 건물 %d개 — 같은 자리를 다시 누르면 뒤쪽 선택" % hits.size())
		return
	_pick_last = []
	if cell.x >= 0 and sim().has_obstacle(vs(), cell):
		select_obstacle(VillageTemplate.obstacle_id(cell))
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
	selected_obstacle = ""
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
	_hud_dirty = true

func select_building(id: int) -> void:
	selected_building = id if (id != 0 and vs().has_building(id)) else 0
	selected_obstacle = ""
	_hud_dirty = true

func select_obstacle(oid: String) -> void:
	var c := VillageSim.obstacle_cell_of(oid)
	selected_obstacle = oid if (c.x >= 0 and sim().has_obstacle(vs(), c)) else ""
	selected_building = 0
	_hud_dirty = true

func _update_preview() -> void:
	if sim() == null:
		return
	match mode:
		"place":
			preview = campaign.village_can_place(place_def, hover_cell.x, hover_cell.y, place_rot) if hover_cell.x >= 0 else {"ok": false, "reason": "마을 밖", "cells": [], "door": Vector2i(-1, -1)}
		"move":
			preview = campaign.village_can_place(place_def, hover_cell.x, hover_cell.y, place_rot, moving_id) if hover_cell.x >= 0 else {"ok": false, "reason": "마을 밖", "cells": [], "door": Vector2i(-1, -1)}
		"canal":
			var cells: Array = canal_cells if not canal_cells.is_empty() else ([hover_cell] if hover_cell.x >= 0 else [])
			preview = campaign.village_can_place_canals(cells) if not cells.is_empty() else {"ok": false, "reason": "마을 밖", "cells": [], "cost_wood": 0}
		_:
			preview = {}

func confirm_place(cell: Vector2i) -> void:
	var restoring := vs().stored_id_for(place_def.id) != 0
	var r := campaign.village_place(place_def.id, cell.x, cell.y, place_rot)
	if r.ok and r.saved:
		_say("%s 무료 재배치 — 이전 진행 유지" % place_def.display_name if restoring else "%s 설치 (%s) — 정령에게 공사를 부탁하자" % [place_def.display_name, place_def.cost_text()])
		_after_change()
		if place_def.kind != &"road":
			cancel_mode()
			select_building(int(r.id))
		else:
			_update_preview()
	elif r.ok:
		_say("설치 저장 실패: %s" % r.reason)
	else:
		_say("설치 불가: %s" % r.reason)

func confirm_canals() -> void:
	if canal_cells.is_empty():
		return
	var paid := maxi(0, canal_cells.size() - vs().stored_count(&"canal"))
	var r := campaign.village_place_canals(canal_cells)
	if r.ok and r.saved:
		_say("수로 %d칸 설치 (목재 %d)" % [r.ids.size(), paid])
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

## 밭 정돈 부탁: 빈손 정령 1명이 걸어가 바람으로 치운다. 한 번 부탁하면 계속 진행된다.
func do_request_clear(oid: String) -> void:
	var r := campaign.village_request_clear(oid)
	if r.ok and r.saved:
		var name := String(vs().villager(int(r.villager)).name)
		var c := VillageSim.obstacle_cell_of(oid)
		_say("%s 에게 %s 정돈 부탁" % [name, VillageTemplate.obstacle_name(template.obstacle_at(c))])
		select_obstacle(oid)
	elif r.ok:
		_say("부탁 저장 실패: %s" % r.reason)
	else:
		_say("부탁 불가: %s" % r.reason)
	_after_change()

func do_cancel_clear(oid: String) -> void:
	var r := campaign.village_cancel_clear(oid)
	_say("정돈 부탁 취소 (진행량은 남음)" if r.ok and r.saved else "취소 불가: %s" % r.reason)
	_after_change()

func request_leave() -> void:
	if mode != "free":
		cancel_mode()
	stage.clear_all()
	leave_requested.emit()

func _after_change() -> void:
	_refresh_walk_grid()
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
			line = "%s 정돈%s" % [VillageTemplate.obstacle_name(String(ev.obstacle)), r]
			if selected_obstacle == String(ev.id):
				selected_obstacle = ""
		"construction_complete":
			var def := data.building(StringName(String(ev.def_id)))
			line = "%s 완공" % (def.display_name if def else String(ev.def_id))
			if int(ev.villagers) > 0:
				line += " — 정령 %d명 합류" % int(ev.villagers)
			if def != null and def.management_on_complete > 0:
				line += " — 관리도 %d" % def.management_on_complete
			if def != null and def.facility_id != &"":
				line += " — 효과 적용(1회)"
		"harvest":
			line = "수확 식량 +%d" % int(ev.food)
			var b := vs().building(int(ev.id))
			if not b.is_empty():
				stage.play_harvest(b, sim().def_of(b), int(ev.get("villager", 0)))
		"production":
			var what := "목재" if String(ev.resource) == "wood" else ("석재" if String(ev.resource) == "stone" else "식량")
			line = "%s +%d%s" % [what, int(ev.amount), "" if int(ev.fed) == 1 else " (식사 없음, 절반)"]
	if line != "":
		event_log.append(line)
		if event_log.size() > 6:
			event_log.pop_front()
		_say(line)

# ------------------------------------------------------------------ 2D 오버레이(이름·안내·진행)

func _label_box(pos: Vector2, text: String, size: int, col: Color, bg: Color = Color(0, 0, 0, 0.55)) -> void:
	var w := text.length() * (size * 0.72) + 14
	overlay.draw_rect(Rect2(pos, Vector2(w, size + 8)), bg)
	overlay.draw_string(UiFont.FONT, pos + Vector2(7, size + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_overlay() -> void:
	var v := vs()
	var s := sim()
	if v == null or s == null:
		return
	var water: Dictionary = s.water if not s.water.is_empty() else s.compute_water(v)
	# 정령 이름·작업
	for vid in v.sorted_villager_ids():
		if not s.actors.has(vid):
			continue
		var a: Dictionary = s.actors[vid]
		var vl: Dictionary = v.villagers[vid]
		var st := s.work_status(v, vid)
		var job := ""
		match String(vl.job_kind):
			"build": job = "공사"
			"farm": job = "농사"
			"lumber": job = "벌목"
			"quarry": job = "채석"
			"clear": job = "정돈"
		var label := String(vl.name)
		if job != "":
			label += " · " + job
			match String(st.state):
				"move": label += " (이동)"
				"blocked": label += " (길 막힘)"
				"rest": label += " (%s)" % String(st.reason)
		var p := stage.ground_to_screen(a.pos, 1.15)
		_label_box(p + Vector2(-label.length() * 4.0 - 7, -12), label, 11, Color(1, 1, 1), Color(0, 0, 0, 0.45))
	# 정돈 진행(부탁한 장애물 위)
	for oid in v.clearing.keys():
		var c := VillageSim.obstacle_cell_of(String(oid))
		if c.x < 0 or not s.has_obstacle(v, c):
			continue
		var need := VillageTemplate.obstacle_work(template.obstacle_at(c))
		var frac := clampf(float(v.clearing[oid]) / maxf(need, 0.01), 0.0, 1.0)
		var p := stage.ground_to_screen(Vector2(c) + Vector2(0.5, 0.5), 1.3)
		overlay.draw_rect(Rect2(p + Vector2(-20, -4), Vector2(40, 6)), Color(0, 0, 0, 0.55))
		overlay.draw_rect(Rect2(p + Vector2(-20, -4), Vector2(40 * frac, 6)), Color(1.0, 0.85, 0.3))
	# 건물 라벨: 공사 진행 / 농장 물 상태 / 식사 없음
	for id in v.sorted_building_ids():
		var b: Dictionary = v.buildings[id]
		var def := s.def_of(b)
		var fp := def.footprint(int(b.rot))
		var top := stage.ground_to_screen(Vector2(float(b.x) + fp.x / 2.0, float(b.y) + 0.2), stage.kind_height(def) + 0.15)
		if b.state == "construction":
			var frac := clampf(float(b.work_done) / maxf(def.work_required, 0.001), 0.0, 1.0)
			var worker := v.worker_of(id)
			var txt := "%s 바람으로 짓는 중 %d%%" % [def.display_name, int(frac * 100)] if worker != 0 else "%s 공사 대기 — 정령에게 부탁" % def.display_name
			_label_box(top + Vector2(-txt.length() * 4.5 - 7, -20), txt, 12, Color(1, 0.95, 0.75))
		elif def.kind == &"farm":
			var finfo: Dictionary = water.get("farms", {}).get(id, {})
			if not bool(finfo.get("watered", false)):
				var reason := "용수 부족" if not (finfo.get("touching", []) as Array).is_empty() else "물 공급 필요"
				_label_box(top + Vector2(-reason.length() * 4.5 - 7, -20), reason, 12, Color(1.0, 0.8, 0.7))
		elif def.is_producer() and int(b.fed) == 0:
			_label_box(top + Vector2(-30, -20), "식사 없음", 11, Color(1.0, 0.75, 0.65))
	# 관개 보기: 공급 수치
	if show_water:
		var comps: Array = water.get("components", [])
		for comp in comps:
			if comp.sources.is_empty() or not v.has_building(comp.sources[0]):
				continue
			var sb: Dictionary = v.buildings[comp.sources[0]]
			var p := stage.ground_to_screen(Vector2(float(sb.x), float(sb.y)), 1.6)
			_label_box(p, "공급 %d/%d" % [int(comp.used), int(comp.capacity)], 12, Color(0.8, 0.95, 1.0))
	# 미리보기 문구
	if mode != "free" and not preview.is_empty():
		var cells: Array = preview.get("cells", [])
		var ok: bool = preview.get("ok", false)
		var line := Color(0.5, 1.0, 0.6) if ok else Color(1.0, 0.5, 0.5)
		var text := ("✓ " + ("설치" if mode != "move" else "이동")) if ok else ("× " + String(preview.reason))
		if mode == "canal":
			text += "  수로 %d칸 · 목재 %d" % [cells.size(), int(preview.get("cost_wood", 0))]
		elif place_def != null and mode == "place":
			text += "  " + place_def.display_name + " · " + place_def.cost_text() + (" · R 회전" if place_def.rotatable else "")
			if place_def.needs_water:
				text += " · 물 공급 필요"
		var anchor: Vector2 = Vector2(cells[0]) if not cells.is_empty() else Vector2(hover_cell)
		if anchor.x >= 0:
			var p := stage.ground_to_screen(anchor + Vector2(0.5, 0.0), 1.2)
			_label_box(p + Vector2(-10, -24), text, 13, line, Color(0, 0, 0, 0.7))
		var door: Vector2i = preview.get("door", Vector2i(-1, -1))
		if mode != "canal" and place_def != null and place_def.needs_door and door.x >= 0:
			var dp := stage.ground_to_screen(Vector2(door) + Vector2(0.5, 0.5), 0.1)
			overlay.draw_string(UiFont.FONT, dp + Vector2(-6, 4), "문", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.8))
	# E 안내(플레이어 발치)
	if mode == "free":
		var hint := ""
		if on_entrance():
			hint = "E: 테스트 종료" if test_mode else "E: 지도로 나가기"
		else:
			var tgt := s.interact_target(v)
			if not tgt.is_empty():
				if tgt.kind == "obstacle":
					var ch := template.obstacle_at(tgt.cell)
					var reward := VillageTemplate.obstacle_reward(ch)
					var rt := ""
					if int(reward.wood) > 0:
						rt = " (목재 +%d)" % int(reward.wood)
					elif int(reward.stone) > 0:
						rt = " (석재 +%d)" % int(reward.stone)
					var worker := v.worker_of_obstacle(String(tgt.id))
					hint = ("정돈 중: %s" % String(v.villager(worker).name)) if worker != 0 else "E: 정령에게 %s 정돈 부탁 (%.0f초%s)" % [VillageTemplate.obstacle_name(ch), VillageTemplate.obstacle_work(ch), rt]
				else:
					var tb := v.building(int(tgt.id))
					hint = "E: %s 선택" % s.def_of(tb).display_name
		if hint != "":
			var pp := stage.ground_to_screen(player_cell_pos(), 0.0)
			_label_box(pp + Vector2(-hint.length() * 4.5 - 7, 10), hint, 12, Color(1, 1, 0.9))

# ------------------------------------------------------------------ HUD

var top_bar: PanelContainer
var top_label: Label
var msg_label: Label
var bottom_bar: PanelContainer
var bottom_box: HBoxContainer
var build_buttons: Dictionary = {}     ## def id -> {button, cost}
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
	# VillageView is a Node2D, so the parent Control theme does not propagate here.
	l.add_theme_font_override("font", UiFont.FONT)
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _btn(text: String, on_pressed: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.add_theme_font_override("font", UiFont.FONT)
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
	top_label = _lbl("", 15, Color(1.0, 0.92, 0.6))
	top_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(top_label)
	msg_label = _lbl("", 14, Color(0.8, 0.95, 0.8))
	msg_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	msg_label.clip_text = true
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(msg_label)
	th.add_child(_btn("관개 보기 (V)", func(): show_water = not show_water; _hud_dirty = true))
	th.add_child(_btn("전체 보기 (M)", func(): overview = not overview; _update_camera(true); _hud_dirty = true))
	th.add_child(_btn("도움말", func(): _help_open = not _help_open; _hud_dirty = true))
	th.add_child(_btn("테스트 종료" if test_mode else "지도로", request_leave))
	bottom_bar = PanelContainer.new()
	bottom_bar.add_theme_stylebox_override("panel", _style(Color(0.09, 0.08, 0.11, 0.92)))
	bottom_bar.position = Vector2(0, VIEW_H - BOTTOM_BAR)
	bottom_bar.size = Vector2(VIEW_W, BOTTOM_BAR)
	hud.add_child(bottom_bar)
	bottom_box = HBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 6)
	bottom_bar.add_child(bottom_box)
	# 건설 목록 버튼은 한 번만 만들고(HWR-005 R1: 누르는 도중 교체되지 않도록) 표시 값만 갱신한다
	var lead := _lbl("건설 (B)", 14, Color(1.0, 0.9, 0.65))
	lead.autowrap_mode = TextServer.AUTOWRAP_OFF
	bottom_box.add_child(lead)
	for def in data.buildings_for_site(site_id):
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		var icon := ColorRect.new()
		icon.color = _building_color(def)
		icon.custom_minimum_size = Vector2(96, 14)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon)
		var d := def
		var b := _btn("%s %d×%d" % [def.display_name, def.size.x, def.size.y], func(): begin_place(d))
		b.name = "Build_%s" % String(def.id)
		b.custom_minimum_size = Vector2(96, 30)
		item.add_child(b)
		var cost := _lbl(def.cost_text(), 11, Color(0.8, 0.8, 0.75))
		cost.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost.custom_minimum_size = Vector2(96, 0)
		item.add_child(cost)
		bottom_box.add_child(item)
		build_buttons[String(def.id)] = {"button": b, "cost": cost, "def": def}
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
	hv.add_child(_lbl("바람 정령 마을 조작", 20, Color(1.0, 0.9, 0.65)))
	hv.add_child(_lbl("방향키/WASD 이동 · E 건물 옆에서 선택 · 출입구에서 E로 나가기. 빈 땅은 치우지 않고 바로 건설할 수 있다.", 14))
	hv.add_child(_lbl("B 건설 목록 · 목록에서 건물 선택 → 마우스로 반투명 미리보기(바닥 기준) → 좌클릭 확정 · R 회전 · 우클릭/Esc 취소 · 겹친 건물은 같은 자리를 다시 눌러 뒤쪽 선택", 14))
	hv.add_child(_lbl("수로: 드래그해서 여러 칸을 한 번에(전부 설치 또는 전부 취소) · 길: 연속 설치", 14))
	hv.add_child(_lbl("설치한 건물은 정령을 배정해야 공사(초당 5)·농사·생산이 진행된다. 플레이어가 직접 짓지 않는다. 건물 클릭 → 오른쪽 패널에서 배정·이동·취소·철거", 14))
	hv.add_child(_lbl("농장은 빈 땅 어디든 3×3. 우물(용량 2)·보(용량 4)의 물이 수로를 타고 상하좌우로 닿아야 자란다. 30초 농사에 식량 6. V 관개 보기 · M 전체 보기", 14))
	hv.add_child(_lbl("벌목소/채석장은 20초 주기. 주기 시작에 식량 1이 있으면 먹고 정상 생산, 없으면 절반. 주택 완공 시 정령 2명 합류(최대 2채).", 14))
	hv.add_child(_lbl("경로 복구 현장(군자금 40)을 완공하면 관리도 60. 훈련장/보급창은 관리도 60에서 건설·완공해야 효과가 난다.", 14))
	hv.add_child(_lbl("경제 시간은 지금 들어와 있는 이 마을에서만 흐른다. 지도·전투·다른 마을·앱을 닫은 동안에는 생산과 공사가 멈춘다.", 14, Color(1.0, 0.85, 0.6)))
	hv.add_child(_btn("닫기 (Esc)", func(): _help_open = false; _hud_dirty = true))

func _building_color(def: BuildingDef) -> Color:
	match def.kind:
		&"farm": return Color(0.5, 0.36, 0.2)
		&"well": return Color(0.6, 0.6, 0.65)
		&"canal": return Color(0.25, 0.5, 0.85)
		&"dam": return Color(0.35, 0.38, 0.45)
		&"lumber": return Color(0.55, 0.38, 0.2)
		&"quarry": return Color(0.55, 0.52, 0.5)
		&"house": return Color(0.7, 0.5, 0.35)
		&"repair": return Color(0.62, 0.55, 0.42)
		&"facility": return Color(0.55, 0.3, 0.3)
	return Color(0.6, 0.6, 0.6)

func _refresh_hud() -> void:
	_hud_dirty = false
	var st := campaign.state
	var v := vs()
	if v == null:
		return
	top_label.text = "%s   군자금 %d · 목재 %d · 석재 %d · 식량 %d   정령 %d/%d (빈손 %d)   관리도 %d" % ["테스트" if test_mode else site.display_name, st.currency, st.wood, st.stone, st.food, v.villagers.size(), VillageState.MAX_VILLAGERS, v.free_villager_count(), st.management(site_id)]
	msg_label.text = message
	log_label.text = "\n".join(event_log)
	help_panel.visible = _help_open
	# 건설 목록: 버튼 인스턴스는 유지하고 활성·문구·강조만 갱신
	bottom_bar.visible = build_list_open
	for key in build_buttons.keys():
		var e: Dictionary = build_buttons[key]
		var def: BuildingDef = e.def
		var enabled := true
		var note := ""
		if def.requires_management > 0 and st.management(site_id) < def.requires_management:
			enabled = false
			note = "관리도 %d" % def.requires_management
		elif def.max_per_village > 0 and v.count_of_def(def.id) >= def.max_per_village:
			enabled = false
			note = "최대 %d" % def.max_per_village
		var stored := v.stored_count(def.id)
		if stored > 0:
			enabled = true
			note = "보관 %d · 무료 재배치" % stored
		var b: Button = e.button
		if b.disabled == enabled:
			b.disabled = not enabled
		var active: bool = mode != "free" and place_def == def and moving_id == 0
		b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4) if active else Color(0.95, 0.93, 0.88))
		var cost: Label = e.cost
		var cost_text := note if note != "" else def.cost_text()
		if cost.text != cost_text:
			cost.text = cost_text
			cost.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75) if note == "" else Color(0.9, 0.6, 0.5))
	_refresh_side_panel(v)

## 선택 패널: 내용 구조가 바뀔 때만 다시 만들고, 진행 수치만 바뀌면 라벨 글자만 갱신한다(버튼 누름 도중 교체 방지).
func _refresh_side_panel(v: VillageState) -> void:
	var sig := ""
	if selected_building != 0 and v.has_building(selected_building):
		var b := v.building(selected_building)
		var vl_sig := ""
		for vid in v.sorted_villager_ids():
			vl_sig += "%d:%d:%s," % [vid, int(v.villagers[vid].job_building), String(v.villagers[vid].job_kind)]
		sig = "b|%d|%s|%s|%d" % [selected_building, b.state, vl_sig, int(b.fed)]
	elif selected_obstacle != "":
		var c := VillageSim.obstacle_cell_of(selected_obstacle)
		if c.x >= 0 and sim().has_obstacle(v, c):
			sig = "o|%s|%d|%d" % [selected_obstacle, v.worker_of_obstacle(selected_obstacle), v.free_villager_count()]
		else:
			selected_obstacle = ""
	if sig == _side_sig:
		_update_side_values(v)
		return
	_side_sig = sig
	for c in side_box.get_children():
		side_box.remove_child(c)
		c.queue_free()
	side_panel.visible = sig != ""
	if sig == "":
		return
	if selected_building != 0:
		var b := v.building(selected_building)
		var def := sim().def_of(b)
		side_box.add_child(_lbl("%s #%d" % [def.display_name, int(b.id)], 18, Color(1.0, 0.9, 0.65)))
		side_box.add_child(_lbl(def.description, 12, Color(0.8, 0.8, 0.75)))
		var status := _lbl("", 13)
		status.name = "Status"
		side_box.add_child(status)
		var kind := sim().job_kind_for(b)
		if kind != "":
			var worker := v.worker_of(int(b.id))
			side_box.add_child(_lbl("정령 배정 (%s) — 현재: %s" % [{"build": "공사", "farm": "농사", "lumber": "벌목", "quarry": "채석"}[kind], (String(v.villager(worker).name) if worker != 0 else "없음")], 13, Color(0.8, 0.9, 1.0)))
			var grid := GridContainer.new()
			grid.columns = 2
			for vid in v.sorted_villager_ids():
				var vl: Dictionary = v.villagers[vid]
				var status_t := "빈손" if VillageState.is_idle(vl) else ("이 건물" if vl.job_building == int(b.id) else ("정돈 중" if vl.job_kind == "clear" else "다른 작업"))
				var bid := int(b.id)
				grid.add_child(_btn("%s (%s)" % [String(vl.name), status_t], func(): do_assign(vid, bid), vl.job_building != bid))
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
		var c := VillageSim.obstacle_cell_of(selected_obstacle)
		var ch := template.obstacle_at(c)
		var reward := VillageTemplate.obstacle_reward(ch)
		side_box.add_child(_lbl("밭 정돈 — %s (%d,%d)" % [VillageTemplate.obstacle_name(ch), c.x, c.y], 18, Color(1.0, 0.9, 0.65)))
		var rt := "보상 없음"
		if int(reward.wood) > 0:
			rt = "목재 +%d" % int(reward.wood)
		elif int(reward.stone) > 0:
			rt = "석재 +%d" % int(reward.stone)
		side_box.add_child(_lbl("정령이 걸어가 바람으로 치운다. 작업 %.0f초 · %s" % [VillageTemplate.obstacle_work(ch), rt], 12, Color(0.8, 0.8, 0.75)))
		var status := _lbl("", 13)
		status.name = "Status"
		side_box.add_child(status)
		var worker := v.worker_of_obstacle(selected_obstacle)
		var oid := selected_obstacle
		var acts := HBoxContainer.new()
		if worker == 0:
			var idle := v.free_villager_count()
			acts.add_child(_btn("정령에게 부탁 (빈손 %d)" % idle, func(): do_request_clear(oid), idle > 0))
			if idle == 0:
				side_box.add_child(_lbl("빈손 정령이 없다. 건물 패널에서 배정을 해제하거나 다른 부탁을 취소하면 된다.", 12, Color(1.0, 0.8, 0.7)))
		else:
			acts.add_child(_btn("부탁 취소", func(): do_cancel_clear(oid)))
		acts.add_child(_btn("닫기", func(): select_building(0)))
		side_box.add_child(acts)
	_update_side_values(v)

func _update_side_values(v: VillageState) -> void:
	var status: Label = side_box.get_node_or_null("Status")
	if status == null:
		return
	if selected_building != 0 and v.has_building(selected_building):
		var b := v.building(selected_building)
		var def := sim().def_of(b)
		if b.state == "construction":
			status.text = "공사 %.0f / %.0f (정령 초당 5)" % [float(b.work_done), def.work_required]
		else:
			var line := "완공"
			if def.kind == &"farm":
				var stage_i := VillageSim.growth_stage(b, def)
				line = "농사 %.0f / %.0f초 · %s · %s" % [float(b.progress), def.cycle_seconds, ["파종", "성장", "수확 직전"][stage_i], "물 공급됨" if sim().is_farm_watered(int(b.id)) else "물 없음"]
			elif def.is_producer():
				line = "생산 %.0f / %.0f초 · %s" % [float(b.progress), def.cycle_seconds, ["식사 없음(절반)", "정상"][maxi(int(b.fed), 0)] if int(b.fed) >= 0 else "대기"]
			elif def.water_capacity > 0:
				line = "수원 용량 %d" % def.water_capacity
			status.text = line
	elif selected_obstacle != "":
		var c := VillageSim.obstacle_cell_of(selected_obstacle)
		var need := VillageTemplate.obstacle_work(template.obstacle_at(c))
		var worker := v.worker_of_obstacle(selected_obstacle)
		var prog := float(v.clearing.get(selected_obstacle, 0.0))
		if worker != 0:
			var ws := sim().work_status(v, worker)
			var wtxt: String = {"move": "걸어가는 중", "work": "바람으로 정돈 중", "blocked": "길 막힘", "idle": "대기", "rest": "대기"}.get(String(ws.state), "")
			status.text = "%s · %s · 진행 %.1f / %.0f초" % [String(v.villager(worker).name), wtxt, prog, need]
		else:
			status.text = "부탁 없음 · 진행 %.1f / %.0f초" % [prog, need]

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
