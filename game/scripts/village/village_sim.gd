class_name VillageSim
extends RefCounted
## 정착지 모형: 격자 점유·통행·배치 검증·물 연결망·주민 이동/작업·공사/생산 진행을 계산한다.
## 영구 상태(VillageState/CampaignState)는 인자로 받아 후보 상태에 적용하고, 주민 위치·경로·도착 같은
## 실행 중 값만 이 객체가 갖는다(저장하지 않음). 화면(VillageView)은 이 객체를 그리고 입력을 전달한다.
## 경제 시간은 10Hz 고정 틱(TICK)으로만 진행하며 프레임률과 무관하다.

const TICK := 0.1
const PLAYER_BUILD_RATE := 5.0      ## 플레이어 E 공사 작업량/초
const VILLAGER_BUILD_RATE := 1.0    ## 배정 주민 공사 작업량/초
const VILLAGER_SPEED := 3.0         ## 칸/초
const PATH_RETRY_SECONDS := 1.0
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var data: CampaignData
var template: VillageTemplate
var site_id: StringName

## 실행 중 주민: id -> {pos: Vector2(칸 단위, 중심 = 칸 + 0.5), path: Array, target: Vector2i, arrived: bool, retry: float}
var actors: Dictionary = {}
var player_cell: Vector2i = Vector2i(-1, -1)
## 이번 틱의 플레이어 E 작업 대상: {} 또는 {"kind": "obstacle", "id": String} / {"kind": "building", "id": int}
var player_work: Dictionary = {}
var water: Dictionary = {}           ## 마지막 틱의 물 연결망 계산 결과
var elapsed: float = 0.0             ## 이 마을에서 진행한 경제 시간(초)

func _init(p_data: CampaignData, p_site_id: StringName) -> void:
	data = p_data
	site_id = p_site_id
	template = data.village_template(site_id)

# ------------------------------------------------------------------ 격자

func def_of(b: Dictionary) -> BuildingDef:
	return data.building(StringName(String(b.def_id)))

static func footprint_cells(def: BuildingDef, x: int, y: int, rot: int) -> Array[Vector2i]:
	var fp := def.footprint(rot)
	var out: Array[Vector2i] = []
	for dy in fp.y:
		for dx in fp.x:
			out.append(Vector2i(x + dx, y + dy))
	return out

func cells_of(b: Dictionary) -> Array[Vector2i]:
	return footprint_cells(def_of(b), int(b.x), int(b.y), int(b.rot))

## 문(작업 위치) 칸: 회전 0 남쪽 가운데, 1 서쪽, 2 북쪽, 3 동쪽. 문이 없는 건물(농장·수로·길)은 점유 가운데 칸.
static func door_cell(def: BuildingDef, x: int, y: int, rot: int) -> Vector2i:
	var fp := def.footprint(rot)
	if not def.needs_door:
		return Vector2i(x + fp.x / 2, y + fp.y / 2)
	match posmod(rot, 4):
		0: return Vector2i(x + fp.x / 2, y + fp.y)
		1: return Vector2i(x - 1, y + fp.y / 2)
		2: return Vector2i(x + fp.x / 2, y - 1)
	return Vector2i(x + fp.x, y + fp.y / 2)

func work_cell(b: Dictionary) -> Vector2i:
	return door_cell(def_of(b), int(b.x), int(b.y), int(b.rot))

## 칸 -> 건물 id
func occupancy(vs: VillageState, ignore_id: int = 0) -> Dictionary:
	var occ := {}
	for id in vs.buildings.keys():
		if id == ignore_id:
			continue
		for c in cells_of(vs.buildings[id]):
			occ[c] = id
	return occ

func has_obstacle(vs: VillageState, c: Vector2i) -> bool:
	return template.obstacle_at(c) != "." and not vs.is_cleared(VillageTemplate.obstacle_id(c))

