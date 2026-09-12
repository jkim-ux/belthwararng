extends SceneTree
## HWR-002 R1 + HWR-003 캠페인 자동 검증. 실행: godot --headless --path game -s tests/run_campaign_tests.gd
## 테스트용 저장 경로(user://test_saves/)만 사용하며 사용자 저장(user://campaign_save.json)은 건드리지 않는다.
## CAMPAIGN_SYSTEMS 7절 인수 시나리오(승리 = 보스 처치)와 DUNGEON_COMBAT 8절 필수 검수 1~10 을 상태·저장·전투·화면 수준에서 확인한다.
## 실패가 있으면 종료 코드 1.

const BATTLE_SCENE := "res://scenes/battle.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const TEST_SAVE := "user://test_saves/hwr002_test.json"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var data: CampaignData
var fight_reports: Array[String] = []     ## 실전 자동 플레이 측정(보고용)

func _initialize() -> void:
	print("=== HWR-002 R1 / HWR-003 캠페인 검증 시작 (Godot %s) ===" % Engine.get_version_info().string)
	data = load(CampaignController.DATA_PATH)
	await process_frame
	var tests := [
		"test_campaign_data_definitions",
		"test_scenario_1_to_4_progression_and_reload",
		"test_scenario_7_8_rejections_and_no_reset",
		"test_scenario_11_save_failure_retry_backup",
		"test_load_cleans_locked_companion_and_rejects_schema",
		"test_d1_room_two_waves_lock_and_clear_is_not_victory",
		"test_d2_room_revisit_door_targets_and_single_transition",
		"test_d3_room_transition_preserves_hp_cooldowns_and_clears_transients",
		"test_d4_enemy_archer_aim_lock_height_depth_sweep_and_shared_slot",
		"test_d5_thrower_telegraph_landing_cancel_death_and_cap",
		"test_d6_fire_damage_timing_overlap_jump_dodge_no_hitstun",
		"test_d7_companion_avoids_fire_and_last_kill_results",
		"test_d8_chest_once_heal_pending_and_rewards",
		"test_d9_boss_only_clears_and_same_tick_death_is_defeat",
		"test_scenario_9_dummy_and_ally_not_counted",
		"test_attack_slot_limit_two",
		"test_captain_two_patterns_and_super_armor",
		"test_archer_follows_fires_and_hits",
		"test_archer_arrow_does_not_break_hitstun_and_passes_ally",
		"test_scenario_5_archer_last_kill_wins_and_reward_120",
		"test_scenario_6_companion_death_and_recovery",
		"test_enemy_targets_nearest_ally_and_locks_on_telegraph",
		"test_scenario_12_dev_keys_ignored_in_campaign",
		"test_real_fight_three_sites_two_strategies",
		"test_game_screens_smoke",
		# --- HWR-004 R1
		"test_h4_1_enemy_damage_doubled_on_every_path",
	]
	for t in tests:
		await _run(t)
	_cleanup_saves()
	print("=== 결과: 통과 %d, 실패 %d ===" % [_pass, _fail])
	for f in _failures:
		print("  FAIL: ", f)
	if not fight_reports.is_empty():
		print("=== 실전 자동 플레이 측정 ===")
		for line in fight_reports:
			print(line)
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

## 경직만 주는 타격(피해 1)
func stagger(e: BattleActor) -> void:
	var info := HitInfo.new()
	info.attack = AttackData.new()
	info.attack.hitstun_ms = 300.0
	info.damage = 1
	info.hitstop_ticks = 0
	info.direction = 1
	e.receive_hit(info)

## 승리까지 진행한 컨트롤러 결과를 돌려주는 도우미(전투 없이 상태만).
func win(c: CampaignController, site_id: StringName) -> Dictionary:
	var r := c.begin_run(site_id)
	if not r.ok:
		return {"ok": false, "status": "rejected", "reason": r.reason, "reward": 0}
	return c.resolve_run(r.run_id, &"victory")

## 방 전이가 끝날 때까지 진행
func settle(b: Battle) -> void:
	var guard := 0
	while b.transition_ticks > 0 and guard < 200:
		b.step(PlayerInput.make())
		guard += 1

func door_dir_to(b: Battle, room_id: StringName) -> StringName:
	for door in b.dungeon.doors_of(b.room):
		if door.target_id == room_id:
			return door.dir
	return &""

## 열린 문으로 이동: 문 구역에 서서 Enter 를 새로 누른다. 전이는 끝내지 않는다(성공 시 room 이 바뀐 상태).
func enter_no_settle(b: Battle, room_id: StringName) -> bool:
	var dir := door_dir_to(b, room_id)
	if dir == &"":
		return false
	var z := b.door_zone(dir)
	place(b.player, z.get_center().x, z.get_center().y)
	if b.player.alive and b.player.state != &"ground":
		b.player.change_state(&"ground")
	b.step(PlayerInput.make())
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	return b.room.id == room_id

func enter(b: Battle, room_id: StringName) -> bool:
	var ok := enter_no_settle(b, room_id)
	settle(b)
	return ok

## 현재 전투방을 웨이브·간격 포함 모두 처치해 정리한다(보스방이면 승리).
func clear_room(b: Battle) -> void:
	var guard := 0
	while b.doors_locked and b.result_state == &"active" and guard < 40:
		guard += 1
		if not b.pending_spawns.is_empty():
			flush_spawns(b)
		for e in b.alive_enemies():
			kill(e)
		idle(b, 1)
		if b.doors_locked and b.pending_spawns.is_empty() and b.required_alive_count() == 0 and b.wave_index < b.total_waves():
			idle(b, b.wave_gap_ticks + 1)

## 입구에서 보스방 출현까지(보물방 생략)
func to_boss(b: Battle) -> void:
	settle(b)
	enter(b, &"battle_1")
	clear_room(b)
	enter(b, &"battle_2")
	clear_room(b)
	enter(b, &"battle_3")
	clear_room(b)
	enter(b, &"boss")
	flush_spawns(b)

func dungeon_win(b: Battle) -> void:
	to_boss(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)

func count_of(arr: Array, cls) -> int:
	var n := 0
	for e in arr:
		if is_instance_of(e, cls):
			n += 1
	return n

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
	check(farm.is_village() and store.is_village() and not pass_site.is_village() and pass_site.facility == null, "농촌·창고 마을, 초소 fort·시설 없음")
	check(store.prerequisite_site_id == &"ch1_farm" and store.prerequisite_management == 60 and pass_site.prerequisite_site_id == &"ch1_store", "선행 조건 농촌 60 → 창고 60 → 초소")
	check(farm.facility.id == &"training_ground" and farm.facility.cost == 60 and store.facility.id == &"supply_depot" and store.facility.cost == 60, "훈련장/보급창 60")
	check(farm.first_reward == 100 and farm.repeat_reward == 20 and farm.repair_cost == 40, "보상 100/20, 정비 40")
	# 던전: 6방, 연결 대칭, 웨이브 수, 적 수, 보스
	var expected := {&"ch1_farm": [21, "징발대장", 450], &"ch1_store": [23, "보급대장", 550], &"ch1_pass": [24, "초소 대장", 600]}
	for s in data.sites:
		var d: DungeonDef = s.dungeon
		check(d != null and d.rooms.size() == 6, "%s: 6방" % s.id)
		check(d.validate().is_empty(), "%s: 연결·웨이브 정의 정상 %s" % [s.id, str(d.validate())])
		var ex: Array = expected[s.id]
		check(d.enemy_count() == ex[0], "%s: 일반 적 %d == %d" % [s.id, d.enemy_count(), ex[0]])
		check(d.boss_display_name == ex[1] and d.boss_max_hp == ex[2], "%s: 보스 %s %d" % [s.id, d.boss_display_name, d.boss_max_hp])
		check(d.chest_currency == 30 and is_equal_approx(d.chest_heal_ratio, 0.2), "%s: 상자 30 / 20%%" % s.id)
		var kinds := {}
		for r in d.rooms:
			if r.kind == &"battle":
				check(r.waves.size() == 2, "%s/%s: 2웨이브" % [s.id, r.id])
			for w in r.waves:
				check(w.enemy_kinds.size() <= 5 and w.spawn_positions.size() == w.enemy_kinds.size(), "%s/%s: 동시 출현 ≤5, 위치 수 일치" % [s.id, r.id])
				for k in w.enemy_kinds:
					kinds[k] = true
		check(kinds.has(&"melee") and kinds.has(&"archer") and kinds.has(&"thrower") and kinds.has(&"boss"), "%s: 근접·궁수·투척·보스 모두 배치" % s.id)
		var b2 := d.room(&"battle_2")
		var tr_conn: Array[StringName] = d.room(&"treasure").connections
		check(b2 != null and b2.connections.has(&"treasure") and tr_conn.size() == 1 and tr_conn[0] == &"battle_2", "%s: 보물방은 전투 2 에서만 갈림" % s.id)
		check(d.direction_between(d.room(&"battle_2"), d.room(&"treasure")) == &"north" and d.direction_between(d.room(&"entry"), d.room(&"battle_1")) == &"east", "%s: 문 방향(북/동)" % s.id)

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

# ------------------------------------------------------------------ DUNGEON_COMBAT 필수 검수 1~9

