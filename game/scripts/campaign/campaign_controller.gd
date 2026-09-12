class_name CampaignController
extends RefCounted
## 캠페인 진행 컨트롤러. 정의(CampaignData)·영구 상태(CampaignState)·저장(SaveStore)을 묶고,
## 승리/구매를 후보 상태 생성 → 조건 검증 → 저장 → 메모리 반영 순서로 한 번만 처리한다.
## 저장 실패 시 기존 상태를 보존하고 같은 후보에 대한 재시도(retry_pending)와 이전 저장 복구(discard_pending)를 제공한다.
## 화면(Game)이 인스턴스 1개를 갖고, 테스트는 별도 저장 경로로 독립 인스턴스를 만든다.

const DATA_PATH := "res://data/campaign/campaign.tres"
const DEFAULT_SAVE_PATH := "user://campaign_save.json"

var data: CampaignData
var store: SaveStore
var state: CampaignState                    ## 디스크와 일치하는(또는 새 게임 직후) 확정 상태
var pending: Dictionary = {}                ## 미저장 후보 {kind, candidate, result}
var current_run: Dictionary = {}            ## {run_id, site_id, companion_id, active}
var _results: Dictionary = {}               ## run_id -> 결과 (같은 run 의 반복 호출은 같은 결과)
var _run_counter: int = 0
var last_load_message: String = ""

func _init(save_path: String = DEFAULT_SAVE_PATH, p_data: CampaignData = null) -> void:
	data = p_data if p_data != null else load(DATA_PATH)
	store = SaveStore.new(save_path)

# ------------------------------------------------------------------ 시작/불러오기

func has_save() -> bool:
	return store.exists()

## 새 게임. 기존 저장을 덮어쓰는 확인은 화면이 맡는다. 첫 저장까지 수행한다.
func new_game() -> Dictionary:
	state = CampaignState.new_game(data)
	pending.clear()
	_results.clear()
	current_run.clear()
	var err := store.write(state.to_dict())
	return {"ok": err == OK, "error": store.last_error}

## 이어하기. {ok, error, recovered_from_backup}
func continue_game() -> Dictionary:
	var r := store.read()
	if not r.ok:
		last_load_message = r.error
		return {"ok": false, "error": r.error, "recovered_from_backup": false}
	var errors: Array = []
	var s := CampaignState.from_dict(r.data, data, errors)
	if s == null:
		last_load_message = "; ".join(errors)
		return {"ok": false, "error": last_load_message, "recovered_from_backup": r.recovered_from_backup}
	state = s
	pending.clear()
	_results.clear()
	current_run.clear()
	last_load_message = "; ".join(errors)
	if r.recovered_from_backup:
		last_load_message = r.error + ("; " + last_load_message if last_load_message != "" else "")
	return {"ok": true, "error": last_load_message, "recovered_from_backup": r.recovered_from_backup}

func is_loaded() -> bool:
	return state != null

func has_pending() -> bool:
	return not pending.is_empty()

# ------------------------------------------------------------------ 출정

func selected_companion() -> CompanionDef:
	if state == null or state.selected_companion_id == "":
		return null
	var c := data.companion(StringName(state.selected_companion_id))
	if c == null or not c.implemented or not state.is_companion_unlocked(c.id):
		return null
	return c

func player_attack_power(base: float) -> float:
	return state.attack_power(base, data)

func player_max_hp(base: int) -> int:
	return state.max_hp(base, data)

## 출정 시작: 진입 조건을 검증하고 run_id 를 발급한다. {ok, reason, run_id}
func begin_run(site_id: StringName) -> Dictionary:
	if has_pending():
		return {"ok": false, "reason": "미저장 결과가 있음. 저장 재시도 또는 이전 저장 복구 후 출정", "run_id": ""}
	var site := data.site(site_id)
	var chk := state.can_enter_site(site, data)
	if not chk.ok:
		return {"ok": false, "reason": chk.reason, "run_id": ""}
	_run_counter += 1
	var run_id := "run_%d_%d_%s" % [Time.get_unix_time_from_system(), _run_counter, String(site_id)]
	var comp := selected_companion()
	current_run = {"run_id": run_id, "site_id": String(site_id), "companion_id": (String(comp.id) if comp else ""), "active": true}
	return {"ok": true, "reason": "", "run_id": run_id}

