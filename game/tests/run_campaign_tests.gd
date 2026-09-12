extends SceneTree
## HWR-002 R1 캠페인 자동 검증. 실행: godot --headless --path game -s tests/run_campaign_tests.gd
## 테스트용 저장 경로(user://test_saves/)만 사용하며 사용자 저장(user://campaign_save.json)은 건드리지 않는다.
## 인수 시나리오(docs/CAMPAIGN_SYSTEMS.md 7절) 1~12 를 상태·저장·전투·화면 수준에서 확인한다. 실패가 있으면 종료 코드 1.

const BATTLE_SCENE := "res://scenes/battle.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const TEST_SAVE := "user://test_saves/hwr002_test.json"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var data: CampaignData

func _initialize() -> void:
	print("=== HWR-002 R1 캠페인 검증 시작 (Godot %s) ===" % Engine.get_version_info().string)
	data = load(CampaignController.DATA_PATH)
	await process_frame
	var tests := [
		"test_campaign_data_definitions",
		"test_scenario_1_to_4_progression_and_reload",
		"test_scenario_7_8_rejections_and_no_reset",
		"test_scenario_11_save_failure_retry_backup",
		"test_load_cleans_locked_companion_and_rejects_schema",
		"test_encounter_waves_victory_once",
		"test_scenario_9_dummy_and_ally_not_counted",
		"test_scenario_10_same_tick_death_is_defeat_and_projectiles_cleared",
		"test_attack_slot_limit_two",
		"test_captain_two_patterns_and_super_armor",
		"test_real_fight_farm_victory_with_spam_attack",
		"test_archer_follows_fires_and_hits",
		"test_archer_arrow_does_not_break_hitstun_and_passes_ally",
		"test_scenario_5_archer_last_kill_wins_and_reward_120",
		"test_scenario_6_companion_death_and_recovery",
		"test_enemy_targets_nearest_ally_and_locks_on_telegraph",
		"test_scenario_12_dev_keys_ignored_in_campaign",
		"test_game_screens_smoke",
	]
	for t in tests:
		await _run(t)
	_cleanup_saves()
	print("=== 결과: 통과 %d, 실패 %d ===" % [_pass, _fail])
	for f in _failures:
		print("  FAIL: ", f)
	quit(1 if _fail > 0 else 0)

func _run(name: String) -> void:
	_cleanup_saves()
	var before := _fail
	await call(name)
	await process_frame
	if _fail == before:
		print("PASS ", name)
	else:
		print("FAIL ", name)

func _cleanup_saves() -> void:
	SaveStore.new(TEST_SAVE).delete_all()

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_failures.append(msg)
		print("    ✗ ", msg)

# ------------------------------------------------------------------ 도우미

func make_controller() -> CampaignController:
	return CampaignController.new(TEST_SAVE, data)

func make_battle(mode: StringName = &"campaign") -> Battle:
	var scene: PackedScene = load(BATTLE_SCENE)
	var b: Battle = scene.instantiate()
	b.manual_step = true
	b.mode = mode
	b.debug_visible = false
	root.add_child(b)
	await process_frame
	return b

func idle(b: Battle, n: int) -> void:
	for i in n:
		b.step(PlayerInput.make())

func press(b: Battle, action: String, move: Vector2 = Vector2.ZERO) -> void:
	b.step(PlayerInput.make(move, [action]))

func place(a: BattleActor, x: float, y: float) -> void:
	a.floor_pos = Vector2(x, y)
	a.height = 0.0
	a.vz = 0.0
	a.position = a.floor_pos

## 대기 중인 출현을 즉시 처리한다.
func flush_spawns(b: Battle) -> void:
	for sp in b.pending_spawns:
		sp.ticks = 1
	idle(b, 1)

func kill(e: BattleActor) -> void:
	var info := HitInfo.new()
	info.attack = AttackData.new()
	info.attack.hitstun_ms = 300.0
	info.damage = 100000
	info.hitstop_ticks = 0
	info.direction = 1
	e.receive_hit(info)

## 승리까지 진행한 컨트롤러 결과를 돌려주는 도우미(전투 없이 상태만).
func win(c: CampaignController, site_id: StringName) -> Dictionary:
	var r := c.begin_run(site_id)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "reward": 0}
	return c.resolve_run(r.run_id, &"victory")

# ------------------------------------------------------------------ 정의 데이터

func test_campaign_data_definitions() -> void:
	check(data.chapters.size() == 5 and data.companions.size() == 5, "5챕터·5동료 정의 (%d, %d)" % [data.chapters.size(), data.companions.size()])
	var implemented_ch := 0
	for ch in data.chapters:
		if ch.implemented:
			implemented_ch += 1
	check(implemented_ch == 1 and data.chapter(&"ch1").implemented, "구현 챕터는 1개")
	var implemented_co := 0
	for co in data.companions:
		if co.implemented:
			implemented_co += 1
	check(implemented_co == 1 and data.companion(&"aya").implemented, "구현 동료는 궁수 1명")
	var farm := data.site(&"ch1_farm")
	var store := data.site(&"ch1_store")
	var pass_site := data.site(&"ch1_pass")
	check(farm.is_village() and farm.enemy_count() == 4 and farm.waves.size() == 2, "농촌: 근접 2×2")
	check(store.is_village() and store.enemy_count() == 6 and store.waves.size() == 2 and store.prerequisite_site_id == &"ch1_farm" and store.prerequisite_management == 60, "창고: 근접 3×2, 선행 농촌 60")
	check(not pass_site.is_village() and pass_site.facility == null and pass_site.waves.size() == 1 and pass_site.waves[0].enemy_kinds[0] == &"captain", "초소: fort, 시설 없음, 대장 1")
	check(farm.facility.id == &"training_ground" and farm.facility.cost == 60 and store.facility.id == &"supply_depot" and store.facility.cost == 60, "훈련장/보급창 60")
	check(farm.first_reward == 100 and farm.repeat_reward == 20 and farm.repair_cost == 40, "보상 100/20, 정비 40")

# ------------------------------------------------------------------ 시나리오 1~4, 7, 8

