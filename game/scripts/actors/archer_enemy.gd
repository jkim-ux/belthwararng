class_name ArcherEnemy
extends EnemyBase
## 적 궁수. 같은 깊이의 살아 있는 가까운 아군(주인공·동료)에게 사격한다. 체력 55, 화살 피해 8, 예고 0.65초, 간격 2.2초, 사거리 560.
## 상태: idle, approach(깊이 맞추기·거리 유지), retreat(근접 시 최대 100px/0.4초 후퇴), aim(예고: 방향·깊이 고정, 바닥 사격선),
##       recover(발사 후 짧은 회복) + 공통 hitstun/launched/down/dead.
## 예고 시작 전에 Battle 의 원거리 허가(request_ranged_slot)를 받고, 회복이 끝나거나 취소/피격/사망하면 반환한다.
## 예고 중 경직되면 발사를 취소한다. 궁지(경기장 경계)에서는 후퇴하지 않고 자리를 잡고 싸운다.

var target: BattleActor
var arrow: AttackData
var cooldown_ticks: int = 0
var aim_facing: int = 1
var aim_y: float = 0.0
var retreat_dir: int = 1
var retreat_done: float = 0.0
var shots_fired: int = 0
var waiting_for_slot: bool = false

func _init() -> void:
	team = &"enemy"
	display_name = "적 궁수"
	body_color = Color(0.6, 0.45, 0.2)

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_target: BattleActor) -> void:
	setup(p_tuning, p_battle, start)
	target = p_target
	max_hp = tuning.archer_max_hp
	hp = max_hp
	half_width = 18.0
	half_depth = 10.0
	body_height = 66.0
	arrow = AttackData.new()
	arrow.id = &"enemy_arrow"
	arrow.display_name = "적 화살"
	arrow.hitstun_ms = tuning.player_hitstun_ms     # 기존 단발 피격 규칙(경직·짧은 밀림)
	arrow.knockback = 30.0
	arrow.knockback_ms = 100.0
	arrow.launch = false
	arrow.strong = false
	facing = -1 if (p_target != null and start.x > p_target.floor_pos.x) else 1
	cooldown_ticks = Ticks.from_ms(600.0)           # 출현 직후 바로 쏘지 않는다
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
		&"retreat":
			_step_retreat()
		&"aim":
			_step_aim()
		&"recover":
			_step_recover()

func _step_idle() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(300.0):
		_pick_target()
		if _target_valid():
			change_state(&"approach")

func _edge_limit(dir: int) -> float:
	var r: Rect2 = battle.arena_rect()
	return (r.end.x - half_width - floor_pos.x) if dir > 0 else (floor_pos.x - r.position.x - half_width)

func _step_approach() -> void:
	_pick_target()
	if not _target_valid():
		change_state(&"idle")
		return
	var dx := target.floor_pos.x - floor_pos.x
	var dy := target.floor_pos.y - floor_pos.y
	facing = 1 if dx >= 0.0 else -1
	# 너무 가까우면 짧게 물러난다(궁지가 아닐 때만). 계속 도망가는 AI 가 아니다.
	if absf(dx) < tuning.archer_retreat_trigger and absf(dy) < 60.0:
		var away := -facing
		if _edge_limit(away) > 40.0:
			retreat_dir = away
			retreat_done = 0.0
			change_state(&"retreat")
			return
	var t := Vector2.ZERO
	if absf(dy) > 4.0:
		t.y = signf(dy) * tuning.archer_speed_y
	# 선호 거리보다 멀면 접근, 사거리 안이고 깊이가 맞으면 정지
	if absf(dx) > tuning.archer_preferred_distance + 40.0:
		t.x = signf(dx) * tuning.archer_speed_x
	velocity = t
	var stepv := velocity * Ticks.DT
	if absf(stepv.y) > absf(dy):
		stepv.y = dy
	floor_pos += stepv
	var aligned := absf(dy) <= tuning.archer_projectile_half_depth + target.half_depth - 2.0
	if aligned and absf(dx) <= tuning.archer_range and cooldown_ticks <= 0:
		var allowed := true
		if battle != null and battle.has_method("request_ranged_slot"):
			allowed = battle.request_ranged_slot(self)
		waiting_for_slot = not allowed
		if allowed:
			# 예고 시작: 좌우 방향과 발사 깊이를 고정한다.
			aim_facing = facing
			aim_y = floor_pos.y
			velocity = Vector2.ZERO
			change_state(&"aim")

