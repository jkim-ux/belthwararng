class_name MeleeEnemy
extends EnemyBase
## 단순 근접 적: 접근 → 예고 → 공격 → 회복(물러남) → 대기.
## 예고 시작 시점에 공격 방향을 고정한다. 깊이를 먼저 맞춘 뒤 좌우 거리를 좁힌다.

var target: BattleActor
var attack_data: AttackData
var recover_backoff_ticks: int = 18

func _init() -> void:
	team = &"enemy"
	display_name = "근접 적"
	body_color = Color(0.85, 0.3, 0.3)

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_target: BattleActor) -> void:
	setup(p_tuning, p_battle, start)
	target = p_target
	max_hp = tuning.enemy_max_hp
	hp = max_hp
	half_width = 20.0
	half_depth = 10.0
	body_height = 68.0
	attack_data = AttackData.new()
	attack_data.id = &"enemy_slash"
	attack_data.display_name = "베기"
	attack_data.startup_ms = 0.0
	attack_data.active_ms = tuning.enemy_attack_active_ms
	attack_data.recovery_ms = 0.0
	attack_data.damage_mult = 1.0
	attack_data.hitstun_ms = tuning.player_hitstun_ms
	attack_data.knockback = 50.0
	attack_data.reach_forward = tuning.enemy_attack_reach
	attack_data.reach_back = 8.0
	attack_data.depth_tolerance = 22.0
	attack_data.z_min = -10.0
	attack_data.z_max = 90.0
	facing = -1 if start.x > p_target.floor_pos.x else 1
	change_state(&"idle")

func _step_state() -> void:
	if _step_common_reactions():
		return
	match state:
		&"idle":
			_step_idle()
		&"approach":
			_step_approach()
		&"telegraph":
			_step_telegraph()
		&"attack":
			_step_attack()
		&"recover":
			_step_recover()

func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.alive

func _face_target() -> void:
	if _target_valid():
		facing = 1 if target.floor_pos.x >= floor_pos.x else -1

func _step_idle() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(tuning.enemy_idle_ms) and _target_valid():
		change_state(&"approach")

func _step_approach() -> void:
	if not _target_valid():
		change_state(&"idle")
		return
	_face_target()
	var desired_x := target.floor_pos.x - facing * (tuning.enemy_attack_reach - 15.0)
	var dx := desired_x - floor_pos.x
	var dy := target.floor_pos.y - floor_pos.y
	var t := Vector2.ZERO
	if absf(dy) > 4.0:
		t.y = signf(dy) * tuning.enemy_speed_y
	if absf(dx) > 6.0:
		t.x = signf(dx) * tuning.enemy_speed_x
	# 목표 속도로 즉시 접근(단순 AI). 프레임당 이동은 남은 거리를 넘지 않게 한다.
	velocity = t
	var stepv := velocity * Ticks.DT
	if absf(stepv.x) > absf(dx):
		stepv.x = dx
	if absf(stepv.y) > absf(dy):
		stepv.y = dy
	floor_pos += stepv
	if absf(dy) <= 6.0 and absf(dx) <= 10.0:
		velocity = Vector2.ZERO
		_face_target()
		change_state(&"telegraph")

func _step_telegraph() -> void:
	# 예고 중에는 방향과 위치를 고정한다.
	if state_ticks >= Ticks.from_ms(tuning.enemy_telegraph_ms):
		change_state(&"attack")

func _step_attack() -> void:
	var t := state_ticks - 1
	var a := attack_data.active_ticks()
	if t == 0:
		begin_hitbox(attack_data, float(tuning.enemy_attack_damage))
	if t >= a:
		end_hitboxes()
		change_state(&"recover")

func _step_recover() -> void:
	if state_ticks <= recover_backoff_ticks:
		velocity = Vector2(-facing * 90.0, 0.0)
	else:
		approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(tuning.enemy_recover_ms):
		change_state(&"idle")

func _on_state_entered(new_state: StringName) -> void:
	if new_state != &"attack":
		end_hitboxes()

func _draw() -> void:
	# 예고 표시: 바닥에 공격 범위를 그린다 (색과 형태 모두로 구분)
	if alive and (state == &"telegraph" or state == &"attack"):
		var progress := 1.0
		if state == &"telegraph":
			progress = clampf(float(state_ticks) / float(maxi(1, Ticks.from_ms(tuning.enemy_telegraph_ms))), 0.0, 1.0)
		var x0 := -attack_data.reach_back if facing > 0 else -attack_data.reach_forward
		var w := attack_data.reach_forward + attack_data.reach_back
		var d := attack_data.depth_tolerance
		var col := Color(1.0, 0.35, 0.1, 0.25 + 0.45 * progress)
		if state == &"attack":
			col = Color(1.0, 0.9, 0.2, 0.8)
		draw_rect(Rect2(x0, -d, w, d * 2.0), col)
		draw_rect(Rect2(x0, -d, w, d * 2.0), Color(1.0, 0.4, 0.1, 0.9), false, 2.0)
	super()

func _draw_body() -> void:
	super()
	if alive and state == &"telegraph":
		# 준비 동작: 머리 위 느낌표 대신 팔(막대)을 뒤로 젖힌다
		var top := -height - body_height
		draw_rect(Rect2(-facing * 34.0 - 6.0, top + 20.0, 12.0, 6.0), Color(1.0, 0.4, 0.1))
	elif alive and state == &"attack":
		var top := -height - body_height
		var x0 := 0.0 if facing > 0 else -attack_data.reach_forward
		draw_rect(Rect2(x0, top + 26.0, attack_data.reach_forward, 6.0), Color(1.0, 0.9, 0.2))