## 1. 일반 방마다 정확히 2웨이브, 웨이브 간 문 잠금, 출현 중인 적 때문에 승리/정리가 조기 발생하지 않음 (+9 일부)
func test_d1_room_two_waves_lock_and_clear_is_not_victory() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var resolved_count := [0]
	var cleared_rooms: Array = []
	b.resolved.connect(func(_o, _rid): resolved_count[0] += 1)
	b.room_cleared.connect(func(rid): cleared_rooms.append(rid))
	b.start_encounter(farm, "run_rooms", null, 20.0, 100)
	check(b.room != null and b.room.id == &"entry" and not b.doors_locked and b.pending_spawns.is_empty(), "입구: 안전한 방, 출현 없음")
	check(b.transition_ticks == Ticks.from_ms(300), "진입 전이 %d틱" % b.transition_ticks)
	settle(b)
	check(b.pending_spawns.is_empty() and b.enemies.is_empty(), "입구는 0웨이브")
	check(enter_no_settle(b, &"battle_1"), "동쪽 문 → 전투 1")
	check(b.transition_ticks > 0 and not b.doors_locked and b.pending_spawns.is_empty(), "전이 중에는 아직 예고 없음")
	settle(b)
	check(b.doors_locked and b.pending_spawns.size() == 3 and b.wave_index == 1 and b.total_waves() == 2, "전이 후 문 잠금, 1웨이브 예고 3")
	check(b.enemies.is_empty() and b.result_state == &"active" and not b.is_room_cleared(&"battle_1"), "예고 중 적 0 이지만 정리·승리 아님")
	# 잠긴 문: Enter 로 이동 불가
	var z := b.door_zone(&"east")
	place(b.player, z.get_center().x, z.get_center().y)
	idle(b, 1)
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b.room.id == &"battle_1" and b.doors_locked, "잠긴 문에서 Enter → 이동 없음")
	place(b.player, 200, 545)
	idle(b, Ticks.from_ms(700) - 2)
	check(b.required_alive_count() == 3 and b.pending_spawns.is_empty(), "1웨이브 출현 3 (근접 3)")
	for e in b.enemies:
		check(absf(e.floor_pos.x - b.player.floor_pos.x) >= 120.0, "등장 위치가 플레이어와 겹치지 않음 (%.0f)" % e.floor_pos.x)
	var es := b.alive_enemies()
	kill(es[0])
	kill(es[1])
	idle(b, 1)
	check(b.doors_locked and b.wave_index == 1 and b.pending_spawns.is_empty(), "1명 남았을 때 다음 웨이브 없음")
	kill(es[2])
	idle(b, 1)
	check(b.doors_locked and b.pending_spawns.is_empty() and b.required_alive_count() == 0 and not b.is_room_cleared(&"battle_1"), "1웨이브 전멸 직후: 적 0 이지만 문 잠금 유지(간격), 정리 아님")
	var gap := Ticks.from_ms(1000)
	idle(b, gap - 2)
	check(b.pending_spawns.is_empty() and b.doors_locked, "간격 중 예고 없음, 문 잠금")
	idle(b, 1)
	check(b.pending_spawns.size() == 3 and b.wave_index == 2, "전멸 1초 뒤 2웨이브 예고 3")
	var kinds: Array = []
	for sp in b.pending_spawns:
		kinds.append(sp.kind)
	check(kinds == [&"melee", &"melee", &"archer"], "2웨이브 구성 근접 2 + 궁수 1 (%s)" % str(kinds))
	flush_spawns(b)
	check(b.required_alive_count() == 3 and count_of(b.alive_enemies(), ArcherEnemy) == 1, "2웨이브 출현: 궁수 포함")
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	check(b.is_room_cleared(&"battle_1") and not b.doors_locked and b.result_state == &"active", "2웨이브 전멸 → 방 정리·문 개방, 거점 승리 아님")
	check(cleared_rooms == [&"battle_1"] and resolved_count[0] == 0, "room_cleared 1회, resolved 0회")
	idle(b, 30)
	check(cleared_rooms.size() == 1 and b.pending_spawns.is_empty(), "정리 후 추가 웨이브·중복 이벤트 없음")
	# 나머지 방을 지나 보스 처치 → 승리 1회
	enter(b, &"battle_2")
	clear_room(b)
	enter(b, &"battle_3")
	clear_room(b)
	check(cleared_rooms.size() == 3 and resolved_count[0] == 0, "일반 방 3개 정리, 아직 승리 아님")
	enter(b, &"boss")
	check(b.doors_locked and b.pending_spawns.size() == 1 and b.total_waves() == 1, "보스방: 예고 1(보스), 추가 웨이브 없음")
	flush_spawns(b)
	var boss := b.boss_enemy()
	check(boss != null and boss.alive and boss.display_name == "징발대장" and boss.max_hp == 450, "농촌 보스 징발대장 450 (%s %d)" % [boss.display_name if boss else "", boss.max_hp if boss else 0])
	check(b.alive_enemies().size() == 1, "보스 외 잡몹 없음")
	kill(boss)
	idle(b, 1)
	check(b.result_state == &"resolved" and b.outcome == &"victory" and resolved_count[0] == 1, "보스 처치 → 승리 1회")
	var t := b.tick
	idle(b, 10)
	check(b.tick == t and resolved_count[0] == 1 and cleared_rooms.size() == 3, "확정 후 진행 정지, 이벤트 반복 없음")
	b.queue_free()

## 2. 정리한 방 재입장 시 적/상자 재생성 없음, 문 목적지와 연결 데이터 일치, Enter 연타/유지로 중복 전이 없음
func test_d2_room_revisit_door_targets_and_single_transition() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var entered: Array = []
	b.room_entered.connect(func(rid): entered.append(rid))
	b.start_encounter(farm, "run_revisit", null, 20.0, 100)
	settle(b)
	enter(b, &"battle_1")
	clear_room(b)
	# 문 목적지 = 연결 데이터, 방향 = 격자 인접
	for door in b.dungeon.doors_of(b.room):
		var other: RoomDef = b.dungeon.room(door.target_id)
		check(b.room.connections.has(door.target_id) and b.dungeon.direction_between(b.room, other) == door.dir, "문 %s → %s 연결 데이터 일치" % [door.dir, door.target_id])
	check(b.dungeon.doors_of(b.room).size() == 2, "전투 1 문 2개(서·동)")
	# 입구로 되돌아갔다가 재입장: 적·예고 없음, 문 열림
	check(enter(b, &"entry") and b.room.id == &"entry" and b.enemies.is_empty(), "서쪽 문으로 입구 복귀")
	check(enter(b, &"battle_1"), "전투 1 재입장")
	check(b.enemies.is_empty() and b.pending_spawns.is_empty() and not b.doors_locked and b.is_room_cleared(&"battle_1"), "재입장: 적·예고 재생성 없음, 문 열림")
	check(b.player.floor_pos == b.entry_point(&"west") and b.player.facing == 1, "서쪽 문 안쪽 안전 지점에 배치 (%s)" % str(b.player.floor_pos))
	# 갈림길 → 보물방 → 되돌아오기
	enter(b, &"battle_2")
	clear_room(b)
	check(b.dungeon.doors_of(b.room).size() == 3, "전투 2 문 3개(서·동·북)")
	check(enter(b, &"treasure") and b.room.kind == &"treasure" and b.chest != null and not b.chest.opened, "북쪽 문 → 보물방, 상자 있음")
	check(b.player.floor_pos == b.entry_point(&"south"), "보물방은 남쪽 문 안쪽에서 시작")
	check(enter(b, &"battle_2") and b.enemies.is_empty() and not b.doors_locked, "보물방 → 전투 2 복귀: 적 재생성 없음")
	check(b.player.floor_pos == b.entry_point(&"north"), "북쪽 문 안쪽 안전 지점")
	# Enter 유지: 문 구역에서 계속 눌러도 1회만 이동
	var before := entered.size()
	var dir := door_dir_to(b, &"battle_3")
	var z := b.door_zone(dir)
	place(b.player, z.get_center().x, z.get_center().y)
	idle(b, 1)
	for i in 30:
		b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b.room.id == &"battle_3" and entered.size() == before + 1, "Enter 유지 30틱 → 전이 1회 (%d)" % (entered.size() - before))
	settle(b)
	check(b.doors_locked and b.pending_spawns.size() == 4, "전투 3 첫 진입: 문 잠금, 1웨이브 예고 4")
	# 전이 중 Enter 무시: 정리 후 다시 문 앞에서 이동을 시작하고 전이 중 새 Enter
	clear_room(b)
	before = entered.size()
	check(enter_no_settle(b, &"battle_2"), "전투 3 → 전투 2 이동 시작")
	b.step(PlayerInput.make())
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b.transition_ticks > 0 and b.room.id == &"battle_2" and entered.size() == before + 1, "전이 중 새 Enter 무시")
	settle(b)
	# 공중·공격 중에는 문을 쓸 수 없다
	dir = door_dir_to(b, &"battle_3")
	z = b.door_zone(dir)
	place(b.player, z.get_center().x, z.get_center().y)
	press(b, "jump")
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b.player.state == &"air" and b.room.id == &"battle_2", "공중에서는 문 이동 불가")
	idle(b, 60)
	place(b.player, z.get_center().x, z.get_center().y)
	press(b, "attack_light")
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b.player.state == &"light" and b.room.id == &"battle_2", "평타 중에는 문 이동 불가")
	b.queue_free()