func test_scenario_1_to_4_progression_and_reload() -> void:
	var c := make_controller()
	check(not c.has_save(), "테스트 저장 없음에서 시작")
	var ng := c.new_game()
	check(ng.ok and c.has_save() and c.state.currency == 0, "새 게임: 군자금 0, 저장 생성")
	var farm := data.site(&"ch1_farm")
	var store := data.site(&"ch1_store")
	var pass_site := data.site(&"ch1_pass")
	check(c.state.can_enter_site(farm, data).ok, "농촌은 새 게임에서 공략 가능")
	check(not c.state.can_enter_site(store, data).ok and not c.state.can_enter_site(pass_site, data).ok, "창고·초소 잠김")
	# 1. 농촌 승리
	var r1 := win(c, &"ch1_farm")
	check(r1.status == "committed" and r1.reward == 100 and r1.first and c.state.currency == 100, "농촌 최초 승리: +100 (%s, %d)" % [r1.status, c.state.currency])
	check(c.state.is_liberated(&"ch1_farm") and c.state.management(&"ch1_farm") == 40, "농촌 해방, 관리도 40")
	check(not c.state.can_enter_site(store, data).ok, "관리도 40 → 창고 잠김: %s" % c.state.can_enter_site(store, data).reason)
	var rep := c.repair(&"ch1_farm")
	check(rep.ok and rep.saved and c.state.management(&"ch1_farm") == 60 and c.state.currency == 60, "정비 후 관리도 60, 군자금 60")
	check(c.state.can_enter_site(store, data).ok, "창고 개방")
	# 2. 훈련장
	var buy := c.buy_facility(&"ch1_farm")
	check(buy.ok and buy.saved and c.state.currency == 0 and c.state.has_facility(&"training_ground"), "훈련장 구매 후 군자금 0")
	check(is_equal_approx(c.player_attack_power(20.0), 21.0), "공격력 20 → %.2f == 21" % c.player_attack_power(20.0))
	# 재실행(로드) 후에도 21
	var c2 := make_controller()
	var lg := c2.continue_game()
	check(lg.ok and not lg.recovered_from_backup, "재실행 로드 성공")
	check(is_equal_approx(c2.player_attack_power(20.0), 21.0) and c2.state.currency == 0 and c2.state.management(&"ch1_farm") == 60, "로드 후 공격력 21, 군자금 0, 관리도 60")
	# 재도전 승리 후에도 21 (아래 시나리오 7에서 다시 확인)
	# 3. 창고
	var r2 := win(c2, &"ch1_store")
	check(r2.status == "committed" and r2.reward == 100 and c2.state.currency == 100 and c2.state.management(&"ch1_store") == 40, "창고 최초 승리 +100, 관리도 40")
	check(not c2.state.can_enter_site(pass_site, data).ok, "초소 잠김(창고 관리도 40)")
	check(c2.repair(&"ch1_store").saved and c2.state.management(&"ch1_store") == 60, "창고 정비 → 60")
	check(c2.buy_facility(&"ch1_store").saved and c2.state.currency == 0, "보급창 구매 → 0")
	check(c2.player_max_hp(100) == 110, "최대 체력 100 → %d == 110" % c2.player_max_hp(100))
	check(c2.state.can_enter_site(pass_site, data).ok, "초소 개방")
	# 4. 초소
	var rr := c2.begin_run(&"ch1_pass")
	var r3 := c2.resolve_run(rr.run_id, &"victory")
	check(r3.status == "committed" and r3.reward == 100 and c2.state.currency == 100, "초소 최초 승리 +100")
	check(r3.chapter_cleared == "ch1" and c2.state.is_chapter_cleared(&"ch1"), "챕터 1 클리어")
	check(r3.companion_unlocked == "aya" and c2.state.is_companion_unlocked(&"aya"), "아야 해금 (같은 저장 변경)")
	check(not c2.state.is_repaired(&"ch1_pass") and c2.state.management(&"ch1_pass") == 0, "초소에는 관리도·정비 없음")
	# 결과 이벤트 반복
	var again := c2.resolve_run(rr.run_id, &"victory")
	check(again.status == "committed" and again.reward == 100 and c2.state.currency == 100, "같은 run_id 반복 호출: 수치 동일, 보상 중복 없음 (군자금 %d)" % c2.state.currency)
	var again2 := c2.resolve_run(rr.run_id, &"defeat")
	check(again2.status == "committed" and c2.state.currency == 100, "늦게 도착한 다른 결과도 무시")
	# 디스크에 해금이 함께 저장됨
	var c3 := make_controller()
	c3.continue_game()
	check(c3.state.is_companion_unlocked(&"aya") and c3.state.is_chapter_cleared(&"ch1") and c3.state.currency == 100 and c3.state.last_committed_run_id == rr.run_id, "디스크: 보상·클리어·해금 모두 저장")
	check(c3.resolve_run(rr.run_id, &"victory").status == "duplicate", "로드 후 같은 run_id 는 duplicate")
	# 챕터 2 는 미구현 → 진입 불가
	var fake := SiteDef.new()
	fake.id = &"ch2_test"
	fake.chapter_id = &"ch2"
	var chk := c3.state.can_enter_site(fake, data)
	check(not chk.ok and chk.kind == "unimplemented", "챕터 1 클리어 후에도 챕터 2 미구현 진입 불가: %s" % chk.reason)

