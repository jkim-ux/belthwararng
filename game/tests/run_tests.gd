extends SceneTree
## 헤드리스 자동 검증. 실행: godot --headless --path game -s tests/run_tests.gd
## 전투 장면을 수동 틱으로 진행하며 판정·연결·입력 규칙을 확인한다. 실패가 있으면 종료 코드 1.

const BATTLE_SCENE := "res://scenes/battle.tscn"

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

func _initialize() -> void:
	print("=== HWR-001 자동 검증 시작 (Godot %s) ===" % Engine.get_version_info().string)
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
