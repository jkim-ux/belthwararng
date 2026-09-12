class_name CampaignState
extends RefCounted
## 캠페인 영구 상태(저장 대상). 정의(CampaignData)와 분리되며 파생값(공격력·진입 가능·물 연결)은 저장하지 않고 계산한다.
## 모든 변경 함수는 규칙을 검증하고 {ok, reason} 를 돌려준다. 거부되면 상태는 바뀌지 않는다.
## schema 2(HWR-005): 목재/석재/식량, 마을별 배치·주민·개간 상태, 일회성 복구 물자 기록을 추가한다. schema 1 은 이전한다.

const SCHEMA_VERSION := 2

var schema_version: int = SCHEMA_VERSION
var currency: int = 0
var wood: int = 0                          ## 해방 마을이 공유하는 저장고(HWR-005)
var stone: int = 0
var food: int = 0
var villages: Dictionary = {}              ## site_id -> VillageState (마을별 배치·주민·개간)
var supplies_granted: Array = []           ## 초기 물자를 지급한 site_id (String), 1회
var migrated_from: int = 0                 ## 로드 시 이전한 원본 schema (실행 값, 저장하지 않음)
var sites: Dictionary = {}                 ## site_id -> {"liberated": bool, "management": int, "repaired": bool}
var facilities: Dictionary = {}            ## facility_id -> true
var cleared_chapters: Array = []           ## String
var unlocked_companions: Array = []        ## String
var selected_companion_id: String = ""
var last_committed_run_id: String = ""

static func new_game(data: CampaignData) -> CampaignState:
	var s := CampaignState.new()
	for site in data.sites:
		s.sites[String(site.id)] = {"liberated": false, "management": 0, "repaired": false}
	return s

func duplicate_state() -> CampaignState:
	var s := CampaignState.new()
	s.schema_version = schema_version
	s.currency = currency
	s.wood = wood
	s.stone = stone
	s.food = food
	for k in villages.keys():
		s.villages[k] = villages[k].duplicate_state()
	s.supplies_granted = supplies_granted.duplicate()
	s.migrated_from = migrated_from
	s.sites = sites.duplicate(true)
	s.facilities = facilities.duplicate(true)
	s.cleared_chapters = cleared_chapters.duplicate()
	s.unlocked_companions = unlocked_companions.duplicate()
	s.selected_companion_id = selected_companion_id
	s.last_committed_run_id = last_committed_run_id
	return s

func to_dict() -> Dictionary:
	var v := {}
	for k in villages.keys():
		v[k] = villages[k].to_dict()
	return {
		"schema_version": SCHEMA_VERSION,
		"currency": currency,
		"wood": wood,
		"stone": stone,
		"food": food,
		"villages": v,
		"supplies_granted": supplies_granted.duplicate(),
		"sites": sites.duplicate(true),
		"facilities": facilities.duplicate(true),
		"cleared_chapters": cleared_chapters.duplicate(),
		"unlocked_companions": unlocked_companions.duplicate(),
		"selected_companion_id": selected_companion_id,
		"last_committed_run_id": last_committed_run_id,
	}