func test_scenario_7_8_rejections_and_no_reset() -> void:
	var c := make_controller()
	c.new_game()
	# 8. 선행 거점 미완료 출정
	var br := c.begin_run(&"ch1_store")
	check(not br.ok, "선행 미완료 창고 출정 거부: %s" % br.reason)
	# 미해방 정비/구매
	check(not c.repair(&"ch1_farm").ok and not c.buy_facility(&"ch1_farm").ok and c.state.currency == 0, "미해방 거점 정비·구매 거부")
	win(c, &"ch1_farm")
	# 돈 부족: 100 → 정비 40 → 60 → 훈련장 60 → 0 → 창고 정비 불가
	c.repair(&"ch1_farm")
	c.buy_facility(&"ch1_farm")
	check(c.state.currency == 0, "군자금 0")
	var dup := c.buy_facility(&"ch1_farm")
	check(not dup.ok and c.state.currency == 0 and c.state.has_facility(&"training_ground"), "중복 구매 거부: %s" % dup.reason)
	var rep2 := c.repair(&"ch1_farm")
	check(not rep2.ok, "중복 정비 거부: %s" % rep2.reason)
	win(c, &"ch1_store")
	c.repair(&"ch1_store")   # 100 → 60
	c.buy_facility(&"ch1_store")  # → 0
	var poor := c.repair(&"ch1_store")
	check(not poor.ok, "이미 정비된 창고 재정비 거부")
	# 잠긴 동료 선택
	var sel := c.select_companion(&"aya")
	check(not sel.ok and c.state.selected_companion_id == "", "해금 전 아야 선택 거부: %s" % sel.reason)
	var sel2 := c.select_companion(&"gen")
	check(not sel2.ok, "미구현 겐 선택 거부: %s" % sel2.reason)
	var sel3 := c.select_companion(&"nobody")
	check(not sel3.ok, "알 수 없는 동료 거부")
	# 미구현 챕터 출정
	var fake := c.begin_run(&"ch2_none")
	check(not fake.ok, "존재하지 않는/미구현 거점 출정 거부")
	# 7. 재도전 승리로 초기화되지 않음
	win(c, &"ch1_pass")
	check(c.state.is_chapter_cleared(&"ch1") and c.state.is_companion_unlocked(&"aya"), "초소 승리로 클리어·해금")
	var before_mgmt := c.state.management(&"ch1_farm")
	var before_cur := c.state.currency
	var rr := win(c, &"ch1_farm")
	check(rr.reward == 20 and not rr.first and c.state.currency == before_cur + 20, "농촌 재도전 +20 (%d → %d)" % [before_cur, c.state.currency])
	check(c.state.management(&"ch1_farm") == before_mgmt and before_mgmt == 60 and c.state.is_repaired(&"ch1_farm"), "재도전 후 관리도 60 유지(40으로 되돌아가지 않음)")
	check(c.state.has_facility(&"training_ground") and c.state.has_facility(&"supply_depot") and c.state.is_chapter_cleared(&"ch1") and c.state.is_companion_unlocked(&"aya"), "시설·챕터·해금 유지")
	check(is_equal_approx(c.player_attack_power(20.0), 21.0) and c.player_max_hp(100) == 110, "재도전 후에도 공격력 21, 최대 체력 110")
	# 시설은 마을당 1회: +5% 가 쌓이지 않는다
	check(c.state.facilities.size() == 2, "시설 플래그 2개 (복제 없음)")
	# 패배: 보상 없음, 자금 유지
	var b := c.begin_run(&"ch1_farm")
	var d := c.resolve_run(b.run_id, &"defeat")
	check(d.status == "defeat" and d.reward == 0 and c.state.currency == before_cur + 20, "패배: 보상 없음, 자금 유지")
	var ab := c.begin_run(&"ch1_farm")
	var abr := c.resolve_run(ab.run_id, &"abandon")
	check(abr.status == "abandon" and c.state.currency == before_cur + 20, "출정 포기: 보상 없음")

# ------------------------------------------------------------------ 시나리오 11: 저장 실패·재시도·백업

func test_scenario_11_save_failure_retry_backup() -> void:
	var c := make_controller()
	c.new_game()
	c.store.fail_next_write = true
	var r := win(c, &"ch1_farm")
	check(r.status == "unsaved" and not r.saved and r.reward == 100, "저장 실패 → unsaved (%s)" % r.reason)
	check(c.state.currency == 0 and not c.state.is_liberated(&"ch1_farm") and c.has_pending(), "메모리 상태는 이전 그대로, 후보 보관")
	check(not c.begin_run(&"ch1_farm").ok, "미저장 상태에서는 다음 출정 거부")
	check(not c.repair(&"ch1_farm").ok, "미저장 상태에서는 구매/정비 거부")
	var rid: String = r.run_id
	var same := c.resolve_run(rid, &"victory")
	check(same.status == "unsaved" and c.state.currency == 0, "확인 연타: 여전히 미저장, 보상 없음")
	var retry := c.retry_pending()
	check(retry.status == "committed" and retry.saved and c.state.currency == 100 and c.state.is_liberated(&"ch1_farm"), "재시도 성공: 정확히 한 번 반영 (군자금 %d)" % c.state.currency)
	check(not c.has_pending() and c.retry_pending().status == "none", "재시도 후 후보 없음")
	check(c.resolve_run(rid, &"victory").status == "committed" and c.state.currency == 100, "재시도 후 같은 run 재호출도 100 유지")
	var c_disk := make_controller()
	c_disk.continue_game()
	check(c_disk.state.currency == 100, "디스크에도 100 (한 번)")
	# 이전 저장으로 돌아가기(discard)
	c.store.fail_next_write = true
	var r2 := win(c, &"ch1_farm")
	check(r2.status == "unsaved", "두 번째 실패 주입")
	var dis := c.discard_pending()
	check(dis.ok and not c.has_pending() and c.state.currency == 100, "이전 저장 복구: 이번 결과 미반영 (군자금 %d)" % c.state.currency)
	check(c.resolve_run(r2.run_id, &"victory").status == "discarded", "버린 run 은 discarded 로 남음")
	# 유효한 백업 복구: 주 저장을 손상시킨다
	check(FileAccess.file_exists(c.store.backup_path()), "백업 파일 존재")
	var f := FileAccess.open(c.store.path, FileAccess.WRITE)
	f.store_string("{ corrupted json")
	f.close()
	var c_bak := make_controller()
	var lr := c_bak.continue_game()
	check(lr.ok and lr.recovered_from_backup, "손상 저장 → 백업에서 복구 (%s)" % lr.error)
	check(c_bak.state.currency == 0 or c_bak.state.currency == 100, "백업 상태는 이전 정상 저장 중 하나 (군자금 %d)" % c_bak.state.currency)
	# 원본을 바로 덮어쓰지 않았다
	var f2 := FileAccess.open(c_bak.store.path, FileAccess.READ)
	check(f2.get_as_text().begins_with("{ corrupted"), "손상 원본은 로드만으로 덮어쓰지 않음")
	f2.close()
	# 손상 + 백업 없음 → 실패
	c_bak.store.delete_all()
	var f3 := FileAccess.open(c_bak.store.path, FileAccess.WRITE)
	f3.store_string("garbage")
	f3.close()
	var c_none := make_controller()
	var lr2 := c_none.continue_game()
	check(not lr2.ok, "손상 + 백업 없음 → 읽기 실패 (새 게임/취소 선택은 화면이 제공): %s" % lr2.error)
	# 저장 임시 파일이 남지 않는다
	check(not FileAccess.file_exists(c.store.tmp_path()), "임시 파일 정리됨")

