class_name ThrowerEnemy
extends EnemyBase
## 화염 투척병. 목표 아군의 발 위치를 준비 시작에 고정하고 착탄 범위를 처음부터 바닥에 표시한다.
## 준비 0.65초 + 비행 0.5초 뒤 그 지점에 바닥 불(FireZone) 생성. 체력 60, 투척 간격 최소 4초, 사거리 460.
## 상태: idle, approach, windup(준비: 원거리 허가 필요, 착탄점 고정), recover + 공통 hitstun/launched/down/dead.
## 준비 중 경직/사망하면 취소하고 허가를 반환한다. 손을 떠난 항아리는 투척병이 죽어도 착탄한다(FirePot 은 Battle 소유).
## 폭발 직격 피해는 없고 장판 피해만 준다. 활성+예약 화염이 방당 최대치면 자리가 날 때까지 기다린다.

var target: BattleActor
var cooldown_ticks: int = 0
var aim_point: Vector2 = Vector2.ZERO
var throws: int = 0
var waiting_for_slot: bool = false
var wait_reason: String = ""

func _init() -> void:
	team = &"enemy"
	display_name = "화염 투척병"
	body_color = Color(0.75, 0.45, 0.15)

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_target: BattleActor) -> void:
	setup(p_tuning, p_battle, start)
	target = p_target
	max_hp = tuning.thrower_max_hp
	hp = max_hp
	half_width = 20.0
	half_depth = 10.0
	body_height = 68.0
	facing = -1 if (p_target != null and start.x > p_target.floor_pos.x) else 1
	cooldown_ticks = Ticks.from_ms(900.0)
	change_state(&"idle")

func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.alive

func _pick_target() -> void:
	if battle == null or not battle.has_method("alive_allies"):
		return
	var best: BattleActor = null
	var best_d := INF
	for a in battle.alive_allies():
		var d: float = absf(a.floor_pos.x - floor_pos.x) + absf(a.floor_pos.y - floor_pos.y) * 1.5
		if d < best_d:
			best_d = d
			best = a
	if best != null:
		target = best

func _release_slot() -> void:
	waiting_for_slot = false
	if battle != null and battle.has_method("release_ranged_slot"):
		battle.release_ranged_slot(self)

func _step_state() -> void:
	if cooldown_ticks > 0:
		cooldown_ticks -= 1
	if _step_common_reactions():
		return
	match state:
		&"idle":
			_step_idle()
		&"approach":
			_step_approach()
		&"windup":
			_step_windup()
		&"recover":
			_step_recover()

func _step_idle() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(300.0):
		_pick_target()
		if _target_valid():
			change_state(&"approach")

## 착탄점 후보: 목표 발 위치. 유효하지 않으면 경기장 중앙 쪽으로 조금 옮겨 다시 시도한다.
func _choose_aim_point() -> Vector2:
	var p: Vector2 = target.floor_pos
	if battle.valid_fire_target(p):
		return p
	var center: Vector2 = battle.arena_rect().get_center()
	for i in 3:
		p = p.move_toward(center, 70.0)
		if battle.valid_fire_target(p):
			return p
	return Vector2.INF

func _step_approach() -> void:
	_pick_target()
	if not _target_valid():
		change_state(&"idle")
		return
	var dx := target.floor_pos.x - floor_pos.x
	var dy := target.floor_pos.y - floor_pos.y
	facing = 1 if dx >= 0.0 else -1
	var t := Vector2.ZERO
	if absf(dy) > 30.0:
		t.y = signf(dy) * tuning.thrower_speed_y
	if absf(dx) > tuning.thrower_range - 60.0:
		t.x = signf(dx) * tuning.thrower_speed_x
	elif absf(dx) < 140.0:
		# 너무 가까우면 조금 물러선다(경계에서는 멈춘다)
		t.x = -signf(dx) * tuning.thrower_speed_x
	velocity = t
	floor_pos += velocity * Ticks.DT
	if absf(dx) <= tuning.thrower_range and cooldown_ticks <= 0:
		if not battle.fire_slot_available():
			waiting_for_slot = true
			wait_reason = "화염 자리 대기"
			return
		var allowed: bool = battle.request_ranged_slot(self)
		waiting_for_slot = not allowed
		wait_reason = "허가 대기" if not allowed else ""
		if allowed:
			var p := _choose_aim_point()
			if p == Vector2.INF:
				# 유효한 지점이 없으면 허가를 돌려주고 잠시 뒤 다시 노린다.
				_release_slot()
				cooldown_ticks = Ticks.from_ms(500.0)
				return
			aim_point = p
			velocity = Vector2.ZERO
			change_state(&"windup")

func _step_windup() -> void:
	if state_ticks >= Ticks.from_ms(tuning.thrower_windup_ms):
		var pot = battle.throw_fire_pot(floor_pos + Vector2(float(facing) * 16.0, 0.0), aim_point)
		if pot != null:
			throws += 1
		cooldown_ticks = Ticks.from_ms(tuning.thrower_interval_ms)
		change_state(&"recover")

func _step_recover() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(tuning.thrower_recover_ms):
		change_state(&"idle")

func _on_state_entered(new_state: StringName) -> void:
	# 준비~회복 동안 허가를 유지하고 그 외(대기·피격·사망)로 가면 반환한다. 준비 중 취소는 항아리를 만들지 않는다.
	if new_state != &"windup" and new_state != &"recover":
		_release_slot()

func _draw() -> void:
	if alive and state == &"windup":
		var progress := clampf(float(state_ticks) / float(maxi(1, Ticks.from_ms(tuning.thrower_windup_ms))), 0.0, 1.0)
		var r: Rect2 = battle.arena_rect()
		# 착탄 예고는 로컬 좌표로 그린다(개체 위치 기준 상대 좌표)
		draw_set_transform(aim_point - floor_pos, 0.0, Vector2.ONE)
		FireZone.draw_telegraph(self, Vector2.ZERO, tuning.fire_radius_x, tuning.fire_radius_y, Rect2(r.position - aim_point, r.size), progress)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	super()

func _draw_body() -> void:
	super()
	if not alive:
		return
	var top := -height - body_height
	# 등에 멘 항아리 / 준비 중에는 머리 위로 든 항아리
	if state == &"windup":
		draw_circle(Vector2(float(facing) * 6.0, top - 10.0), 8.0, Color(0.55, 0.35, 0.2))
		draw_line(Vector2(float(facing) * 6.0, top - 18.0), Vector2(float(facing) * 6.0, top - 26.0), Color(1.0, 0.7, 0.2), 2.0)
	else:
		draw_circle(Vector2(-float(facing) * 14.0, top + 22.0), 7.0, Color(0.55, 0.35, 0.2))
	if waiting_for_slot and state == &"approach":
		draw_circle(Vector2(0, top - 20.0), 3.0, Color(1.0, 0.8, 0.4, 0.8))