## 저장 데이터를 검증하며 읽는다. 형식이 맞지 않으면 null 을 돌려주고 error 에 이유를 적는다.
## schema 1 은 2 로 이전한다(migrated_from = 1). 알 수 없는 상위 schema_version 은 읽지 않는다(임의로 낮춰 읽지 않음).
static func from_dict(d: Variant, data: CampaignData, error: Array) -> CampaignState:
	if typeof(d) != TYPE_DICTIONARY:
		error.append("저장 데이터가 객체가 아님")
		return null
	var ver := int(d.get("schema_version", -1))
	if ver != SCHEMA_VERSION and ver != 1:
		error.append("지원하지 않는 schema_version %d (지원: 1, %d)" % [ver, SCHEMA_VERSION])
		return null
	var s := CampaignState.new()
	s.currency = maxi(0, int(d.get("currency", 0)))
	s.wood = maxi(0, int(d.get("wood", 0)))
	s.stone = maxi(0, int(d.get("stone", 0)))
	s.food = maxi(0, int(d.get("food", 0)))
	var raw_sites: Variant = d.get("sites", {})
	if typeof(raw_sites) != TYPE_DICTIONARY:
		error.append("sites 형식 오류")
		return null
	for site in data.sites:
		var key := String(site.id)
		var entry: Variant = raw_sites.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			entry = {}
		var liberated := bool(entry.get("liberated", false))
		var management := clampi(int(entry.get("management", 0)), 0, 100)
		var repaired := bool(entry.get("repaired", false))
		if not site.is_village():
			management = 0
			repaired = false
		s.sites[key] = {"liberated": liberated, "management": management, "repaired": repaired}
	var raw_fac: Variant = d.get("facilities", {})
	if typeof(raw_fac) == TYPE_DICTIONARY:
		for k in raw_fac.keys():
			if bool(raw_fac[k]) and data.facility_site(StringName(String(k))) != null:
				s.facilities[String(k)] = true
	var raw_cleared: Variant = d.get("cleared_chapters", [])
	if typeof(raw_cleared) == TYPE_ARRAY:
		for c in raw_cleared:
			if data.chapter(StringName(String(c))) != null and not s.cleared_chapters.has(String(c)):
				s.cleared_chapters.append(String(c))
	var raw_unlocked: Variant = d.get("unlocked_companions", [])
	if typeof(raw_unlocked) == TYPE_ARRAY:
		for c in raw_unlocked:
			if data.companion(StringName(String(c))) != null and not s.unlocked_companions.has(String(c)):
				s.unlocked_companions.append(String(c))
	s.selected_companion_id = String(d.get("selected_companion_id", ""))
	s.last_committed_run_id = String(d.get("last_committed_run_id", ""))
	# 잠긴/미구현 동료가 선택돼 있으면 동행 없음으로 정리한다.
	if s.selected_companion_id != "":
		var chk := s.can_select_companion(StringName(s.selected_companion_id), data)
		if not chk.ok:
			error.append("선택 동료 '%s' 정리: %s" % [s.selected_companion_id, chk.reason])
			s.selected_companion_id = ""
	# 마을 상태(schema 2) 읽기
	var raw_granted: Variant = d.get("supplies_granted", [])
	if typeof(raw_granted) == TYPE_ARRAY:
		for g in raw_granted:
			if not s.supplies_granted.has(String(g)):
				s.supplies_granted.append(String(g))
	var raw_villages: Variant = d.get("villages", {})
	if typeof(raw_villages) == TYPE_DICTIONARY:
		for k in raw_villages.keys():
			var site := data.site(StringName(String(k)))
			if site == null or not site.is_village() or data.village_template(site.id) == null:
				error.append("알 수 없는 마을 '%s' 제외" % String(k))
				continue
			var vs := VillageState.from_dict(raw_villages[k], String(k), data, error)
			if vs.initialized:
				s.villages[String(k)] = vs
	if ver == 1:
		s.migrated_from = 1
		s._migrate_from_v1(data, error)
	return s

## schema 1 → 2: 해방 마을에 템플릿·주민 3명을 만들고, 정비 완료는 복구 현장 완공으로, 산 시설은 예약 자리에 완공 배치한다.
## 비용을 다시 받지 않고 효과 플래그(facilities)는 그대로 둔다. 첫 농촌 물자는 같은 상태에서 한 번 지급한다.
func _migrate_from_v1(data: CampaignData, error: Array) -> void:
	for site in data.sites:
		if not site.is_village() or not is_liberated(site.id):
			continue
		var r := ensure_village(site.id, data)
		if not r.ok:
			error.append("마을 '%s' 이전 실패: %s" % [String(site.id), r.reason])

# ------------------------------------------------------------------ 마을 (HWR-005)

func village(site_id: StringName) -> VillageState:
	return villages.get(String(site_id), null)

func has_village(site_id: StringName) -> bool:
	return villages.has(String(site_id))

