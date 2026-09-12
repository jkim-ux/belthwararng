class_name ArcherCompanion
extends BattleActor
## 동료 궁수. 주인공 뒤쪽을 따라가며 사거리 안의 적에게 화살을 쏜다. 첫 버전은 지상 이동만 지원한다.
## 상태: follow(따라가기·깊이 맞추기), aim(준비: 방향·발사 깊이 고정), hitstun, dead(이탈)
## 화살은 실제 투사체(Projectile)이며 유도하지 않는다. 아군 팀이라 아군끼리 피해가 없다.
## HWR-003: 바닥 불을 감지해 안전한 따라가기 위치를 고르고, 불 안에 있으면 먼저 빠져나오며, 다음 이동이 불을 지나면 우회한다.
## 방 이동 때는 reset_for_room 으로 상태·속도만 정리하고 체력·발사 대기시간은 유지한다.

var def: CompanionDef
var leader: BattleActor
var arrow: AttackData
var cooldown_ticks: int = 0
var aim_facing: int = 1
var aim_target: BattleActor
var shots_fired: int = 0
var last_event: String = ""

func _init() -> void:
	team = &"player"
	display_name = "궁수 아야"
	body_color = Color(0.35, 0.7, 0.45)

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_def: CompanionDef, p_leader: BattleActor) -> void:
	setup(p_tuning, p_battle, start)
	def = p_def
	leader = p_leader
	display_name = p_def.display_name
	max_hp = p_def.max_hp
	hp = max_hp
	half_width = 18.0
	half_depth = 10.0
	body_height = 64.0
	arrow = AttackData.new()
	arrow.id = &"arrow"
	arrow.display_name = "화살"
	arrow.hitstun_ms = 0.0        # 큰 경직·밀림·띄우기 없음: 피해만
	arrow.knockback = 0.0
	arrow.knockback_ms = 0.0
	arrow.launch = false
	arrow.strong = false
	facing = 1
	alive = true
	change_state(&"follow")

func _step_state() -> void:
	if cooldown_ticks > 0:
		cooldown_ticks -= 1
	match state:
		&"follow":
			_step_follow()
		&"aim":
			_step_aim()
		&"hitstun":
			_step_hitstun()
		&"dead":
			pass

func _leader_valid() -> bool:
	return leader != null and is_instance_valid(leader) and leader.alive

## 살아 있는 적 중 사거리 안의 가까운 대상
func _pick_enemy() -> BattleActor:
	if battle == null or not battle.has_method("alive_enemies"):
		return null
	var best: BattleActor = null
	var best_d := INF
	for e in battle.alive_enemies():
		var dx: float = absf(e.floor_pos.x - floor_pos.x)
		if dx > def.attack_range:
			continue
		var d: float = dx + absf(e.floor_pos.y - floor_pos.y) * 0.5
		if d < best_d:
			best_d = d
			best = e
	return best

## 방 이동 뒤 정리: 상태·속도·조준 참조만 초기화한다(체력·발사 대기시간 유지).
func reset_for_room() -> void:
	velocity = Vector2.ZERO
	knockback_remaining = 0.0
	aim_target = null
	hitstop_ticks = 0
	if alive:
		change_state(&"follow")

func _fire_at(p: Vector2) -> FireZone:
	if battle == null or not battle.has_method("fire_at"):
		return null
	return battle.fire_at(p)

## 불 감지: 지점이 불(여유 margin 포함) 안인가
func _near_fire(p: Vector2, margin: float) -> FireZone:
	if battle == null or not battle.has_method("fire_at"):
		return null
	for fz in battle.fires:
		if not is_instance_valid(fz) or not fz.alive:
			continue
		var dx: float = (p.x - fz.center.x) / (fz.rx + margin)
		var dy: float = (p.y - fz.center.y) / (fz.ry + margin * 0.5)
		if dx * dx + dy * dy <= 1.0:
			return fz
	return null

