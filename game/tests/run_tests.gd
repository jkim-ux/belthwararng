extends SceneTree
## 헤드리스 자동 검증. 실행: godot --headless --path game -s tests/run_tests.gd
## 전투 장면을 수동 틱으로 진행하며 판정·연결·입력 규칙을 확인한다. 실패가 있으면 종료 코드 1.

const BATTLE_SCENE := "res://scenes/battle.tscn"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

func _initialize() -> void:
	print("=== HWR-001/HWR-002 R1/HWR-004 R1 전투 자동 검증 시작 (Godot %s) ===" % Engine.get_version_info().string)
	await process_frame
	var tests := [
		"test_tick_quantization",
		"test_diagonal_movement_normalized",
		"test_depth_mismatch_misses",
		"test_height_mismatch_misses",
		"test_single_hit_per_instance",
		"test_hitstop_not_summed_across_targets",
		"test_chain_window_with_early_input",
		"test_expired_input_does_not_fire",
		"test_unimplemented_skill_ignored",
		"test_skill_cooldown",
		"test_launch_once",
		"test_dodge_invulnerability",
		"test_input_collected_during_hitstop",
		"test_death_clears_buffer",
		"test_enemy_attack_cycle_and_facing_lock",
		"test_light_combo_kills_enemy_in_one_set",
		# --- HWR-002 R1 A: 평타 모멘텀
		"test_r1_advance_totals_both_directions",
		"test_r1_advance_same_with_hitstop",
		"test_r1_advance_no_leak_after_wall_or_hit",
		"test_r1_combo_connects_on_knockback_target",
		"test_r1_knockback_curve_and_replacement",
		"test_r1_same_tick_last_hit_wins",
		"test_r1_legacy_profile_keeps_m1_behaviour",
		"test_r1_profile_switch_rules",
		# --- HWR-004 R1: 강인병·보스 반응
		"test_h4_brute_immune_patterns_progress_under_hits",
		"test_h4_brute_slam_ellipse_and_slot",
		"test_h4_brute_guard_break_stagger_once",
		"test_h4_boss_hitstop_policy_selection_and_recover_step",
		# --- HWR-004 R1: D/F/Q/W
		"test_h4_skill_d_knockdown_ground_air_down_getup",
		"test_h4_skill_f_both_sides_once_outward",
		"test_h4_skill_q_normal_brute_boss",
		"test_h4_skill_w_pierce_order_limits_and_reactions",
		"test_h4_new_skill_cancel_lock_cooldown_and_air",
		"test_h4_skill_damage_at_attack_21",
		# --- HWR-004 R1: E/R
		"test_h4_e_window_front_back_same_tick_fire",
		"test_h4_e_arrows_boss_charge_brute_combo",
		"test_h4_r_five_hits_once_no_cancel_and_interrupt",
	]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	for t in tests:
		if only != "" and not t.contains(only):
			continue
		await _run(t)
	print("=== 결과: 통과 %d, 실패 %d ===" % [_pass, _fail])
	for f in _failures:
		print("  FAIL: ", f)
	quit(1 if _fail > 0 else 0)

func _run(name: String) -> void:
	var b: Battle = await _make_battle()
	var before := _fail
	await call(name, b)
	b.queue_free()
	await process_frame
	if _fail == before:
		print("PASS ", name)
	else:
		print("FAIL ", name)

func _make_battle() -> Battle:
	var scene: PackedScene = load(BATTLE_SCENE)
	var b: Battle = scene.instantiate()
	b.manual_step = true
	b.spawn_enemy = false     # 기본은 허수아비만. 필요한 테스트가 적을 추가한다.
	root.add_child(b)
	await process_frame
	return b

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_failures.append(msg)
		print("    ✗ ", msg)

func idle(b: Battle, n: int) -> void:
	for i in n:
		b.step(PlayerInput.make())

func press(b: Battle, action: String, move: Vector2 = Vector2.ZERO) -> void:
	b.step(PlayerInput.make(move, [action]))

func hold(b: Battle, move: Vector2, n: int) -> void:
	for i in n:
		b.step(PlayerInput.make(move))

func place(a: BattleActor, x: float, y: float, z: float = 0.0) -> void:
	a.floor_pos = Vector2(x, y)
	a.height = z
	a.vz = 0.0
	a.position = a.floor_pos

# ------------------------------------------------------------------ 테스트

func test_tick_quantization(_b: Battle) -> void:
	check(Ticks.from_ms(120) == 7, "입력 보관 120ms → 7틱")
	check(Ticks.from_ms(35) == 2, "타격 정지 35ms → 2틱")
	check(Ticks.from_ms(60) == 4, "타격 정지 60ms → 4틱")
	check(Ticks.from_ms(180) == 11, "회피 180ms → 11틱")
	check(Ticks.from_ms(100) == 6, "무적/연결창 100ms → 6틱")
	check(Ticks.from_ms(900) == 54, "회피 재사용 900ms → 54틱")
	check(Ticks.from_ms(4000) == 240 and Ticks.from_ms(6000) == 360, "스킬 재사용 4초/6초 → 240/360틱")

