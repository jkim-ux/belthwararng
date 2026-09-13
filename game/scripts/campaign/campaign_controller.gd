class_name CampaignController
extends RefCounted
## 캠페인 진행 컨트롤러. 정의(CampaignData)·영구 상태(CampaignState)·저장(SaveStore)을 묶고,
## 승리/구매를 후보 상태 생성 → 조건 검증 → 저장 → 메모리 반영 순서로 한 번만 처리한다.
## 저장 실패 시 기존 상태를 보존하고 같은 후보에 대한 재시도(retry_pending)와 이전 저장 복구(discard_pending)를 제공한다.
## 화면(Game)이 인스턴스 1개를 갖고, 테스트는 별도 저장 경로로 독립 인스턴스를 만든다.
## HWR-005: 마을 진입/배치/공사/주민/생산은 같은 후보 상태 → 검증 → 저장 → 반영 경로를 쓴다. 경제 틱은 현재 마을에서만 진행하고
## 완료 이벤트는 즉시, 중간 진행은 PROGRESS_SAVE_SECONDS 마다 저장한다. 저장 실패 시 틱과 추가 변경을 멈춘다.

const DATA_PATH := "res://data/campaign/campaign.tres"
const DEFAULT_SAVE_PATH := "user://campaign_save.json"
const PROGRESS_SAVE_SECONDS := 10.0

var data: CampaignData
var store: SaveStore
var state: CampaignState                    ## 디스크와 일치하는(또는 새 게임 직후) 확정 상태
var pending: Dictionary = {}                ## 미저장 후보 {kind, candidate, result}
var current_run: Dictionary = {}            ## {run_id, site_id, companion_id, active}
var _results: Dictionary = {}               ## run_id -> 결과 (같은 run 의 반복 호출은 같은 결과)
var _run_counter: int = 0
var last_load_message: String = ""
var active_village: StringName = &""       ## 현재 들어가 있는 마을(경제 시간이 진행되는 곳)
var sim: VillageSim = null
var _tick_accum: float = 0.0
var _since_progress_save: float = 0.0
var _progress_dirty: bool = false

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
	_clear_village_runtime()
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
	_clear_village_runtime()
	last_load_message = "; ".join(errors)
	if r.recovered_from_backup:
		last_load_message = r.error + ("; " + last_load_message if last_load_message != "" else "")
	if s.migrated_from == 1:
		# 원본 schema 1 저장을 별도 보존한 뒤 새 형식으로 원자 저장한다. 실패해도 원본은 그대로 남는다.
		var keep := store.preserve_copy(".v1.bak")
		var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "migrate"}
		_commit("migrate", s, result)
		var note := "저장 형식 1 → 2 이전" + (" (원본 보존: %s)" % keep if keep != "" else "")
		if not result.saved:
			note += " — 새 형식 저장 실패: %s (원본 저장 유지, 재시도 가능)" % store.last_error
		last_load_message = note + ("; " + last_load_message if last_load_message != "" else "")
		s.migrated_from = 0
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
	if active_village != &"":
		var lv := leave_village()
		if not lv.ok:
			return {"ok": false, "reason": "마을 저장 실패: %s" % lv.reason, "run_id": ""}
	var site := data.site(site_id)
	var chk := state.can_enter_site(site, data)
	if not chk.ok:
		return {"ok": false, "reason": chk.reason, "run_id": ""}
	_run_counter += 1
	var run_id := "run_%d_%d_%s" % [Time.get_unix_time_from_system(), _run_counter, String(site_id)]
	var comp := selected_companion()
	current_run = {"run_id": run_id, "site_id": String(site_id), "companion_id": (String(comp.id) if comp else ""), "active": true}
	return {"ok": true, "reason": "", "run_id": run_id}

## 전투 결과 확정. outcome: &"victory" / &"defeat" / &"abandon". victory 는 거점 보스 처치를 뜻한다.
## extras.chest_bonus: 출정 중 상자로 보류한 군자금. 거점 던전의 chest_currency 로 검증(0 또는 정확히 그 값)해
## 기본 보상과 함께 같은 후보 상태에 한 번 합산한다. 저장 재시도는 같은 후보를 쓰므로 중복 가산이 없다.
## 같은 run_id 로 다시 호출하면 이전 결과를 그대로 돌려준다(보상 중복 없음).
func resolve_run(run_id: String, outcome: StringName, extras: Dictionary = {}) -> Dictionary:
	if _results.has(run_id):
		return _results[run_id].duplicate(true)
	if state != null and state.last_committed_run_id == run_id:
		return {"ok": true, "status": "duplicate", "reason": "이미 반영된 출정", "run_id": run_id, "outcome": String(outcome), "reward": 0, "saved": true}
	if current_run.is_empty() or current_run.run_id != run_id or not current_run.active:
		return {"ok": false, "status": "rejected", "reason": "알 수 없는 출정 %s" % run_id, "run_id": run_id, "outcome": String(outcome), "reward": 0, "saved": false}
	current_run.active = false
	var site := data.site(StringName(current_run.site_id))
	var result := {"ok": true, "status": "", "reason": "", "run_id": run_id, "outcome": String(outcome), "site_id": current_run.site_id,
		"reward": 0, "base_reward": 0, "chest_bonus": 0, "first": false, "liberated_now": false, "chapter_cleared": "", "companion_unlocked": "", "saved": false, "currency": state.currency}
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
	result.base_reward = int(applied.reward)
	# 상자 보류 군자금: 던전 정의 값과 일치할 때만 인정한다(임의 금액 거부).
	var bonus := _validated_chest_bonus(site, extras)
	if bonus > 0:
		candidate.currency += bonus
		result.chest_bonus = bonus
		result.reward = int(result.base_reward) + bonus
	_commit("victory", candidate, result)
	_results[run_id] = result
	return result.duplicate(true)