## 3. 방 이동 후 주인공 HP/스킬·회피 대기/생존 동료 HP·이탈 유지, 공격/불/투사체는 이동하지 않음
func test_d3_room_transition_preserves_hp_cooldowns_and_clears_transients() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_keep", aya, 20.0, 100)
	settle(b)
	enter(b, &"battle_1")
	clear_room(b)
	var p := b.player
	var comp: ArcherCompanion = b.companion
	p.hp = 57
	comp.hp = 33
	comp.cooldown_ticks = 77
	press(b, "skill_a")
	idle(b, 40)
	press(b, "dodge")
	idle(b, 15)
	check(p.state == &"ground" and p.cooldowns[&"bieonchan"] > 0 and p.dodge_cooldown_ticks > 0, "스킬·회피 대기시간 진행 중")
	# 떠나는 방에 불·항아리·적 화살·예고를 남긴다
	b._spawn_fire(Vector2(500, 545))
	b.throw_fire_pot(Vector2(900, 545), Vector2(700, 545))
	var pr := Projectile.new()
	pr.setup(&"enemy", null, AttackData.new(), 8.0, Vector2(1000, 545), 35.0, -1, 650.0, 560.0, 90, 4.0, 8.0)
	b.add_projectile(pr)
	place(p, 500, 545)
	idle(b, 3)
	check(not b.fires.is_empty() and not b.pots.is_empty() and not b.projectiles.is_empty() and not b.fire_clocks.is_empty(), "불·항아리·적 화살·불 시계 존재")
	var cd_before: int = p.cooldowns[&"bieonchan"]
	var dodge_before := p.dodge_cooldown_ticks
	var comp_cd_before := comp.cooldown_ticks
	check(enter_no_settle(b, &"battle_2"), "전투 2 로 이동 시작")
	# enter_no_settle 은 일반 틱 1개 + Enter 틱(전이 시작, 진행 없음)을 진행한다 → 대기시간은 정확히 1 줄어 있어야 한다
	check(p.cooldowns[&"bieonchan"] == cd_before - 1 and p.dodge_cooldown_ticks == dodge_before - 1, "이동 직전까지 일반 틱에서만 대기시간 감소 (Enter 틱부터 정지)")
	var cd_mid: int = p.cooldowns[&"bieonchan"]
	var comp_cd_mid := comp.cooldown_ticks
	settle(b)
	check(p.cooldowns[&"bieonchan"] == cd_mid and p.dodge_cooldown_ticks == dodge_before - 1 and comp.cooldown_ticks == comp_cd_mid, "전이 %d틱 동안 대기시간 정지" % Ticks.from_ms(300))
	check(comp_cd_before - comp_cd_mid == 1, "동료 발사 대기시간도 전이 중 정지")
	check(p.hp == 57 and p.max_hp == 100, "주인공 체력 57 유지(회복 없음)")
	check(comp.alive and comp.hp == 33 and comp.state == &"follow" and comp.velocity == Vector2.ZERO, "동료 체력 33 유지, 따라가기 상태 (alive %s hp %d state %s vel %s)" % [str(comp.alive), comp.hp, comp.state, str(comp.velocity)])
	check(b.fires.is_empty() and b.pots.is_empty() and b.projectiles.is_empty() and b.fire_clocks.is_empty() and b.pending_spawns.size() == 3, "불·항아리·투사체·시계 이동 없음, 새 방 예고 3")
	check(p.active_hitboxes.is_empty() and p.buffered_action == &"" and p.velocity == Vector2.ZERO and p.knockback_remaining == 0.0, "공격 판정·보관 입력·이동량 정리")
	check(comp.floor_pos.distance_to(p.floor_pos) < 120.0 and not b.is_in_fire(comp.floor_pos), "동료는 주인공 근처에 배치")
	for sp in b.pending_spawns:
		check(sp.pos.distance_to(p.floor_pos) > 150.0, "새 방 출현 예고가 플레이어와 겹치지 않음 (%.0f)" % sp.pos.distance_to(p.floor_pos))
	# 이탈한 동료는 다음 방에서 부활하지 않는다
	kill(comp)
	idle(b, 1)
	check(not comp.alive and not b.alive_allies().has(comp), "동료 이탈")
	clear_room(b)
	enter(b, &"battle_3")
	check(not comp.alive and not comp.visible and not b.alive_allies().has(comp) and b.result_state == &"active", "방 이동 후에도 이탈 유지, 패배 아님")
	b.queue_free()
	# 새 출정에서만 회복
	var b2: Battle = await make_battle()
	b2.start_encounter(farm, "run_keep_2", aya, 20.0, 100)
	check(b2.player.hp == 100 and b2.companion.alive and b2.companion.hp == 60 and b2.player.cooldowns[&"bieonchan"] == 0, "새 출정: 체력·동료·대기시간 초기화")
	b2.queue_free()

## 4. 궁수 조준 고정·높이·깊이·아군 팀 구분·고속 투사체 이동 구간 적중, 원거리 허가 공유 1, 예고 중 경직 취소, 짧은 후퇴
func test_d4_enemy_archer_aim_lock_height_depth_sweep_and_shared_slot() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	b.start_encounter(farm, "run_archer_enemy", null, 20.0, 100)
	settle(b)
	var p := b.player
	var a := b.spawn_archer_enemy(Vector2(900, 545))
	check(a.max_hp == 55 and a.required_for_victory, "적 궁수 체력 55")
	place(p, 400, 545)
	a.cooldown_ticks = 0
	var aim_seen := false
	var aim_y := -1.0
	var aim_facing := 0
	var moved_while_aim := false
	var prev: StringName = a.state
	var fired: Projectile = null
	for i in 240:
		b.step(PlayerInput.make())
		if a.state == &"aim":
			if prev != &"aim":
				aim_seen = true
				aim_y = a.aim_y
				aim_facing = a.aim_facing
				# 예고 시작 뒤 주인공이 깊이를 바꿔도 사격선은 고정
				place(p, 400, 620)
			elif a.aim_y != aim_y or a.aim_facing != aim_facing or a.facing != aim_facing:
				moved_while_aim = true
		if a.state == &"recover" and fired == null and not b.projectiles.is_empty():
			fired = b.projectiles[0]
			break
		prev = a.state
	check(aim_seen and not moved_while_aim, "예고 중 방향·깊이 고정")
	check(fired != null and fired.team == &"enemy" and is_equal_approx(fired.floor_pos.y, aim_y) and fired.facing == -1 and is_equal_approx(absf(fired.vx), 650.0), "적 화살: 팀 enemy, 고정 깊이, 650 px/s")
	check(a.shots_fired == 1 and Ticks.to_ms(Ticks.from_ms(650.0)) >= 640.0, "예고 0.65초 뒤 1발")
	var hp0 := p.hp
	idle(b, 70)
	check(p.hp == hp0 and b.projectiles.is_empty(), "깊이를 벗어난 주인공은 맞지 않고 화살은 사거리에서 소멸")
	# 높이: 점프 중(높이 100)에는 맞지 않는다
	place(p, 400, 545)
	a.change_state(&"idle")
	a.cooldown_ticks = 0
	var fired_tick := -1
	for i in 240:
		b.step(PlayerInput.make())
		if a.shots_fired == 2 and fired_tick < 0:
			fired_tick = i
		if fired_tick >= 0:
			p.height = 100.0
			p.vz = 0.0
		if fired_tick >= 0 and b.projectiles.is_empty():
			break
	check(fired_tick >= 0 and p.hp == hp0, "높이 100 의 주인공은 화살(35±4)에 맞지 않음")
	p.height = 0.0
	# 정상 적중: 피해 8 + 기존 단발 피격 규칙(경직)
	a.change_state(&"idle")
	a.cooldown_ticks = 0
	var e_between := b.spawn_melee_enemy(Vector2(650, 545))
	e_between.state = &"idle"
	e_between.state_ticks = -100000
	var ehp := e_between.hp
	for i in 300:
		b.step(PlayerInput.make())
		e_between.state = &"idle"
		e_between.state_ticks = -100000
		if p.hp < hp0:
			break
	check(p.hp == hp0 - 16 and p.state == &"hitstun", "적중: 피해 16 (HWR-004: 8→16), 경직 (체력 %d, %s)" % [p.hp, p.state])
	check(e_between.hp == ehp, "적 화살은 같은 팀(사이의 근접병)을 관통")
	check(b.projectiles.is_empty(), "단일 아군 피해 후 소멸")
	a.cooldown_ticks = 100000
	# 고속 투사체 이동 구간 판정: 한 틱에 200 px 이동해 대상을 지나쳐도 적중
	idle(b, 30)
	place(p, 400, 545)
	p.change_state(&"ground")
	hp0 = p.hp
	var fast := Projectile.new()
	fast.setup(&"enemy", a, a.arrow, float(b.tuning.archer_damage), Vector2(300, 545), 35.0, 1, 12000.0, 560.0, 10, 4.0, 8.0)
	b.add_projectile(fast)
	idle(b, 1)
	check(fast.floor_pos.x >= 490.0 and p.hp == hp0 - 16, "200 px/틱 화살이 이동 구간(300→500)에서 x=400 의 주인공 적중 (체력 %d)" % p.hp)
	# 최대 사거리 마지막 구간도 판정: 남은 거리 5 px 인 화살이 대상에 닿으면 적중
	idle(b, 30)
	place(p, 400, 545)
	p.change_state(&"ground")
	hp0 = p.hp
	var last := Projectile.new()
	last.setup(&"enemy", a, a.arrow, float(b.tuning.archer_damage), Vector2(360, 545), 35.0, 1, 650.0, 12.0, 10, 4.0, 8.0)
	b.add_projectile(last)
	idle(b, 2)
	check(p.hp == hp0 - 16 and b.projectiles.is_empty(), "사거리 12 px 로 끝나는 마지막 구간에서도 적중 후 제거")
	# 원거리 허가 공유 1: 궁수 2명이 같은 깊이 → 동시에 예고하지 않는다
	idle(b, 30)
	p.invuln_ticks = 100000
	place(p, 300, 545)
	var a2 := b.spawn_archer_enemy(Vector2(1000, 545))
	place(a, 800, 545)
	a.change_state(&"idle")
	a.cooldown_ticks = 0
	a2.cooldown_ticks = 0
	var max_aiming := 0
	var waited := false
	var both_fired := false
	for i in 400:
		b.step(PlayerInput.make())
		var n := 0
		for x in [a, a2]:
			if x.state == &"aim":
				n += 1
			if x.waiting_for_slot:
				waited = true
		max_aiming = maxi(max_aiming, n)
		if a.shots_fired > 0 and a2.shots_fired > 0:
			both_fired = true
	check(max_aiming == 1 and waited, "동시 예고 최대 %d == 1, 허가 대기 발생" % max_aiming)
	check(b.ranged_slot_holders.size() <= 1, "원거리 허가 보유 ≤ 1")
	# 예고 중 경직 → 발사 취소·허가 반환
	b.enemies.erase(a2)
	a2.free()
	a.change_state(&"idle")
	a.cooldown_ticks = 0
	var shots := a.shots_fired
	for i in 200:
		b.step(PlayerInput.make())
		if a.state == &"aim" and a.state_ticks >= 5:
			stagger(a)
			break
	check(a.state == &"hitstun" and not b.ranged_slot_holders.has(a), "예고 중 피격 → 경직, 허가 반환")
	a.cooldown_ticks = 100000
	idle(b, 60)
	check(a.shots_fired == shots, "취소된 예고는 발사하지 않음")
	# 근접 시 짧은 후퇴(최대 100 px / 0.4초) 후 다시 싸움; 궁지(경계)에서는 후퇴하지 않음
	a.change_state(&"idle")
	a.cooldown_ticks = 100000
	place(a, 700, 545)
	place(p, 660, 545)
	var start_x := a.floor_pos.x
	var retreated := false
	var retreat_max := 0.0
	var back_to_fight := false
	for i in 120:
		b.step(PlayerInput.make())
		place(p, 660, 545)
		if a.state == &"retreat":
			retreated = true
			retreat_max = maxf(retreat_max, absf(a.floor_pos.x - start_x))
		elif retreated and (a.state == &"approach" or a.state == &"aim" or a.state == &"idle"):
			back_to_fight = true
	check(retreated and retreat_max <= 100.01 and back_to_fight, "근접 시 후퇴 ≤ 100 px (%.0f) 후 복귀" % retreat_max)
	place(a, b.arena_rect().end.x - a.half_width - 5.0, 545)
	place(p, a.floor_pos.x - 60.0, 545)
	a.change_state(&"idle")
	var cornered_retreat := false
	for i in 60:
		b.step(PlayerInput.make())
		place(p, a.floor_pos.x - 60.0, 545)
		if a.state == &"retreat":
			cornered_retreat = true
	check(not cornered_retreat, "경계에 몰린 궁수는 후퇴하지 않고 자리를 잡음")
	b.queue_free()