func test_load_cleans_locked_companion_and_rejects_schema() -> void:
	var c := make_controller()
	c.new_game()
	var d := c.state.to_dict()
	d.selected_companion_id = "aya"    # 잠긴 동료가 선택돼 있는 저장
	c.store.write(d)
	var c2 := make_controller()
	var r := c2.continue_game()
	check(r.ok and c2.state.selected_companion_id == "" and r.error.contains("정리"), "잠긴 동료 선택은 동행 없음으로 정리하고 기록: %s" % r.error)
	# 상위 schema_version 은 읽지 않는다
	d.schema_version = 2
	c.store.write(d)
	var c3 := make_controller()
	var r3 := c3.continue_game()
	check(not r3.ok and r3.error.contains("schema_version"), "지원하지 않는 schema_version 거부: %s" % r3.error)
	# 필드 검증: 알 수 없는 시설/챕터/동료 ID 는 버린다
	d.schema_version = 1
	d.facilities = {"bogus": true, "training_ground": true}
	d.cleared_chapters = ["ch9", "ch1"]
	d.unlocked_companions = ["nobody", "aya"]
	c.store.write(d)
	var c4 := make_controller()
	c4.continue_game()
	check(c4.state.facilities.size() == 1 and c4.state.cleared_chapters == ["ch1"] and c4.state.unlocked_companions == ["aya"], "알 수 없는 ID 는 로드 시 버림")

# ------------------------------------------------------------------ 전투: 웨이브·승패

func test_encounter_waves_victory_once() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var resolved_count := [0]
	var resolved_outcome := [""]
	b.resolved.connect(func(o, _rid): resolved_count[0] += 1; resolved_outcome[0] = String(o))
	b.start_encounter(farm, "run_test_1", null, 20.0, 100)
	check(b.enemies.is_empty() and b.pending_spawns.size() == 2 and b.wave_index == 1, "시작: 출현 예고 2, 적 0")
	check(b.result_state == &"active" and b.required_alive_count() == 0, "출현 예고 중 적 0 이지만 승리 아님")
	idle(b, Ticks.from_ms(700))
	check(b.enemies.size() == 2 and b.required_alive_count() == 2 and b.pending_spawns.is_empty(), "묶음 1 출현 (2명)")
	for e in b.enemies:
		check(absf(e.floor_pos.x - b.player.floor_pos.x) >= 120.0, "등장 위치가 플레이어와 겹치지 않음 (%.0f)" % e.floor_pos.x)
	kill(b.enemies[0])
	idle(b, 1)
	check(b.result_state == &"active" and b.wave_index == 1 and b.pending_spawns.is_empty(), "1명 남았을 때 다음 묶음 없음")
	kill(b.enemies[1])
	idle(b, 1)
	check(b.result_state == &"active" and b.wave_index == 2 and b.pending_spawns.size() == 2, "묶음 1 전멸 → 묶음 2 예고 (승리 아님)")
	idle(b, Ticks.from_ms(700))
	check(b.required_alive_count() == 2, "묶음 2 출현")
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	check(b.result_state == &"resolved" and b.outcome == &"victory" and resolved_count[0] == 1, "마지막 묶음 전멸 → 승리 1회 (%d)" % resolved_count[0])
	var t := b.tick
	idle(b, 10)
	check(b.tick == t and resolved_count[0] == 1, "확정 후 진행 정지, 이벤트 반복 없음")
	b.queue_free()

func test_scenario_9_dummy_and_ally_not_counted() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_test_2", aya, 20.0, 100)
	check(b.companion != null and b.companion.alive and b.allies.size() == 1, "동료 생성")
	# 허수아비를 억지로 추가해도 승리 조건에 들어가지 않는다
	var d := Dummy.new()
	b.actors_root.add_child(d)
	d.configure(b.tuning, b, Vector2(700, 540))
	b.enemies.append(d)
	flush_spawns(b)
	check(b.required_alive_count() == 2, "허수아비 제외 필수 적 2")
	for e in b.alive_enemies():
		if not e is Dummy:
			kill(e)
	idle(b, 1)
	flush_spawns(b)
	for e in b.alive_enemies():
		if not e is Dummy:
			kill(e)
	idle(b, 1)
	check(b.result_state == &"resolved" and b.outcome == &"victory" and d.alive and b.companion.alive, "허수아비·아군이 살아 있어도 필수 적 0 이면 승리")
	b.queue_free()

func test_scenario_10_same_tick_death_is_defeat_and_projectiles_cleared() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_test_3", aya, 20.0, 100)
	flush_spawns(b)
	# 마지막 묶음까지 진행: 묶음 1 전멸 → 묶음 2 출현 → 1명만 남김
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	flush_spawns(b)
	var alive := b.alive_enemies()
	kill(alive[0])
	var last := alive[1]
	idle(b, 1)
	check(b.required_alive_count() == 1 and b.result_state == &"active", "마지막 적 1명")
	# 주인공 체력 1, 적이 공격 → 같은 틱에 아군 화살이 마지막 적을 처치
	var p := b.player
	place(p, 600, 540)
	p.hp = 1
	place(last, 660, 540)
	last.hp = 1
	last.facing = -1
	last.invuln_ticks = 0
	last.change_state(&"attack")
	place(b.companion, 400, 540)
	b.companion.change_state(&"follow")
	b.companion.cooldown_ticks = 9999
	var pr := Projectile.new()
	pr.setup(&"player", b.companion, b.companion.arrow, 7.0, Vector2(650, 540), 35.0, 1, 600.0, 360.0, 36, 4.0, 4.0)
	b.add_projectile(pr)
	idle(b, 1)
	check(not p.alive and not last.alive, "같은 틱에 주인공과 마지막 적 사망 (%s / %s)" % [str(p.alive), str(last.alive)])
	check(b.result_state == &"resolved" and b.outcome == &"defeat", "동일 틱 → 패배 우선 (%s)" % b.outcome)
	check(b.projectiles.is_empty(), "확정 후 남은 투사체 정리")
	for a in b.all_actors():
		check(a.active_hitboxes.is_empty(), "%s 판정 정리" % a.display_name)
	b.queue_free()