## 불을 피한 목표 지점: 목표가 불 안이면 불의 위/아래(경기장 안쪽) 가장자리로 옮긴다.
func _safe_desired(desired: Vector2) -> Vector2:
	var fz := _near_fire(desired, 14.0)
	if fz == null:
		return desired
	var r: Rect2 = battle.arena_rect()
	var up := fz.center.y - fz.ry - 24.0
	var down := fz.center.y + fz.ry + 24.0
	var cand := up if absf(up - floor_pos.y) <= absf(down - floor_pos.y) else down
	if cand < r.position.y or cand > r.end.y:
		cand = down if cand == up else up
	return Vector2(desired.x, clampf(cand, r.position.y, r.end.y))

## 경로 우회: 자신과 목표 사이(x)에 불이 있고 현재 차선이 불과 겹치면 불 위/아래 차선으로 목표 깊이를 옮긴다.
func _route_around(desired: Vector2) -> Vector2:
	if battle == null or not battle.has_method("fire_at"):
		return desired
	var lo := minf(floor_pos.x, desired.x) - 10.0
	var hi := maxf(floor_pos.x, desired.x) + 10.0
	for fz in battle.fires:
		if not is_instance_valid(fz) or not fz.alive:
			continue
		if fz.center.x + fz.rx < lo or fz.center.x - fz.rx > hi:
			continue
		var clearance: float = fz.ry + 22.0
		var lane_dy: float = floor_pos.y - fz.center.y
		var dest_dy: float = desired.y - fz.center.y
		if absf(lane_dy) > clearance and absf(dest_dy) > clearance and signf(lane_dy) == signf(dest_dy):
			continue
		var side := -1.0 if lane_dy <= 0.0 else 1.0
		var r: Rect2 = battle.arena_rect()
		var y: float = fz.center.y + side * (fz.ry + 30.0)
		if y < r.position.y or y > r.end.y:
			y = fz.center.y - side * (fz.ry + 30.0)
		return Vector2(desired.x, clampf(y, r.position.y, r.end.y))
	return desired

func _step_follow() -> void:
	var desired := floor_pos
	if _leader_valid():
		desired = leader.floor_pos + Vector2(-float(leader.facing) * def.follow_distance, 0.0)
	var target := _pick_enemy()
	if target != null:
		# 목표 깊이에 맞추되 좌우는 따라가기 위치를 유지한다(적 옆까지 파고들지 않음).
		desired.y = target.floor_pos.y
	# 불 안에 서 있으면 먼저 가장 가까운 방향으로 빠져나온다.
	var inside := _near_fire(floor_pos, 4.0)
	if inside != null:
		var away := floor_pos - inside.center
		if away.length() < 1.0:
			away = Vector2(0, -1)
		away = Vector2(away.x / maxf(inside.rx, 1.0), away.y / maxf(inside.ry, 1.0)).normalized()
		var r: Rect2 = battle.arena_rect()
		var target_y := floor_pos.y + signf(away.y if absf(away.y) > 0.05 else -1.0) * (inside.ry + 30.0)
		if target_y < r.position.y or target_y > r.end.y:
			target_y = floor_pos.y - signf(target_y - floor_pos.y) * (inside.ry * 2.0 + 30.0)
		desired = Vector2(floor_pos.x + away.x * 40.0, target_y)
		last_event = "불 회피"
	else:
		desired = _route_around(_safe_desired(desired))
	var dx := desired.x - floor_pos.x
	var dy := desired.y - floor_pos.y
	var t := Vector2.ZERO
	if absf(dx) > 6.0:
		t.x = signf(dx) * def.move_speed_x
	if absf(dy) > 3.0:
		t.y = signf(dy) * def.move_speed_y
	approach_velocity(t)
	var stepv := velocity * Ticks.DT
	if absf(stepv.x) > absf(dx):
		stepv.x = dx
	if absf(stepv.y) > absf(dy):
		stepv.y = dy
	# 다음 이동 구간이 불을 관통하면 좌우 이동을 멈추고 깊이로 우회한다.
	if inside == null and stepv.x != 0.0:
		var ahead := floor_pos + Vector2(stepv.x * 6.0, stepv.y * 6.0)
		var blocking := _near_fire(ahead, 10.0)
		if blocking != null:
			stepv.x = 0.0
			velocity.x = 0.0
			var side := -1.0 if floor_pos.y <= blocking.center.y else 1.0
			stepv.y = side * def.move_speed_y * Ticks.DT
			last_event = "불 우회"
	floor_pos += stepv
	if absf(t.x) > 0.0:
		facing = 1 if t.x > 0.0 else -1
	elif _leader_valid():
		facing = leader.facing
	if inside != null:
		return
	if target != null and cooldown_ticks <= 0 and absf(target.floor_pos.y - floor_pos.y) <= def.projectile_half_depth + target.half_depth:
		# 준비 시작: 방향과 발사 깊이를 고정한다.
		aim_target = target
		aim_facing = 1 if target.floor_pos.x >= floor_pos.x else -1
		facing = aim_facing
		velocity = Vector2.ZERO
		change_state(&"aim")
		last_event = "조준"

