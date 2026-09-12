extends SceneTree
## 헤드리스 자동 검증. 실행: godot --headless --path game -s tests/run_tests.gd
## 전투 장면을 수동 틱으로 진행하며 판정·연결·입력 규칙을 확인한다. 실패가 있으면 종료 코드 1.

const BATTLE_SCENE := "res://scenes/battle.tscn"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

func _initialize() -> void:
	print("=== HWR-001/HWR-002 R1 자동 검증 시작 (Godot %s) ===" % Engine.get_version_info().string)
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
	]
	for t in tests:
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
	for a in ["skill_d", "skill_f", "skill_q", "skill_w", "skill_e", "skill_r"]:
		press(b, a)
		idle(b, 2)
		check(p.state == &"ground" and p.buffered_action == &"", "미구현 %s 은 무시되고 보관도 안 됨 (state %s)" % [a, p.state])

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
	check(p.hp == p.max_hp - 10 and p.state == &"hitstun", "무적 종료 후 피해 10 (hp %d, %s)" % [p.hp, p.state])
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