func test_attack_slot_limit_two() -> void:
	var b: Battle = await make_battle(&"training")
	b.spawn_enemy = false
	b.respawn_enemies()
	var p := b.player
	place(p, 640, 540)
	var es: Array[MeleeEnemy] = []
	for pos in [Vector2(760, 540), Vector2(520, 540), Vector2(760, 600), Vector2(520, 600)]:
		var e := b.spawn_melee_enemy(pos)
		e.state = &"idle"
		e.state_ticks = 100
		es.append(e)
	p.invuln_ticks = 100000
	var max_active := 0
	var waited := false
	for i in 300:
		b.step(PlayerInput.make())
		var n := 0
		for e in es:
			if e.state == &"telegraph" or e.state == &"attack" or e.state == &"recover":
				n += 1
			if e.waiting_for_slot:
				waited = true
		max_active = maxi(max_active, n)
	check(max_active <= 2 and max_active >= 1, "동시 공격자 최대 %d ≤ 2" % max_active)
	check(waited, "허가 없는 적은 대기함")
	check(b.attack_slot_holders.size() <= 2, "허가 보유 ≤ 2")
	# 사망 시 허가 반환
	var holder: BattleActor = null
	for e in es:
		if b.attack_slot_holders.has(e):
			holder = e
			break
	if holder != null:
		kill(holder)
		idle(b, 1)
		check(not b.attack_slot_holders.has(holder), "사망한 적의 허가 반환")
	b.queue_free()

func test_captain_two_patterns_and_super_armor() -> void:
	var b: Battle = await make_battle()
	var pass_site := data.site(&"ch1_pass")
	b.start_encounter(pass_site, "run_test_boss", null, 20.0, 100)
	flush_spawns(b)
	check(b.enemies.size() == 1 and b.enemies[0] is CaptainEnemy, "대장 1명 출현")
	var boss: CaptainEnemy = b.enemies[0]
	check(boss.max_hp == 600 and boss.hp == 600, "대장 체력 600")
	var p := b.player
	p.invuln_ticks = 100000
	place(p, 500, 540)
	var patterns_seen := {}
	var order: Array = []
	var charge_start_x := 0.0
	var charge_facing := 0
	var telegraph_hit_checked := false
	var prev_state: StringName = boss.state
	for i in 900:
		b.step(PlayerInput.make())
		var entered_telegraph := boss.state == &"telegraph" and prev_state != &"telegraph"
		prev_state = boss.state
		if entered_telegraph:
			patterns_seen[boss.current_pattern] = true
			order.append(boss.current_pattern)
			if boss.current_pattern == 1:
				charge_start_x = boss.floor_pos.x
				charge_facing = boss.facing
			if not telegraph_hit_checked:
				# 예고 중 피격: 피해는 받고 상태는 유지
				var hp0 := boss.hp
				var info := HitInfo.new()
				info.attack = p.light_attacks[0]
				info.damage = 20
				info.hitstop_ticks = 2
				info.direction = 1
				boss.receive_hit(info)
				check(boss.hp == hp0 - 20 and boss.state == &"telegraph", "예고 중 피격: 피해 20, 상태 유지 (%s)" % boss.state)
				telegraph_hit_checked = true
		if boss.state == &"attack" and boss.current_pattern == 1 and boss.state_ticks >= boss.charge.active_ticks():
			var moved := (boss.floor_pos.x - charge_start_x) * charge_facing
			check(moved <= 300.01, "돌진 이동 %.0f ≤ 300" % moved)
		if patterns_seen.size() == 2 and order.size() >= 3:
			break
	check(patterns_seen.has(0) and patterns_seen.has(1), "베기·돌진 두 패턴 사용 (%s)" % str(order))
	var alternates := true
	for i in range(1, order.size()):
		if order[i] == order[i - 1]:
			alternates = false
	check(alternates, "패턴 교대 (%s)" % str(order))
	# 띄우기 면역: 올려베기 맞아도 launched 아님
	boss.change_state(&"idle")
	boss.state_ticks = 0
	var info2 := HitInfo.new()
	info2.attack = load("res://data/attacks/seungwolcham.tres")
	info2.damage = 30
	info2.hitstop_ticks = 4
	info2.direction = 1
	boss.receive_hit(info2)
	check(boss.state != &"launched" and boss.height == 0.0 and boss.state == &"hitstun" and boss.hitstun_ticks == Ticks.from_ms(120), "대기 중 피격: 짧은 경직 7틱, 띄우기 없음 (%s)" % boss.state)
	var hs := boss.hitstun_ticks
	boss.receive_hit(info2)
	check(boss.hitstun_ticks == hs, "연타로 경직 연장 없음")
	# 경계에서 멈추는 돌진
	place(boss, b.arena_rect().end.x - 100.0, 540)
	place(p, b.arena_rect().end.x - 40.0, 540)
	boss.pattern_index = 1
	boss.change_state(&"approach")
	for i in 200:
		b.step(PlayerInput.make())
		if boss.state == &"recover":
			break
	check(boss.floor_pos.x <= b.arena_rect().end.x - boss.half_width + 0.01, "돌진이 경기장 경계에서 멈춤 (x %.0f)" % boss.floor_pos.x)
	b.queue_free()