## 마을 초기화(1회): 템플릿 적용·주민 3명·초기 물자. 이미 정비/구매한 기록은 완공 건물로 옮긴다.
## 이미 초기화된 마을이면 changed=false. {ok, reason, changed, supplies}
func ensure_village(site_id: StringName, data: CampaignData) -> Dictionary:
	var site := data.site(site_id)
	if site == null or not site.is_village():
		return {"ok": false, "reason": "마을이 아님", "changed": false, "supplies": {}}
	if not is_liberated(site_id):
		return {"ok": false, "reason": "해방 전에는 들어갈 수 없음", "changed": false, "supplies": {}}
	var template := data.village_template(site_id)
	if template == null:
		return {"ok": false, "reason": "마을 템플릿 없음", "changed": false, "supplies": {}}
	if has_village(site_id):
		return {"ok": true, "reason": "", "changed": false, "supplies": {}}
	var vs := VillageState.create(String(site_id))
	# 기존 정비 완료 → 고정 복구 현장 완공(비용 없음)
	if is_repaired(site_id):
		var repair_def := data.building(&"repair")
		var rr := template.repair_site()
		if repair_def != null and rr.size.x > 0:
			vs.add_building(repair_def, rr.position.x, rr.position.y, 0, true)
	# 기존 구매 시설 → 예약 자리에 같은 시설 ID 로 완공 배치(효과 플래그는 기존 것 유지)
	if site.facility != null and has_facility(site.facility.id):
		var fdef := data.building_for_facility(site.facility.id)
		if fdef != null:
			var spot := template.facility_spot
			vs.add_building(fdef, spot.position.x, spot.position.y, 0, true)
	villages[String(site_id)] = vs
	var supplies := {}
	if not supplies_granted.has(String(site_id)):
		supplies_granted.append(String(site_id))
		if site.initial_wood > 0 or site.initial_stone > 0 or site.initial_food > 0:
			wood += site.initial_wood
			stone += site.initial_stone
			food += site.initial_food
			supplies = {"wood": site.initial_wood, "stone": site.initial_stone, "food": site.initial_food}
	return {"ok": true, "reason": "", "changed": true, "supplies": supplies}

# ------------------------------------------------------------------ 조회

func site_state(site_id: StringName) -> Dictionary:
	return sites.get(String(site_id), {"liberated": false, "management": 0, "repaired": false})

func is_liberated(site_id: StringName) -> bool:
	return bool(site_state(site_id).get("liberated", false))

func management(site_id: StringName) -> int:
	return int(site_state(site_id).get("management", 0))

func is_repaired(site_id: StringName) -> bool:
	return bool(site_state(site_id).get("repaired", false))

func has_facility(facility_id: StringName) -> bool:
	return facilities.has(String(facility_id))

func is_chapter_cleared(chapter_id: StringName) -> bool:
	return cleared_chapters.has(String(chapter_id))

func is_companion_unlocked(companion_id: StringName) -> bool:
	return unlocked_companions.has(String(companion_id))

## 출정 시 공격력 = 기본값 × (훈련장 구매 시 1.05). 저장된 구매 플래그에서 계산한다.
func attack_power(base: float, data: CampaignData) -> float:
	var v := base
	for site in data.sites:
		var f := site.facility
		if f != null and f.effect_kind == &"attack_mult" and has_facility(f.id):
			v *= f.value
	return v

## 출정 시 최대 체력 = 기본값 + (보급창 구매 시 10)
func max_hp(base: int, data: CampaignData) -> int:
	var v := base
	for site in data.sites:
		var f := site.facility
		if f != null and f.effect_kind == &"max_hp_add" and has_facility(f.id):
			v += int(f.value)
	return v