func test_diagonal_movement_normalized(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	var start := p.floor_pos
	hold(b, Vector2(1, 1), 60)
	var d := p.floor_pos - start
	# 가속 3틱 정도를 제외하면 1초 동안 x≈300·0.707, y≈200·0.707
	check(absf(d.x - 300.0 * 0.7071) < 20.0, "대각선 x 이동 거리 %.1f ≈ 212" % d.x)
	check(absf(d.y - 200.0 * 0.7071) < 15.0, "대각선 y 이동 거리 %.1f ≈ 141" % d.y)
	check(absf(p.velocity.x - 212.1) < 1.0 and absf(p.velocity.y - 141.4) < 1.0, "대각선 속도 (%.1f, %.1f)" % [p.velocity.x, p.velocity.y])
	# 손을 떼면 40ms(2~3틱) 안에 정지
	hold(b, Vector2.ZERO, 3)
	check(p.velocity.length() < 0.01, "감속 후 정지 (%.2f)" % p.velocity.length())
	# 직선 이동 속도
	hold(b, Vector2(1, 0), 10)
	check(absf(p.velocity.x - 300.0) < 0.01, "좌우 최고 속도 300 (%.1f)" % p.velocity.x)

func test_depth_mismatch_misses(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 370, 540 + 40)   # 같은 x, 깊이 40 차이
	press(b, "attack_light")
	idle(b, 20)
	check(d.total_damage_taken == 0, "깊이 40 차이 → 빗나감 (피해 %d)" % d.total_damage_taken)
	place(d, 370, 540 + 10)   # 허용 범위 안 (22 + 10)
	idle(b, 10)
	press(b, "attack_light")
	idle(b, 20)
	check(d.total_damage_taken == 20, "깊이 10 차이 → 적중 20 (피해 %d)" % d.total_damage_taken)

func test_height_mismatch_misses(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 370, 540, 200)   # 공중 높이 200: 평타(z 0~90)는 못 맞춤
	d.state = &"launched"
	d.airborne_by_launch = true
	d.vz = 0.0
	press(b, "attack_light")
	# 허수아비가 떨어지지 않게 매 틱 높이를 고정
	for i in 12:
		d.height = 200.0
		d.vz = 0.0
		b.step(PlayerInput.make())
	check(d.total_damage_taken == 0, "높이 200의 적에게 평타 빗나감 (피해 %d)" % d.total_damage_taken)
	# 승월참(z 0~150)은 높이 100의 적을 맞춘다
	idle(b, 30)
	d.total_damage_taken = 0
	press(b, "skill_s")
	for i in 14:
		d.height = 100.0
		d.vz = 0.0
		b.step(PlayerInput.make())
	check(d.total_damage_taken == 30, "높이 100의 적에게 승월참 적중 30 (피해 %d)" % d.total_damage_taken)

func test_single_hit_per_instance(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 370, 540)
	var hits := [0]
	b.hit_applied.connect(func(_a, _t, _i): hits[0] += 1)
	press(b, "attack_light")
	idle(b, 25)   # 타격 구간 3틱 동안 겹쳐 있어도 1회
	check(hits[0] == 1, "평타 1타의 적중 횟수 %d == 1" % hits[0])
	check(d.total_damage_taken == 20, "피해 합계 %d == 20" % d.total_damage_taken)

func test_hitstop_not_summed_across_targets(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 360, 540)
	var e := b.spawn_melee_enemy(Vector2(380, 545))
	e.state = &"idle"
	press(b, "attack_light")
	# 타격 시작 틱: 준비 5틱 후. 적중 직후 타격 정지가 2틱이어야 한다.
	var max_stop := 0
	for i in 12:
		b.step(PlayerInput.make())
		max_stop = maxi(max_stop, p.hitstop_ticks)
	check(d.total_damage_taken == 20 and e.total_damage_taken == 20, "두 대상 모두 적중 (%d, %d)" % [d.total_damage_taken, e.total_damage_taken])
	check(max_stop == 2, "두 대상을 맞혀도 타격 정지 최대 %d틱 == 2" % max_stop)

func test_chain_window_with_early_input(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	press(b, "attack_light")
	var total := p.light_attacks[0].total_ticks()      # 18
	var window := p.light_attacks[0].chain_window_ticks()  # 6
	# 연결창 시작 3틱 전에 미리 누른다 (보관 7틱 이내)
	var window_start_t := total - window            # t=12
	# 현재 t=0. t=9 가 되도록 8틱 진행 후 누름(그 틱이 t=9)
	idle(b, 8)
	press(b, "attack_light")
	check(p.state == &"light" and p.light_index == 1 and p.attack_t() == 9, "미리 누른 시점 t=%d, 아직 1타" % p.attack_t())
	idle(b, 2)   # t=11
	check(p.light_index == 1, "연결창 전에는 2타로 넘어가지 않음 (t=%d)" % p.attack_t())
	idle(b, 1)   # t=12 → 연결창 시작, 보관 입력 소비
	check(p.light_index == 2 and p.attack_t() == 0, "연결창 시작 틱에 2타 시작 (index %d, t=%d)" % [p.light_index, p.attack_t()])
	# 2타 → 3타 → 종료
	idle(b, p.light_attacks[1].total_ticks() - window)
	press(b, "attack_light")
	check(p.light_index == 3, "3타 연결 (index %d)" % p.light_index)
	idle(b, p.light_attacks[2].total_ticks() - window)
	press(b, "attack_light")
	idle(b, 2)
	check(p.state == &"light" and p.light_index == 3, "3타 뒤에는 평타로 연결되지 않음 (state %s, index %d)" % [p.state, p.light_index])
	idle(b, 40)
	check(p.state == &"ground", "평타 종료 후 지상 (%s)" % p.state)

func test_expired_input_does_not_fire(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	press(b, "attack_light")
	idle(b, 1)                    # t=1 (준비 구간)
	press(b, "attack_light")      # t=2 에 누름. 연결창(t=12)까지 10틱 > 7틱 → 만료
	idle(b, 25)
	check(p.state == &"ground" and p.light_index == 0, "만료된 입력은 2타를 발동하지 않음 (state %s)" % p.state)
	# 스킬도 마찬가지: 대기 중 누른 뒤 한참 뒤에 발동하지 않는다
	press(b, "attack_light")
	idle(b, 1)
	press(b, "skill_a")           # 준비 구간에 누름 → 만료
	idle(b, 30)
	check(p.state == &"ground" and p.cooldown_for(p.skill_set.skills[0]) == 0, "만료된 스킬 입력은 발동하지 않음 (state %s)" % p.state)

func test_unimplemented_skill_ignored(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	# HWR-004: 8개 모두 구현. 미구현 표시로 남은 슬롯이 없어야 하고, 미구현 규칙 자체는 유지된다(임시 SkillData 로 확인).
	for sd in p.skill_set.skills:
		check(sd.implemented and sd.attack != null, "%s(%s) 구현·공격 데이터 연결" % [sd.display_name, sd.key_label])
	var fake := SkillData.new()
	fake.id = &"fake"
	fake.action_name = &"skill_r"
	fake.implemented = false
	var real: SkillData = p.skills_by_action[&"skill_r"]
	p.skills_by_action[&"skill_r"] = fake
	press(b, "skill_r")
	idle(b, 2)
	check(p.state == &"ground" and p.buffered_action == &"", "미구현 슬롯 입력은 무시되고 보관도 안 됨 (state %s)" % p.state)
	p.skills_by_action[&"skill_r"] = real

func test_skill_cooldown(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 460, 540)
	press(b, "skill_a")
	var sd: SkillData = p.skill_set.skills[0]
	check(p.state == &"skill" and p.cooldown_for(sd) == 240, "비연참 시작, 대기 %d틱" % p.cooldown_for(sd))
	idle(b, 30)
	check(d.total_damage_taken == 24, "비연참 돌진 적중 24 (피해 %d)" % d.total_damage_taken)
	check(p.floor_pos.x > 300.0 + 150.0, "비연참으로 전진 x=%.0f" % p.floor_pos.x)
	press(b, "skill_a")
	idle(b, 2)
	check(p.state == &"ground", "재사용 대기 중 비연참 재사용 불가 (state %s)" % p.state)
	idle(b, 240)
	check(p.cooldown_for(sd) == 0, "240틱 뒤 대기 종료 (%d)" % p.cooldown_for(sd))

func test_launch_once(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 370, 540)
	press(b, "skill_s")
	idle(b, 6)   # 준비 6틱 → 타격 틱
	check(d.state == &"launched" and d.vz > 0.0 and d.height > 0.0, "승월참에 허수아비 띄워짐 (state %s, vz %.0f)" % [d.state, d.vz])
	check(d.total_damage_taken == 30, "승월참 피해 30 (합계 %d)" % d.total_damage_taken)
	idle(b, 40)  # 스킬 종료(26틱)와 착지(약 25틱)까지 진행
	check(d.height == 0.0 and d.state == &"idle" and p.state == &"ground", "착지 후 대기 상태 (%s / %s)" % [d.state, p.state])
	# 이미 떠 있는 대상: 공중 상태를 강제로 만든 뒤 다시 승월참
	d.change_state(&"launched")
	d.airborne_by_launch = true
	d.height = 60.0
	d.vz = 0.0
	p.cooldowns[p.skill_set.skills[1].id] = 0
	press(b, "skill_s")
	idle(b, 6)
	check(d.total_damage_taken == 60, "공중의 적에게 피해는 적용 (합계 %d)" % d.total_damage_taken)
	check(d.vz < 0.0 and d.state == &"launched", "재차 띄우기 없음: 상승 속도가 다시 생기지 않음 (vz %.0f, 높이 %.0f)" % [d.vz, d.height])
	idle(b, 40)
	check(d.height == 0.0 and d.state == &"idle", "두 번째 착지 후 대기 (%s)" % d.state)

func test_dodge_invulnerability(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	var e := b.spawn_melee_enemy(Vector2(360, 540))
	# 적을 공격 상태로 강제하고 플레이어는 회피 시작
	press(b, "dodge", Vector2(0, 0))
	check(p.state == &"dodge" and p.invuln_ticks == 6, "회피 시작, 무적 %d틱" % p.invuln_ticks)
	e.facing = -1
	e.change_state(&"attack")
	idle(b, 2)      # 무적 중 타격 구간(6틱)과 겹침
	check(p.hp == p.max_hp, "무적 중 피해 없음 (hp %d)" % p.hp)
	idle(b, 20)
	# 회피 뒤 다시 공격받으면 피해
	place(p, 300, 540)
	place(e, 360, 540)
	e.facing = -1
	e.change_state(&"attack")
	idle(b, 3)
	check(p.hp == p.max_hp - 20 and p.state == &"hitstun", "무적 종료 후 피해 20 (HWR-004: 근접 10→20) (hp %d, %s)" % [p.hp, p.state])
	# 회피 재사용 대기
	idle(b, 20)
	press(b, "dodge")
	check(p.state != &"dodge", "재사용 대기 중 회피 불가 (%s)" % p.state)

func test_input_collected_during_hitstop(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 370, 540)
	press(b, "attack_light")
	idle(b, 5)               # t=5: 타격 시작 틱에 적중 → 타격 정지 2틱
	check(p.hitstop_ticks == 2, "적중 직후 타격 정지 %d틱" % p.hitstop_ticks)
	press(b, "attack_light") # 타격 정지 중 입력
	check(p.buffered_action == &"attack_light", "타격 정지 중에도 입력이 보관됨")
	idle(b, 1)
	check(p.hitstop_ticks == 0 and p.attack_t() == 5, "타격 정지 동안 공격 진행이 멈춤 (t=%d)" % p.attack_t())
	# 연결창(t=12)까지 7틱: 보관 만료 전에 도달하므로 2타가 이어져야 한다
	idle(b, 7)
	check(p.light_index == 2, "타격 정지 중 보관한 입력으로 2타 연결 (index %d)" % p.light_index)

func test_death_clears_buffer(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	var e := b.spawn_melee_enemy(Vector2(360, 540))
	p.hp = 5
	press(b, "skill_a")      # 즉시 시작됨(지상). 다시 대기 상태로 만들기 위해 한참 진행
	idle(b, 40)
	p.cooldowns[p.skill_set.skills[0].id] = 0
	place(p, 300, 540)
	place(e, 360, 540)
	e.change_state(&"idle")
	# 공격 준비 구간에 입력을 보관해 두고 그 사이에 사망
	press(b, "attack_light")
	press(b, "skill_a")      # 보관됨 (평타 준비 구간)
	check(p.buffered_action == &"skill_a", "스킬 입력 보관 상태")
	e.facing = -1
	e.change_state(&"attack")
	idle(b, 2)
	check(not p.alive and p.state == &"dead", "사망 처리 (%s)" % p.state)
	check(p.buffered_action == &"", "사망 시 보관 입력 제거")
	idle(b, 60)
	check(p.state == &"dead" and p.cooldown_for(p.skill_set.skills[0]) == 0, "사망 뒤 보관 입력이 실행되지 않음")

func test_enemy_attack_cycle_and_facing_lock(b: Battle) -> void:
	var p := b.player
	place(p, 600, 540)
	var e := b.spawn_melee_enemy(Vector2(900, 600))
	var seen := {}
	var telegraph_facing := 0
	var facing_changed_in_telegraph := false
	for i in 240:
		b.step(PlayerInput.make())
		seen[e.state] = true
		if e.state == &"telegraph":
			if telegraph_facing == 0:
				telegraph_facing = e.facing
				# 예고 중 플레이어가 뒤로 돌아가도 방향이 바뀌지 않아야 한다
				place(p, e.floor_pos.x + 200, e.floor_pos.y)
			elif e.facing != telegraph_facing:
				facing_changed_in_telegraph = true
		if e.state == &"recover":
			break
	check(seen.has(&"approach") and seen.has(&"telegraph") and seen.has(&"attack") and seen.has(&"recover"), "접근→예고→공격→회복 순환 (%s)" % str(seen.keys()))
	check(not facing_changed_in_telegraph and telegraph_facing == -1, "예고 시작 시 방향 고정 (facing %d)" % telegraph_facing)

func test_light_combo_kills_enemy_in_one_set(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	var e := b.spawn_melee_enemy(Vector2(370, 540))
	e.change_state(&"idle")
	for i in 3:
		press(b, "attack_light")
		var atk := p.current_attack
		idle(b, atk.total_ticks() - atk.chain_window_ticks() - 1)
	idle(b, 30)
	check(not e.alive, "평타 3연격(20+20+28=68)으로 체력 65 적 처치 (hp %d, alive %s)" % [e.hp, str(e.alive)])

# ------------------------------------------------------------------ HWR-002 R1 A: 평타 모멘텀

## 현재 평타의 연결창 시작 직전 틱까지 진행한다. 이어서 press 하면 그 틱(연결창 첫 틱)에 소비된다.
func advance_to_chain(b: Battle) -> void:
	var p := b.player
	var atk := p.current_attack
	var target_t := atk.total_ticks() - atk.chain_window_ticks() - 1
	while p.attack_t() < target_t and (p.state == &"light" or p.state == &"skill"):
		idle(b, 1)

func face_left(b: Battle) -> void:
	hold(b, Vector2(-1, 0), 1)
	hold(b, Vector2.ZERO, 4)

func test_r1_advance_totals_both_directions(b: Battle) -> void:
	var p := b.player
	check(b.current_profile().id == &"r1_momentum", "수련장 기본 프로필은 새 모멘텀 (%s)" % b.current_profile().id)
	var expected := [12.0, 18.0, 30.0]
	for dir_name in ["오른쪽", "왼쪽"]:
		# 허수아비(700)에 닿지 않는 위치에서 단독 평타
		place(p, 300 if dir_name == "오른쪽" else 600, 540)
		p.velocity = Vector2.ZERO
		if dir_name == "왼쪽":
			face_left(b)
		var sign := float(p.facing)
		var x0 := p.floor_pos.x
		var deltas: Array[float] = []
		for i in 3:
			var start_x := p.floor_pos.x
			press(b, "attack_light")
			var atk := p.current_attack
			var s := atk.startup_ticks()
			var a := atk.active_ticks()
			idle(b, s - 1)
			check(absf(p.floor_pos.x - start_x) < 0.001, "%s %d타: 준비 구간 동안 전진 없음 (%.2f)" % [dir_name, i + 1, p.floor_pos.x - start_x])
			var first := 0.0
			var last := 0.0
			for k in a:
				var before := p.floor_pos.x
				idle(b, 1)
				var d := absf(p.floor_pos.x - before)
				if k == 0:
					first = d
				last = d
			check(first > last, "%s %d타: 이른 틱 전진(%.2f)이 마지막 틱(%.2f)보다 큼" % [dir_name, i + 1, first, last])
			var after_active := p.floor_pos.x
			advance_to_chain(b)
			check(absf(p.floor_pos.x - after_active) < 0.001, "%s %d타: 회복 구간 전진 없음 (%.2f)" % [dir_name, i + 1, p.floor_pos.x - after_active])
			deltas.append((p.floor_pos.x - start_x) * sign)
		for i in 3:
			check(absf(deltas[i] - expected[i]) < 0.01, "%s %d타 전진 합 %.2f == %.0f" % [dir_name, i + 1, deltas[i], expected[i]])
		idle(b, 30)
		check(p.state == &"ground" and p.velocity.length() < 0.001, "%s: 3연타 뒤 지상 정지 (속도 %.2f)" % [dir_name, p.velocity.length()])
		check(absf((p.floor_pos.x - x0) * sign - 60.0) < 0.01, "%s: 3연타 총 전진 %.2f == 60" % [dir_name, (p.floor_pos.x - x0) * sign])

func test_r1_advance_same_with_hitstop(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	place(p, 300, 540)
	place(d, 370, 540)
	var x0 := p.floor_pos.x
	press(b, "attack_light")
	var atk := p.current_attack
	idle(b, atk.startup_ticks())   # 타격 첫 틱: 적중 → 타격 정지 2틱
	check(p.hitstop_ticks == 2 and d.total_damage_taken == 20, "타격 첫 틱 적중, 타격 정지 %d틱" % p.hitstop_ticks)
	var frozen_x := p.floor_pos.x
	idle(b, 2)
	check(absf(p.floor_pos.x - frozen_x) < 0.001, "타격 정지 중 전진 멈춤")
	idle(b, atk.total_ticks())
	check(absf(p.floor_pos.x - x0 - 12.0) < 0.01, "타격 정지가 있어도 1타 전진 합 %.2f == 12" % (p.floor_pos.x - x0))

func test_r1_advance_no_leak_after_wall_or_hit(b: Battle) -> void:
	var p := b.player
	# 1) 경계: 오른쪽 벽에 붙어 3연타 → 위치 고정, 이후 회피 거리가 평소와 같다
	var r := b.arena_rect()
	var wall_x := r.end.x - p.half_width
	place(p, wall_x, 540)
	for i in 3:
		press(b, "attack_light")
		advance_to_chain(b)
	idle(b, 30)
	check(absf(p.floor_pos.x - wall_x) < 0.001, "벽에서 평타 전진은 잘려 나가고 누적되지 않음 (x %.1f)" % p.floor_pos.x)
	# 벽에서 왼쪽으로 회피: 평소 회피 거리와 비교
	face_left(b)
	var before := p.floor_pos.x
	press(b, "dodge")
	idle(b, 12)
	var wall_dodge := before - p.floor_pos.x
	place(p, 600, 540)
	p.dodge_cooldown_ticks = 0
	face_left(b)
	before = p.floor_pos.x
	press(b, "dodge")
	idle(b, 12)
	var normal_dodge := before - p.floor_pos.x
	check(absf(wall_dodge - normal_dodge) < 0.01 and absf(normal_dodge - 210.0) < 0.5, "벽에서 잘린 전진이 회피에 더해지지 않음 (%.1f vs %.1f)" % [wall_dodge, normal_dodge])
	# 2) 타격 구간에 피격으로 공격이 끊기면 남은 전진을 버린다
	idle(b, 60)
	place(p, 300, 540)
	p.facing = 1
	var e := b.spawn_melee_enemy(Vector2(1100, 540))
	e.change_state(&"idle")
	e.invuln_ticks = 200       # 주인공의 평타가 먼저 닿아 적 공격이 끊기지 않게 한다
	press(b, "attack_light")   # 3타는 전진 30, 타격 5틱
	var atk3: AttackData = p.light_attacks[2]
	advance_to_chain(b)
	press(b, "attack_light")
	advance_to_chain(b)
	press(b, "attack_light")
	check(p.light_index == 3, "3타 시작")
	idle(b, atk3.startup_ticks() + 1)   # 타격 2틱째
	var x_before_hit := p.floor_pos.x
	place(e, p.floor_pos.x + 60, 540)
	e.facing = -1
	e.change_state(&"attack")
	idle(b, 1)
	check(p.state == &"hitstun", "타격 구간에 피격 (%s)" % p.state)
	var kb: float = e.attack_data.knockback
	idle(b, 40)
	check(p.state == &"ground", "경직 종료 후 지상")
	var moved := p.floor_pos.x - x_before_hit
	check(moved <= kb + 0.01, "취소된 3타의 남은 전진이 새지 않음 (이동 %.1f ≤ 밀림 %.0f)" % [moved, kb])
	var rest_x := p.floor_pos.x
	idle(b, 10)
	check(absf(p.floor_pos.x - rest_x) < 0.001, "이후 정지 상태에서 이동 없음")

func _run_combo_on(b: Battle, e: EnemyBase, label: String, expected_damage: int) -> void:
	var p := b.player
	e.total_damage_taken = 0
	for i in 3:
		press(b, "attack_light")
		advance_to_chain(b)
	idle(b, 30)
	check(e.total_damage_taken == expected_damage, "%s: 3연타 피해 %d == %d" % [label, e.total_damage_taken, expected_damage])

func test_r1_combo_connects_on_knockback_target(b: Battle) -> void:
	var p := b.player
	# 체력이 큰 밀리는 검증용 표적(근접 적, 대기 상태)
	for dist in [70.0, 80.0, 90.0]:
		var e := b.spawn_melee_enemy(Vector2(300 + dist, 540))
		e.max_hp = 100000
		e.hp = e.max_hp
		e.change_state(&"idle")
		place(p, 300, 540)
		p.facing = 1
		_run_combo_on(b, e, "오른쪽 %.0fpx" % dist, 68)
		e.queue_free()
		b.enemies.erase(e)
	# 왼쪽 바라보기
	for dist in [70.0, 80.0, 90.0]:
		var e := b.spawn_melee_enemy(Vector2(900 - dist, 540))
		e.max_hp = 100000
		e.hp = e.max_hp
		e.change_state(&"idle")
		place(p, 900, 540)
		face_left(b)
		e.change_state(&"idle")
		_run_combo_on(b, e, "왼쪽 %.0fpx" % dist, 68)
		e.queue_free()
		b.enemies.erase(e)
	# 적을 벽에 붙인 경우: 밀리지 못해도 3타 모두 닿는다
	var wall := b.arena_rect().end.x - 20.0
	var ew := b.spawn_melee_enemy(Vector2(wall, 540))
	ew.max_hp = 100000
	ew.hp = ew.max_hp
	ew.change_state(&"idle")
	place(p, wall - 80.0, 540)
	p.facing = 1
	_run_combo_on(b, ew, "벽에 붙은 적", 68)
	check(absf(ew.floor_pos.x - wall) < 0.001, "벽에 붙은 적은 밀리지 않음 (x %.1f)" % ew.floor_pos.x)
	ew.queue_free()
	b.enemies.erase(ew)
	# 헛치기 후 연결: 1타는 빗나가고 2·3타만 닿는다
	idle(b, 30)
	var ef := b.spawn_melee_enemy(Vector2(700, 540))
	ef.max_hp = 100000
	ef.hp = ef.max_hp
	ef.change_state(&"idle")
	place(p, 300, 540)
	p.facing = 1
	press(b, "attack_light")
	advance_to_chain(b)
	check(ef.total_damage_taken == 0 and p.hitstop_ticks == 0, "헛치기: 피해·타격 정지 없음")
	place(ef, p.floor_pos.x + 75.0, 540)
	press(b, "attack_light")
	check(p.light_index == 2, "헛친 뒤에도 2타 연결")
	advance_to_chain(b)
	press(b, "attack_light")
	idle(b, 40)
	check(ef.total_damage_taken == 48, "헛치기 후 2·3타 적중 피해 %d == 48" % ef.total_damage_taken)

func test_r1_knockback_curve_and_replacement(b: Battle) -> void:
	var p := b.player
	var kd := b.knockback_dummy
	check(kd != null and kd.knockback_enabled and b.dummy != null and not b.dummy.knockback_enabled, "고정 허수아비와 밀림 표적이 따로 있음")
	place(p, 300, 540)
	place(kd, 370, 540)
	var x0 := kd.floor_pos.x
	press(b, "attack_light")
	idle(b, p.light_attacks[0].startup_ticks())   # 적중 틱
	check(kd.state == &"hitstun" and kd.knockback_total == 12.0 and kd.knockback_ticks == 6, "1타 밀림 12px / 6틱(100ms) 설정 (%.0f, %d)" % [kd.knockback_total, kd.knockback_ticks])
	# 타격 정지 2틱 동안 밀림 진행 없음
	idle(b, 2)
	check(absf(kd.floor_pos.x - x0) < 0.001, "타격 정지 중 밀림 없음")
	var steps: Array[float] = []
	for k in 6:
		var before := kd.floor_pos.x
		idle(b, 1)
		steps.append(kd.floor_pos.x - before)
	check(absf(kd.floor_pos.x - x0 - 12.0) < 0.01, "6틱 뒤 밀림 합 %.2f == 12" % (kd.floor_pos.x - x0))
	check(steps[0] > steps[5] and steps[0] > 3.0, "밀림 첫 틱 %.2f > 마지막 틱 %.2f (감속)" % [steps[0], steps[5]])
	check(kd.state == &"hitstun" and kd.knockback_remaining == 0.0, "밀림이 끝나도 경직은 유지 (%s, %d/%d틱)" % [kd.state, kd.state_ticks, kd.hitstun_ticks])
	var x_after := kd.floor_pos.x
	idle(b, 12)
	check(kd.state == &"idle" and absf(kd.floor_pos.x - x_after) < 0.001, "경직 종료 후 추가 이동 없음 (%s)" % kd.state)
	# 교체: 1타 밀림 진행 중 2타가 들어오면 2타 값(18/7틱)으로 바뀌고 합산되지 않는다
	idle(b, 20)
	place(p, 300, 540)
	place(kd, 370, 540)
	x0 = kd.floor_pos.x
	press(b, "attack_light")
	advance_to_chain(b)
	press(b, "attack_light")
	idle(b, p.light_attacks[1].startup_ticks())
	check(kd.knockback_total == 18.0 and kd.knockback_ticks == 7 and kd.knockback_t == 0, "2타 적중 시 밀림 교체 18px/7틱 (%.0f, %d)" % [kd.knockback_total, kd.knockback_ticks])
	idle(b, 30)
	check(absf(kd.floor_pos.x - x0 - 30.0) < 0.01, "1타 12 + 2타 18 = 총 %.2f == 30 (합산 아님, 순차 교체)" % (kd.floor_pos.x - x0))
	# 3타는 65px / 11틱
	idle(b, 10)
	place(p, kd.floor_pos.x - 75.0, 540)
	x0 = kd.floor_pos.x
	press(b, "attack_light")
	advance_to_chain(b)
	press(b, "attack_light")
	advance_to_chain(b)
	press(b, "attack_light")
	idle(b, p.light_attacks[2].startup_ticks())
	check(kd.knockback_total == 65.0 and kd.knockback_ticks == 11, "3타 밀림 65px/11틱(180ms) (%.0f, %d)" % [kd.knockback_total, kd.knockback_ticks])

func test_r1_same_tick_last_hit_wins(b: Battle) -> void:
	var kd := b.knockback_dummy
	place(kd, 600, 540)
	var i1 := HitInfo.new()
	i1.attack = b.player.light_attacks[0]
	i1.damage = 20
	i1.hitstop_ticks = 2
	i1.direction = 1
	var i2 := HitInfo.new()
	i2.attack = b.player.light_attacks[2]
	i2.damage = 28
	i2.hitstop_ticks = 4
	i2.direction = -1
	kd.receive_hit(i1)
	kd.receive_hit(i2)
	check(kd.total_damage_taken == 48, "같은 틱 두 타격의 피해는 각각 적용 (%d)" % kd.total_damage_taken)
	check(kd.knockback_total == 65.0 and kd.knockback_dir == -1 and kd.hitstun_ticks == Ticks.from_ms(420), "밀림·경직은 마지막 적용 타격 값 (%.0f, 방향 %d)" % [kd.knockback_total, kd.knockback_dir])
	check(kd.hitstop_ticks == 4, "타격 정지는 최댓값 (%d)" % kd.hitstop_ticks)

func test_r1_legacy_profile_keeps_m1_behaviour(b: Battle) -> void:
	var p := b.player
	check(b.set_profile(0), "기존 M1 프로필로 전환")
	check(p.light_attacks[0].advance_px == 0.0 and p.light_attacks[0].knockback == 30.0 and p.light_attacks[0].knockback_ms == 0.0, "기존 프로필: 전진 0, 밀림 30, 일정 속도")
	place(p, 300, 540)
	var x0 := p.floor_pos.x
	for i in 3:
		press(b, "attack_light")
		advance_to_chain(b)
	idle(b, 30)
	check(absf(p.floor_pos.x - x0) < 0.001, "기존 프로필 3연타 전진 0 (%.2f)" % (p.floor_pos.x - x0))
	# 일정 속도 밀림: 30px 를 매초 240px → 8틱(7틱 4px + 2px)
	var kd := b.knockback_dummy
	place(p, 300, 540)
	place(kd, 370, 540)
	var kx := kd.floor_pos.x
	press(b, "attack_light")
	idle(b, p.light_attacks[0].startup_ticks() + 2)   # 적중 + 타격 정지
	idle(b, 1)
	check(absf(kd.floor_pos.x - kx - 4.0) < 0.01, "기존 밀림 첫 틱 4px (%.2f)" % (kd.floor_pos.x - kx))
	idle(b, 7)
	check(absf(kd.floor_pos.x - kx - 30.0) < 0.01 and kd.knockback_remaining == 0.0, "기존 밀림 8틱 뒤 30px (%.2f)" % (kd.floor_pos.x - kx))

func test_r1_profile_switch_rules(b: Battle) -> void:
	var p := b.player
	var legacy: CombatProfile = b.profiles[0]
	var r1: CombatProfile = b.profiles[1]
	place(p, 300, 540)
	press(b, "attack_light")
	check(not b.set_profile(0) and b.profile_index == 1, "공격 중에는 프로필 전환 거부")
	idle(b, 30)
	check(b.set_profile(0) and p.profile_id == &"m1_legacy", "행동 종료 후 전환 허용")
	check(b.toggle_profile() and p.profile_id == &"r1_momentum", "F2 토글로 새 모멘텀 복귀")
	# 공유 Resource 가 수정되지 않았다
	check(legacy.light_attacks[0].advance_px == 0.0 and legacy.light_attacks[2].knockback == 70.0, "기존 프로필 리소스 값 보존")
	check(r1.light_attacks[0].advance_px == 12.0 and r1.light_attacks[2].knockback == 65.0 and r1.light_attacks[2].knockback_ms == 180.0, "새 프로필 리소스 값 보존")
	check(legacy.light_attacks[0] != r1.light_attacks[0], "두 프로필은 서로 다른 리소스를 참조")
	# 캠페인 모드에서는 전환 불가
	b.mode = &"campaign"
	check(not b.set_profile(0) and p.profile_id == &"r1_momentum", "캠페인 모드에서는 프로필 전환 불가")
	b.mode = &"training"

# ------------------------------------------------------------------ HWR-004 R1: 강인병

## 경직 300ms·피해 dmg 의 일반 타격을 직접 적용한다(테스트용). 밀림은 공격 값(20)을 쓴다.
func hit_with(target: BattleActor, dmg: int, extra: Dictionary = {}) -> HitInfo:
	var info := HitInfo.new()
	info.attack = AttackData.new()
	info.attack.hitstun_ms = 300.0
	info.attack.knockback = 20.0
	for k in extra.keys():
		info.attack.set(k, extra[k])
	info.damage = dmg
	info.hitstop_ticks = 4
	info.direction = 1
	target.receive_hit(info)
	return info

func test_h4_brute_immune_patterns_progress_under_hits(b: Battle) -> void:
	var p := b.player
	p.max_hp = 100000
	p.hp = p.max_hp
	place(p, 300, 540)
	var br := b.spawn_brute_enemy(Vector2(900, 540))
	check(br.max_hp == 180 and br.half_width == 32.0 and br.half_depth == 14.0 and br.body_height == 94.0 and br.is_stagger_immune(), "강인병 체력 180, 피격 범위 32/14/94")
	# 접근 → 발 간격 x90/y8 안에서 허가 → 예고(방향 고정)
	var reached := false
	for i in 400:
		b.step(PlayerInput.make())
		if br.state == &"telegraph":
			reached = true
			break
	check(reached and absf(br.floor_pos.x - p.floor_pos.x) <= 90.0 + 0.01 and absf(br.floor_pos.y - p.floor_pos.y) <= 8.0, "접근 후 x≤90/y≤8 에서 예고 시작 (dx %.0f dy %.0f)" % [absf(br.floor_pos.x - p.floor_pos.x), absf(br.floor_pos.y - p.floor_pos.y)])
	check(br.current_pattern == 0 and br.facing == -1 and b.attack_slot_holders.has(br), "첫 패턴은 전방 2연격, 방향 고정(-1), 공격 허가 보유")
	# 예고~회복 동안 매 틱 타격(피해 1, 히트스톱 4): 시계가 실제로 진행하고 경직·밀림·타격 정지가 없다
	var x0 := br.floor_pos.x
	var telegraph_ticks := 0
	var max_hitstop := 0
	var states := {}
	var hp_before := br.hp
	var hits := 0
	while br.state == &"telegraph" and telegraph_ticks < 200:
		hit_with(br, 1)
		hits += 1
		max_hitstop = maxi(max_hitstop, br.hitstop_ticks)
		b.step(PlayerInput.make())
		telegraph_ticks += 1
		states[br.state] = true
	check(telegraph_ticks == Ticks.from_ms(700.0), "반복 피격 중에도 예고 0.7초(42틱)가 지연 없이 진행 (%d틱)" % telegraph_ticks)
	check(max_hitstop == 0 and br.hp == hp_before - hits and absf(br.floor_pos.x - x0) < 0.001, "피격 타격 정지 0, HP 는 정확히 감소(%d), 밀림 0" % (hp_before - br.hp))
	# 타격 구간: 첫 타(hit_index 0) → 15틱 간격 → 두 번째 타(hit_index 1). 매 틱 피격 중에도 두 타격이 만들어진다.
	var attack_ticks := 0
	var idx_seen := {}
	while br.state == &"attack" and attack_ticks < 100:
		hit_with(br, 1)
		for hb in br.active_hitboxes:
			idx_seen[hb.hit_index] = hb.instance_id
		b.step(PlayerInput.make())
		attack_ticks += 1
	check(idx_seen.has(0) and idx_seen.has(1) and idx_seen[0] != idx_seen[1] and br.hits_created == 2, "2연격: hit_index 0/1 의 서로 다른 판정 2개 (%s)" % str(idx_seen.keys()))
	# 27틱 + 회복 전이 1틱 + 자기 타격이 실제 적중했을 때의 공격자 타격 정지(강공격 4틱 × 2). 피격 쪽 정지는 0.
	check(attack_ticks == 6 + 15 + 6 + 1 + 2 * Ticks.from_ms(60.0) and br.state == &"recover", "타격 27틱(+공격자 히트스톱 8, 전이 1) 뒤 회복 (%d틱, %s)" % [attack_ticks, br.state])
	# 플레이어는 2연격 첫 타 24 + 두 번째 타 24 를 받았다(각 1회)
	check(p.max_hp - p.hp == 48, "2연격 두 타 모두 각 1회 적중, 총 48 (%d)" % (p.max_hp - p.hp))
	var recover_ticks := 0
	while br.state == &"recover" and recover_ticks < 200:
		hit_with(br, 1)
		b.step(PlayerInput.make())
		recover_ticks += 1
	check(recover_ticks == Ticks.from_ms(900.0) and br.state == &"idle" and not b.attack_slot_holders.has(br), "회복 0.9초(54틱) 뒤 대기, 허가 반환 (%d틱)" % recover_ticks)
	check(not states.has(&"hitstun") and not states.has(&"launched") and not states.has(&"down"), "경직/띄우기/다운 상태에 들어가지 않음")
	# 띄우기(승월참)·다운 면역: 높이 0 유지
	var launch_atk := load("res://data/attacks/seungwolcham.tres")
	var li := HitInfo.new()
	li.attack = launch_atk
	li.damage = 30
	li.hitstop_ticks = 4
	li.direction = 1
	br.receive_hit(li)
	b.step(PlayerInput.make())
	check(br.height == 0.0 and br.vz == 0.0 and br.state != &"launched", "올려베기에 띄워지지 않음 (높이 %.0f)" % br.height)
	hit_with(br, 1, {"knockdown": true})
	b.step(PlayerInput.make())
	check(br.state != &"down" and br.state != &"launched", "내려베기 다운 면역 (%s)" % br.state)
	# 다음 패턴은 내려찍기(교대)
	check(br.next_pattern == 1, "다음 패턴은 주변 내려찍기")

func test_h4_brute_slam_ellipse_and_slot(b: Battle) -> void:
	var p := b.player
	p.max_hp = 100000
	p.hp = p.max_hp
	place(p, 300, 540)
	var br := b.spawn_brute_enemy(Vector2(600, 540))
	br.next_pattern = 1
	br.state = &"idle"
	br.state_ticks = 1000
	# 접근 후 예고가 시작되면 플레이어를 타원 밖(dx 100, dy 30 → 0.83+0.44 > 1)으로 옮긴다
	for i in 300:
		b.step(PlayerInput.make())
		if br.state == &"telegraph":
			break
	check(br.state == &"telegraph" and br.current_pattern == 1, "내려찍기 예고 (%s, 패턴 %d)" % [br.state, br.current_pattern])
	var cx := br.floor_pos.x
	var cy := br.floor_pos.y
	place(p, cx - 100.0, cy + 30.0)
	p.change_state(&"ground")
	var t := 0
	while br.state == &"telegraph" and t < 200:
		b.step(PlayerInput.make())
		t += 1
	check(t == Ticks.from_ms(950.0) and br.state == &"attack", "내려찍기 예고 0.95초(57틱) (%d)" % t)
	check(absf(br.floor_pos.x - cx) < 0.001 and absf(br.floor_pos.y - cy) < 0.001, "예고 중 기준 위치 고정")
	idle(b, 7)
	check(p.hp == p.max_hp, "타원 밖(dx 100, dy 30)은 빗나감")
	check(br.state == &"recover", "타격 0.1초 뒤 회복 (%s)" % br.state)
	# 두 번째 내려찍기: 타원 안(dx 100, dy 0)이면 적중, 높이 100 이면 빗나감
	br.next_pattern = 1
	br.change_state(&"idle")
	br.state_ticks = 1000
	b.release_attack_slot(br)
	place(p, br.floor_pos.x - 60.0, br.floor_pos.y)
	p.change_state(&"ground")
	for i in 300:
		b.step(PlayerInput.make())
		if br.state == &"telegraph":
			break
	check(br.state == &"telegraph" and br.current_pattern == 1, "두 번째 내려찍기 예고")
	cx = br.floor_pos.x
	cy = br.floor_pos.y
	place(p, cx - 100.0, cy, 100.0)
	p.change_state(&"air")
	p.vz = 0.0
	while br.state == &"telegraph":
		p.height = 100.0
		p.vz = 0.0
		b.step(PlayerInput.make())
	p.height = 100.0
	p.vz = 0.0
	b.step(PlayerInput.make())
	check(p.hp == p.max_hp and br.state == &"attack", "높이 100(피격 z 100~170)은 0~90 범위 밖이라 빗나감")
	place(p, cx - 100.0, cy)
	p.change_state(&"ground")
	b.step(PlayerInput.make())
	check(p.max_hp - p.hp == 24 and p.state == &"hitstun", "타원 안(dx 100, dy 0)·지상 → 24 피해 (%d)" % (p.max_hp - p.hp))
	check(not br.slam.parryable and br.combo_hit.parryable, "내려찍기 반격 불가, 2연격 반격 가능")

func test_h4_brute_guard_break_stagger_once(b: Battle) -> void:
	var p := b.player
	p.invuln_ticks = 100000
	place(p, 300, 540)
	var br := b.spawn_brute_enemy(Vector2(380, 540))
	br.state = &"idle"
	br.state_ticks = 1000
	for i in 200:
		b.step(PlayerInput.make())
		if br.state == &"telegraph":
			break
	check(br.state == &"telegraph" and b.attack_slot_holders.has(br), "예고 중·허가 보유")
	idle(b, 10)
	# Q(guard_break): 현재 공격 취소, 무너짐 1초, 허가 반환
	hit_with(br, 5, {"guard_break": true})
	check(br.state == &"stagger" and br.active_hitboxes.is_empty() and not b.attack_slot_holders.has(br), "Q 적중: 자세 무너짐, 판정·허가 정리 (%s)" % br.state)
	b.step(PlayerInput.make())
	check(br.stagger_remaining_ticks() == 59 and br.hitstop_ticks == 0, "적용 다음 틱부터 60틱 (남은 %d)" % br.stagger_remaining_ticks())
	idle(b, 20)
	var rem := br.stagger_remaining_ticks()
	hit_with(br, 5, {"guard_break": true})
	hit_with(br, 5)
	check(br.stagger_remaining_ticks() == rem and br.staggers == 1, "Q 재적중·다른 타격으로 갱신/연장 없음 (남은 %d)" % br.stagger_remaining_ticks())
	b.step(PlayerInput.make())
	check(br.stagger_remaining_ticks() == rem - 1, "피해를 받아도 시간이 멈추지 않음")
	idle(b, rem - 2)
	check(br.state == &"stagger" and br.stagger_remaining_ticks() == 1, "무너짐 마지막 틱 (남은 %d)" % br.stagger_remaining_ticks())
	b.step(PlayerInput.make())
	check(br.state == &"idle", "60틱 뒤 대기로 복귀 (%s)" % br.state)
	# 복귀 후: 새 허가와 온전한 예고(중간 타격 상태로 돌아가지 않음)
	var tele := 0
	var prev: StringName = br.state
	for i in 400:
		b.step(PlayerInput.make())
		if br.state == &"telegraph":
			tele += 1
		elif prev == &"telegraph":
			break
		prev = br.state
	check(br.state == &"attack" and (tele == Ticks.from_ms(700.0) or tele == Ticks.from_ms(950.0)), "복귀 후 온전한 예고 (%d틱, %s)" % [tele, br.state])
	check(b.attack_slot_holders.size() <= 1, "허가 누수 없음 (%d)" % b.attack_slot_holders.size())

# ------------------------------------------------------------------ HWR-004 R1: 보스 반응·선택·회복 재배치

func test_h4_boss_hitstop_policy_selection_and_recover_step(b: Battle) -> void:
	var p := b.player
	p.invuln_ticks = 100000
	place(p, 400, 540)
	var boss := b.spawn_captain(Vector2(480, 540))
	boss.change_state(&"idle")
	boss.state_ticks = 1000
	# 대기 중 평타: 짧은 경직 7틱 + 타격 정지 2 (기존)
	var li := HitInfo.new()
	li.attack = p.light_attacks[0]
	li.damage = 20
	li.hitstop_ticks = 2
	li.direction = 1
	boss.receive_hit(li)
	check(boss.state == &"hitstun" and boss.hitstop_ticks == 2, "대기 중 평타: 짧은 경직·타격 정지 2 (%s, %d)" % [boss.state, boss.hitstop_ticks])
	idle(b, 15)
	boss.change_state(&"idle")
	boss.state_ticks = 1000
	# 대기 중 Q/W/R(ignores_boss_flinch): 피해만, 경직·타격 정지 0
	hit_with(boss, 60, {"ignores_boss_flinch": true, "guard_break": true})
	check(boss.state == &"idle" and boss.hitstop_ticks == 0 and boss.hp == 600 - 20 - 60, "대기 중 Q: 상태 유지·타격 정지 0·피해 60 (%s)" % boss.state)
	# 패턴 중 연타: 예고 시간이 지연되지 않는다
	for i in 100:
		b.step(PlayerInput.make())
		if boss.state == &"telegraph":
			break
	check(boss.state == &"telegraph" and boss.current_pattern == 0, "|dx| 80 → 베기 예고")
	var t := 0
	var max_stop := 0
	while boss.state == &"telegraph" and t < 100:
		hit_with(boss, 1)
		max_stop = maxi(max_stop, boss.hitstop_ticks)
		b.step(PlayerInput.make())
		t += 1
	check(t == Ticks.from_ms(600.0) and max_stop == 0, "패턴 중 매 틱 피격에도 예고 36틱 유지, 피격 타격 정지 0 (%d, %d)" % [t, max_stop])
	# 회복: 첫 18틱 동안 공격 방향 반대로 60px, 이후 정지. 총 회복 48틱 유지.
	while boss.state == &"attack":
		b.step(PlayerInput.make())
	check(boss.state == &"recover", "타격 뒤 회복")
	var rx := boss.floor_pos.x
	var f := boss.facing
	idle(b, 18)
	check(absf((rx - boss.floor_pos.x) * f - 60.0) < 0.01, "회복 첫 300ms 에 뒤로 60px (%.1f)" % ((rx - boss.floor_pos.x) * f))
	var rx2 := boss.floor_pos.x
	var rt := 18
	while boss.state == &"recover":
		b.step(PlayerInput.make())
		rt += 1
	check(absf(boss.floor_pos.x - rx2) < 0.001 and rt == Ticks.from_ms(800.0), "이후 이동 없음, 회복 총 48틱 (%d)" % rt)
	check(boss.recent_patterns.size() == 1 and boss.recent_patterns[0] == 0, "완료 패턴 기록")
	# 벽: 오른쪽 벽에 붙어 왼쪽을 공격하면 후퇴가 벽에서 잘린다
	var r := b.arena_rect()
	place(boss, r.end.x - boss.half_width - 10.0, 540)
	place(p, boss.floor_pos.x - 80.0, 540)
	boss.change_state(&"approach")
	for i in 200:
		b.step(PlayerInput.make())
		if boss.state == &"recover":
			break
	idle(b, 18)
	check(boss.floor_pos.x <= r.end.x - boss.half_width + 0.01 and boss.floor_pos.x >= r.end.x - boss.half_width - 0.01, "벽에서 후퇴 중단 (x %.0f, 벽 %.0f)" % [boss.floor_pos.x, r.end.x - boss.half_width])
	# 선택 교착 없음: 여러 위치에서 접근 → 예고에 도달
	for pos in [Vector2(300, 540), Vector2(300, 700), Vector2(1100, 450), Vector2(r.end.x - 40, 540)]:
		place(p, pos.x, pos.y)
		place(boss, 640, 540)
		boss.recent_patterns.clear()
		boss.change_state(&"approach")
		var ok := false
		for i in 600:
			b.step(PlayerInput.make())
			if boss.state == &"telegraph":
				ok = true
				break
		check(ok, "플레이어 %s 에서 접근 → 예고 도달" % str(pos))
	# 돌진 후보: |dx| 200 같은 깊이 → 베기 불가, 돌진 사용. 돌진 중 연타해도 이동 300 유지
	place(boss, 400, 540)
	place(p, 600, 540)
	boss.recent_patterns.clear()
	boss.change_state(&"approach")
	b.step(PlayerInput.make())
	check(boss.state == &"telegraph" and boss.current_pattern == 1, "|dx| 200 → 돌진 (패턴 %d, %s)" % [boss.current_pattern, boss.state])
	var sx := boss.floor_pos.x
	while boss.state != &"recover":
		hit_with(boss, 1)
		b.step(PlayerInput.make())
	check(absf(boss.floor_pos.x - sx - 300.0) < 0.01, "돌진 중 매 틱 피격에도 300px 이동 (%.0f)" % (boss.floor_pos.x - sx))

# ------------------------------------------------------------------ HWR-004 R1: D/F/Q/W

func big_enemy(b: Battle, x: float, y: float) -> MeleeEnemy:
	var e := b.spawn_melee_enemy(Vector2(x, y))
	e.max_hp = 100000
	e.hp = e.max_hp
	e.change_state(&"idle")
	e.state_ticks = -1000000
	return e

func skill(b: Battle, key: String) -> SkillData:
	return b.player.skills_by_action[StringName("skill_" + key)]

func test_h4_skill_d_knockdown_ground_air_down_getup(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	var e := big_enemy(b, 380, 540)
	var sd := skill(b, "d")
	check(sd.implemented and sd.attack.startup_ticks() == 9 and sd.attack.active_ticks() == 5 and sd.attack.recovery_ticks() == 16 and sd.cooldown_ticks() == 480, "내려베기 9/5/16 틱, 재사용 480틱")
	press(b, "skill_d")
	check(p.state == &"skill" and p.cooldown_for(sd) == 480, "내려베기 시작·재사용 적용")
	idle(b, 9)
	check(e.total_damage_taken == 44 and e.state == &"down" and absf(e.floor_pos.x - 380.0) < 0.001, "지상 적: 피해 44, 즉시 다운, 수평 밀림 0 (%s, %d)" % [e.state, e.total_damage_taken])
	var down_t := e.state_ticks
	# 다운 중 재차 내려베기: 피해만, 다운 타이머 재시작 없음
	idle(b, 25)
	p.cooldowns[sd.id] = 0
	var dt_before := e.state_ticks
	press(b, "skill_d")
	idle(b, 9)
	check(e.total_damage_taken == 88 and e.state == &"down" and e.state_ticks == dt_before + 10, "다운 중 피해만, 타이머 유지 (state_ticks %d → %d)" % [dt_before, e.state_ticks])
	# 다운 0.6초 → 기상 보호 0.5초(무적) → 대기
	while e.state == &"down":
		idle(b, 1)
	check(e.state == &"getup" and e.invuln_ticks == 30, "다운 36틱 뒤 기상 보호 30틱 (%s, 무적 %d)" % [e.state, e.invuln_ticks])
	p.cooldowns[sd.id] = 0
	press(b, "skill_d")
	idle(b, 9)
	check(e.total_damage_taken == 88 and e.state == &"getup", "기상 보호 중 피해 없음 (%d, %s)" % [e.total_damage_taken, e.state])
	idle(b, 40)
	check(e.state == &"idle", "기상 뒤 대기 (%s)" % e.state)
	# 실제 S→D 시간표(검수 6): 올려베기 t6 띄움(양쪽 강공격 히트스톱 4틱, vz 520 → 체공 25틱 → 착지 t34), S 종료 t30,
	# 내려베기 준비 9틱 → 적중 t40. 적은 이미 착지해 down 이므로 D 는 '다운 중 피해만' 이다. 수치로 콤보를 주장하지 않고 실측을 기록한다.
	place(p, 300, 540)
	place(e, 370, 540)
	e.change_state(&"idle")
	e.state_ticks = -1000000
	e.total_damage_taken = 0
	p.cooldowns[skill(b, "s").id] = 0
	p.cooldowns[sd.id] = 0
	press(b, "skill_s")
	var tk := 0
	var launch_tick := -1
	var land_tick := -1
	var d_hit_tick := -1
	var state_at_d_hit: StringName = &""
	var pressed_d := false
	var d_press_tick := -1
	while tk < 120:
		if not pressed_d and p.state == &"ground":
			press(b, "skill_d")
			pressed_d = true
			d_press_tick = tk
		else:
			idle(b, 1)
		tk += 1
		if launch_tick < 0 and e.state == &"launched":
			launch_tick = tk
		if launch_tick >= 0 and land_tick < 0 and e.height <= 0.0 and e.state != &"launched":
			land_tick = tk
		if pressed_d and d_hit_tick < 0 and e.total_damage_taken >= 30 + 44:
			d_hit_tick = tk
			state_at_d_hit = e.state
		if d_hit_tick >= 0 and tk > d_hit_tick + 5:
			break
	print("    [측정] S→D: 띄움 t%d, 착지 t%d, D 입력 t%d, D 적중 t%d, 적중 시 적 상태 %s" % [launch_tick, land_tick, d_press_tick, d_hit_tick, state_at_d_hit])
	check(launch_tick == 6 and land_tick == 34 and d_press_tick == 30 and d_hit_tick == 40 and state_at_d_hit == &"down", "S→D 실측: 띄움 6/착지 34/D 입력 30/적중 40 (다운 중 피해만) — 공중에서 연결되지 않음")
	check(e.total_damage_taken == 74, "S 30 + D 44 = 74 (%d)" % e.total_damage_taken)
	# 공중 적 규칙 자체: 떠 있는 적(높이 60, vz 0)에 D → z 를 옮기지 않고 vz ≤ -500, 착지 전 추가 띄우기 금지, 착지 후 다운
	idle(b, 60)
	place(p, 300, 540)
	place(e, 370, 540, 60.0)
	e.change_state(&"launched")
	e.airborne_by_launch = true
	e.vz = 0.0
	e.total_damage_taken = 0
	p.cooldowns[sd.id] = 0
	press(b, "skill_d")
	for i in 8:
		e.height = 60.0
		e.vz = 0.0
		idle(b, 1)
	var h_before := e.height
	idle(b, 1)
	check(e.total_damage_taken == 44 and e.vz <= -500.0 and e.height > 0.0 and absf(e.height - h_before) < 20.0, "공중 적중: vz %.0f ≤ -500, 순간 이동 없음(높이 %.0f→%.0f)" % [e.vz, h_before, e.height])
	var li := HitInfo.new()
	li.attack = load("res://data/attacks/seungwolcham.tres")
	li.damage = 1
	li.hitstop_ticks = 0
	li.direction = 1
	e.receive_hit(li)
	check(e.vz <= -500.0 and e.height > 0.0, "착지 전 추가 띄우기 없음 (vz %.0f)" % e.vz)
	var landed := false
	for i in 60:
		idle(b, 1)
		if e.height <= 0.0:
			landed = true
			break
	check(landed and e.state == &"down", "실제 착지 후 다운 (%s)" % e.state)

func test_h4_skill_f_both_sides_once_outward(b: Battle) -> void:
	var p := b.player
	place(p, 640, 540)
	place(b.dummy, 1200, 700)
	place(b.knockback_dummy, 1200, 720)
	var right := big_enemy(b, 720, 540)
	var left := big_enemy(b, 560, 540)
	var far := big_enemy(b, 800, 540)
	var deep := big_enemy(b, 700, 590)
	var sd := skill(b, "f")
	check(sd.attack.startup_ticks() == 5 and sd.attack.active_ticks() == 5 and sd.attack.recovery_ticks() == 14 and sd.cooldown_ticks() == 600, "회전베기 5/5/14 틱, 재사용 600틱")
	var hits := [0]
	b.hit_applied.connect(func(a, _t, _i): if a == p: hits[0] += 1)
	press(b, "skill_f")
	idle(b, 5)
	check(right.total_damage_taken == 36 and left.total_damage_taken == 36, "양쪽 36 (%d/%d)" % [right.total_damage_taken, left.total_damage_taken])
	check(right.knockback_dir == 1 and left.knockback_dir == -1 and right.hitstun_ticks == 18 and left.knockback_total == 20.0, "바깥으로 20px 밀림·300ms 경직")
	idle(b, 30)
	check(hits[0] == 2 and far.total_damage_taken == 0 and deep.total_damage_taken == 0, "대상당 1회(총 %d), 범위 밖(x 160)·깊이 50 은 빗나감" % hits[0])
	check(right.floor_pos.x > 720.0 + 19.0 and left.floor_pos.x < 560.0 - 19.0, "밀림 결과 좌우 바깥 (%.0f / %.0f)" % [right.floor_pos.x, left.floor_pos.x])

func test_h4_skill_q_normal_brute_boss(b: Battle) -> void:
	var p := b.player
	place(p, 300, 540)
	var e := big_enemy(b, 380, 540)
	var sd := skill(b, "q")
	check(sd.attack.startup_ticks() == 15 and sd.attack.active_ticks() == 6 and sd.attack.recovery_ticks() == 21 and sd.cooldown_ticks() == 720, "방어깨기 15/6/21 틱, 재사용 720틱")
	press(b, "skill_q")
	idle(b, 15)
	check(e.total_damage_taken == 60 and e.state == &"hitstun" and e.hitstun_ticks == 27 and e.knockback_total == 35.0, "일반 적: 60, 경직 450ms(27틱), 밀림 35 (%s)" % e.state)
	check(p.hitstop_ticks == 4, "공격자 타격 정지 강공격 4틱")
	idle(b, 60)
	b.enemies.erase(e)
	e.free()
	# 강인병: 60 피해 + 무너짐, 피격 타격 정지 0
	place(p, 300, 540)
	var br := b.spawn_brute_enemy(Vector2(390, 540))
	br.state = &"idle"
	br.state_ticks = 1000
	for i in 100:
		idle(b, 1)
		if br.state == &"telegraph":
			break
	p.cooldowns[sd.id] = 0
	press(b, "skill_q")
	idle(b, 15)
	check(br.total_damage_taken == 60 and br.state == &"stagger" and br.hitstop_ticks == 0 and not b.attack_slot_holders.has(br), "강인병: 60·무너짐·타격 정지 0·허가 반환 (%s)" % br.state)
	idle(b, 30)
	b.enemies.erase(br)
	br.free()
	# 보스: 어느 상태에서도 피해만
	place(p, 300, 540)
	var boss := b.spawn_captain(Vector2(390, 540))
	boss.change_state(&"idle")
	boss.state_ticks = -100000
	p.cooldowns[sd.id] = 0
	press(b, "skill_q")
	idle(b, 15)
	check(boss.hp == 540 and boss.state == &"idle" and boss.hitstop_ticks == 0, "보스 대기 중 Q: 피해 60, 상태 유지, 타격 정지 0 (%s)" % boss.state)
	idle(b, 40)
	boss.state_ticks = 1000
	for i in 100:
		idle(b, 1)
		if boss.state == &"telegraph":
			break
	var st := boss.state
	p.cooldowns[sd.id] = 0
	place(p, boss.floor_pos.x - 80.0 * boss.facing * -1, 540)
	press(b, "skill_q")
	idle(b, 15)
	check(boss.hp == 480 and boss.state == st, "보스 패턴 중 Q: 피해만, 패턴 유지 (%s)" % boss.state)

func test_h4_skill_w_pierce_order_limits_and_reactions(b: Battle) -> void:
	var p := b.player
	place(p, 200, 540)
	p.facing = 1
	# 등록 순서를 거꾸로(먼 적부터) 두어 배열 순서가 아니라 접촉 거리순임을 확인한다
	var e700 := big_enemy(b, 700, 540)
	var e600 := big_enemy(b, 600, 540)
	var e500 := big_enemy(b, 500, 540)
	var e400 := big_enemy(b, 400, 540)
	var sd := skill(b, "w")
	check(sd.attack.startup_ticks() == 6 and sd.attack.active_ticks() == 3 and sd.attack.recovery_ticks() == 12 and sd.cooldown_ticks() == 420, "검기 6/3/12 틱, 재사용 420틱")
	var melee_hb := [0]
	press(b, "skill_w")
	var fired_tick := -1
	for i in 30:
		if not p.active_hitboxes.is_empty():
			melee_hb[0] += 1
		idle(b, 1)
		if fired_tick < 0 and b.projectiles.size() > 0:
			fired_tick = i
	check(fired_tick == 5 and melee_hb[0] == 0, "t=6 에 투사체 1개, 근접 판정 0 (발사 %d)" % (fired_tick + 1))
	idle(b, 30)
	check(e400.total_damage_taken == 32 and e500.total_damage_taken == 32 and e600.total_damage_taken == 32 and e700.total_damage_taken == 0, "가까운 3명만 32 (%d/%d/%d/%d)" % [e400.total_damage_taken, e500.total_damage_taken, e600.total_damage_taken, e700.total_damage_taken])
	check(b.projectiles.is_empty(), "세 번째 적중 직후 소멸")
	check(e400.hitstun_ticks == 12 and e400.knockback_total == 10.0, "일반 적 200ms 경직·10px 밀림")
	# 무적/아군 통과: 관통 수 미소비, 뒤늦게 재타격 없음
	idle(b, 40)
	for e in [e400, e500, e600, e700]:
		e.total_damage_taken = 0
		e.change_state(&"idle")
		e.state_ticks = -1000000
	var inv := big_enemy(b, 300, 540)
	inv.invuln_ticks = 100000
	var ally := Dummy.new()
	b.actors_root.add_child(ally)
	ally.configure(b.tuning, b, Vector2(350, 540))
	ally.team = &"player"
	b.allies.append(ally)
	p.cooldowns[sd.id] = 0
	press(b, "skill_w")
	idle(b, 60)
	check(inv.total_damage_taken == 0 and ally.total_damage_taken == 0 and e400.total_damage_taken == 32 and e600.total_damage_taken == 32 and e700.total_damage_taken == 0, "무적·아군 통과(미소비), 그 뒤 3명 (%d/%d/%d/%d)" % [inv.total_damage_taken, e400.total_damage_taken, e600.total_damage_taken, e700.total_damage_taken])
	b.allies.erase(ally)
	ally.free()
	# 무적이 풀려도 이미 지나간 검기는 재타격하지 않는다(다음 검기까지 대기 없음)
	inv.invuln_ticks = 0
	idle(b, 10)
	check(inv.total_damage_taken == 0, "지나간 대상 재타격 없음")
	# 사거리: 시작 x+30 에서 500 이동. 시작 230 → 중심 730 까지, 반길이 10 → 740 근처까지 판정. 760 의 적(피격 738~782) 은 맞고 800 은 안 맞음
	idle(b, 30)
	for e in b.enemies.duplicate():
		if e is MeleeEnemy:
			b.enemies.erase(e)
			e.free()
	var e760 := big_enemy(b, 760, 540)
	var e800 := big_enemy(b, 800, 540)
	place(p, 200, 540)
	p.cooldowns[sd.id] = 0
	press(b, "skill_w")
	idle(b, 60)
	check(e760.total_damage_taken == 32 and e800.total_damage_taken == 0 and b.projectiles.is_empty(), "사거리 500(+반길이 10) 안 적중, 밖 미적중, 만료 제거 (%d/%d)" % [e760.total_damage_taken, e800.total_damage_taken])
	# 왼쪽 방향·보스 반응(피해만)
	idle(b, 10)
	var boss := b.spawn_captain(Vector2(300, 540))
	boss.change_state(&"idle")
	boss.state_ticks = -100000
	place(p, 500, 540)
	face_left(b)
	p.cooldowns[sd.id] = 0
	press(b, "skill_w")
	idle(b, 30)
	check(boss.hp == 600 - 32 and boss.state == &"idle" and boss.hitstop_ticks == 0, "왼쪽 검기: 보스 피해 32 만, 경직 없음 (%s)" % boss.state)

func test_h4_new_skill_cancel_lock_cooldown_and_air(b: Battle) -> void:
	var p := b.player
	var sa := skill(b, "a")
	for key in ["d", "f", "q", "w"]:
		place(p, 300, 540)
		p.velocity = Vector2.ZERO
		var sd := skill(b, key)
		p.cooldowns[sd.id] = 0
		p.cooldowns[sa.id] = 0
		press(b, "skill_" + key)
		var total: int = sd.attack.total_ticks()
		var mc: int = sd.attack.move_cancel_ticks()
		idle(b, total - mc - 1)
		check(p.state == &"skill" and p.attack_t() == total - mc - 1, "%s: 이동 취소 창 직전 (t=%d)" % [key, p.attack_t()])
		# 이동 + 다른 스킬(A) 동시 입력: 이동 취소는 되지만 A 는 원래 종료(t=total)까지 실행되지 않는다
		b.step(PlayerInput.make(Vector2(1, 0), ["skill_a"]))
		check(p.state == &"ground" and p.action_lock_ticks == mc and p.cooldown_for(sa) == 0, "%s: 이동 취소 뒤 남은 제한 %d틱, A 미실행" % [key, p.action_lock_ticks])
		hold(b, Vector2(1, 0), mc - 1)
		check(p.state == &"ground" and p.cooldown_for(sa) == 0, "%s: 원래 종료 직전까지 A 실행 없음 (lock %d)" % [key, p.action_lock_ticks])
		hold(b, Vector2(1, 0), 1)
		check(p.state == &"skill" and p.current_skill == sa, "%s: 원래 종료 시점(t=%d)에 보관한 A 실행" % [key, total])
		check(p.cooldown_for(sd) == sd.cooldown_ticks() - total, "%s: 재사용은 시작 시 1회, 취소해도 돌려주지 않음 (%d)" % [key, p.cooldown_for(sd)])
		idle(b, 60)
	# 회피 취소 뒤에도 제한 유지: D t24 회피 → 회피(11틱) 뒤 평타 가능(원래 종료 t30 < 회피 종료 t35)
	place(p, 300, 540)
	var sd := skill(b, "d")
	p.cooldowns[sd.id] = 0
	p.dodge_cooldown_ticks = 0
	press(b, "skill_d")
	idle(b, 23)
	press(b, "dodge")
	check(p.state == &"dodge" and p.action_lock_ticks == 6, "D t24 회피 취소, 남은 제한 6틱")
	press(b, "attack_light")
	idle(b, 3)
	check(p.state == &"dodge", "회피 중 평타 미실행")
	idle(b, 20)
	check(p.state == &"ground" or p.state == &"light", "회피 종료 뒤 정상 (%s)" % p.state)
	# 공중 입력은 나중에 실행되지 않는다
	idle(b, 30)
	place(p, 300, 540)
	p.cooldowns[sd.id] = 0
	press(b, "jump")
	idle(b, 3)
	press(b, "skill_d")
	idle(b, 40)
	check(p.state == &"ground" and p.cooldown_for(sd) == 0, "공중에서 누른 D 는 착지 뒤 실행되지 않음 (%s, cd %d)" % [p.state, p.cooldown_for(sd)])
	# 헛치기도 재사용 소모
	press(b, "skill_d")
	check(p.cooldown_for(sd) == 480, "헛치기 시작에도 재사용 480")

func test_h4_skill_damage_at_attack_21(b: Battle) -> void:
	var p := b.player
	var d := b.dummy
	p.attack_power = 21.0
	var expected := {"d": 46, "f": 38, "q": 63, "w": 34, "r": 105}
	for key in expected.keys():
		place(p, 300, 540)
		place(d, 380, 540)
		d.change_state(&"idle")
		d.invuln_ticks = 0
		d.total_damage_taken = 0
		var sd := skill(b, key)
		p.cooldowns[sd.id] = 0
		press(b, "skill_" + key)
		idle(b, 80)
		check(d.total_damage_taken == expected[key], "공격력 21: %s 피해 %d == %d" % [key, d.total_damage_taken, expected[key]])
		idle(b, 60)

# ------------------------------------------------------------------ HWR-004 R1: E 흘려받기

func enemy_facing_player(b: Battle, x: float, y: float) -> MeleeEnemy:
	var e := big_enemy(b, x, y)
	e.facing = -1 if x > b.player.floor_pos.x else 1
	return e

func test_h4_e_window_front_back_same_tick_fire(b: Battle) -> void:
	var p := b.player
	var se := skill(b, "e")
	check(se.attack.guard and se.attack.startup_ticks() == 12 and se.attack.recovery_ticks() == 18 and se.cooldown_ticks() == 840, "흘려받기 방어 12 + 회복 18 틱, 재사용 840틱")
	var ctr: AttackData = se.attack.counter_attack
	check(ctr != null and ctr.startup_ticks() == 3 and ctr.active_ticks() == 5 and ctr.recovery_ticks() == 10 and is_equal_approx(ctr.damage_mult, 2.5), "반격 3/5/10 틱, 250%")
	place(p, 400, 540)
	p.facing = 1
	var e := enemy_facing_player(b, 470, 540)
	# t11 성공: 방어 t=10 에 적이 공격 상태로 들어가 다음 틱(t=11)에 판정
	press(b, "skill_e")
	check(p.state == &"guard" and p.guard_window_open() and p.cooldown_for(se) == 840, "방어 창 열림·재사용 적용")
	idle(b, 10)
	e.change_state(&"attack")
	idle(b, 1)
	check(p.hp == 100 and p.parries == 1 and p.guard_consumed and p.state == &"guard" and e.state == &"attack" and e.active_hitboxes[0].already_hit(p), "t11 정면 베기 방어 성공: 피해 0, 처리 완료 기록, 적은 동작 진행")
	check(p.hitstop_ticks == 0 and e.hitstop_ticks == 0, "방어 성공 자체에는 양쪽 타격 정지 0")
	idle(b, 1)
	check(p.state == &"skill" and p.current_attack == ctr and p.attack_t() == 0 and p.counters_started == 1, "다음 틱 t=0 으로 반격 시작 (%s)" % p.state)
	var cd_after := p.cooldown_for(se)
	idle(b, 4)   # 같은 베기의 남은 활성 틱(총 6) 동안 재피해 없음, 반격 t=3 적중
	check(p.hp == 100, "같은 근접 타격의 다음 활성 틱 재피해 0")
	check(e.total_damage_taken == 50 and e.state == &"hitstun" and e.hitstun_ticks == 21 and e.knockback_total == 0.0, "반격 50, 일반 적 350ms 경직·밀림 0 (%d, %s)" % [e.total_damage_taken, e.state])
	check(p.cooldown_for(se) == cd_after - 4, "반격 시작 시 재사용을 다시 걸지 않음")
	# 반격 t8 부터 회피, t12 부터 이동, 그 전에는 이동 불가 (적중 히트스톱 2틱 동안 t 는 멈춘다)
	while p.attack_t() < 6:
		idle(b, 1)
	b.step(PlayerInput.make(Vector2(-1, 0)))   # t=7: 이동 취소 불가
	check(p.state == &"skill" and p.attack_t() == 7, "반격 t7: 이동 취소 불가")
	p.dodge_cooldown_ticks = 0
	press(b, "dodge", Vector2(-1, 0))   # t=8: 회피 가능
	check(p.state == &"dodge" and p.action_lock_ticks == 18 - 8 and p.counters_started == 1, "반격 t8 회피 연결, 남은 제한 %d틱" % p.action_lock_ticks)
	idle(b, 30)
	# t12 실패: 방어 t=11 에 적 공격 → t=12 판정 → 정상 피해·경직
	place(p, 400, 540)
	p.facing = 1
	p.change_state(&"ground")
	e.change_state(&"idle")
	e.state_ticks = -1000000
	place(e, 470, 540)
	e.facing = -1
	p.cooldowns[se.id] = 0
	press(b, "skill_e")
	idle(b, 11)
	e.change_state(&"attack")
	idle(b, 1)
	check(p.hp == 80 and p.state == &"hitstun" and p.parries == 1, "t12 는 실패 회복: 피해 20·경직 (체력 %d, %s)" % [p.hp, p.state])
	idle(b, 40)
	# 뒤쪽 공격은 방어 불가
	place(p, 400, 540)
	p.facing = 1
	p.change_state(&"ground")
	var back := enemy_facing_player(b, 330, 540)
	back.facing = 1
	e.change_state(&"idle")
	e.state_ticks = -1000000
	place(e, 1100, 700)
	p.cooldowns[se.id] = 0
	press(b, "skill_e")
	idle(b, 2)
	back.change_state(&"attack")
	idle(b, 1)
	check(p.hp == 60 and p.state == &"hitstun" and p.parries == 1, "뒤쪽 베기: 방어 실패·정상 피해 (체력 %d)" % p.hp)
	idle(b, 40)
	b.enemies.erase(back)
	back.free()
	# 같은 틱 정면 근접 + 정면 화살: 근접 판정이 먼저이므로 근접만 방어, 화살은 피해 → 실제 경직 → 반격 예약 폐기
	place(p, 400, 540)
	p.facing = 1
	p.change_state(&"ground")
	place(e, 470, 540)
	e.facing = -1
	e.change_state(&"idle")
	e.state_ticks = -1000000
	var archer := b.spawn_archer_enemy(Vector2(900, 540))
	archer.change_state(&"idle")
	archer.state_ticks = -1000000
	p.cooldowns[se.id] = 0
	press(b, "skill_e")
	idle(b, 2)
	e.change_state(&"attack")
	var arrow := Projectile.new()
	arrow.setup(&"enemy", archer, archer.arrow, float(b.tuning.archer_damage), Vector2(500, 540), 35.0, -1, 12000.0, 560.0, 10, 4.0, 8.0)
	b.add_projectile(arrow)
	var ctr_before := p.counters_started
	idle(b, 1)
	check(p.parries == 2 and p.hp == 60 - 16 and p.state == &"hitstun", "같은 틱: 근접 1회만 방어, 화살 16 피해·경직 (체력 %d, %s)" % [p.hp, p.state])
	idle(b, 1)
	check(p.counters_started == ctr_before and p.state == &"hitstun", "실제 경직이면 반격 0회")
	idle(b, 40)
	b.enemies.erase(archer)
	archer.free()
	# 방어 성공 + 같은 틱 불 6 만 받으면 반격 1회. 불은 방어 창을 소모하지 않는다.
	place(p, 400, 540)
	p.facing = 1
	p.change_state(&"ground")
	place(e, 470, 540)
	e.facing = -1
	e.change_state(&"idle")
	e.state_ticks = -1000000
	e.total_damage_taken = 0
	p.cooldowns[se.id] = 0
	var fz := b._spawn_fire(Vector2(400, 540))
	press(b, "skill_e")
	idle(b, 2)
	b.fire_clocks[p.get_instance_id()] = b.tick + 1
	e.change_state(&"attack")
	var hp0 := p.hp
	idle(b, 1)
	check(p.parries == 3 and p.hp == hp0 - 6 and p.state == &"guard", "방어 성공 + 같은 틱 불 6: 방어 창 유지 상태로 HP 만 감소 (체력 %d, %s)" % [p.hp, p.state])
	idle(b, 1)
	check(p.state == &"skill" and p.current_attack == ctr, "불만 받았으면 반격 1회 실행")
	idle(b, 5)
	check(e.total_damage_taken == 50, "반격 적중 50")
	fz.finish()
	b.fires.clear()
	b.fire_clocks.clear()
	# 방어 창 중 자발적 취소 없음 / 실패 회복 t24 이동 취소 + 남은 제한 6
	idle(b, 40)
	place(p, 400, 540)
	p.change_state(&"ground")
	place(e, 1100, 700)
	e.change_state(&"idle")
	e.state_ticks = -1000000
	p.cooldowns[se.id] = 0
	p.dodge_cooldown_ticks = 0
	press(b, "skill_e")
	for i in 11:
		b.step(PlayerInput.make(Vector2(1, 0), ["dodge"]))
	check(p.state == &"guard" and p.attack_t() == 11 and absf(p.floor_pos.x - 400.0) < 0.001, "방어 창 중 이동/회피 취소 없음 (t=%d)" % p.attack_t())
	idle(b, 12)   # t=23
	b.step(PlayerInput.make(Vector2(1, 0), ["skill_a"]))   # t=24 이동 취소
	check(p.state == &"ground" and p.action_lock_ticks == 6 and p.last_guard_result == "흘려받기 실패", "실패 회복 t24 이동 취소, 남은 제한 6 (%s)" % p.state)
	hold(b, Vector2(1, 0), 5)
	check(p.state == &"ground" and p.cooldown_for(skill(b, "a")) == 0, "원래 종료(t30) 전 A 미실행")
	hold(b, Vector2(1, 0), 1)
	check(p.state == &"skill" and p.current_skill == skill(b, "a"), "t30 에 보관한 A 실행")

func test_h4_e_arrows_boss_charge_brute_combo(b: Battle) -> void:
	var p := b.player
	var se := skill(b, "e")
	var ctr: AttackData = se.attack.counter_attack
	place(p, 400, 540)
	p.facing = 1
	var archer := b.spawn_archer_enemy(Vector2(900, 540))
	archer.change_state(&"idle")
	archer.state_ticks = -1000000
	# 정면 고속 화살(한 틱에 뒤까지 통과): 진행 방향으로 정면 판정 → 성공·화살 제거·사수 원격 피해 없음
	press(b, "skill_e")
	var fast := Projectile.new()
	fast.setup(&"enemy", archer, archer.arrow, float(b.tuning.archer_damage), Vector2(600, 540), 35.0, -1, 12000.0, 560.0, 10, 4.0, 8.0)
	b.add_projectile(fast)
	idle(b, 1)
	check(p.hp == 100 and p.parries == 1 and b.projectiles.is_empty() and archer.hp == archer.max_hp, "고속 정면 화살 방어 성공·제거, 궁수 피해 없음")
	idle(b, 1)
	check(p.state == &"skill" and p.current_attack == ctr, "화살 방어 뒤 반격 시작(허공)")
	idle(b, 20)
	check(archer.hp == archer.max_hp, "먼 궁수에게 반격 피해 없음")
	# 뒤쪽 화살은 방어 불가
	idle(b, 20)
	place(p, 400, 540)
	p.facing = 1
	p.change_state(&"ground")
	p.cooldowns[se.id] = 0
	press(b, "skill_e")
	var back := Projectile.new()
	back.setup(&"enemy", archer, archer.arrow, float(b.tuning.archer_damage), Vector2(300, 540), 35.0, 1, 650.0, 560.0, 30, 4.0, 8.0)
	b.add_projectile(back)
	idle(b, 8)
	check(p.hp == 84 and p.state == &"hitstun", "뒤쪽 화살: 피해 16 (체력 %d)" % p.hp)
	idle(b, 40)
	b.enemies.erase(archer)
	archer.free()
	# 강인병 내려찍기(parryable=false)는 방어 불가
	place(p, 400, 540)
	p.facing = 1
	p.change_state(&"ground")
	var br := b.spawn_brute_enemy(Vector2(470, 540))
	br.facing = -1
	br.current_pattern = 1
	p.cooldowns[se.id] = 0
	press(b, "skill_e")
	idle(b, 2)
	br.change_state(&"attack")
	idle(b, 1)
	check(p.hp == 84 - 24 and p.state == &"hitstun", "내려찍기: 방어 불가·24 피해 (체력 %d)" % p.hp)
	idle(b, 80)
	# 강인병 2연격: 첫 타 방어 → 강인병 계속 진행(두 번째 타 생성) → 반격 t8 회피로 두 번째 타 회피
	place(p, 400, 540)
	p.facing = 1
	p.change_state(&"ground")
	place(br, 470, 540)
	br.facing = -1
	br.current_pattern = 0
	br.change_state(&"idle")
	b.release_attack_slot(br)
	br.hits_created = 0
	p.cooldowns[se.id] = 0
	p.dodge_cooldown_ticks = 0
	press(b, "skill_e")
	idle(b, 2)
	br.change_state(&"attack")
	var hp1 := p.hp
	idle(b, 1)
	check(p.hp == hp1 and p.parries == 2 and br.state == &"attack", "2연격 첫 타 방어, 강인병 진행")
	idle(b, 1)   # 반격 t0
	while p.state == &"skill" and p.attack_t() < 7:
		idle(b, 1)
	press(b, "dodge", Vector2(-1, 0))   # 반격 t8
	check(p.state == &"dodge", "반격 t8 회피 연결 (%s)" % p.state)
	idle(b, 30)
	check(p.hp == hp1 and br.hits_created == 2, "두 번째 타(15틱 뒤)는 회피로 피함, 강인병은 두 타를 모두 만듦 (체력 %d, 타격 %d)" % [p.hp, br.hits_created])
	b.enemies.erase(br)
	br.free()
	# 보스 돌진: 방어해도 보스는 계속 돌진하고 같은 돌진으로 재피해 없음
	idle(b, 20)
	place(p, 500, 540)
	p.facing = 1
	p.change_state(&"ground")
	var boss := b.spawn_captain(Vector2(700, 540))
	boss.facing = -1
	boss.current_pattern = 1
	boss.charge_remaining = 300.0
	p.cooldowns[se.id] = 0
	press(b, "skill_e")
	boss.change_state(&"attack")
	var hp2 := p.hp
	var parried_at := -1
	for i in 30:
		idle(b, 1)
		if parried_at < 0 and p.parries == 3:
			parried_at = i
	check(parried_at >= 0 and parried_at < 12 and p.hp == hp2, "보스 돌진 방어 성공 (t=%d), 재피해 0 (체력 %d)" % [parried_at + 1, p.hp])
	check(boss.state == &"recover" and boss.floor_pos.x < 500.0, "보스는 멈추지 않고 끝까지 돌진 (%s, x %.0f)" % [boss.state, boss.floor_pos.x])

# ------------------------------------------------------------------ HWR-004 R1: R 일섬연무

func test_h4_r_five_hits_once_no_cancel_and_interrupt(b: Battle) -> void:
	var p := b.player
	var sr := skill(b, "r")
	check(sr.attack.startup_ticks() == 9 and sr.attack.active_ticks() == 27 and sr.attack.recovery_ticks() == 24 and sr.attack.total_ticks() == 60 and sr.cooldown_ticks() == 2100, "일섬연무 9/27/24 = 60틱, 재사용 2100틱")
	place(p, 300, 540)
	place(b.dummy, 1200, 700)
	place(b.knockback_dummy, 1200, 720)
	var e := big_enemy(b, 400, 540)
	var hit_ticks: Array = []
	var hit_t: Array = []
	var kbs: Array = []
	b.hit_applied.connect(func(a, _t, i): if a == p: hit_ticks.append(b.tick); hit_t.append(i.hit_index); kbs.append(i.knockback))
	var hb_ids := {}
	var moved := false
	press(b, "skill_r")
	var x0 := p.floor_pos.x
	var t_states: Array = []
	for i in 120:
		for hb in p.active_hitboxes:
			hb_ids[hb.instance_id] = hb.hit_index
		if p.state == &"skill":
			t_states.append(p.attack_t())
		# t<50 동안 매 틱 이동 + 회피 + 다른 스킬 입력: 자발적 취소 없음. 그 뒤엔 입력 없이 종료(보관 만료)
		if p.attack_t() < 50:
			b.step(PlayerInput.make(Vector2(1, 0), ["dodge", "skill_a"]))
		else:
			idle(b, 1)
		if absf(p.floor_pos.x - x0) > 0.001:
			moved = true
		if p.state != &"skill":
			break
	check(hit_t == [0, 1, 2, 3, 4] and e.total_damage_taken == 100, "5타 각 1회, 총 100 (%s, %d)" % [str(hit_t), e.total_damage_taken])
	check(hb_ids.size() == 5, "만든 판정은 정확히 5개(통짜 판정·히트스톱 중 재생성 없음) (%d)" % hb_ids.size())
	check(kbs.slice(0, 4) == [0.0, 0.0, 0.0, 0.0] and kbs[4] == 40.0, "마지막 타만 40px 밀림 (%s)" % str(kbs))
	check(e.hitstun_ticks == 12 and e.knockback_total == 40.0, "일반 적 각 타 200ms 경직, 마지막 밀림 40")
	check(not moved and t_states.max() == 59, "준비~종료(t59)까지 이동/회피/스킬 취소 없음 (이동 %s)" % str(moved))
	check(hit_ticks[1] - hit_ticks[0] >= 6 and hit_ticks[4] - hit_ticks[0] >= 24, "타격 간격 ≥ 6틱(히트스톱 포함 실제 %s)" % str(hit_ticks))
	check(p.cooldown_for(sr) > 0 and p.state == &"ground", "종료 후 지상·재사용 중")
	# 실제 경직이면 남은 타격 취소
	idle(b, 30)
	place(p, 300, 540)
	place(e, 400, 540)
	e.change_state(&"idle")
	e.state_ticks = -1000000
	e.total_damage_taken = 0
	var hitter := enemy_facing_player(b, 240, 540)
	hitter.facing = 1
	p.cooldowns[sr.id] = 0
	press(b, "skill_r")
	idle(b, 16)   # 2타까지 적중
	hitter.change_state(&"attack")
	idle(b, 1)
	check(p.state == &"hitstun" and p.active_hitboxes.is_empty(), "피격 시 R 중단·판정 정리 (%s)" % p.state)
	idle(b, 60)
	check(e.total_damage_taken == 40, "중단 뒤 남은 타격 없음 (피해 %d == 40)" % e.total_damage_taken)
	b.enemies.erase(hitter)
	hitter.free()
	# 보스 예고 중 5타: 피격 타격 정지 0 이라 예고 36틱 유지
	idle(b, 30)
	b.enemies.erase(e)
	e.free()
	place(p, 300, 540)
	p.change_state(&"ground")
	var boss := b.spawn_captain(Vector2(400, 540))
	boss.facing = -1
	boss.current_pattern = 0
	boss.change_state(&"telegraph")
	p.invuln_ticks = 100000
	p.cooldowns[sr.id] = 0
	press(b, "skill_r")
	var tele := 0
	while boss.state == &"telegraph" and tele < 100:
		idle(b, 1)
		tele += 1
	check(tele == 35, "R 를 맞는 동안 보스 예고 36틱 유지(시작 틱 제외 %d)" % tele)
	idle(b, 30)
	check(boss.hp == 500 and boss.hitstop_ticks == 0, "R 5타 피해 100, 보스 피격 타격 정지 0 (hp %d)" % boss.hp)
