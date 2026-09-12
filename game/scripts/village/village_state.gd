class_name VillageState
extends RefCounted
## 마을 1곳의 영구 상태(저장 대상). 템플릿·건물 정의(공유 데이터)와 분리된다.
## 건물 인스턴스와 주민은 Dictionary 로 두며 고유 ID(next_id)는 이동/철거로 재발급하지 않는다.
## 파생값(물 연결·통행 격자·경로)은 저장하지 않고 VillageSim 이 다시 계산한다.
##
## 건물 인스턴스: {id:int, def_id:String, x:int, y:int, rot:int, state:"construction"|"complete",
##   work_done:float, progress:float(농사/생산 유효 작업초), fed:int(-1 주기 미시작, 0 식량 없이 시작, 1 식량 소비),
##   house_returned:bool(주택 귀환 1회 기록)}
## 주민: {id:int, name:String, job_kind:""|"build"|"farm"|"lumber"|"quarry", job_building:int(0 = 없음)}

const INITIAL_VILLAGERS := 3
const MAX_VILLAGERS := 7
const NAMES := ["하루", "미나", "고로", "사요", "타로", "유키", "겐타", "아키", "리쿠", "하나"]

var site_id: String = ""
var initialized: bool = false
var next_id: int = 1
var cleared: Array = []            ## 제거한 장애물 ID(String)
var clearing: Dictionary = {}      ## 장애물 ID -> 진행 작업량(float)
var buildings: Dictionary = {}     ## int id -> Dictionary
var villagers: Dictionary = {}     ## int id -> Dictionary

static func create(p_site_id: String) -> VillageState:
	var v := VillageState.new()
	v.site_id = p_site_id
	v.initialized = true
	for i in INITIAL_VILLAGERS:
		v.add_villager()
	return v

func duplicate_state() -> VillageState:
	var v := VillageState.new()
	v.site_id = site_id
	v.initialized = initialized
	v.next_id = next_id
	v.cleared = cleared.duplicate()
	v.clearing = clearing.duplicate()
	v.buildings = buildings.duplicate(true)
	v.villagers = villagers.duplicate(true)
	return v

func to_dict() -> Dictionary:
	var b := {}
	for id in buildings.keys():
		b[str(id)] = buildings[id].duplicate()
	var vs := {}
	for id in villagers.keys():
		vs[str(id)] = villagers[id].duplicate()
	return {
		"site_id": site_id,
		"initialized": initialized,
		"next_id": next_id,
		"cleared": cleared.duplicate(),
		"clearing": clearing.duplicate(),
		"buildings": b,
		"villagers": vs,
	}

## 검증하며 읽는다. 알 수 없는 건물 정의·범위 밖 좌표는 버리고 error 에 남긴다.
static func from_dict(d: Variant, p_site_id: String, data: CampaignData, error: Array) -> VillageState:
	var v := VillageState.new()
	v.site_id = p_site_id
	if typeof(d) != TYPE_DICTIONARY:
		v.initialized = false
		return v
	v.initialized = bool(d.get("initialized", false))
	v.next_id = maxi(1, int(d.get("next_id", 1)))
	var raw_cleared: Variant = d.get("cleared", [])
	if typeof(raw_cleared) == TYPE_ARRAY:
		for c in raw_cleared:
			if not v.cleared.has(String(c)):
				v.cleared.append(String(c))
	var raw_clearing: Variant = d.get("clearing", {})
	if typeof(raw_clearing) == TYPE_DICTIONARY:
		for k in raw_clearing.keys():
			var w := float(raw_clearing[k])
			if w > 0.0 and not v.cleared.has(String(k)):
				v.clearing[String(k)] = w
	var raw_b: Variant = d.get("buildings", {})
	var max_id := 0
	if typeof(raw_b) == TYPE_DICTIONARY:
		for k in raw_b.keys():
			var e: Variant = raw_b[k]
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var id := int(e.get("id", int(String(k)) if String(k).is_valid_int() else 0))
			var def := data.building(StringName(String(e.get("def_id", ""))))
			if id <= 0 or def == null:
				error.append("%s: 건물 %s 정의 없음 → 제외" % [p_site_id, str(k)])
				continue
			var x := int(e.get("x", -1))
			var y := int(e.get("y", -1))
			var rot := posmod(int(e.get("rot", 0)), 4)
			var fp := def.footprint(rot)
			if x < 0 or y < 0 or x + fp.x > VillageTemplate.WIDTH or y + fp.y > VillageTemplate.HEIGHT:
				error.append("%s: 건물 %d 좌표 범위 밖 → 제외" % [p_site_id, id])
				continue
			var st := String(e.get("state", "construction"))
			if st != "complete":
				st = "construction"
			v.buildings[id] = {
				"id": id, "def_id": String(def.id), "x": x, "y": y, "rot": rot, "state": st,
				"work_done": maxf(0.0, float(e.get("work_done", 0.0))),
				"progress": maxf(0.0, float(e.get("progress", 0.0))),
				"fed": clampi(int(e.get("fed", -1)), -1, 1),
				"house_returned": bool(e.get("house_returned", false)),
			}
			max_id = maxi(max_id, id)
	var raw_v: Variant = d.get("villagers", {})
	if typeof(raw_v) == TYPE_DICTIONARY:
		for k in raw_v.keys():
			var e: Variant = raw_v[k]
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var id := int(e.get("id", int(String(k)) if String(k).is_valid_int() else 0))
			if id <= 0 or v.villagers.size() >= MAX_VILLAGERS:
				continue
			var jb := int(e.get("job_building", 0))
			var jk := String(e.get("job_kind", ""))
			if jb != 0 and not v.buildings.has(jb):
				jb = 0
				jk = ""
			v.villagers[id] = {"id": id, "name": String(e.get("name", "주민")), "job_kind": jk, "job_building": jb}
			max_id = maxi(max_id, id)
	if v.next_id <= max_id:
		v.next_id = max_id + 1
	# 한 건물에 주민 1명: 중복 배정은 뒤의 주민을 해제한다.
	var taken := {}
	for id in v.villagers.keys():
		var vl: Dictionary = v.villagers[id]
		if vl.job_building != 0:
			if taken.has(vl.job_building):
				vl.job_building = 0
				vl.job_kind = ""
				error.append("%s: 주민 %d 중복 배정 해제" % [p_site_id, id])
			else:
				taken[vl.job_building] = true
	return v