## 진입 가능 여부: 콘텐츠 구현 여부와 진행 잠금을 구분해 이유를 돌려준다.
func can_enter_site(site: SiteDef, data: CampaignData) -> Dictionary:
	if site == null:
		return {"ok": false, "reason": "알 수 없는 거점", "kind": "invalid"}
	var ch := data.chapter(site.chapter_id)
	if ch == null or not ch.implemented:
		return {"ok": false, "reason": "콘텐츠 준비 중 (이 챕터의 전투는 아직 없음)", "kind": "unimplemented"}
	if not site.implemented:
		return {"ok": false, "reason": "콘텐츠 준비 중", "kind": "unimplemented"}
	if ch.prerequisite_chapter_id != &"" and not is_chapter_cleared(ch.prerequisite_chapter_id):
		var prev := data.chapter(ch.prerequisite_chapter_id)
		return {"ok": false, "reason": "선행 챕터 '%s' 클리어 필요" % (prev.display_name if prev else String(ch.prerequisite_chapter_id)), "kind": "locked"}
	if site.prerequisite_site_id != &"":
		var prev_site := data.site(site.prerequisite_site_id)
		var prev_name := prev_site.display_name if prev_site != null else String(site.prerequisite_site_id)
		if not is_liberated(site.prerequisite_site_id):
			return {"ok": false, "reason": "%s 해방 필요" % prev_name, "kind": "locked"}
		if prev_site != null and prev_site.is_village() and management(site.prerequisite_site_id) < site.prerequisite_management:
			return {"ok": false, "reason": "%s 관리도 %d 필요 (현재 %d, 정비로 올릴 수 있음)" % [prev_name, site.prerequisite_management, management(site.prerequisite_site_id)], "kind": "locked"}
	return {"ok": true, "reason": "", "kind": "open"}

## 정비/시설 즉시 구매(schema 1 의 버튼 규칙)는 HWR-005 에서 제거했다.
## 경로 복구·훈련장·보급창은 마을에서 배치·공사·완공해야 하며(VillageSim), 완공 시 repaired/management/facilities 를 설정한다.

func can_select_companion(companion_id: StringName, data: CampaignData) -> Dictionary:
	if companion_id == &"":
		return {"ok": true, "reason": ""}
	var c := data.companion(companion_id)
	if c == null:
		return {"ok": false, "reason": "알 수 없는 동료"}
	if not c.implemented:
		return {"ok": false, "reason": "미구현 동료"}
	if not is_companion_unlocked(companion_id):
		return {"ok": false, "reason": "아직 해금되지 않음 (%s 클리어)" % companion_id}
	return {"ok": true, "reason": ""}

# ------------------------------------------------------------------ 변경 (후보 상태에 적용)

## 승리 적용. 최초 승리는 해방·관리도·최초 보상, 재도전은 반복 보상만. 챕터 클리어와 동료 해금을 같은 변경으로 확정한다.
func apply_victory(site: SiteDef, data: CampaignData) -> Dictionary:
	var result := {"ok": true, "reason": "", "reward": 0, "first": false, "liberated_now": false, "chapter_cleared": "", "companion_unlocked": ""}
	var key := String(site.id)
	if not sites.has(key):
		sites[key] = {"liberated": false, "management": 0, "repaired": false}
	var st: Dictionary = sites[key]
	if not st.liberated:
		st.liberated = true
		result.first = true
		result.liberated_now = true
		result.reward = site.first_reward
		if site.is_village():
			st.management = maxi(int(st.management), site.management_on_liberate)
	else:
		result.reward = site.repeat_reward
		# 재도전 승리로 관리도·정비·시설을 되돌리지 않는다.
	currency += int(result.reward)
	# 챕터 클리어 판정
	var ch := data.chapter(site.chapter_id)
	if ch != null and not is_chapter_cleared(ch.id):
		var all_done := true
		for sid in ch.site_ids:
			if not is_liberated(sid):
				all_done = false
				break
		if all_done:
			cleared_chapters.append(String(ch.id))
			result.chapter_cleared = String(ch.id)
			if ch.reward_companion_id != &"" and data.companion(ch.reward_companion_id) != null and not is_companion_unlocked(ch.reward_companion_id):
				unlocked_companions.append(String(ch.reward_companion_id))
				result.companion_unlocked = String(ch.reward_companion_id)
	return result

func apply_select_companion(companion_id: StringName, data: CampaignData) -> Dictionary:
	var chk := can_select_companion(companion_id, data)
	if not chk.ok:
		return chk
	selected_companion_id = String(companion_id)
	return {"ok": true, "reason": ""}