func _step_retreat() -> void:
	var dur := Ticks.from_ms(tuning.archer_retreat_ms)
	var per_tick := tuning.archer_retreat_distance / float(maxi(1, dur))
	var stepd := minf(per_tick, tuning.archer_retreat_distance - retreat_done)
	stepd = minf(stepd, maxf(0.0, _edge_limit(retreat_dir)))
	floor_pos.x += retreat_dir * stepd
	retreat_done += stepd
	if state_ticks >= dur or retreat_done >= tuning.archer_retreat_distance or stepd <= 0.0:
		change_state(&"approach")

func _step_aim() -> void:
	if state_ticks >= Ticks.from_ms(tuning.archer_telegraph_ms):
		_fire()
		cooldown_ticks = Ticks.from_ms(tuning.archer_interval_ms)
		change_state(&"recover")

func _fire() -> void:
	if battle == null or not battle.has_method("add_projectile"):
		return
	var pr := Projectile.new()
	pr.setup(team, self, arrow, float(tuning.archer_damage), Vector2(floor_pos.x + float(aim_facing) * 22.0, aim_y), tuning.archer_projectile_height, aim_facing,
		tuning.archer_projectile_speed, tuning.archer_range, Ticks.from_ms(1500.0), tuning.archer_projectile_half_height, tuning.archer_projectile_half_depth)
	battle.add_projectile(pr)
	shots_fired += 1

func _step_recover() -> void:
	if state_ticks >= Ticks.from_ms(tuning.archer_recover_ms):
		change_state(&"idle")

func _on_state_entered(new_state: StringName) -> void:
	# 예고~회복 동안 허가를 유지하고 그 외(대기·후퇴·피격·사망)로 가면 반환한다.
	if new_state != &"aim" and new_state != &"recover":
		_release_slot()

func _draw() -> void:
	if alive and state == &"aim":
		# 바닥 사격선: 고정한 방향·깊이로 사거리만큼. 목표를 따라 휘지 않는다.
		var progress := clampf(float(state_ticks) / float(maxi(1, Ticks.from_ms(tuning.archer_telegraph_ms))), 0.0, 1.0)
		var r: Rect2 = battle.arena_rect()
		var x1 := clampf(floor_pos.x + float(aim_facing) * tuning.archer_range, r.position.x, r.end.x) - floor_pos.x
		var col := Color(1.0, 0.4, 0.15, 0.35 + 0.5 * progress)
		var d := tuning.archer_projectile_half_depth
		draw_rect(Rect2(minf(0.0, x1), -d, absf(x1), d * 2.0), Color(col.r, col.g, col.b, col.a * 0.4))
		draw_line(Vector2(0, 0), Vector2(x1, 0), col, 2.0)
		draw_line(Vector2(x1, -6), Vector2(x1, 6), col, 2.0)
	super()

func _draw_body() -> void:
	super()
	if not alive:
		return
	var bx := float(facing) * 14.0
	var by := -height - body_height + 26.0
	var pull := 1.0 if state == &"aim" else 0.3
	draw_arc(Vector2(bx, by), 15.0, deg_to_rad(-70.0), deg_to_rad(70.0), 12, Color(0.4, 0.25, 0.15), 2.0)
	if facing < 0:
		draw_arc(Vector2(bx, by), 15.0, deg_to_rad(110.0), deg_to_rad(250.0), 12, Color(0.4, 0.25, 0.15), 2.0)
	draw_line(Vector2(bx, by - 14.0), Vector2(bx - float(facing) * 11.0 * pull, by), Color(0.9, 0.9, 0.9), 1.0)
	draw_line(Vector2(bx, by + 14.0), Vector2(bx - float(facing) * 11.0 * pull, by), Color(0.9, 0.9, 0.9), 1.0)
	if waiting_for_slot and state == &"approach":
		draw_circle(Vector2(0, -height - body_height - 20.0), 3.0, Color(1.0, 0.8, 0.4, 0.8))
