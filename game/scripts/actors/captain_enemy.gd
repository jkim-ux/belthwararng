class_name CaptainEnemy
extends EnemyBase
## 거점 보스(대장). 초기값 체력 600(초소)·피해 24(HWR-004), 띄우기·다운 면역. 표시명·체력은 거점 던전 데이터로 바꿀 수 있다.
## 전방 베기(예고 0.6/타격 0.1/회복 0.8초)와 직선 돌진(예고 0.8/이동 타격 0.3/회복 1.0초).
## HWR-004 R1 선택: 표적과 발 y 차이 ≤ 8 에서 베기는 |dx| ≤ 110, 돌진은 80 ≤ |dx| ≤ 300 이고 고정 경로가 실제로 닿을 때 후보.
##   둘 다 가능하면 베기 우선, 직전 완료 패턴이 2회 연속 같으면 다른 후보. 하나만 가능하면 그것. 둘 다 불가면 깊이를 맞추며 접근.
##   회복 첫 300 ms 에 공격 방향 반대로 60 px 균등 이동(벽에서 중단), 마지막 0.5 초는 이동 없음.
## 예고 시작 시 좌우 방향과 바닥 경로를 고정하고, 돌진은 최대 300 px·경기장 경계에서 멈추며 깊이를 추적하지 않는다.
## 피격: 패턴(예고/타격/회복) 중에는 경직·피격 타격 정지 0, 피해·섬광만. 대기·접근 중 평타/A/S/D/F/E 반격에는 120 ms 짧은 경직(비갱신).
##   Q/W/R(ignores_boss_flinch)은 어느 상태에서도 피해·섬광만(피격 타격 정지 0). 면역은 무적이 아니다.
## 상태: idle, approach, telegraph, attack, recover (+ 공통 hitstun/dead). 자세 파괴·페이즈 시스템은 아니다.

var target: BattleActor
var slash: AttackData
var charge: AttackData
var current_pattern: int = 0
var recent_patterns: Array[int] = []  ## 최근 완료한 패턴(최대 2)
var charge_remaining: float = 0.0
var flinch_ticks: int = 0             ## 피격 표시용(경직 아님)
var recover_step_done: float = 0.0    ## 회복 첫 구간의 후퇴 누적
var attacks_started: int = 0

func _init() -> void:
	team = &"enemy"
	display_name = "초소 대장"
	body_color = Color(0.55, 0.12, 0.18)
	can_be_launched = false
	knockback_enabled = false

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_target: BattleActor, p_display_name: String = "", p_max_hp: int = 0) -> void:
	setup(p_tuning, p_battle, start)
	target = p_target
	if p_display_name != "":
		display_name = p_display_name
	max_hp = p_max_hp if p_max_hp > 0 else tuning.captain_max_hp
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

func is_stagger_immune() -> bool:
	return true

## 피격 대상 쪽 타격 정지: 패턴 중 0, Q/W/R 은 어느 상태에서도 0. 그 외(대기·접근)는 공격 값.
func _victim_hitstop(info: HitInfo) -> int:
	if in_pattern() or info.attack.ignores_boss_flinch:
		return 0
	return info.hitstop_ticks

## 피격: 패턴 중에는 경직 없이 피해만. Q/W/R 은 어느 상태에서도 피해만. 대기·접근 중 짧은 경직(비갱신). 다운/띄우기/Q 무너짐 없음.
func _on_hit(info: HitInfo) -> void:
	flinch_ticks = 4
	if in_pattern():
		return
	if info.attack.ignores_boss_flinch:
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

func _charge_limit(dir: int) -> float:
	var r: Rect2 = battle.arena_rect()
	var limit := (r.end.x - half_width - floor_pos.x) if dir > 0 else (floor_pos.x - r.position.x - half_width)
	return minf(tuning.captain_charge_distance, maxf(0.0, limit))

## 거리 기반 패턴 후보. 돌진은 고정 경로(경계까지 잘린 거리 + 판정 폭)가 실제로 표적에 닿아야 후보다.
func _pattern_candidates() -> Array[int]:
	var out: Array[int] = []
	if not _target_valid():
		return out
	var dx := absf(target.floor_pos.x - floor_pos.x)
	var dy := absf(target.floor_pos.y - floor_pos.y)
	if dy > 8.0:
		return out
	if dx <= tuning.captain_slash_range:
		out.append(0)
	if dx >= tuning.captain_charge_min_range and dx <= tuning.captain_charge_max_range:
		var dir := 1 if target.floor_pos.x >= floor_pos.x else -1
		if _charge_limit(dir) + charge.reach_forward + target.half_width >= dx:
			out.append(1)
	return out

## 베기 우선. 둘 다 가능하고 직전 완료 패턴이 2회 연속 같으면 다른 후보. 하나만 가능하면 반복 제한 없이 사용.
func _choose_pattern(cands: Array[int]) -> int:
	if cands.size() == 1:
		return cands[0]
	var preferred := 0
	if recent_patterns.size() >= 2 and recent_patterns[0] == recent_patterns[1]:
		preferred = 1 - recent_patterns[0]
	return preferred if cands.has(preferred) else cands[0]

func _step_approach() -> void:
	_pick_target()
	if not _target_valid():
		change_state(&"idle")
		return
	facing = 1 if target.floor_pos.x >= floor_pos.x else -1
	var cands := _pattern_candidates()
	if not cands.is_empty():
		velocity = Vector2.ZERO
		current_pattern = _choose_pattern(cands)
		attacks_started += 1
		# 예고 시작: 방향·경로 고정. 이후 표적/방향을 다시 고르지 않는다.
		if current_pattern == 1:
			charge_remaining = _charge_limit(facing)
		change_state(&"telegraph")
		return
	# 둘 다 불가: 깊이를 맞추며 베기 거리(90)까지 접근한다. 돌진을 위해 물러나지 않는다.
	var want_dist := 90.0
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
		recent_patterns.push_front(current_pattern)
		if recent_patterns.size() > 2:
			recent_patterns.resize(2)
		recover_step_done = 0.0
		change_state(&"recover")

## 회복: 첫 300 ms 동안 고정한 공격 방향의 반대로 총 60 px 균등 이동(벽에서 중단, 미소비 거리는 버림). 이후 정지.
func _step_recover() -> void:
	var step_ticks := Ticks.from_ms(tuning.captain_recover_step_ms)
	if state_ticks <= step_ticks and recover_step_done < tuning.captain_recover_step_px:
		var per := tuning.captain_recover_step_px / float(maxi(1, step_ticks))
		var stepd := minf(per, tuning.captain_recover_step_px - recover_step_done)
		var r: Rect2 = battle.arena_rect()
		var limit := (floor_pos.x - r.position.x - half_width) if facing > 0 else (r.end.x - half_width - floor_pos.x)
		stepd = minf(stepd, maxf(0.0, limit))
		floor_pos.x -= facing * stepd
		recover_step_done += stepd
	velocity = Vector2.ZERO
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
