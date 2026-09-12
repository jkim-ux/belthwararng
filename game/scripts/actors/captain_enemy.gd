class_name CaptainEnemy
extends EnemyBase
## 고개 초소 대장. 체력 600, 피해 12, 띄우기·다운 면역.
## 전방 베기(예고 0.6/타격 0.1/회복 0.8초)와 직선 돌진(예고 0.8/이동 타격 0.3/회복 1.0초)을 교대로 쓴다.
## 예고 시작 시 좌우 방향과 바닥 경로를 고정하고, 돌진은 최대 300 px·경기장 경계에서 멈추며 깊이를 추적하지 않는다.
## 예고/타격/회복 중에는 경직을 받지 않되 피해는 받는다(작은 피격 표시). 대기·접근 중에만 짧은 경직.
## 상태: idle, approach, telegraph, attack, recover (+ 공통 hitstun/dead). 자세 파괴·페이즈 시스템은 아니다.

var target: BattleActor
var slash: AttackData
var charge: AttackData
var pattern_index: int = 0            ## 0 = 베기, 1 = 돌진 (교대)
var current_pattern: int = 0
var charge_remaining: float = 0.0
var flinch_ticks: int = 0             ## 피격 표시용(경직 아님)

func _init() -> void:
	team = &"enemy"
	display_name = "초소 대장"
	body_color = Color(0.55, 0.12, 0.18)
	can_be_launched = false
	knockback_enabled = false

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_target: BattleActor) -> void:
	setup(p_tuning, p_battle, start)
	target = p_target
	max_hp = tuning.captain_max_hp
	hp = max_hp
	half_width = 26.0
	half_depth = 12.0
	body_height = 86.0
	slash = AttackData.new()
	slash.id = &"captain_slash"
	slash.display_name = "전방 베기"
	slash.startup_ms = 0.0
	slash.active_ms = tuning.captain_slash_active_ms
	slash.recovery_ms = 0.0
	slash.hitstun_ms = tuning.player_hitstun_ms
	slash.knockback = 70.0
	slash.reach_forward = tuning.captain_slash_reach
	slash.reach_back = 10.0
	slash.depth_tolerance = 24.0
	slash.z_min = -10.0
	slash.z_max = 100.0
	charge = AttackData.new()
	charge.id = &"captain_charge"
	charge.display_name = "직선 돌진"
	charge.startup_ms = 0.0
	charge.active_ms = tuning.captain_charge_active_ms
	charge.recovery_ms = 0.0
	charge.hitstun_ms = tuning.player_hitstun_ms
	charge.knockback = 90.0
	charge.reach_forward = 60.0
	charge.reach_back = 20.0
	charge.depth_tolerance = 22.0
	charge.z_min = -10.0
	charge.z_max = 100.0
	facing = -1 if (p_target != null and start.x > p_target.floor_pos.x) else 1
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

func in_pattern() -> bool:
	return state == &"telegraph" or state == &"attack" or state == &"recover"

## 피격: 패턴 중에는 경직 없이 피해만(기본 클래스가 피해와 타격 정지를 이미 적용). 대기·접근 중 짧은 경직.
func _on_hit(info: HitInfo) -> void:
	flinch_ticks = 4
	if in_pattern():
		return
	if info.attack.hitstun_ms <= 0.0:
		return
	if state == &"hitstun":
		# 연타로 경직을 무한 연장하지 않는다: 남은 경직만 유지
		return
	hitstun_ticks = Ticks.from_ms(tuning.captain_flinch_ms)
	knockback_remaining = 0.0
	velocity = Vector2.ZERO
	change_state(&"hitstun")

func _step_state() -> void:
	if flinch_ticks > 0:
		flinch_ticks -= 1
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

func _step_idle() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= Ticks.from_ms(500.0):
		_pick_target()
		if _target_valid():
			change_state(&"approach")