func test_real_fight_farm_victory_with_spam_attack() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	b.start_encounter(farm, "run_real", null, 20.0, 100)
	var p := b.player
	var ticks := 0
	while b.result_state == &"active" and ticks < 60 * 90:
		# 단순 조작: 가장 가까운 적을 향해 깊이를 맞추고 평타 연타
		var move := Vector2.ZERO
		var nearest: EnemyBase = null
		var best := INF
		for e in b.alive_enemies():
			var d: float = absf(e.floor_pos.x - p.floor_pos.x)
			if d < best:
				best = d
				nearest = e
		if nearest != null:
			var dy := nearest.floor_pos.y - p.floor_pos.y
			if absf(dy) > 8.0:
				move.y = signf(dy)
			if nearest.floor_pos.x < p.floor_pos.x and p.facing > 0 and p.state == &"ground":
				move.x = -1
			elif nearest.floor_pos.x > p.floor_pos.x and p.facing < 0 and p.state == &"ground":
				move.x = 1
		b.step(PlayerInput.make(move, ["attack_light"]))
		ticks += 1
	check(b.result_state == &"resolved" and b.outcome == &"victory", "실제 전투로 농촌 승리 (%s, %d틱, 남은 체력 %d, 처치 %d)" % [b.outcome, ticks, p.hp, b.kills])
	print("    [정보] 농촌 실전 %d틱 (%.1f초), 주인공 체력 %d/%d" % [ticks, ticks / 60.0, p.hp, p.max_hp])
	b.queue_free()

# ------------------------------------------------------------------ 동료 궁수

func test_archer_follows_fires_and_hits() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_archer", aya, 20.0, 100)
	var c: ArcherCompanion = b.companion
	var p := b.player
	check(c.max_hp == 60 and is_equal_approx(c.def.attack_damage, 7.0), "아야 체력 60, 화살 피해 7")
	# 적 없이 따라가기: 주인공 뒤 약 100px
	for sp in b.pending_spawns:
		sp.ticks = 100000
	place(p, 700, 560)
	p.facing = 1
	idle(b, 200)
	check(absf(c.floor_pos.x - (p.floor_pos.x - 100.0)) < 12.0 and absf(c.floor_pos.y - p.floor_pos.y) < 8.0, "따라가기 위치 (%.0f, %.0f) ≈ (600, 560)" % [c.floor_pos.x, c.floor_pos.y])
	# 적 배치: 사거리 안, 깊이 다름 → 깊이를 맞춘 뒤 사격
	var e := b.spawn_melee_enemy(Vector2(950, 600))
	e.max_hp = 100000
	e.hp = e.max_hp
	e.state = &"idle"
	e.state_ticks = -100000   # 접근하지 않게
	var hits := [0]
	b.hit_applied.connect(func(a, t, _i): if a == c and t == e: hits[0] += 1)
	var fired_at_y := -1.0
	var aim_start := Vector2.ZERO
	var aim_facing := 0
	var moved_after_aim := false
	var prev_state: StringName = c.state
	for i in 240:
		b.step(PlayerInput.make())
		e.state = &"idle"
		e.state_ticks = -100000
		if c.state == &"aim":
			if prev_state != &"aim":
				aim_start = c.floor_pos
				aim_facing = c.facing
				if fired_at_y < 0.0:
					fired_at_y = c.floor_pos.y
			elif c.floor_pos.distance_to(aim_start) > 0.01 or c.facing != aim_facing:
				moved_after_aim = true
		prev_state = c.state
	check(c.shots_fired >= 1, "사격 %d회" % c.shots_fired)
	check(absf(fired_at_y - 600.0) <= 14.0, "조준 시 적 깊이에 맞춤 (%.0f, 허용 ±14 = 화살 반폭 4 + 적 반두께 10)" % fired_at_y)
	check(not moved_after_aim, "조준 중 이동·방향 변경 없음(방향·깊이 고정)")
	check(hits[0] >= 1 and e.total_damage_taken == hits[0] * 7, "화살 명중 %d회, 피해 %d" % [hits[0], e.total_damage_taken])
	check(c.floor_pos.x < e.floor_pos.x - 150.0, "적 옆까지 파고들지 않음 (%.0f vs %.0f)" % [c.floor_pos.x, e.floor_pos.x])
	# 사격 간격 1.5초 = 90틱
	var shots0 := c.shots_fired
	idle(b, 60)
	check(c.shots_fired <= shots0 + 1, "1초 동안 추가 사격 ≤ 1")
	# 사거리 밖: 사격 없음, 투사체는 360px 안에서 종료
	place(e, c.floor_pos.x + 500.0, c.floor_pos.y)
	shots0 = c.shots_fired
	idle(b, 120)
	check(c.shots_fired == shots0, "사거리 360 밖에서는 사격하지 않음")
	b.queue_free()