func _step_aim() -> void:
	if state_ticks >= Ticks.from_ms(def.aim_ms):
		_fire()
		cooldown_ticks = Ticks.from_ms(def.fire_interval_ms)
		change_state(&"follow")

func _fire() -> void:
	if battle == null or not battle.has_method("add_projectile"):
		return
	var pr := Projectile.new()
	pr.setup(team, self, arrow, def.attack_damage, floor_pos + Vector2(float(aim_facing) * 22.0, 0.0), def.projectile_height, aim_facing,
		def.projectile_speed, def.projectile_max_distance, Ticks.from_ms(def.projectile_life_ms), def.projectile_half_height, def.projectile_half_depth)
	battle.add_projectile(pr)
	shots_fired += 1
	last_event = "사격"

func _step_hitstun() -> void:
	if knockback_remaining > 0.0:
		var stepd := minf(knockback_remaining, 240.0 * Ticks.DT)
		floor_pos.x += stepd * knockback_dir
		knockback_remaining -= stepd
	if state_ticks >= hitstun_ticks:
		change_state(&"follow")

func _on_hit(info: HitInfo) -> void:
	if info.attack.hitstun_ms <= 0.0:
		return
	hitstun_ticks = Ticks.from_ms(info.attack.hitstun_ms)
	knockback_remaining = info.effective_knockback() * 0.6
	knockback_dir = info.direction
	velocity = Vector2.ZERO
	change_state(&"hitstun")

## 체력 0: 이번 출정에서 이탈한다(다음 출정에서 회복). 동료 이탈만으로 패배하지 않는다.
func _die() -> void:
	super()
	visible = false
	last_event = "이탈"

func _draw_body() -> void:
	super()
	if not alive:
		return
	# 머리 위 체력 막대
	var top := -height - body_height - 12.0
	draw_rect(Rect2(-half_width, top, half_width * 2.0, 5.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-half_width, top, half_width * 2.0 * float(hp) / float(maxi(1, max_hp)), 5.0), Color(0.4, 0.9, 0.5))
	# 활: 조준 중에는 당긴 활
	var bx := float(facing) * 16.0
	var by := -height - body_height + 24.0
	var pull := 1.0 if state == &"aim" else 0.4
	draw_arc(Vector2(bx, by), 16.0, deg_to_rad(-70.0), deg_to_rad(70.0), 12, Color(0.85, 0.7, 0.4), 2.0)
	if facing < 0:
		draw_arc(Vector2(bx, by), 16.0, deg_to_rad(110.0), deg_to_rad(250.0), 12, Color(0.85, 0.7, 0.4), 2.0)
	draw_line(Vector2(bx, by - 15.0), Vector2(bx - float(facing) * 12.0 * pull, by), Color(0.9, 0.9, 0.9), 1.0)
	draw_line(Vector2(bx, by + 15.0), Vector2(bx - float(facing) * 12.0 * pull, by), Color(0.9, 0.9, 0.9), 1.0)