## 5. 투척 예고와 착탄 일치, 준비 취소/발사 후 투척병 사망, 화염 예약 포함 최대 2, 직격 피해 없음, 안전 지점 회피
func test_d5_thrower_telegraph_landing_cancel_death_and_cap() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	b.start_encounter(farm, "run_thrower", null, 20.0, 100)
	settle(b)
	var p := b.player
	var t := b.spawn_thrower_enemy(Vector2(950, 545))
	check(t.max_hp == 60, "투척병 체력 60")
	place(p, 600, 560)
	t.cooldown_ticks = 0
	var aim := Vector2.INF
	var windup_tick := -1
	var pot_tick := -1
	var land_tick := -1
	var hp_at_land := -1
	for i in 300:
		b.step(PlayerInput.make())
		if t.state == &"windup" and windup_tick < 0:
			windup_tick = i
			aim = t.aim_point
			check(aim.distance_to(Vector2(600, 560)) < 1.0, "준비 시작 시 목표 발 위치 고정 (%s)" % str(aim))
			place(p, 600, 660)   # 준비 중 이동해도 착탄점 불변
		if not b.pots.is_empty() and pot_tick < 0:
			pot_tick = i
			check(t.aim_point == aim and b.pots[0].target == aim, "항아리 목표 = 고정 착탄점")
			place(p, aim.x, aim.y)   # 착탄 지점에 서 있기(직격 피해 없음 확인)
		if not b.fires.is_empty() and land_tick < 0:
			land_tick = i
			hp_at_land = p.hp
			break
	# 항아리는 던진 틱에도 한 번 진행하므로 관측 기준 비행은 30틱(던진 틱 포함) = 관측 29틱 뒤 착탄
	check(windup_tick >= 0 and pot_tick - windup_tick == Ticks.from_ms(650.0) and land_tick - pot_tick == Ticks.from_ms(500.0) - 1, "준비 %d틱 + 비행 %d틱(던진 틱 포함 30)" % [pot_tick - windup_tick, land_tick - pot_tick + 1])
	check(b.fires.size() == 1 and b.fires[0].center == aim and b.pots.is_empty(), "착탄 지점에 불 생성, 예약 소모")
	check(hp_at_land == 100, "직격 피해 없음(장판 피해만)")
	check(b.is_in_fire(p.floor_pos), "불 범위 = 예고 범위(발 위치 안)")
	place(p, 300, 545)
	# 준비 중 경직 → 취소(항아리 없음), 허가 반환
	t.change_state(&"idle")
	t.cooldown_ticks = 0
	var throws := t.throws
	for i in 200:
		b.step(PlayerInput.make())
		if t.state == &"windup" and t.state_ticks >= 5:
			stagger(t)
			break
	check(t.state == &"hitstun" and not b.ranged_slot_holders.has(t), "준비 중 피격 → 취소·허가 반환")
	idle(b, 80)
	check(t.throws == throws and b.pots.is_empty(), "취소된 준비는 항아리를 던지지 않음")
	# 발사 후 사망: 항아리는 착탄한다
	t.change_state(&"idle")
	t.cooldown_ticks = 0
	for i in 200:
		b.step(PlayerInput.make())
		if not b.pots.is_empty():
			break
	check(not b.pots.is_empty(), "항아리 발사")
	kill(t)
	var fires_before := b.fires.size()
	idle(b, Ticks.from_ms(500.0) + 1)
	check(b.fires.size() == fires_before + 1 and b.pots.is_empty(), "투척병 사망 후에도 착탄 (불 %d)" % b.fires.size())
	# 예약 포함 최대 2: 불 2개가 살아 있는 동안 새 투척병 2명은 준비하지 못한다
	while b.fires.size() < 2:
		b._spawn_fire(Vector2(400, 500))
	check(b.fires.size() == 2 and not b.fire_slot_available(), "활성 화염 2 → 자리 없음")
	var t2 := b.spawn_thrower_enemy(Vector2(700, 500))
	var t3 := b.spawn_thrower_enemy(Vector2(750, 600))
	t2.cooldown_ticks = 0
	t3.cooldown_ticks = 0
	var max_used := 0
	var windup_seen := false
	var waited := false
	for i in 120:
		b.step(PlayerInput.make())
		max_used = maxi(max_used, b.fire_slots_used())
		if t2.state == &"windup" or t3.state == &"windup":
			windup_seen = true
		if t2.waiting_for_slot or t3.waiting_for_slot:
			waited = true
	check(max_used <= 2 and not windup_seen and waited, "활성+예약 화염 최대 %d ≤ 2, 자리 없으면 대기(기존 불 삭제 없음)" % max_used)
	# 불이 꺼진 뒤 두 투척병이 동시에 예약해 2를 넘기지 않는다(원거리 허가 1 + 화염 자리)
	for fz in b.fires:
		fz.age = fz.life_ticks
	idle(b, 2)
	check(b.fires.is_empty(), "수명 종료로 불 제거")
	max_used = 0
	for i in 400:
		b.step(PlayerInput.make())
		max_used = maxi(max_used, b.fire_slots_used())
	check(max_used <= 2, "두 투척병 동시 예약에도 최대 %d ≤ 2" % max_used)
	# 안전 지점 회피: 주인공이 문 진입 지점에 서 있으면 착탄점 중심을 거기 두지 않는다
	for fz in b.fires:
		fz.age = fz.life_ticks
	idle(b, 2)
	b.enemies.erase(t3)
	t3.free()
	var ep := b.entry_point(&"west")
	place(p, ep.x, ep.y)
	t2.change_state(&"idle")
	t2.cooldown_ticks = 0
	place(t2, 600, 545)
	var aim2 := Vector2.INF
	var trace: Array = []
	for i in 200:
		b.step(PlayerInput.make())
		place(p, ep.x, ep.y)
		if i % 20 == 0:
			trace.append("%d:%s@%.0f cd%d slots%d/%d w%s" % [i, t2.state, t2.floor_pos.x, t2.cooldown_ticks, b.fire_slots_used(), b.ranged_slot_holders.size(), t2.wait_reason])
		if t2.state == &"windup":
			aim2 = t2.aim_point
			break
	if aim2 == Vector2.INF:
		print("    [trace] ", trace)
	check(aim2 != Vector2.INF and aim2.distance_to(ep) >= 80.0 and b.valid_fire_target(aim2), "문 진입 안전 지점을 피한 착탄점 (%s, 거리 %.0f)" % [str(aim2), aim2.distance_to(ep) if aim2 != Vector2.INF else -1.0])
	b.queue_free()