func test_archer_arrow_does_not_break_hitstun_and_passes_ally() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_arrow", aya, 20.0, 100)
	for sp in b.pending_spawns:
		sp.ticks = 100000
	var c: ArcherCompanion = b.companion
	var p := b.player
	var e := b.spawn_melee_enemy(Vector2(700, 540))
	e.max_hp = 100000
	e.hp = e.max_hp
	# 주인공의 3타로 경직·밀림 중인 적
	place(p, 625, 540)
	var info := HitInfo.new()
	info.attack = p.light_attacks[2]
	info.damage = 28
	info.hitstop_ticks = 0
	info.direction = 1
	e.receive_hit(info)
	check(e.state == &"hitstun" and e.knockback_total == 65.0, "적이 3타 경직·밀림 중")
	var hs := e.hitstun_ticks
	var kb := e.knockback_total
	# 화살이 주인공(아군)을 지나 적에게 닿는다
	place(c, 500, 540)
	c.cooldown_ticks = 100000
	var pr := Projectile.new()
	pr.setup(&"player", c, c.arrow, 7.0, Vector2(520, 540), 35.0, 1, 600.0, 360.0, 36, 4.0, 4.0)
	b.add_projectile(pr)
	var php := p.hp
	var hit_tick := -1
	for i in 30:
		b.step(PlayerInput.make())
		if e.total_damage_taken >= 35 and hit_tick < 0:
			hit_tick = i
	check(p.hp == php, "화살은 아군을 관통 (주인공 피해 없음)")
	check(e.total_damage_taken == 35, "화살 적중 피해 7 (합계 %d)" % e.total_damage_taken)
	check(e.hitstun_ticks == hs and e.knockback_total == kb, "화살은 경직·밀림을 바꾸지 않음")
	check(p.hitstop_ticks == 0, "원거리 적중이 주인공 히트스톱을 만들지 않음")
	check(b.projectiles.is_empty(), "명중 후 투사체 제거")
	# 높이 불일치: 떠 있는 적(높이 200)은 화살(35±4)에 맞지 않는다
	e.total_damage_taken = 0
	e.change_state(&"launched")
	e.airborne_by_launch = true
	var pr2 := Projectile.new()
	pr2.setup(&"player", c, c.arrow, 7.0, Vector2(600, 540), 35.0, 1, 600.0, 360.0, 36, 4.0, 4.0)
	b.add_projectile(pr2)
	for i in 30:
		e.height = 200.0
		e.vz = 0.0
		b.step(PlayerInput.make())
	check(e.total_damage_taken == 0, "높이 200 의 적은 화살에 맞지 않음")
	# 깊이 불일치
	e.change_state(&"idle")
	e.height = 0.0
	e.airborne_by_launch = false
	place(e, 700, 580)
	var pr3 := Projectile.new()
	pr3.setup(&"player", c, c.arrow, 7.0, Vector2(600, 540), 35.0, 1, 600.0, 360.0, 36, 4.0, 4.0)
	b.add_projectile(pr3)
	idle(b, 30)
	check(e.total_damage_taken == 0, "깊이 40 차이의 적은 화살에 맞지 않음")
	b.queue_free()