func _step_approach() -> void:
	_pick_target()
	if not _target_valid():
		change_state(&"idle")
		return
	facing = 1 if target.floor_pos.x >= floor_pos.x else -1
	var want_dist := 90.0 if pattern_index == 0 else 220.0
	var desired_x := target.floor_pos.x - facing * want_dist
	var dx := desired_x - floor_pos.x
	var dy := target.floor_pos.y - floor_pos.y
	var t := Vector2.ZERO
	if absf(dy) > 4.0:
		t.y = signf(dy) * tuning.captain_speed_y
	if absf(dx) > 8.0:
		t.x = signf(dx) * tuning.captain_speed_x
	velocity = t
	var stepv := velocity * Ticks.DT
	if absf(stepv.x) > absf(dx):
		stepv.x = dx
	if absf(stepv.y) > absf(dy):
		stepv.y = dy
	floor_pos += stepv
	if absf(dy) <= 8.0 and absf(dx) <= 14.0:
		velocity = Vector2.ZERO
		current_pattern = pattern_index
		pattern_index = (pattern_index + 1) % 2
		# 예고 시작: 방향·경로 고정
		facing = 1 if target.floor_pos.x >= floor_pos.x else -1
		if current_pattern == 1:
			var r: Rect2 = battle.arena_rect()
			var limit := (r.end.x - half_width - floor_pos.x) if facing > 0 else (floor_pos.x - r.position.x - half_width)
			charge_remaining = minf(tuning.captain_charge_distance, maxf(0.0, limit))
		change_state(&"telegraph")

func _telegraph_ticks() -> int:
	return Ticks.from_ms(tuning.captain_slash_telegraph_ms if current_pattern == 0 else tuning.captain_charge_telegraph_ms)

func _recover_ticks() -> int:
	return Ticks.from_ms(tuning.captain_slash_recover_ms if current_pattern == 0 else tuning.captain_charge_recover_ms)

func _step_telegraph() -> void:
	if state_ticks >= _telegraph_ticks():
		change_state(&"attack")

func _step_attack() -> void:
	var t := state_ticks - 1
	var atk := slash if current_pattern == 0 else charge
	var a := atk.active_ticks()
	if t == 0:
		begin_hitbox(atk, float(tuning.captain_attack_damage))
	if current_pattern == 1:
		# 돌진: 남은 거리를 이동 구간에 균등 배분. 경계에 막히면 그 자리에서 멈춘다.
		var per_tick := tuning.captain_charge_distance / float(maxi(1, a))
		var stepd := minf(per_tick, charge_remaining)
		floor_pos.x += facing * stepd
		charge_remaining -= stepd
	if t >= a:
		end_hitboxes()
		change_state(&"recover")

func _step_recover() -> void:
	approach_velocity(Vector2.ZERO)
	move_by_velocity()
	if state_ticks >= _recover_ticks():
		change_state(&"idle")

func _on_state_entered(new_state: StringName) -> void:
	if new_state != &"attack":
		end_hitboxes()

func _draw() -> void:
	if alive and (state == &"telegraph" or state == &"attack"):
		var progress := 1.0
		if state == &"telegraph":
			progress = clampf(float(state_ticks) / float(maxi(1, _telegraph_ticks())), 0.0, 1.0)
		var col := Color(1.0, 0.3, 0.1, 0.22 + 0.45 * progress)
		if state == &"attack":
			col = Color(1.0, 0.9, 0.2, 0.75)
		if current_pattern == 0:
			var x0 := -slash.reach_back if facing > 0 else -slash.reach_forward
			var w := slash.reach_forward + slash.reach_back
			draw_rect(Rect2(x0, -slash.depth_tolerance, w, slash.depth_tolerance * 2.0), col)
			draw_rect(Rect2(x0, -slash.depth_tolerance, w, slash.depth_tolerance * 2.0), Color(1.0, 0.4, 0.1, 0.9), false, 2.0)
		else:
			# 돌진 경로: 고정된 방향으로 남은 거리 + 판정 폭
			var length := charge_remaining + charge.reach_forward
			var x0 := -charge.reach_back if facing > 0 else -length
			var w := length + charge.reach_back
			draw_rect(Rect2(x0, -charge.depth_tolerance, w, charge.depth_tolerance * 2.0), col)
			draw_rect(Rect2(x0, -charge.depth_tolerance, w, charge.depth_tolerance * 2.0), Color(1.0, 0.4, 0.1, 0.9), false, 2.0)
	super()

func _draw_body() -> void:
	var saved := body_color
	if flinch_ticks > 0 and alive:
		body_color = body_color.lightened(0.35)
	super()
	body_color = saved
	if not alive:
		return
	var top := -height - body_height
	# 투구 장식과 큰 검
	draw_rect(Rect2(-half_width, top - 6.0, half_width * 2.0, 6.0), Color(0.9, 0.75, 0.2))
	if state == &"telegraph":
		draw_rect(Rect2(-facing * 40.0 - 8.0, top + 16.0, 16.0, 8.0), Color(1.0, 0.4, 0.1))
	elif state == &"attack":
		var reach := slash.reach_forward if current_pattern == 0 else charge.reach_forward
		var x0 := 0.0 if facing > 0 else -reach
		draw_rect(Rect2(x0, top + 30.0, reach, 8.0), Color(1.0, 0.9, 0.2))