func _validated_chest_bonus(site: SiteDef, extras: Dictionary) -> int:
	if site == null or site.dungeon == null or extras.is_empty():
		return 0
	var v: Variant = extras.get("chest_bonus", 0)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return 0
	var bonus := int(v)
	if bonus <= 0:
		return 0
	if bonus != site.dungeon.chest_currency:
		push_warning("상자 보류 금액 %d 이 정의값 %d 과 다름 → 정의값으로 제한" % [bonus, site.dungeon.chest_currency])
		bonus = site.dungeon.chest_currency
	return bonus

## 후보 상태를 저장하고 성공하면 메모리 상태로 반영한다. 실패하면 pending 에 보관한다.
func _commit(kind: String, candidate: CampaignState, result: Dictionary) -> void:
	var err := store.write(candidate.to_dict())
	if err == OK:
		state = candidate
		pending.clear()
		_progress_dirty = false
		_since_progress_save = 0.0
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
	_progress_dirty = false
	_since_progress_save = 0.0
	if sim != null:
		sim.invalidate_paths()
	return {"ok": true, "reason": result.reason}

# ------------------------------------------------------------------ 마을 (HWR-005)

func _clear_village_runtime() -> void:
	active_village = &""
	sim = null
	_tick_accum = 0.0
	_since_progress_save = 0.0
	_progress_dirty = false

func in_village() -> bool:
	return active_village != &"" and sim != null

func active_village_state() -> VillageState:
	return state.village(active_village) if in_village() else null

## 마을 진입: 해방된 마을만. 첫 진입이면 초기화(템플릿·주민 3명·일회성 물자)를 같은 후보로 저장한다. {ok, reason, supplies, saved}
func enter_village(site_id: StringName) -> Dictionary:
	if has_pending():
		return {"ok": false, "reason": "미저장 결과가 있음", "supplies": {}, "saved": false}
	var site := data.site(site_id)
	if site == null or not site.is_village():
		return {"ok": false, "reason": "마을이 아님", "supplies": {}, "saved": false}
	if not state.is_liberated(site_id):
		return {"ok": false, "reason": "해방 전에는 들어갈 수 없음", "supplies": {}, "saved": false}
	if data.village_template(site_id) == null:
		return {"ok": false, "reason": "마을 템플릿 없음", "supplies": {}, "saved": false}
	if active_village != &"" and active_village != site_id:
		leave_village()
	var result := {"ok": true, "reason": "", "supplies": {}, "saved": true, "status": "", "kind": "village_init"}
	if not state.has_village(site_id):
		var candidate := state.duplicate_state()
		var r := candidate.ensure_village(site_id, data)
		if not r.ok:
			return {"ok": false, "reason": r.reason, "supplies": {}, "saved": false}
		result.supplies = r.supplies
		_commit("village_init", candidate, result)
		if not result.saved:
			result.ok = false
			return result
	active_village = site_id
	sim = VillageSim.new(data, site_id)
	sim.spawn_all(state.village(site_id))
	_tick_accum = 0.0
	_since_progress_save = 0.0
	_progress_dirty = false
	return result

## 마을 퇴장: 진행 중 값을 저장하고 경제 시간을 멈춘다. {ok, reason, saved}
func leave_village() -> Dictionary:
	if not in_village():
		return {"ok": true, "reason": "", "saved": true}
	var out := {"ok": true, "reason": "", "saved": true}
	if _progress_dirty and not has_pending():
		var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_progress"}
		_commit("village_progress", state.duplicate_state(), result)
		out.saved = result.saved
		out.ok = result.saved
		out.reason = result.reason
		if not result.saved:
			return out
	_clear_village_runtime()
	return out