## 전투 결과 확정. outcome: &"victory" / &"defeat" / &"abandon".
## 같은 run_id 로 다시 호출하면 이전 결과를 그대로 돌려준다(보상 중복 없음).
func resolve_run(run_id: String, outcome: StringName) -> Dictionary:
	if _results.has(run_id):
		return _results[run_id].duplicate(true)
	if state != null and state.last_committed_run_id == run_id:
		return {"ok": true, "status": "duplicate", "reason": "이미 반영된 출정", "run_id": run_id, "outcome": String(outcome), "reward": 0, "saved": true}
	if current_run.is_empty() or current_run.run_id != run_id or not current_run.active:
		return {"ok": false, "status": "rejected", "reason": "알 수 없는 출정 %s" % run_id, "run_id": run_id, "outcome": String(outcome), "reward": 0, "saved": false}
	current_run.active = false
	var site := data.site(StringName(current_run.site_id))
	var result := {"ok": true, "status": "", "reason": "", "run_id": run_id, "outcome": String(outcome), "site_id": current_run.site_id,
		"reward": 0, "first": false, "liberated_now": false, "chapter_cleared": "", "companion_unlocked": "", "saved": false, "currency": state.currency}
	if outcome != &"victory":
		# 패배/포기: 보상 없음, 저장 변경 없음. 이전 점령·시설·자금은 유지.
		result.status = "defeat" if outcome == &"defeat" else "abandon"
		result.saved = true
		_results[run_id] = result
		return result.duplicate(true)
	var candidate := state.duplicate_state()
	var applied := candidate.apply_victory(site, data)
	candidate.last_committed_run_id = run_id
	for k in ["reward", "first", "liberated_now", "chapter_cleared", "companion_unlocked"]:
		result[k] = applied[k]
	_commit("victory", candidate, result)
	_results[run_id] = result
	return result.duplicate(true)

## 후보 상태를 저장하고 성공하면 메모리 상태로 반영한다. 실패하면 pending 에 보관한다.
func _commit(kind: String, candidate: CampaignState, result: Dictionary) -> void:
	var err := store.write(candidate.to_dict())
	if err == OK:
		state = candidate
		pending.clear()
		result.status = "committed"
		result.saved = true
		result.currency = state.currency
		result.reason = ""
	else:
		pending = {"kind": kind, "candidate": candidate, "result": result}
		result.status = "unsaved"
		result.saved = false
		result.currency = state.currency
		result.reason = "저장 실패: %s" % store.last_error

## 같은 후보 상태로 저장을 다시 시도한다. 보상을 다시 더하지 않는다.
func retry_pending() -> Dictionary:
	if pending.is_empty():
		return {"ok": false, "status": "none", "reason": "재시도할 미저장 결과 없음", "saved": true}
	var result: Dictionary = pending.result
	_commit(pending.kind, pending.candidate, result)
	if result.has("run_id"):
		_results[result.run_id] = result
	return result.duplicate(true)

## 미저장 후보를 버리고 마지막 정상 저장으로 돌아간다. 이번 결과는 반영되지 않는다.
func discard_pending() -> Dictionary:
	if pending.is_empty():
		return {"ok": true, "reason": ""}
	var result: Dictionary = pending.result
	pending.clear()
	result.status = "discarded"
	result.saved = false
	result.reason = "이번 결과는 반영되지 않음 (이전 저장 유지)"
	if result.has("run_id"):
		_results[result.run_id] = result
	# 디스크의 저장이 정상이면 그것을, 아니면 메모리의 확정 상태를 유지한다.
	var r := store.read()
	if r.ok:
		var errors: Array = []
		var s := CampaignState.from_dict(r.data, data, errors)
		if s != null:
			state = s
	return {"ok": true, "reason": result.reason}

# ------------------------------------------------------------------ 마을 관리

func repair(site_id: StringName) -> Dictionary:
	if has_pending():
		return {"ok": false, "status": "rejected", "reason": "미저장 결과가 있음", "saved": false}
	var site := data.site(site_id)
	var chk := state.can_repair(site)
	if not chk.ok:
		return {"ok": false, "status": "rejected", "reason": chk.reason, "saved": false}
	var candidate := state.duplicate_state()
	var applied := candidate.apply_repair(site)
	if not applied.ok:
		return {"ok": false, "status": "rejected", "reason": applied.reason, "saved": false}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "repair", "site_id": String(site_id)}
	_commit("repair", candidate, result)
	return result

func buy_facility(site_id: StringName) -> Dictionary:
	if has_pending():
		return {"ok": false, "status": "rejected", "reason": "미저장 결과가 있음", "saved": false}
	var site := data.site(site_id)
	var chk := state.can_buy_facility(site)
	if not chk.ok:
		return {"ok": false, "status": "rejected", "reason": chk.reason, "saved": false}
	var candidate := state.duplicate_state()
	var applied := candidate.apply_facility(site)
	if not applied.ok:
		return {"ok": false, "status": "rejected", "reason": applied.reason, "saved": false}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "facility", "site_id": String(site_id)}
	_commit("facility", candidate, result)
	return result

func select_companion(companion_id: StringName) -> Dictionary:
	if has_pending():
		return {"ok": false, "status": "rejected", "reason": "미저장 결과가 있음", "saved": false}
	var chk := state.can_select_companion(companion_id, data)
	if not chk.ok:
		return {"ok": false, "status": "rejected", "reason": chk.reason, "saved": false}
	var candidate := state.duplicate_state()
	candidate.apply_select_companion(companion_id, data)
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "companion"}
	_commit("companion", candidate, result)
	return result
