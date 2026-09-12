class_name ArcherCompanion
extends BattleActor
## 동료 궁수. 주인공 뒤쪽을 따라가며 사거리 안의 적에게 화살을 쏜다. 첫 버전은 지상 이동만 지원한다.
## 상태: follow(따라가기·깊이 맞추기), aim(준비: 방향·발사 깊이 고정), hitstun, dead(이탈)
## 화살은 실제 투사체(Projectile)이며 유도하지 않는다. 아군 팀이라 아군끼리 피해가 없다.

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

func _step_follow() -> void:
	var desired := floor_pos
	if _leader_valid():
		desired = leader.floor_pos + Vector2(-float(leader.facing) * def.follow_distance, 0.0)
	var target := _pick_enemy()
	if target != null:
		# 목표 깊이에 맞추되 좌우는 따라가기 위치를 유지한다(적 옆까지 파고들지 않음).
		desired.y = target.floor_pos.y
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
	floor_pos += stepv
	if absf(t.x) > 0.0:
		facing = 1 if t.x > 0.0 else -1
	elif _leader_valid():
		facing = leader.facing
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
	knockback_remaining = info.attack.knockback * 0.6
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