## 경제 시간 진행(현재 마을에서만). 실제 경과 시간을 받아 10Hz 고정 틱으로 나눠 처리한다.
## 완료 이벤트가 있는 틱은 즉시 저장, 없으면 10초마다 진행량을 저장한다. 저장 실패면 틱을 멈춘다. 이벤트 목록을 돌려준다.
func village_tick(delta: float) -> Array:
	var events: Array = []
	if not in_village() or has_pending():
		return events
	_tick_accum = minf(_tick_accum + delta, 0.5)   # 긴 프레임 정지는 최대 0.5초까지만 따라잡는다(오프라인 생산 없음)
	while _tick_accum + 1e-9 >= VillageSim.TICK:
		_tick_accum -= VillageSim.TICK
		var candidate := state.duplicate_state()
		var vs := candidate.village(active_village)
		var ev := sim.tick(candidate, vs)
		if not ev.is_empty():
			var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_event", "events": ev}
			_commit("village_event", candidate, result)
			events.append_array(ev)
			if not result.saved:
				break
			_progress_dirty = false
			_since_progress_save = 0.0
		else:
			state = candidate
			_progress_dirty = true
			_since_progress_save += VillageSim.TICK
			if _since_progress_save + 1e-9 >= PROGRESS_SAVE_SECONDS:
				var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_progress"}
				_commit("village_progress", state.duplicate_state(), result)
				_since_progress_save = 0.0
				if not result.saved:
					break
				_progress_dirty = false
	return events

func _village_guard() -> Dictionary:
	if not in_village():
		return {"ok": false, "status": "rejected", "reason": "마을에 있지 않음", "saved": false}
	if has_pending():
		return {"ok": false, "status": "rejected", "reason": "미저장 결과가 있음", "saved": false}
	return {"ok": true}

func village_can_place(def: BuildingDef, x: int, y: int, rot: int, moving_id: int = 0) -> Dictionary:
	if not in_village():
		return {"ok": false, "reason": "마을에 있지 않음", "cells": [], "door": Vector2i(-1, -1)}
	return sim.can_place(state, active_village_state(), def, x, y, rot, moving_id)

func village_can_place_canals(cells: Array) -> Dictionary:
	if not in_village():
		return {"ok": false, "reason": "마을에 있지 않음", "cells": [], "cost_wood": 0}
	return sim.can_place_canals(state, active_village_state(), cells)

## 설치 확정(비용 차감·인스턴스 생성을 한 후보로 저장). {ok, status, reason, saved, id}
func village_place(def_id: StringName, x: int, y: int, rot: int) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		g.id = 0
		return g
	var candidate := state.duplicate_state()
	var r := sim.place(candidate, candidate.village(active_village), data.building(def_id), x, y, rot)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false, "id": 0}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_place", "id": r.id}
	_commit("village_place", candidate, result)
	return result

func village_place_canals(cells: Array) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		g.ids = []
		return g
	var candidate := state.duplicate_state()
	var r := sim.place_canals(candidate, candidate.village(active_village), cells)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false, "ids": []}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_place_canals", "ids": r.ids}
	_commit("village_place_canals", candidate, result)
	return result

func village_cancel(id: int) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		return g
	var candidate := state.duplicate_state()
	var r := sim.cancel_construction(candidate, candidate.village(active_village), id)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_cancel"}
	_commit("village_cancel", candidate, result)
	return result

func village_demolish(id: int) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		return g
	var candidate := state.duplicate_state()
	var r := sim.demolish(candidate, candidate.village(active_village), id)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_demolish"}
	_commit("village_demolish", candidate, result)
	return result

func village_move(id: int, x: int, y: int, rot: int) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		return g
	var candidate := state.duplicate_state()
	var r := sim.move_building(candidate, candidate.village(active_village), id, x, y, rot)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_move"}
	_commit("village_move", candidate, result)
	return result

## 밭 정돈 부탁(HWR-006): 빈손 정령 1명에게 장애물 정돈을 예약한다. {ok, status, reason, saved, villager}
func village_request_clear(obstacle_id: String) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		g.villager = 0
		return g
	var candidate := state.duplicate_state()
	var r := sim.request_clear(candidate.village(active_village), obstacle_id)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false, "villager": 0}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_request_clear", "villager": r.villager}
	_commit("village_request_clear", candidate, result)
	return result

## 정돈 부탁 취소: 진행량은 남는다. {ok, status, reason, saved}
func village_cancel_clear(obstacle_id: String) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		return g
	var candidate := state.duplicate_state()
	var r := sim.cancel_clear(candidate.village(active_village), obstacle_id)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_cancel_clear"}
	_commit("village_cancel_clear", candidate, result)
	return result

func village_assign(villager_id: int, building_id: int) -> Dictionary:
	var g := _village_guard()
	if not g.ok:
		return g
	var candidate := state.duplicate_state()
	var r := sim.assign_villager(candidate.village(active_village), villager_id, building_id)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "saved": false}
	var result := {"ok": true, "status": "", "reason": "", "saved": false, "kind": "village_assign"}
	_commit("village_assign", candidate, result)
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