# ------------------------------------------------------------------ 조회

func building(id: int) -> Dictionary:
	return buildings.get(id, {})

func has_building(id: int) -> bool:
	return buildings.has(id)

func count_of_def(def_id: StringName) -> int:
	var n := 0
	for b in buildings.values():
		if b.def_id == String(def_id):
			n += 1
	return n

func has_complete_of_def(def_id: StringName) -> bool:
	for b in buildings.values():
		if b.def_id == String(def_id) and b.state == "complete":
			return true
	return false

func sorted_building_ids() -> Array:
	var ids := buildings.keys()
	ids.sort()
	return ids

func villager(id: int) -> Dictionary:
	return villagers.get(id, {})

func sorted_villager_ids() -> Array:
	var ids := villagers.keys()
	ids.sort()
	return ids

func free_villager_count() -> int:
	var n := 0
	for v in villagers.values():
		if v.job_building == 0:
			n += 1
	return n

## 건물에 배정된 주민 ID(없으면 0)
func worker_of(building_id: int) -> int:
	for id in sorted_villager_ids():
		if villagers[id].job_building == building_id:
			return id
	return 0

func is_cleared(obstacle_id: String) -> bool:
	return cleared.has(obstacle_id)

# ------------------------------------------------------------------ 변경 (후보 상태에서 호출)

func add_villager() -> int:
	if villagers.size() >= MAX_VILLAGERS:
		return 0
	var id := next_id
	next_id += 1
	var name: String = NAMES[(villagers.size() + (hash(site_id) % 3)) % NAMES.size()]
	villagers[id] = {"id": id, "name": name, "job_kind": "", "job_building": 0}
	return id

func add_building(def: BuildingDef, x: int, y: int, rot: int, complete: bool = false) -> int:
	var id := next_id
	next_id += 1
	buildings[id] = {
		"id": id, "def_id": String(def.id), "x": x, "y": y, "rot": posmod(rot, 4),
		"state": "complete" if complete else "construction",
		"work_done": def.work_required if complete else 0.0,
		"progress": 0.0, "fed": -1, "house_returned": false,
	}
	return id

func remove_building(id: int) -> void:
	buildings.erase(id)
	for v in villagers.values():
		if v.job_building == id:
			v.job_building = 0
			v.job_kind = ""

func assign(villager_id: int, building_id: int, job_kind: String) -> void:
	# 같은 건물의 기존 주민은 해제(한 현장 주민 최대 1명)
	for v in villagers.values():
		if v.job_building == building_id and v.id != villager_id:
			v.job_building = 0
			v.job_kind = ""
	var vl: Dictionary = villagers[villager_id]
	vl.job_building = building_id
	vl.job_kind = job_kind

func unassign(villager_id: int) -> void:
	if villagers.has(villager_id):
		villagers[villager_id].job_building = 0
		villagers[villager_id].job_kind = ""