## 6. 첫 불 피해까지 0.5초, 연속 4초 체류 시 최대 8회(24), 겹침 비중첩, 출입·점프·회피, 공격 경직 없음, 적 무피해, 방 이동 시 시계 정리
func test_d6_fire_damage_timing_overlap_jump_dodge_no_hitstun() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	b.start_encounter(farm, "run_fire", null, 20.0, 100)
	settle(b)
	var p := b.player
	place(p, 500, 545)
	var burns: Array = []
	p.burn_taken.connect(func(_a, amt): burns.append([b.tick, amt]))
	# A. 시간 규칙: 노출을 확인한 틱(생성 뒤 첫 틱) + 30 에 첫 피해, 이후 30틱마다, 수명 마지막 틱 판정 뒤 제거
	var fz := b._spawn_fire(Vector2(500, 545))
	var t0 := b.tick
	idle(b, 30)
	check(p.hp == 100 and burns.is_empty(), "노출 뒤 30틱 동안 피해 없음")
	idle(b, 1)
	check(p.hp == 94 and burns.size() == 1 and burns[0][0] == t0 + 31, "첫 피해는 노출 확인 틱 + 30 (= 생성 뒤 31틱째) 에 6 (HWR-004: 3→6)")
	var steps := 31
	while is_instance_valid(fz) and fz.alive and steps < 400:
		idle(b, 1)
		steps += 1
	check(steps == 241, "생성 뒤 241틱째(나이 240 판정 뒤) 제거 (%d)" % steps)
	check(burns.size() == 8 and p.hp == 100 - 48, "4초 체류: 8회 48 피해 (%d회, 체력 %d)" % [burns.size(), p.hp])
	check(b.fire_clocks.is_empty(), "불이 없으면 피해 시계 정리")
	# B. 겹침: 같은 자리 불 2개 → 대상당 주기 하나(초당 6 최대)
	p.hp = 100
	burns.clear()
	b._spawn_fire(Vector2(500, 545))
	b._spawn_fire(Vector2(520, 545))
	idle(b, 91)
	check(burns.size() == 3 and p.hp == 82, "겹친 불 위 91틱: 3회 18 피해 (비중첩) (%d회, 체력 %d)" % [burns.size(), p.hp])
	_expire_fires(b)
	# C. 나가면 없음, 재진입 시 시계를 초기화하지 않고 예정 주기에 피해(몰아 넣기 없음)
	b._spawn_fire(Vector2(500, 545))
	idle(b, 31)
	check(p.hp == 76, "재생성 불: 31틱째 피해")
	place(p, 300, 545)
	idle(b, 60)
	check(p.hp == 76, "불 밖 60틱: 피해 없음")
	place(p, 500, 545)
	idle(b, 30)
	check(p.hp == 70, "재진입 30틱 안에 정확히 1회(예정 주기 유지, 몰아 넣기 없음)")
	_expire_fires(b)
	# D. 점프: 예정 틱에 높이 12 초과면 건너뛰고 착지 후 다음 주기에 피해
	b._spawn_fire(Vector2(500, 545))
	idle(b, 30)
	p.height = 40.0
	idle(b, 1)
	check(p.hp == 70, "예정 틱에 공중(높이 40) → 건너뜀")
	p.height = 0.0
	idle(b, 30)
	check(p.hp == 64, "착지 후 다음 주기에 피해")
	_expire_fires(b)
	# E. 회피 무적: 예정 틱에 무적이면 건너뜀
	b._spawn_fire(Vector2(500, 545))
	idle(b, 30)
	p.invuln_ticks = 3
	idle(b, 1)
	check(p.hp == 64, "예정 틱에 무적(회피) → 건너뜀")
	_expire_fires(b)
	# F. 공격 중 피해: 경직·히트스톱·행동 취소 없음
	b._spawn_fire(Vector2(500, 545))
	idle(b, 27)
	press(b, "attack_light")
	idle(b, 2)
	check(p.state == &"light" and p.hp == 64, "평타 진행 중, 아직 피해 없음")
	idle(b, 1)
	check(p.hp == 58 and p.state == &"light" and p.hitstop_ticks == 0 and p.hitstun_ticks == 0, "평타 중 불 피해 6: 경직·히트스톱·취소 없음 (%s)" % p.state)
	# G. 적은 자기 불에 피해 없음 (평타가 끝난 뒤 생성)
	idle(b, 30)
	var e := b.spawn_melee_enemy(Vector2(500, 545))
	e.state = &"idle"
	e.state_ticks = -100000
	var ehp := e.hp
	for i in 70:
		b.step(PlayerInput.make())
		place(e, 500, 545)
		e.state = &"idle"
		e.state_ticks = -100000
	check(e.hp == ehp, "적은 불 피해 없음")
	# H. 방 이동 시 시계·불 정리
	check(not b.fire_clocks.is_empty(), "이동 전 시계 존재")
	e.queue_free()
	b.enemies.erase(e)
	place(p, 300, 545)
	p.change_state(&"ground")
	idle(b, 5)
	enter(b, &"battle_1")
	check(b.fires.is_empty() and b.fire_clocks.is_empty(), "방 이동 후 불·시계 없음")
	b.queue_free()

func _expire_fires(b: Battle) -> void:
	for fz in b.fires:
		fz.age = fz.life_ticks
	idle(b, 1)

## 7. 동료 화염 우회/피격/이탈, 일반 방 또는 보스의 마지막 처치를 동료가 해도 올바른 결과
func test_d7_companion_avoids_fire_and_last_kill_results() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_comp_fire", aya, 20.0, 100)
	settle(b)
	var p := b.player
	var comp: ArcherCompanion = b.companion
	# 불 안에 서 있으면 빠져나온다
	place(p, 700, 545)
	p.facing = 1
	place(comp, 500, 545)
	b._spawn_fire(Vector2(500, 545))
	var escaped_tick := -1
	for i in 60:
		b.step(PlayerInput.make())
		if not b.is_in_fire(comp.floor_pos) and escaped_tick < 0:
			escaped_tick = i
	check(escaped_tick >= 0 and escaped_tick < 30 and comp.total_damage_taken == 0, "불 안의 동료가 %d틱에 탈출, 피해 0" % escaped_tick)
	idle(b, 60)
	check(not b.is_in_fire(comp.floor_pos), "탈출 후 불 위에 정지하지 않음")
	# 따라가기 목표가 불 안이면 안전한 위치를 고른다
	for fz in b.fires:
		fz.age = fz.life_ticks
	idle(b, 2)
	place(p, 700, 545)
	p.facing = 1
	place(comp, 600, 545)
	b._spawn_fire(Vector2(600, 545))   # 정확히 따라가기 위치(700-100)
	var in_fire_ticks := 0
	for i in 240:
		b.step(PlayerInput.make())
		if b.is_in_fire(comp.floor_pos):
			in_fire_ticks += 1
	check(in_fire_ticks < 30 and comp.total_damage_taken <= 3, "목표 지점의 불을 피해 대기 (불 위 %d틱, 피해 %d)" % [in_fire_ticks, comp.total_damage_taken])
	# 경로의 불을 우회: 동료 (300) → 목표 (600), 불 (450)
	for fz in b.fires:
		fz.age = fz.life_ticks
	idle(b, 2)
	comp.total_damage_taken = 0
	comp.hp = comp.max_hp
	place(comp, 300, 545)
	place(p, 700, 545)
	b._spawn_fire(Vector2(450, 545))
	for i in 240:
		b.step(PlayerInput.make())
	check(comp.total_damage_taken == 0 and comp.floor_pos.x > 520.0, "경로의 불을 우회해 도착 (x %.0f, 피해 %d)" % [comp.floor_pos.x, comp.total_damage_taken])
	# 동료 피격·이탈
	place(comp, 500, 545)
	b._spawn_fire(Vector2(500, 545))
	comp.hp = 2
	for i in 80:
		b.step(PlayerInput.make())
		place(comp, 500, 545)
		if not comp.alive:
			break
	check(not comp.alive and not comp.visible and b.result_state == &"active", "불 피해로 동료 이탈, 패배 아님")
	b.queue_free()
	# 마지막 처치를 동료가: 일반 방 → 정리, 보스 → 승리
	var b2: Battle = await make_battle()
	b2.start_encounter(farm, "run_comp_last", aya, 20.0, 100)
	settle(b2)
	enter(b2, &"battle_1")
	var comp2: ArcherCompanion = b2.companion
	flush_spawns(b2)
	var alive := b2.alive_enemies()
	for i in range(1, alive.size()):
		kill(alive[i])
	var last := alive[0]
	last.hp = 5
	place(b2.player, 250, 545)
	b2.player.invuln_ticks = 100000
	place(last, 700, 545)
	place(comp2, 450, 545)
	comp2.cooldown_ticks = 0
	var cleared := [0]
	var resolved := [0]
	b2.room_cleared.connect(func(_r): cleared[0] += 1)
	b2.resolved.connect(func(_o, _r): resolved[0] += 1)
	for i in 200:
		b2.step(PlayerInput.make())
		last.state = &"idle"
		last.state_ticks = -100000
		if not last.alive:
			break
	check(not last.alive and comp2.shots_fired >= 1, "동료 화살로 1웨이브 마지막 처치")
	idle(b2, 1)
	check(b2.doors_locked and cleared[0] == 0 and b2.wave_index == 1, "1웨이브 뒤에는 정리 아님(간격 뒤 2웨이브)")
	clear_room(b2)
	check(cleared[0] == 1 and resolved[0] == 0, "방 정리 1회, 승리 아님")
	enter(b2, &"battle_2")
	clear_room(b2)
	enter(b2, &"battle_3")
	clear_room(b2)
	enter(b2, &"boss")
	flush_spawns(b2)
	var boss := b2.boss_enemy()
	boss.hp = 5
	place(boss, 700, 545)
	boss.change_state(&"idle")
	place(b2.player, 250, 545)
	place(comp2, 450, 545)
	comp2.cooldown_ticks = 0
	for i in 200:
		b2.step(PlayerInput.make())
		if b2.result_state != &"active":
			break
		boss.change_state(&"idle")
		place(boss, 700, 545)
	check(not boss.alive and b2.result_state == &"resolved" and b2.outcome == &"victory" and resolved[0] == 1, "동료 화살로 보스 처치 → 승리 1회")
	b2.queue_free()

