class_name CampaignState
extends RefCounted
## 캠페인 영구 상태(저장 대상). 정의(CampaignData)와 분리되며 파생값(공격력·진입 가능)은 저장하지 않고 계산한다.
## 모든 변경 함수는 규칙을 검증하고 {ok, reason} 를 돌려준다. 거부되면 상태는 바뀌지 않는다.

const SCHEMA_VERSION := 1

var schema_version: int = SCHEMA_VERSION
var currency: int = 0
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
	s.sites = sites.duplicate(true)
	s.facilities = facilities.duplicate(true)
	s.cleared_chapters = cleared_chapters.duplicate()
	s.unlocked_companions = unlocked_companions.duplicate()
	s.selected_companion_id = selected_companion_id
	s.last_committed_run_id = last_committed_run_id
	return s

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"currency": currency,
		"sites": sites.duplicate(true),
		"facilities": facilities.duplicate(true),
		"cleared_chapters": cleared_chapters.duplicate(),
		"unlocked_companions": unlocked_companions.duplicate(),
		"selected_companion_id": selected_companion_id,
		"last_committed_run_id": last_committed_run_id,
	}

## 저장 데이터를 검증하며 읽는다. 형식이 맞지 않으면 null 을 돌려주고 error 에 이유를 적는다.
## 알 수 없는 상위 schema_version 은 읽지 않는다(임의로 낮춰 읽지 않음).
static func from_dict(d: Variant, data: CampaignData, error: Array) -> CampaignState:
	if typeof(d) != TYPE_DICTIONARY:
		error.append("저장 데이터가 객체가 아님")
		return null
	var ver := int(d.get("schema_version", -1))
	if ver != SCHEMA_VERSION:
		error.append("지원하지 않는 schema_version %d (지원: %d)" % [ver, SCHEMA_VERSION])
		return null
	var s := CampaignState.new()
	s.currency = maxi(0, int(d.get("currency", 0)))
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
	return s

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

func can_repair(site: SiteDef) -> Dictionary:
	if site == null or not site.is_village():
		return {"ok": false, "reason": "군사 거점에는 정비가 없음"}
	if not is_liberated(site.id):
		return {"ok": false, "reason": "미해방 거점"}
	if is_repaired(site.id):
		return {"ok": false, "reason": "이미 정비 완료"}
	if currency < site.repair_cost:
		return {"ok": false, "reason": "군자금 부족 (%d 필요, 보유 %d)" % [site.repair_cost, currency]}
	return {"ok": true, "reason": ""}

func can_buy_facility(site: SiteDef) -> Dictionary:
	if site == null or not site.is_village() or site.facility == null:
		return {"ok": false, "reason": "구매할 시설이 없음"}
	if not is_liberated(site.id):
		return {"ok": false, "reason": "미해방 거점"}
	if management(site.id) < site.management_on_repair:
		return {"ok": false, "reason": "관리도 %d 필요 (정비 먼저)" % site.management_on_repair}
	if has_facility(site.facility.id):
		return {"ok": false, "reason": "이미 구매함"}
	if currency < site.facility.cost:
		return {"ok": false, "reason": "군자금 부족 (%d 필요, 보유 %d)" % [site.facility.cost, currency]}
	return {"ok": true, "reason": ""}

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

func apply_repair(site: SiteDef) -> Dictionary:
	var chk := can_repair(site)
	if not chk.ok:
		return chk
	currency -= site.repair_cost
	var st: Dictionary = sites[String(site.id)]
	st.repaired = true
	st.management = maxi(int(st.management), site.management_on_repair)
	return {"ok": true, "reason": ""}

func apply_facility(site: SiteDef) -> Dictionary:
	var chk := can_buy_facility(site)
	if not chk.ok:
		return chk
	currency -= site.facility.cost
	facilities[String(site.facility.id)] = true
	return {"ok": true, "reason": ""}

func apply_select_companion(companion_id: StringName, data: CampaignData) -> Dictionary:
	var chk := can_select_companion(companion_id, data)
	if not chk.ok:
		return chk
	selected_companion_id = String(companion_id)
	return {"ok": true, "reason": ""}