func test_scenario_5_archer_last_kill_wins_and_reward_120() -> void:
	var c := make_controller()
	c.new_game()
	win(c, &"ch1_farm")
	c.repair(&"ch1_farm")
	c.buy_facility(&"ch1_farm")
	win(c, &"ch1_store")
	c.repair(&"ch1_store")
	c.buy_facility(&"ch1_store")
	win(c, &"ch1_pass")
	check(c.state.currency == 100 and c.state.is_companion_unlocked(&"aya"), "초소까지 클리어, 군자금 100")
	var sel := c.select_companion(&"aya")
	check(sel.ok and sel.saved and c.selected_companion() != null, "아야 선택 저장")
	var br := c.begin_run(&"ch1_farm")
	check(br.ok and c.current_run.companion_id == "aya", "아야와 농촌 재도전 출정")
	var b: Battle = await make_battle()
	b.start_encounter(data.site(&"ch1_farm"), br.run_id, c.selected_companion(), c.player_attack_power(20.0), c.player_max_hp(100))
	check(is_equal_approx(b.player.attack_power, 21.0) and b.player.max_hp == 110 and b.player.hp == 110, "출정 시 공격력 21, 체력 110/110")
	check(b.companion != null and b.companion.hp == 60, "동료 체력 가득")
	var comp: ArcherCompanion = b.companion
	# 묶음 1 처치, 묶음 2 는 마지막 1명을 화살로 처치
	flush_spawns(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	flush_spawns(b)
	var alive := b.alive_enemies()
	kill(alive[0])
	var last := alive[1]
	last.hp = 5
	place(b.player, 300, 540)
	b.player.invuln_ticks = 100000
	place(last, 700, 540)
	last.state = &"idle"
	last.state_ticks = -100000
	place(comp, 450, 540)
	comp.cooldown_ticks = 0
	var resolved := [""]
	b.resolved.connect(func(o, _r): resolved[0] = String(o))
	for i in 200:
		b.step(PlayerInput.make())
		if b.result_state != &"active":
			break
		last.state = &"idle"
		last.state_ticks = -100000
	check(not last.alive and comp.shots_fired >= 1 and resolved[0] == "victory", "동료의 마지막 화살로 처치 → 승리 (사격 %d)" % comp.shots_fired)
	var res := c.resolve_run(b.run_id, b.outcome)
	check(res.status == "committed" and res.reward == 20 and c.state.currency == 120, "재도전 승리 후 군자금 %d == 120" % c.state.currency)
	b.queue_free()

func test_scenario_6_companion_death_and_recovery() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_comp_die", aya, 20.0, 100)
	flush_spawns(b)
	var comp: ArcherCompanion = b.companion
	comp.hp = 5
	place(comp, 600, 540)
	var e := b.enemies[0]
	place(e, 660, 540)
	e.facing = -1
	e.change_state(&"attack")
	idle(b, 2)
	check(not comp.alive and not comp.visible, "동료 체력 0 → 이탈")
	check(b.result_state == &"active" and b.player.alive, "동료 이탈만으로 패배하지 않음")
	check(not b.alive_allies().has(comp), "이탈한 동료는 대상 목록에서 제외")
	# 주인공 사망 → 패배
	b.player.hp = 5
	place(b.player, 600, 540)
	e.change_state(&"idle")
	idle(b, 1)
	place(e, 660, 540)
	e.facing = -1
	e.change_state(&"attack")
	idle(b, 2)
	check(b.result_state == &"resolved" and b.outcome == &"defeat", "주인공 체력 0 → 패배")
	b.queue_free()
	# 다음 출정: 동료 회복
	var b2: Battle = await make_battle()
	b2.start_encounter(farm, "run_comp_next", aya, 20.0, 100)
	check(b2.companion.alive and b2.companion.hp == 60, "다음 출정에서 동료 회복 (체력 %d)" % b2.companion.hp)
	b2.queue_free()

func test_enemy_targets_nearest_ally_and_locks_on_telegraph() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_target", aya, 20.0, 100)
	for sp in b.pending_spawns:
		sp.ticks = 100000
	var comp: ArcherCompanion = b.companion
	var p := b.player
	p.invuln_ticks = 100000
	comp.invuln_ticks = 100000
	place(p, 200, 540)
	place(comp, 700, 600)
	comp.cooldown_ticks = 100000
	var e := b.spawn_melee_enemy(Vector2(900, 600))
	e.state = &"idle"
	e.state_ticks = 100
	var locked_target: BattleActor = null
	var lock_facing := 0
	var changed := false
	for i in 300:
		b.step(PlayerInput.make())
		# 동료를 제자리에 고정
		place(comp, 700, 600)
		if e.state == &"telegraph":
			if locked_target == null:
				locked_target = e.target
				lock_facing = e.facing
				# 예고 중 주인공을 적 바로 옆으로 옮겨도 대상·방향이 바뀌지 않아야 한다
				place(p, e.floor_pos.x + 60, e.floor_pos.y)
			elif e.target != locked_target or e.facing != lock_facing:
				changed = true
		if e.state == &"recover":
			break
	check(locked_target == comp, "가까운 아군(동료)을 대상으로 선택")
	check(not changed, "예고 시작 후 대상·방향 고정")
	# 대상 사망 후 참조 오류 없이 재선택
	kill(comp)
	e.change_state(&"idle")
	e.state_ticks = 100
	place(p, 760, 600)
	var retargeted := false
	for i in 200:
		b.step(PlayerInput.make())
		if e.state == &"telegraph" and e.target == p:
			retargeted = true
			break
	check(retargeted, "동료 사망 후 주인공으로 재선택")
	b.queue_free()

func test_scenario_12_dev_keys_ignored_in_campaign() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	b.start_encounter(farm, "run_dev", null, 20.0, 100)
	flush_spawns(b)
	var n := b.enemies.size()
	b.player.hp = 30
	place(b.player, 400, 600)
	# 개발 키를 눌러도 캠페인에서는 무시된다
	Input.action_press(&"dev_respawn_enemies")
	Input.action_press(&"dev_reset_player")
	Input.action_press(&"dev_toggle_profile")
	b._handle_dev_input()
	Input.action_release(&"dev_respawn_enemies")
	Input.action_release(&"dev_reset_player")
	Input.action_release(&"dev_toggle_profile")
	check(b.enemies.size() == n and b.player.hp == 30 and b.player.floor_pos == Vector2(400, 600), "캠페인에서 F5/F6 무시")
	check(not b.set_profile(0) and b.player.profile_id == &"r1_momentum", "캠페인은 새 프로필 고정")
	b.queue_free()
	# 수련장에서는 동작
	var t: Battle = await make_battle(&"training")
	t.player.hp = 30
	Input.action_press(&"dev_reset_player")
	t._handle_dev_input()
	Input.action_release(&"dev_reset_player")
	check(t.player.hp == t.player.max_hp, "수련장에서 F6 동작")
	t.queue_free()

# ------------------------------------------------------------------ 화면 흐름

func test_game_screens_smoke() -> void:
	var scene: PackedScene = load(MAIN_SCENE)
	var g: Game = scene.instantiate()
	root.add_child(g)
	await process_frame
	g.campaign = CampaignController.new(TEST_SAVE, data)
	g.show_title()
	await process_frame
	check(g.current_screen == "title" and g.screen_root.get_child_count() > 0, "시작 화면 표시")
	g._start_new_game()
	await process_frame
	check(g.current_screen == "map" and g.campaign.state.currency == 0, "새 게임 → 지도")
	# 출정 → 전투 장면 → 결과 → 관리 → 정비/훈련장 → 동료 흐름
	g.start_battle(&"ch1_farm")
	await process_frame
	check(g.current_screen == "battle" and g.battle != null and g.battle.mode == &"campaign" and g.battle.encounter.id == &"ch1_farm", "농촌 출정: 캠페인 전투 장면")
	g.battle.manual_step = true
	var b := g.battle
	flush_spawns(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	flush_spawns(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	await process_frame
	check(b.result_state == &"resolved" and g.last_result.status == "committed" and g.campaign.state.currency == 100, "승리 → 결과 확정·저장 (군자금 %d)" % g.campaign.state.currency)
	check(g.overlay_root.get_child_count() > 0, "결과 창 표시")
	g._after_result()
	await process_frame
	check(g.current_screen == "map", "확인 → 지도")
	g.show_manage(&"ch1_farm")
	await process_frame
	check(g.current_screen == "manage", "관리 화면")
	g._do_repair(&"ch1_farm")
	await process_frame
	check(g.campaign.state.management(&"ch1_farm") == 60, "관리 화면 정비")
	g._do_buy(&"ch1_farm")
	await process_frame
	check(g.campaign.state.has_facility(&"training_ground") and g.campaign.state.currency == 0, "관리 화면 훈련장 구매")
	g.show_manage(&"ch1_pass")
	await process_frame
	check(g.current_screen == "map", "초소는 관리 화면 없음 → 지도")
	g.show_companions()
	await process_frame
	check(g.current_screen == "companions", "동료 선택 화면")
	g.show_join("aya")
	await process_frame
	check(g.current_screen == "join", "합류 화면")
	# 저장 실패 결과 창
	g.show_map()
	g.campaign.store.fail_next_write = true
	g.start_battle(&"ch1_farm")
	await process_frame
	g.battle.manual_step = true
	b = g.battle
	flush_spawns(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	flush_spawns(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	await process_frame
	check(g.last_result.status == "unsaved" and g.campaign.has_pending(), "저장 실패 결과 창 (unsaved)")
	g._retry_pending_from_result()
	await process_frame
	check(g.last_result.status == "committed" and g.campaign.state.currency == 20, "결과 창 저장 재시도 → 반영 (군자금 %d)" % g.campaign.state.currency)
	g._after_result()
	await process_frame
	# 수련장은 저장을 건드리지 않는다
	var before := FileAccess.get_file_as_string(TEST_SAVE)
	g.start_training()
	await process_frame
	check(g.current_screen == "training" and g.battle.mode == &"training", "수련장 시작")
	g.battle.manual_step = true
	press(g.battle, "attack_light")
	idle(g.battle, 30)
	g.show_title()
	await process_frame
	check(FileAccess.get_file_as_string(TEST_SAVE) == before, "수련장 뒤 저장 파일 불변")
	g.queue_free()
	await process_frame