## 8. 상자 1회, 생존자만 20% 회복, 최초 130/반복 50(미개봉 100/20), 패배·포기 0, 저장 실패 재시도 중복 없음
func test_d8_chest_once_heal_pending_and_rewards() -> void:
	var c := make_controller()
	c.new_game()
	var farm := data.site(&"ch1_farm")
	var br := c.begin_run(&"ch1_farm")
	var b: Battle = await make_battle()
	b.start_encounter(farm, br.run_id, null, 20.0, 100)
	settle(b)
	enter(b, &"battle_1")
	clear_room(b)
	enter(b, &"battle_2")
	clear_room(b)
	enter(b, &"treasure")
	var p := b.player
	p.hp = 50
	place(p, 640, 545)
	idle(b, 1)
	var opened := [0]
	b.chest_opened_signal.connect(func(_h, _c): opened[0] += 1)
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b.chest_opened and p.hp == 70 and b.pending_currency == 30 and opened[0] == 1, "상자 개봉: 체력 50→70(20%%), 보류 30 (체력 %d, 보류 %d)" % [p.hp, b.pending_currency])
	idle(b, 1)
	for i in 5:
		b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
		idle(b, 1)
	check(p.hp == 70 and b.pending_currency == 30 and opened[0] == 1, "연타해도 재지급 없음")
	check(b.open_chest().ok == false, "직접 호출도 거부")
	# 재방문에도 열린 상태
	enter(b, &"battle_2")
	enter(b, &"treasure")
	check(b.chest.opened and b.chest_opened, "재방문: 열린 상자 유지")
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(p.hp == 70 and b.pending_currency == 30, "재방문 Enter 도 무효")
	enter(b, &"battle_2")
	enter(b, &"battle_3")
	clear_room(b)
	enter(b, &"boss")
	flush_spawns(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	check(b.outcome == &"victory" and b.pending_currency == 30, "보스 승리, 보류 30 유지")
	var r1 := c.resolve_run(b.run_id, b.outcome, {"chest_bonus": b.pending_currency})
	check(r1.status == "committed" and r1.reward == 130 and r1.base_reward == 100 and r1.chest_bonus == 30 and c.state.currency == 130, "최초 승리 + 상자 = 130 (군자금 %d)" % c.state.currency)
	check(c.state.is_liberated(&"ch1_farm") and c.state.management(&"ch1_farm") == 40, "해방·관리도 40 은 그대로")
	var again := c.resolve_run(b.run_id, b.outcome, {"chest_bonus": 30})
	check(again.reward == 130 and c.state.currency == 130, "같은 run 반복 호출: 중복 없음")
	b.queue_free()
	# 재도전 + 상자 = 50 (동료 포함 회복: 생존자만, 최대 초과 없음, 이탈 부활 없음)
	c.state.unlocked_companions.append("aya")
	c.select_companion(&"aya")
	br = c.begin_run(&"ch1_farm")
	var b2: Battle = await make_battle()
	b2.start_encounter(farm, br.run_id, c.selected_companion(), 20.0, 100)
	check(not b2.chest_opened and b2.pending_currency == 0, "새 출정: 상자 상태 초기화")
	settle(b2)
	enter(b2, &"battle_1")
	clear_room(b2)
	enter(b2, &"battle_2")
	clear_room(b2)
	enter(b2, &"treasure")
	b2.player.hp = 95
	var comp: ArcherCompanion = b2.companion
	comp.hp = 30
	place(b2.player, 640, 545)
	idle(b2, 1)
	b2.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b2.player.hp == 100 and comp.hp == 42 and b2.chest_heal_total == 17, "주인공 95→100(초과 없음), 동료 30→42(+12=20%% of 60)")
	enter(b2, &"battle_2")
	enter(b2, &"battle_3")
	clear_room(b2)
	enter(b2, &"boss")
	flush_spawns(b2)
	for e in b2.alive_enemies():
		kill(e)
	idle(b2, 1)
	var r2 := c.resolve_run(b2.run_id, b2.outcome, {"chest_bonus": b2.pending_currency})
	check(r2.reward == 50 and r2.base_reward == 20 and c.state.currency == 180, "재도전 + 상자 = 50 (군자금 %d)" % c.state.currency)
	b2.queue_free()
	# 이탈한 동료는 상자로 부활하지 않는다
	br = c.begin_run(&"ch1_farm")
	var b3: Battle = await make_battle()
	b3.start_encounter(farm, br.run_id, c.selected_companion(), 20.0, 100)
	settle(b3)
	kill(b3.companion)
	enter(b3, &"battle_1")
	clear_room(b3)
	enter(b3, &"battle_2")
	clear_room(b3)
	enter(b3, &"treasure")
	place(b3.player, 640, 545)
	idle(b3, 1)
	b3.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b3.chest_opened and not b3.companion.alive and b3.companion.hp == 0, "상자는 이탈 동료를 부활시키지 않음")
	# 미개봉 재도전 = 20
	enter(b3, &"battle_2")
	enter(b3, &"battle_3")
	clear_room(b3)
	enter(b3, &"boss")
	flush_spawns(b3)
	for e in b3.alive_enemies():
		kill(e)
	idle(b3, 1)
	b3.pending_currency = 0   # (이 run 은 상자를 열었지만 미개봉 경로 검증을 위해 보류 0 으로 전달)
	var r3 := c.resolve_run(b3.run_id, b3.outcome, {"chest_bonus": 0})
	check(r3.reward == 20 and r3.chest_bonus == 0 and c.state.currency == 200, "미개봉 재도전 = 20 (군자금 %d)" % c.state.currency)
	b3.queue_free()
	# 임의 금액 거부: 정의값(30)으로 제한
	br = c.begin_run(&"ch1_farm")
	var r4 := c.resolve_run(br.run_id, &"victory", {"chest_bonus": 999})
	check(r4.reward == 50 and r4.chest_bonus == 30 and c.state.currency == 250, "임의 금액 999 → 30 으로 제한")
	# 패배·포기: 보류 소멸, 자금 불변
	br = c.begin_run(&"ch1_farm")
	var b5: Battle = await make_battle()
	b5.start_encounter(farm, br.run_id, null, 20.0, 100)
	settle(b5)
	b5.pending_currency = 30
	b5.chest_opened = true
	kill(b5.player)
	idle(b5, 1)
	check(b5.outcome == &"defeat", "패배")
	var r5 := c.resolve_run(b5.run_id, b5.outcome, {"chest_bonus": b5.pending_currency})
	check(r5.reward == 0 and r5.status == "defeat" and c.state.currency == 250, "패배: 보류 군자금 소멸, 자금 불변")
	b5.queue_free()
	br = c.begin_run(&"ch1_farm")
	var b6: Battle = await make_battle()
	b6.start_encounter(farm, br.run_id, null, 20.0, 100)
	b6.pending_currency = 30
	b6.abandon()
	var r6 := c.resolve_run(b6.run_id, b6.outcome, {"chest_bonus": 30})
	check(r6.reward == 0 and r6.status == "abandon" and c.state.currency == 250, "포기: 보류 군자금 소멸")
	b6.queue_free()
	# 저장 실패 → 재시도: 상자 30 을 중복 가산하지 않는다
	c.store.fail_next_write = true
	br = c.begin_run(&"ch1_farm")
	var r7 := c.resolve_run(br.run_id, &"victory", {"chest_bonus": 30})
	check(r7.status == "unsaved" and c.state.currency == 250 and c.has_pending(), "저장 실패: 미반영")
	var r8 := c.retry_pending()
	check(r8.status == "committed" and r8.reward == 50 and c.state.currency == 300, "재시도 성공: 50 한 번만 (군자금 %d)" % c.state.currency)
	var c2 := make_controller()
	c2.continue_game()
	check(c2.state.currency == 300, "디스크 300")

## 9. 일반 방 전멸로 거점 해방 없음, 보스 처치만 클리어, 보스/주인공 동시 사망은 패배 (+ 초소 보스 → 챕터 클리어)
func test_d9_boss_only_clears_and_same_tick_death_is_defeat() -> void:
	var c := make_controller()
	c.new_game()
	var farm := data.site(&"ch1_farm")
	var br := c.begin_run(&"ch1_farm")
	var b: Battle = await make_battle()
	b.start_encounter(farm, br.run_id, null, 20.0, 100)
	settle(b)
	enter(b, &"battle_1")
	clear_room(b)
	enter(b, &"battle_2")
	clear_room(b)
	enter(b, &"battle_3")
	clear_room(b)
	var resolved_any := [0]
	b.resolved.connect(func(_o, _r): resolved_any[0] += 1)
	idle(b, 60)
	check(b.result_state == &"active" and resolved_any[0] == 0 and not c.state.is_liberated(&"ch1_farm") and c.state.currency == 0, "일반 방 3개 정리해도 승리 신호·해방·보상 없음")
	b.abandon()
	c.resolve_run(br.run_id, b.outcome)
	b.queue_free()
	# 보스/주인공 동시 사망 → 패배
	var c3 := make_controller()
	c3.new_game()
	br = c3.begin_run(&"ch1_farm")
	var b3: Battle = await make_battle()
	var aya := data.companion(&"aya")
	b3.start_encounter(farm, br.run_id, aya, 20.0, 100)
	to_boss(b3)
	var boss := b3.boss_enemy()
	var p := b3.player
	place(p, 600, 545)
	p.hp = 1
	place(boss, 690, 545)
	boss.hp = 1
	boss.facing = -1
	boss.current_pattern = 0
	boss.change_state(&"attack")
	place(b3.companion, 400, 545)
	b3.companion.cooldown_ticks = 9999
	var pr := Projectile.new()
	pr.setup(&"player", b3.companion, b3.companion.arrow, 7.0, Vector2(680, 545), 35.0, 1, 600.0, 360.0, 36, 4.0, 4.0)
	b3.add_projectile(pr)
	idle(b3, 1)
	check(not p.alive and not boss.alive, "같은 틱에 주인공과 보스 사망 (%s / %s)" % [str(p.alive), str(boss.alive)])
	check(b3.result_state == &"resolved" and b3.outcome == &"defeat", "동일 틱 → 패배 우선 (%s)" % b3.outcome)
	check(b3.projectiles.is_empty() and b3.fires.is_empty() and b3.pots.is_empty(), "확정 후 투사체·불 정리")
	var rd := c3.resolve_run(br.run_id, b3.outcome, {"chest_bonus": 0})
	check(rd.status == "defeat" and not c3.state.is_liberated(&"ch1_farm"), "패배: 해방 없음")
	b3.queue_free()
	# 초소 보스 처치 → 챕터 1 클리어·아야 해금 (Battle 경로)
	win(c3, &"ch1_farm")
	c3.repair(&"ch1_farm")
	win(c3, &"ch1_store")
	c3.repair(&"ch1_store")
	br = c3.begin_run(&"ch1_pass")
	var b4: Battle = await make_battle()
	b4.start_encounter(data.site(&"ch1_pass"), br.run_id, null, 20.0, 100)
	to_boss(b4)
	var boss4 := b4.boss_enemy()
	check(boss4.display_name == "초소 대장" and boss4.max_hp == 600, "초소 보스 600")
	kill(boss4)
	idle(b4, 1)
	var rp := c3.resolve_run(br.run_id, b4.outcome, {"chest_bonus": b4.pending_currency})
	check(rp.status == "committed" and rp.chapter_cleared == "ch1" and rp.companion_unlocked == "aya" and c3.state.is_companion_unlocked(&"aya"), "초소 보스 → 챕터 1 클리어·아야 해금")
	b4.queue_free()