## 통행 격자: 1 = 막힘. extra 는 추가로 막을 칸(미리보기), ignore_id 는 무시할 건물(이동 중)
func blocked_grid(vs: VillageState, extra_block: Array[Vector2i] = [], ignore_id: int = 0) -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(VillageTemplate.WIDTH * VillageTemplate.HEIGHT)
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			g[y * VillageTemplate.WIDTH + x] = 0 if (template.is_terrain_walkable(c) and not has_obstacle(vs, c)) else 1
	for id in vs.buildings.keys():
		if id == ignore_id:
			continue
		var b: Dictionary = vs.buildings[id]
		if def_of(b).walkable:
			continue
		for c in cells_of(b):
			g[c.y * VillageTemplate.WIDTH + c.x] = 1
	for c in extra_block:
		if template.in_bounds(c):
			g[c.y * VillageTemplate.WIDTH + c.x] = 1
	return g

static func grid_blocked(g: PackedByteArray, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= VillageTemplate.WIDTH or c.y >= VillageTemplate.HEIGHT:
		return true
	return g[c.y * VillageTemplate.WIDTH + c.x] != 0

func is_walkable(vs: VillageState, c: Vector2i) -> bool:
	return not grid_blocked(blocked_grid(vs), c)

## 너비 우선 탐색. 도달 가능한 칸 -> 이전 칸. 고리에서도 한 번씩만 방문한다.
static func flood(g: PackedByteArray, from: Vector2i) -> Dictionary:
	var prev := {}
	if grid_blocked(g, from):
		return prev
	prev[from] = from
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in DIRS:
			var n := c + d
			if prev.has(n) or grid_blocked(g, n):
				continue
			prev[n] = c
			queue.append(n)
	return prev

static func path_from_flood(prev: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not prev.has(to):
		return out
	var c := to
	while c != from:
		out.push_front(c)
		c = prev[c]
	return out

func find_path(g: PackedByteArray, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return []
	return path_from_flood(flood(g, from), from, to)

func entrance_cell() -> Vector2i:
	var e := template.entrance_cells()
	return e[0] if not e.is_empty() else template.spawn

func actor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if player_cell.x >= 0:
		out.append(player_cell)
	for a in actors.values():
		out.append(actor_cell(a))
	return out

static func actor_cell(a: Dictionary) -> Vector2i:
	var p: Vector2 = a.pos
	return Vector2i(floori(p.x), floori(p.y))

func adjacent_to_terrain(cells: Array[Vector2i], ch: String) -> bool:
	for c in cells:
		for d in DIRS:
			if template.terrain_at(c + d) == ch:
				return true
	return false

# ------------------------------------------------------------------ 배치 검증

static func _terrain_reason(t: String) -> String:
	match t:
		"~": return "강 위"
		"#": return "절벽"
		"W": return "숲 작업 구역"
		"Q": return "암반 작업 구역"
		"e": return "출입구 예약 칸"
		"p": return "통행로 예약 칸"
		"d": return "보 부지"
		"x": return "복구 현장 자리"
	return "설치 불가 지형"

func resource_shortage(cs: CampaignState, def: BuildingDef, count: int = 1) -> String:
	var parts: Array[String] = []
	if cs.currency < def.cost_currency * count:
		parts.append("군자금 %d 부족" % (def.cost_currency * count - cs.currency))
	if cs.wood < def.cost_wood * count:
		parts.append("목재 %d 부족" % (def.cost_wood * count - cs.wood))
	if cs.stone < def.cost_stone * count:
		parts.append("석재 %d 부족" % (def.cost_stone * count - cs.stone))
	return ", ".join(parts)

## 필수 통행 목표: 기존 건물의 작업 위치, 미건설 복구 현장의 문, 보 출구, 숲/암반 작업 구역 접근, 플레이어 위치
func _required_reach_cells(vs: VillageState, ignore_id: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id in vs.buildings.keys():
		if id != ignore_id:
			out.append(work_cell(vs.buildings[id]))
	var repair_def := data.building(&"repair")
	var rr := template.repair_site()
	if repair_def != null and rr.size.x > 0 and vs.count_of_def(&"repair") == 0:
		out.append(door_cell(repair_def, rr.position.x, rr.position.y, 0))
	if template.dam_outlet.x >= 0 and vs.count_of_def(&"dam") == 0:
		out.append(template.dam_outlet)
	if player_cell.x >= 0:
		out.append(player_cell)
	return out

func _zone_reachable(reach: Dictionary, ch: String) -> bool:
	for c in reach.keys():
		for d in DIRS:
			if template.terrain_at(c + d) == ch:
				return true
	return false

## 통로 검증: 출입구에서 필수 목표까지 모두 도달 가능해야 한다. {ok, reason}
func check_paths(vs: VillageState, extra_block: Array[Vector2i], ignore_id: int, new_work: Vector2i) -> Dictionary:
	var g := blocked_grid(vs, extra_block, ignore_id)
	var reach := flood(g, entrance_cell())
	if new_work.x >= 0 and not reach.has(new_work):
		return {"ok": false, "reason": "작업 위치 통로 막힘"}
	for c in _required_reach_cells(vs, ignore_id):
		if not reach.has(c):
			return {"ok": false, "reason": "통로 막힘"}
	if not _zone_reachable(reach, "W") or not _zone_reachable(reach, "Q"):
		return {"ok": false, "reason": "숲/암반 접근 막힘"}
	return {"ok": true, "reason": ""}

## 배치 가능 여부. moving_id 가 있으면 그 건물의 이동이며 비용을 검사하지 않는다.
## {ok, reason, cells, door}
func can_place(cs: CampaignState, vs: VillageState, def: BuildingDef, x: int, y: int, rot: int, moving_id: int = 0) -> Dictionary:
	rot = posmod(rot, 4)
	var res := {"ok": false, "reason": "", "cells": [], "door": Vector2i(-1, -1)}
	if def == null:
		res.reason = "알 수 없는 건물"
		return res
	var cells := footprint_cells(def, x, y, rot)
	res.cells = cells
	res.door = door_cell(def, x, y, rot)
	if def.site_id != &"" and def.site_id != site_id:
		res.reason = "이 마을에는 지을 수 없음"
		return res
	if rot != 0 and not def.rotatable:
		res.reason = "회전 불가"
		return res
	if moving_id != 0:
		if not vs.buildings.has(moving_id) or not def.movable:
			res.reason = "이동 불가 건물"
			return res
	else:
		if def.requires_management > 0 and cs.management(site_id) < def.requires_management:
			res.reason = "관리도 %d 필요" % def.requires_management
			return res
		if def.max_per_village > 0 and vs.count_of_def(def.id) >= def.max_per_village:
			res.reason = "마을당 최대 %d" % def.max_per_village
			return res
	# 고정 부지
	if def.placement == &"dam_site" or def.placement == &"repair_site":
		var fixed := template.dam_site() if def.placement == &"dam_site" else template.repair_site()
		if Rect2i(x, y, def.footprint(rot).x, def.footprint(rot).y) != fixed:
			res.reason = "강가 보 자리에만 설치" if def.placement == &"dam_site" else "고정 복구 현장에만 설치"
			return res
	var occ := occupancy(vs, moving_id)
	var actor_set := {}
	for c in actor_cells():
		actor_set[c] = true
	for c in cells:
		if not template.in_bounds(c):
			res.reason = "마을 경계 밖"
			return res
		var t := template.terrain_at(c)
		if def.placement == &"dam_site":
			if t != "d":
				res.reason = "강가 보 자리에만 설치"
				return res
		elif def.placement == &"repair_site":
			if t != "x":
				res.reason = "고정 복구 현장에만 설치"
				return res
		elif def.placement == &"fertile":
			if t != "f":
				res.reason = "비옥한 땅 아님" if template.is_land(c) else _terrain_reason(t)
				return res
		elif not template.is_land(c):
			res.reason = _terrain_reason(t)
			return res
		if has_obstacle(vs, c):
			res.reason = "%s 제거 필요" % VillageTemplate.obstacle_name(template.obstacle_at(c))
			return res
		if occ.has(c):
			res.reason = "다른 건물과 겹침"
			return res
		if actor_set.has(c):
			res.reason = "주민/플레이어가 서 있음"
			return res
	if def.placement == &"forest_adjacent" and not adjacent_to_terrain(cells, "W"):
		res.reason = "숲 작업 구역에 접해야 함"
		return res
	if def.placement == &"rock_adjacent" and not adjacent_to_terrain(cells, "Q"):
		res.reason = "암반 작업 구역에 접해야 함"
		return res
	# 문(작업 위치)
	var door: Vector2i = res.door
	if def.needs_door:
		if not template.in_bounds(door) or not template.is_terrain_walkable(door) or has_obstacle(vs, door):
			res.reason = "작업 위치 막힘"
			return res
		if occ.has(door) and not def_of(vs.buildings[occ[door]]).walkable:
			res.reason = "작업 위치 막힘"
			return res
	# 통로
	var extra: Array[Vector2i] = []
	if not def.walkable:
		extra = cells
	var pc := check_paths(vs, extra, moving_id, door)
	if not pc.ok:
		res.reason = pc.reason
		return res
	# 비용
	if moving_id == 0:
		var short := resource_shortage(cs, def)
		if short != "":
			res.reason = short
			return res
	res.ok = true
	return res

## 수로 묶음 검증: 모든 칸이 유효하고 합계 비용이 있어야 한다. {ok, reason, cells, cost_wood}
func can_place_canals(cs: CampaignState, vs: VillageState, raw_cells: Array) -> Dictionary:
	var def := data.building(&"canal")
	var cells: Array[Vector2i] = []
	for c in raw_cells:
		var v: Vector2i = c
		if not cells.has(v):
			cells.append(v)
	var res := {"ok": false, "reason": "", "cells": cells, "cost_wood": def.cost_wood * cells.size()}
	if cells.is_empty():
		res.reason = "칸 없음"
		return res
	var occ := occupancy(vs)
	var actor_set := {}
	for c in actor_cells():
		actor_set[c] = true
	for c in cells:
		if not template.in_bounds(c):
			res.reason = "마을 경계 밖"
			return res
		if not template.is_land(c):
			res.reason = _terrain_reason(template.terrain_at(c))
			return res
		if has_obstacle(vs, c):
			res.reason = "%s 제거 필요" % VillageTemplate.obstacle_name(template.obstacle_at(c))
			return res
		if occ.has(c):
			res.reason = "다른 건물과 겹침"
			return res
		if actor_set.has(c):
			res.reason = "주민/플레이어가 서 있음"
			return res
	var short := resource_shortage(cs, def, cells.size())
	if short != "":
		res.reason = short
		return res
	res.ok = true
	return res

# ------------------------------------------------------------------ 상태 변경 (후보 상태에 적용)

func _pay(cs: CampaignState, def: BuildingDef, count: int = 1) -> void:
	cs.currency -= def.cost_currency * count
	cs.wood -= def.cost_wood * count
	cs.stone -= def.cost_stone * count

func _refund(cs: CampaignState, def: BuildingDef, count: int = 1) -> void:
	cs.currency += def.cost_currency * count
	cs.wood += def.cost_wood * count
	cs.stone += def.cost_stone * count

## 설치 확정: 검증 → 비용 차감 → 인스턴스 생성. 공사량 0 인 건물(길)은 즉시 완공. {ok, reason, id}
func place(cs: CampaignState, vs: VillageState, def: BuildingDef, x: int, y: int, rot: int) -> Dictionary:
	var chk := can_place(cs, vs, def, x, y, rot)
	if not chk.ok:
		return {"ok": false, "reason": chk.reason, "id": 0}
	_pay(cs, def)
	var id := vs.add_building(def, x, y, rot, def.work_required <= 0.0)
	invalidate_paths()
	return {"ok": true, "reason": "", "id": id}

func place_canals(cs: CampaignState, vs: VillageState, raw_cells: Array) -> Dictionary:
	var chk := can_place_canals(cs, vs, raw_cells)
	if not chk.ok:
		return {"ok": false, "reason": chk.reason, "ids": []}
	var def := data.building(&"canal")
	_pay(cs, def, chk.cells.size())
	var ids := []
	for c in chk.cells:
		ids.append(vs.add_building(def, c.x, c.y, 0, def.work_required <= 0.0))
	invalidate_paths()
	return {"ok": true, "reason": "", "ids": ids}

## 공사 취소: 투입 자원 100% 반환, 공사량 폐기
func cancel_construction(cs: CampaignState, vs: VillageState, id: int) -> Dictionary:
	if not vs.buildings.has(id):
		return {"ok": false, "reason": "없는 건물"}
	var b: Dictionary = vs.buildings[id]
	if b.state != "construction":
		return {"ok": false, "reason": "공사 중인 건물이 아님"}
	_refund(cs, def_of(b))
	vs.remove_building(id)
	invalidate_paths()
	return {"ok": true, "reason": ""}

## 철거: 완공 건물의 원재료 100% 반환, 진행 중 생산물은 지급하지 않는다.
func demolish(cs: CampaignState, vs: VillageState, id: int) -> Dictionary:
	if not vs.buildings.has(id):
		return {"ok": false, "reason": "없는 건물"}
	var b: Dictionary = vs.buildings[id]
	var def := def_of(b)
	if b.state != "complete":
		return {"ok": false, "reason": "공사 중에는 취소를 사용"}
	if not def.demolishable:
		return {"ok": false, "reason": "철거할 수 없는 건물"}
	# 철거 후 남은 통로 검증(철거는 칸을 비우므로 막히지 않는다)
	_refund(cs, def)
	vs.remove_building(id)
	invalidate_paths()
	return {"ok": true, "reason": ""}

## 이동: 무료, 상태/주민/진행/ID 유지. 확정 전 원래 점유를 없애지 않는다(검증은 ignore 로 처리).
func move_building(cs: CampaignState, vs: VillageState, id: int, x: int, y: int, rot: int) -> Dictionary:
	if not vs.buildings.has(id):
		return {"ok": false, "reason": "없는 건물"}
	var b: Dictionary = vs.buildings[id]
	var def := def_of(b)
	var chk := can_place(cs, vs, def, x, y, rot, id)
	if not chk.ok:
		return {"ok": false, "reason": chk.reason}
	b.x = x
	b.y = y
	b.rot = posmod(rot, 4)
	invalidate_paths()
	return {"ok": true, "reason": ""}

## 건물에서 가능한 주민 작업 종류("" 이면 없음)
func job_kind_for(b: Dictionary) -> String:
	if b.state == "construction":
		return "build"
	var def := def_of(b)
	match def.kind:
		&"farm": return "farm"
		&"lumber": return "lumber"
		&"quarry": return "quarry"
	return ""

## 주민 배정. building_id 0 이면 해제. 이미 일하는 주민을 옮기면 기존 배정은 해제된다.
func assign_villager(vs: VillageState, villager_id: int, building_id: int) -> Dictionary:
	if not vs.villagers.has(villager_id):
		return {"ok": false, "reason": "없는 주민"}
	if building_id == 0:
		vs.unassign(villager_id)
		_reset_actor(villager_id)
		return {"ok": true, "reason": ""}
	if not vs.buildings.has(building_id):
		return {"ok": false, "reason": "없는 건물"}
	var kind := job_kind_for(vs.buildings[building_id])
	if kind == "":
		return {"ok": false, "reason": "배정할 작업이 없는 건물"}
	var prev := vs.worker_of(building_id)
	vs.assign(villager_id, building_id, kind)
	_reset_actor(villager_id)
	if prev != 0 and prev != villager_id:
		_reset_actor(prev)
	return {"ok": true, "reason": ""}

func invalidate_paths() -> void:
	for a in actors.values():
		a.path = []
		a.arrived = false
		a.retry = 0.0

func _reset_actor(villager_id: int) -> void:
	if actors.has(villager_id):
		actors[villager_id].path = []
		actors[villager_id].arrived = false
		actors[villager_id].retry = 0.0

# ------------------------------------------------------------------ 물 연결망

## 완공된 수원(우물 점유 칸·보 출구)과 수로를 상하좌우로 묶어 연결망을 만들고, 농장 ID 순서로 용량을 배정한다.
## {components: [{cells: Dictionary, sources: Array, capacity: int, used: int, min_source: int}],
##  cell_component: Dictionary(칸 -> 연결망 index), farms: Dictionary(농장 id -> {watered, component, touching})}
func compute_water(vs: VillageState) -> Dictionary:
	var node_cells := {}          # 칸 -> true
	var source_of_cell := {}      # 칸 -> 수원 id
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		if b.state != "complete":
			continue
		var def := def_of(b)
		if def.kind == &"canal":
			node_cells[Vector2i(b.x, b.y)] = true
		elif def.water_capacity > 0:
			if def.kind == &"dam":
				if template.dam_outlet.x >= 0:
					node_cells[template.dam_outlet] = true
					source_of_cell[template.dam_outlet] = id
			else:
				for c in cells_of(b):
					node_cells[c] = true
					source_of_cell[c] = id
	var components: Array = []
	var cell_component := {}
	for start in node_cells.keys():
		if cell_component.has(start):
			continue
		var idx := components.size()
		var comp := {"cells": {}, "sources": [], "capacity": 0, "used": 0, "min_source": 0}
		var queue: Array[Vector2i] = [start]
		cell_component[start] = idx
		var head := 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			comp.cells[c] = true
			if source_of_cell.has(c):
				var sid: int = source_of_cell[c]
				if not comp.sources.has(sid):
					comp.sources.append(sid)
			for d in DIRS:
				var n: Vector2i = c + d
				if node_cells.has(n) and not cell_component.has(n):
					cell_component[n] = idx
					queue.append(n)
		for sid in comp.sources:
			comp.capacity += def_of(vs.buildings[sid]).water_capacity
		comp.sources.sort()
		comp.min_source = comp.sources[0] if not comp.sources.is_empty() else 0
		components.append(comp)
	var farms := {}
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		var def := def_of(b)
		if not def.needs_water or b.state != "complete":
			continue
		var touching: Array = []
		for c in cells_of(b):
			for d in DIRS:
				var n: Vector2i = c + d
				if cell_component.has(n) and not touching.has(cell_component[n]):
					touching.append(cell_component[n])
		var chosen := -1
		for ci in touching:
			var comp: Dictionary = components[ci]
			if comp.capacity - comp.used <= 0:
				continue
			if chosen < 0 or comp.min_source < components[chosen].min_source:
				chosen = ci
		if chosen >= 0:
			components[chosen].used += 1
		farms[id] = {"watered": chosen >= 0, "component": chosen, "touching": touching}
	return {"components": components, "cell_component": cell_component, "farms": farms}

func is_farm_watered(id: int) -> bool:
	return bool(water.get("farms", {}).get(id, {}).get("watered", false))

# ------------------------------------------------------------------ 주민 실행 상태

func spawn_actor(villager_id: int, cell: Vector2i) -> void:
	actors[villager_id] = {"pos": Vector2(cell) + Vector2(0.5, 0.5), "path": [], "target": Vector2i(-1, -1), "arrived": false, "retry": 0.0}

## 마을 진입 시 주민을 시작 칸 주변에 세운다(저장하지 않는 실행 값).
func spawn_all(vs: VillageState) -> void:
	actors.clear()
	var g := blocked_grid(vs)
	var reach := flood(g, template.spawn)
	var cells: Array = reach.keys()
	var i := 0
	for id in vs.sorted_villager_ids():
		var c: Vector2i = template.spawn
		if i < cells.size():
			c = cells[mini(i * 5 + 2, cells.size() - 1)]
		spawn_actor(id, c)
		i += 1

func _ensure_actor(vs: VillageState, id: int, near: Vector2i) -> Dictionary:
	if not actors.has(id):
		var g := blocked_grid(vs)
		var c := near
		if grid_blocked(g, c):
			var reach := flood(g, entrance_cell())
			for k in reach.keys():
				c = k
				break
		spawn_actor(id, c)
	return actors[id]

## 주민 1명을 목표 칸으로 이동시킨다. 도착하면 arrived. 경로가 없으면 1초 뒤 다시 찾는다.
func _move_actor(a: Dictionary, g: PackedByteArray, target: Vector2i, dt: float) -> void:
	var cur := actor_cell(a)
	if a.target != target:
		a.target = target
		a.path = []
		a.arrived = false
	if cur == target and a.path.is_empty():
		a.pos = Vector2(target) + Vector2(0.5, 0.5)
		a.arrived = true
		return
	a.arrived = false
	if a.path.is_empty():
		a.retry -= dt
		if a.retry > 0.0:
			return
		a.retry = PATH_RETRY_SECONDS
		a.path = find_path(g, cur, target)
		if a.path.is_empty():
			return
	var next: Vector2i = a.path[0]
	if grid_blocked(g, next):
		a.path = []
		a.retry = 0.0
		return
	var goal := Vector2(next) + Vector2(0.5, 0.5)
	var step := VILLAGER_SPEED * dt
	var to_goal: Vector2 = goal - a.pos
	if to_goal.length() <= step:
		a.pos = goal
		a.path.pop_front()
		if a.path.is_empty() and actor_cell(a) == target:
			a.arrived = true
	else:
		a.pos += to_goal.normalized() * step

# ------------------------------------------------------------------ 틱

## 플레이어가 건물(점유 칸)에 인접(8방향)하거나 그 위에 있는지
func player_near_building(b: Dictionary) -> bool:
	if player_cell.x < 0:
		return false
	for c in cells_of(b):
		if absi(c.x - player_cell.x) <= 1 and absi(c.y - player_cell.y) <= 1:
			return true
	return false

func player_near_cell(c: Vector2i) -> bool:
	return player_cell.x >= 0 and absi(c.x - player_cell.x) <= 1 and absi(c.y - player_cell.y) <= 1

## 경제 1틱(0.1초). 후보 상태 cs/vs 를 갱신하고 완료 이벤트 목록을 돌려준다.
## 이벤트: {kind: "obstacle_cleared"|"construction_complete"|"harvest"|"production", ...}
func tick(cs: CampaignState, vs: VillageState) -> Array:
	var dt := TICK
	var events: Array = []
	elapsed += dt
	var g := blocked_grid(vs)
	water = compute_water(vs)
	# --- 플레이어 작업
	var player_farm := 0
	if not player_work.is_empty():
		if player_work.kind == "obstacle":
			var oid: String = player_work.id
			var cell := _obstacle_cell(oid)
			if cell.x >= 0 and has_obstacle(vs, cell) and player_near_cell(cell):
				var ch := template.obstacle_at(cell)
				var w := float(vs.clearing.get(oid, 0.0)) + dt
				if w + 1e-6 >= VillageTemplate.obstacle_work(ch):
					vs.clearing.erase(oid)
					vs.cleared.append(oid)
					var reward := VillageTemplate.obstacle_reward(ch)
					cs.wood += int(reward.wood)
					cs.stone += int(reward.stone)
					events.append({"kind": "obstacle_cleared", "id": oid, "cell": cell, "obstacle": ch, "wood": int(reward.wood), "stone": int(reward.stone)})
					g = blocked_grid(vs)
				else:
					vs.clearing[oid] = w
		elif player_work.kind == "building":
			var bid: int = int(player_work.id)
			if vs.buildings.has(bid) and player_near_building(vs.buildings[bid]):
				var b: Dictionary = vs.buildings[bid]
				if b.state == "construction":
					b.work_done = float(b.work_done) + PLAYER_BUILD_RATE * dt
				elif def_of(b).kind == &"farm":
					player_farm = bid
	# --- 주민 이동·작업
	var farm_workers := {}      # 농장 id -> true (도착한 농부)
	var producer_workers := {}  # 생산 시설 id -> true
	for vid in vs.sorted_villager_ids():
		var vl: Dictionary = vs.villagers[vid]
		var a := _ensure_actor(vs, vid, template.spawn)
		if vl.job_building == 0 or not vs.buildings.has(vl.job_building):
			if vl.job_building != 0:
				vs.unassign(vid)
			_move_actor(a, g, template.spawn, dt)
			continue
		var b: Dictionary = vs.buildings[vl.job_building]
		var target := work_cell(b)
		_move_actor(a, g, target, dt)
		if not a.arrived:
			continue
		match String(vl.job_kind):
			"build":
				if b.state == "construction":
					b.work_done = float(b.work_done) + VILLAGER_BUILD_RATE * dt
			"farm":
				farm_workers[vl.job_building] = true
			"lumber", "quarry":
				producer_workers[vl.job_building] = true
	# --- 완공
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		if b.state != "construction":
			continue
		var def := def_of(b)
		if float(b.work_done) + 1e-6 < def.work_required:
			continue
		b.state = "complete"
		b.work_done = def.work_required
		var ev := {"kind": "construction_complete", "id": id, "def_id": String(def.id), "villagers": 0}
		if def.villagers_on_complete > 0 and not bool(b.house_returned):
			b.house_returned = true
			var door := work_cell(b)
			for i in def.villagers_on_complete:
				var nid := vs.add_villager()
				if nid != 0:
					spawn_actor(nid, door)
					ev.villagers += 1
		if def.management_on_complete > 0:
			var st: Dictionary = cs.sites[String(site_id)]
			st.repaired = true
			st.management = maxi(int(st.management), def.management_on_complete)
		if def.facility_id != &"":
			cs.facilities[String(def.facility_id)] = true
		# 건설 주민 해제
		for vid in vs.villagers.keys():
			if vs.villagers[vid].job_building == id and vs.villagers[vid].job_kind == "build":
				vs.unassign(vid)
				_reset_actor(vid)
		events.append(ev)
		water = compute_water(vs)
	# --- 농사
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		var def := def_of(b)
		if b.state != "complete" or def.kind != &"farm":
			continue
		if not is_farm_watered(id):
			continue
		if not (farm_workers.has(id) or player_farm == id):
			continue
		b.progress = float(b.progress) + dt
		if float(b.progress) + 1e-6 >= def.cycle_seconds:
			b.progress = 0.0
			cs.food += def.produce_amount
			events.append({"kind": "harvest", "id": id, "food": def.produce_amount})
	# --- 벌목·채석
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		var def := def_of(b)
		if b.state != "complete" or not def.is_producer() or def.kind == &"farm":
			continue
		if not producer_workers.has(id):
			continue
		if int(b.fed) < 0:
			if def.eats_food and cs.food >= 1:
				cs.food -= 1
				b.fed = 1
			else:
				b.fed = 0 if def.eats_food else 1
		b.progress = float(b.progress) + dt
		if float(b.progress) + 1e-6 >= def.cycle_seconds:
			var amount := def.produce_amount if int(b.fed) == 1 else def.produce_amount_unfed
			match def.produce_kind:
				&"wood": cs.wood += amount
				&"stone": cs.stone += amount
				&"food": cs.food += amount
			events.append({"kind": "production", "id": id, "resource": String(def.produce_kind), "amount": amount, "fed": int(b.fed)})
			b.progress = 0.0
			b.fed = -1
	return events

func _obstacle_cell(oid: String) -> Vector2i:
	var parts := oid.split("_")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]), int(parts[2]))

## 농장 성장 단계 0(빈 밭/파종)·1·2, 수확 직전 3 (0~10/10~20/20~30초)
static func growth_stage(b: Dictionary, def: BuildingDef) -> int:
	if def.cycle_seconds <= 0.0:
		return 0
	return clampi(int(floor(float(b.progress) / (def.cycle_seconds / 3.0))), 0, 2)

## 플레이어 인접 상호작용 대상 찾기: 8방향 안에서 가장 가까운 것(상하좌우가 대각선보다 우선), 같은 거리면 공사 현장/농장 우선.
## {kind, id} 또는 {}
func interact_target(vs: VillageState) -> Dictionary:
	if player_cell.x < 0:
		return {}
	var best := {}
	var best_d := 99
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		if b.state != "construction" and def_of(b).kind != &"farm":
			continue
		for c in cells_of(b):
			var dx := absi(c.x - player_cell.x)
			var dy := absi(c.y - player_cell.y)
			if maxi(dx, dy) <= 1 and dx + dy < best_d:
				best_d = dx + dy
				best = {"kind": "building", "id": id}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := player_cell + Vector2i(dx, dy)
			if template.in_bounds(c) and has_obstacle(vs, c):
				var d := absi(dx) + absi(dy)
				if d < best_d:
					best_d = d
					best = {"kind": "obstacle", "id": VillageTemplate.obstacle_id(c), "cell": c}
	return best