# ------------------------------------------------------------------ 기존 전투·동료 검증(방 구조에 맞춰 조정)

func test_scenario_9_dummy_and_ally_not_counted() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_test_2", aya, 20.0, 100)
	check(b.companion != null and b.companion.alive and b.allies.size() == 1, "동료 생성")
	settle(b)
	enter(b, &"battle_1")
	# 허수아비를 억지로 추가해도 방 정리 조건에 들어가지 않는다
	var d := Dummy.new()
	b.actors_root.add_child(d)
	d.configure(b.tuning, b, Vector2(700, 540))
	b.enemies.append(d)
	flush_spawns(b)
	check(b.required_alive_count() == 3, "허수아비 제외 필수 적 3")
	for e in b.alive_enemies():
		if not e is Dummy:
			kill(e)
	idle(b, 1)
	idle(b, b.wave_gap_ticks + 1)
	flush_spawns(b)
	for e in b.alive_enemies():
		if not e is Dummy:
			kill(e)
	idle(b, 1)
	check(b.is_room_cleared(&"battle_1") and not b.doors_locked and d.alive and b.companion.alive and b.result_state == &"active", "허수아비·아군이 살아 있어도 필수 적 0 이면 방 정리")
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
	to_boss(b)
	var boss := b.boss_enemy()
	check(boss != null and b.alive_enemies().size() == 1, "대장 1명 출현")
	check(boss.max_hp == 600 and boss.hp == 600 and boss.display_name == "초소 대장", "초소 대장 체력 600")
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
	# 거점별 보스 데이터: 농촌 450 / 창고 550
	var b2: Battle = await make_battle()
	b2.start_encounter(data.site(&"ch1_store"), "run_store_boss", null, 20.0, 100)
	to_boss(b2)
	check(b2.boss_enemy().display_name == "보급대장" and b2.boss_enemy().max_hp == 550, "창고 보스 보급대장 550")
	b2.queue_free()

# ------------------------------------------------------------------ 동료 궁수

func test_archer_follows_fires_and_hits() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_archer", aya, 20.0, 100)
	settle(b)
	var c: ArcherCompanion = b.companion
	var p := b.player
	check(c.max_hp == 60 and is_equal_approx(c.def.attack_damage, 7.0), "아야 체력 60, 화살 피해 7")
	place(p, 700, 560)
	p.facing = 1
	idle(b, 200)
	check(absf(c.floor_pos.x - (p.floor_pos.x - 100.0)) < 12.0 and absf(c.floor_pos.y - p.floor_pos.y) < 8.0, "따라가기 위치 (%.0f, %.0f) ≈ (600, 560)" % [c.floor_pos.x, c.floor_pos.y])
	var e := b.spawn_melee_enemy(Vector2(950, 600))
	e.max_hp = 100000
	e.hp = e.max_hp
	e.state = &"idle"
	e.state_ticks = -100000
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
	var shots0 := c.shots_fired
	idle(b, 60)
	check(c.shots_fired <= shots0 + 1, "1초 동안 추가 사격 ≤ 1")
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
	settle(b)
	var c: ArcherCompanion = b.companion
	var p := b.player
	var e := b.spawn_melee_enemy(Vector2(700, 540))
	e.max_hp = 100000
	e.hp = e.max_hp
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
	place(c, 500, 540)
	c.cooldown_ticks = 100000
	var pr := Projectile.new()
	pr.setup(&"player", c, c.arrow, 7.0, Vector2(520, 540), 35.0, 1, 600.0, 360.0, 36, 4.0, 4.0)
	b.add_projectile(pr)
	var php := p.hp
	for i in 30:
		b.step(PlayerInput.make())
	check(p.hp == php, "화살은 아군을 관통 (주인공 피해 없음)")
	check(e.total_damage_taken == 35, "화살 적중 피해 7 (합계 %d)" % e.total_damage_taken)
	check(e.hitstun_ticks == hs and e.knockback_total == kb, "화살은 경직·밀림을 바꾸지 않음")
	check(p.hitstop_ticks == 0, "원거리 적중이 주인공 히트스톱을 만들지 않음")
	check(b.projectiles.is_empty(), "명중 후 투사체 제거")
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
	to_boss(b)
	var boss := b.boss_enemy()
	boss.hp = 5
	place(b.player, 250, 545)
	b.player.invuln_ticks = 100000
	place(boss, 700, 545)
	boss.change_state(&"idle")
	place(comp, 450, 545)
	comp.cooldown_ticks = 0
	var resolved := [""]
	b.resolved.connect(func(o, _r): resolved[0] = String(o))
	for i in 200:
		b.step(PlayerInput.make())
		if b.result_state != &"active":
			break
		boss.change_state(&"idle")
		place(boss, 700, 545)
	check(not boss.alive and comp.shots_fired >= 1 and resolved[0] == "victory", "동료의 마지막 화살로 보스 처치 → 승리 (사격 %d)" % comp.shots_fired)
	var res := c.resolve_run(b.run_id, b.outcome, {"chest_bonus": b.pending_currency})
	check(res.status == "committed" and res.reward == 20 and c.state.currency == 120, "재도전 승리(상자 미개봉) 후 군자금 %d == 120" % c.state.currency)
	b.queue_free()

func test_scenario_6_companion_death_and_recovery() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_comp_die", aya, 20.0, 100)
	settle(b)
	enter(b, &"battle_1")
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
	var b2: Battle = await make_battle()
	b2.start_encounter(farm, "run_comp_next", aya, 20.0, 100)
	check(b2.companion.alive and b2.companion.hp == 60, "다음 출정에서 동료 회복 (체력 %d)" % b2.companion.hp)
	b2.queue_free()

func test_enemy_targets_nearest_ally_and_locks_on_telegraph() -> void:
	var b: Battle = await make_battle()
	var farm := data.site(&"ch1_farm")
	var aya := data.companion(&"aya")
	b.start_encounter(farm, "run_target", aya, 20.0, 100)
	settle(b)
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
		place(comp, 700, 600)
		if e.state == &"telegraph":
			if locked_target == null:
				locked_target = e.target
				lock_facing = e.facing
				place(p, e.floor_pos.x + 60, e.floor_pos.y)
			elif e.target != locked_target or e.facing != lock_facing:
				changed = true
		if e.state == &"recover":
			break
	check(locked_target == comp, "가까운 아군(동료)을 대상으로 선택")
	check(not changed, "예고 시작 후 대상·방향 고정")
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
	settle(b)
	enter(b, &"battle_1")
	flush_spawns(b)
	var n := b.enemies.size()
	b.player.hp = 30
	place(b.player, 400, 600)
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
	var t: Battle = await make_battle(&"training")
	t.player.hp = 30
	Input.action_press(&"dev_reset_player")
	t._handle_dev_input()
	Input.action_release(&"dev_reset_player")
	check(t.player.hp == t.player.max_hp, "수련장에서 F6 동작")
	t.queue_free()

# ------------------------------------------------------------------ 실전 자동 플레이(측정용)

## 단순 자동 조작: 방이 잠기면 대상에게 붙어 평타, 불 위면 빠져나옴, 방이 열리면 다음 문으로 이동(보물방 생략).
## strategy: "nearest" (가까운 적) / "ranged_first" (궁수·투척병 우선)
func auto_play(b: Battle, strategy: String, max_ticks: int = 60 * 300) -> Dictionary:
	var p := b.player
	var ticks := 0
	var toggle := false
	var order: Array[StringName] = [&"entry", &"battle_1", &"battle_2", &"battle_3", &"boss"]
	while b.result_state == &"active" and ticks < max_ticks:
		ticks += 1
		var move := Vector2.ZERO
		var actions: Array = []
		if b.transition_ticks > 0:
			b.step(PlayerInput.make())
			continue
		if b.doors_locked:
			var target: EnemyBase = _auto_target(b, strategy)
			var fz := b.fire_at(p.floor_pos)
			if fz != null:
				move.y = -1.0 if p.floor_pos.y <= fz.center.y else 1.0
				if p.floor_pos.y - 45.0 < b.arena_rect().position.y:
					move.y = 1.0
				elif p.floor_pos.y + 45.0 > b.arena_rect().end.y:
					move.y = -1.0
			elif target != null:
				var dx := target.floor_pos.x - p.floor_pos.x
				var dy := target.floor_pos.y - p.floor_pos.y
				if absf(dy) > 8.0:
					move.y = signf(dy)
				if absf(dx) > 75.0:
					move.x = signf(dx)
				elif (dx > 0.0) != (p.facing > 0) and p.state == &"ground":
					move.x = signf(dx)
				if absf(dx) <= 95.0 and absf(dy) <= 14.0:
					actions.append("attack_light")
				if move.x != 0.0:
					var ahead := p.floor_pos + Vector2(move.x * 45.0, move.y * 10.0)
					var f2 := b.fire_at(ahead)
					if f2 != null:
						move.x = 0.0
						move.y = -1.0 if p.floor_pos.y <= f2.center.y else 1.0
		else:
			var idx := order.find(b.room.id)
			var next: StringName = order[mini(idx + 1, order.size() - 1)]
			var dir := door_dir_to(b, next)
			if dir != &"":
				var z := b.door_zone(dir)
				if z.has_point(p.floor_pos):
					toggle = not toggle
					if toggle:
						actions.append("interact")
				else:
					var d := z.get_center() - p.floor_pos
					if absf(d.x) > 6.0:
						move.x = signf(d.x)
					if absf(d.y) > 6.0:
						move.y = signf(d.y)
		b.step(PlayerInput.make(move, actions))
	var rooms := {}
	var total_damage := 0
	for rid in b.run_stats.keys():
		var st: Dictionary = b.run_stats[rid]
		rooms[rid] = st.duplicate()
		total_damage += int(st.damage_taken)
	return {"ticks": ticks, "outcome": String(b.outcome), "hp": p.hp, "max_hp": p.max_hp, "damage": total_damage, "kills": b.kills, "rooms": rooms}

func _auto_target(b: Battle, strategy: String) -> EnemyBase:
	var p := b.player
	var best: EnemyBase = null
	var best_d := INF
	var ranged_exists := false
	if strategy == "ranged_first":
		for e in b.alive_enemies():
			if e is ArcherEnemy or e is ThrowerEnemy:
				ranged_exists = true
	for e in b.alive_enemies():
		if ranged_exists and not (e is ArcherEnemy or e is ThrowerEnemy):
			continue
		var d: float = absf(e.floor_pos.x - p.floor_pos.x) + absf(e.floor_pos.y - p.floor_pos.y)
		if d < best_d:
			best_d = d
			best = e
	return best

func test_real_fight_three_sites_two_strategies() -> void:
	for site_id in [&"ch1_farm", &"ch1_store", &"ch1_pass"]:
		for strategy in ["nearest", "ranged_first"]:
			var b: Battle = await make_battle()
			b.start_encounter(data.site(site_id), "run_auto_%s_%s" % [site_id, strategy], null, 20.0, 100)
			var r := auto_play(b, strategy)
			check(r.outcome != "", "%s/%s: 5분 안에 결과 확정 (%s, %d틱)" % [site_id, strategy, r.outcome, r.ticks])
			var parts: Array[String] = []
			for rid in [&"battle_1", &"battle_2", &"battle_3", &"boss"]:
				var st: Dictionary = r.rooms.get(rid, {"combat_ticks": 0, "damage_taken": 0, "kills": 0})
				parts.append("%s %.1f초/피해%d/처치%d" % [rid, int(st.combat_ticks) / 60.0, int(st.damage_taken), int(st.kills)])
			fight_reports.append("%s [%s] %s %.1f초 체력 %d/%d 받은 피해 %d 처치 %d | %s" % [site_id, strategy, r.outcome, r.ticks / 60.0, r.hp, r.max_hp, r.damage, r.kills, " · ".join(parts)])
			b.queue_free()
			await process_frame

# ------------------------------------------------------------------ HWR-004 R1 검수 1: 적 피해 2배(모든 경로), 아야·플레이어 피해 유지

func test_h4_1_enemy_damage_doubled_on_every_path() -> void:
	var b: Battle = await make_battle()
	b.start_encounter(data.site(&"ch1_pass"), "run_h4_dmg", data.companion(&"aya"), 20.0, 100)
	settle(b)
	var p := b.player
	var comp := b.companion
	check(b.tuning.enemy_attack_damage == 20 and b.tuning.archer_damage == 16 and b.tuning.captain_attack_damage == 24 and b.tuning.fire_damage == 6, "조정값 근접 20 / 화살 16 / 보스 24 / 불 6")
	# 근접병 베기 → 주인공 20, 동료 20 (같은 새 피해)
	place(p, 400, 545)
	place(comp, 400, 600)
	comp.change_state(&"follow")
	var e := b.spawn_melee_enemy(Vector2(460, 545))
	e.change_state(&"idle")
	e.facing = -1
	e.change_state(&"attack")
	idle(b, 2)
	check(p.hp == 80, "근접병 → 주인공 20 (체력 %d)" % p.hp)
	idle(b, 60)
	place(comp, 400, 545)
	comp.change_state(&"follow")
	place(p, 200, 700)
	p.change_state(&"ground")
	e.facing = -1
	place(e, 460, 545)
	e.change_state(&"attack")
	idle(b, 2)
	check(comp.hp == 40, "근접병 → 동료 20 (체력 %d)" % comp.hp)
	b.enemies.erase(e)
	e.free()
	# 보스 베기 → 24 (Battle.step 경로)
	idle(b, 60)
	place(p, 400, 545)
	p.change_state(&"ground")
	var boss := b.spawn_captain(Vector2(480, 545))
	boss.facing = -1
	boss.current_pattern = 0
	boss.change_state(&"attack")
	idle(b, 2)
	check(p.hp == 56, "보스 베기 → 24 (체력 %d)" % p.hp)
	b.enemies.erase(boss)
	boss.free()
	# 불 한 틱 6
	idle(b, 60)
	place(p, 300, 545)
	p.change_state(&"ground")
	b._spawn_fire(Vector2(300, 545))
	idle(b, 32)
	check(p.hp == 50, "불 한 틱 → 6 (체력 %d)" % p.hp)
	# 플레이어 평타 20·아야 화살 7 은 그대로
	for fz in b.fires:
		fz.finish()
	b.fires.clear()
	place(p, 300, 545)
	p.change_state(&"ground")
	var e2 := b.spawn_melee_enemy(Vector2(370, 545))
	e2.hp = 1000
	e2.max_hp = 1000
	e2.change_state(&"idle")
	press(b, "attack_light")
	idle(b, 8)
	check(e2.total_damage_taken == 20, "플레이어 평타 20 유지 (%d)" % e2.total_damage_taken)
	check(is_equal_approx(comp.def.attack_damage, 7.0), "아야 화살 7 유지")
	b.queue_free()

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
	g.start_battle(&"ch1_farm")
	await process_frame
	check(g.current_screen == "battle" and g.battle != null and g.battle.mode == &"campaign" and g.battle.encounter.id == &"ch1_farm", "농촌 출정: 캠페인 전투 장면")
	g.battle.manual_step = true
	var b := g.battle
	check(b.room != null and b.room.id == &"entry" and b.dungeon != null, "던전 입구에서 시작")
	settle(b)
	enter(b, &"battle_1")
	clear_room(b)
	await process_frame
	check(g.current_screen == "battle" and g.overlay_root.get_child_count() == 0 and g.campaign.state.currency == 0, "방 정리는 결과 창·저장을 만들지 않음")
	enter(b, &"battle_2")
	clear_room(b)
	enter(b, &"treasure")
	place(b.player, 640, 545)
	idle(b, 1)
	b.step(PlayerInput.make(Vector2.ZERO, ["interact"]))
	check(b.chest_opened and b.pending_currency == 30, "보물방 상자 개봉")
	enter(b, &"battle_2")
	enter(b, &"battle_3")
	clear_room(b)
	enter(b, &"boss")
	flush_spawns(b)
	for e in b.alive_enemies():
		kill(e)
	idle(b, 1)
	await process_frame
	check(b.result_state == &"resolved" and g.last_result.status == "committed" and g.last_result.reward == 130 and g.campaign.state.currency == 130, "보스 승리 → 결과 확정·저장 (군자금 %d)" % g.campaign.state.currency)
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
	check(g.campaign.state.has_facility(&"training_ground") and g.campaign.state.currency == 30, "관리 화면 훈련장 구매 (군자금 %d)" % g.campaign.state.currency)
	g.show_manage(&"ch1_pass")
	await process_frame
	check(g.current_screen == "map", "초소는 관리 화면 없음 → 지도")
	g.show_companions()
	await process_frame
	check(g.current_screen == "companions", "동료 선택 화면")
	g.show_join("aya")
	await process_frame
	check(g.current_screen == "join", "합류 화면")
	# 저장 실패 결과 창 (상자 미개봉 재도전 20)
	g.show_map()
	g.campaign.store.fail_next_write = true
	g.start_battle(&"ch1_farm")
	await process_frame
	g.battle.manual_step = true
	b = g.battle
	dungeon_win(b)
	await process_frame
	check(g.last_result.status == "unsaved" and g.campaign.has_pending(), "저장 실패 결과 창 (unsaved)")
	g._retry_pending_from_result()
	await process_frame
	check(g.last_result.status == "committed" and g.last_result.reward == 20 and g.campaign.state.currency == 50, "결과 창 저장 재시도 → 반영 (군자금 %d)" % g.campaign.state.currency)
	g._after_result()
	await process_frame
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
