class_name Player
extends BattleActor
## 주인공(사무라이) 조작. 입력 보관, 지상 이동, 점프 높이, 회피, 평타 3연격, 스킬 실행을 담당한다.
## 상태: ground, air, dodge, light, air_attack, skill, hitstun, dead
## R1: 지상 평타는 타격 구간 동안 감속 곡선으로 전진한다(AttackData.advance_px). 전진량은 틱마다 곡선에서
## 계산하므로 취소·피격·경계로 공격이 끝나면 남은 전진은 자동으로 폐기되고 다음 행동에 새지 않는다.

const ACTION_LIGHT: StringName = &"attack_light"
const ACTION_JUMP: StringName = &"jump"
const ACTION_DODGE: StringName = &"dodge"
const SKILL_ACTIONS: Array[StringName] = [&"skill_a", &"skill_s", &"skill_d", &"skill_f", &"skill_q", &"skill_w", &"skill_e", &"skill_r"]
const BUFFERABLE_ACTIONS: Array[StringName] = [&"attack_light", &"jump", &"dodge", &"skill_a", &"skill_s", &"skill_d", &"skill_f", &"skill_q", &"skill_w", &"skill_e", &"skill_r"]
const SWING_TRAIL_TICKS := 4               ## 타격 종료 후 잔상이 남는 틱

var light_attacks: Array[AttackData] = []
var air_attack: AttackData
var skill_set: SkillSet
var skills_by_action: Dictionary = {}     ## action_name -> SkillData
var cooldowns: Dictionary = {}            ## skill id -> 남은 틱
var dodge_cooldown_ticks: int = 0
var attack_power: float = 20.0
var profile_id: StringName = &""

# 입력
var move_input: Vector2 = Vector2.ZERO
var buffered_action: StringName = &""
var buffer_age: int = 0                   ## 보관 입력이 흐른 틱 수. 타격 정지 중에는 흐르지 않는다.
var tick_count: int = 0                   ## 타격 정지와 무관하게 매 틱 증가

# 공격 실행 상태
var current_attack: AttackData
var current_skill: SkillData
var light_index: int = 0
var current_hitbox: HitBox
var air_attack_used: bool = false
var dodge_dir: Vector2 = Vector2.RIGHT
var attack_facing: int = 1                ## 공격 시작 때 고정한 좌우 방향
var attack_advance_done: float = 0.0      ## 이번 공격에서 곡선으로 요청한 전진 합(디버그 표시용)
var last_event: String = ""               ## 디버그 표시용

func _init() -> void:
	team = &"player"
	display_name = "사무라이"
	body_color = Color(0.25, 0.55, 0.95)

func configure(p_tuning: CombatTuning, p_battle: Node, start: Vector2, p_lights: Array[AttackData], p_air: AttackData, p_skills: SkillSet) -> void:
	setup(p_tuning, p_battle, start)
	light_attacks = p_lights
	air_attack = p_air
	skill_set = p_skills
	skills_by_action.clear()
	cooldowns.clear()
	for sd in skill_set.skills:
		skills_by_action[sd.action_name] = sd
		cooldowns[sd.id] = 0
	max_hp = tuning.player_max_hp
	hp = max_hp
	attack_power = tuning.player_attack
	half_width = tuning.player_half_width
	half_depth = tuning.player_half_depth
	body_height = tuning.player_height
	facing = 1
	alive = true
	change_state(&"ground")

## 프로필 적용: 평타 리소스 참조만 바꾼다. 공유 Resource 의 값은 수정하지 않는다.
func apply_profile(profile: CombatProfile) -> void:
	light_attacks = profile.light_attacks
	profile_id = profile.id

## 개발용 초기화: 위치와 체력, 대기시간을 되돌린다.
func reset_to(start: Vector2) -> void:
	floor_pos = start
	velocity = Vector2.ZERO
	height = 0.0
	vz = 0.0
	hp = max_hp
	alive = true
	hitstop_ticks = 0
	invuln_ticks = 0
	hitstun_ticks = 0
	buffered_action = &""
	end_hitboxes()
	for k in cooldowns.keys():
		cooldowns[k] = 0
	dodge_cooldown_ticks = 0
	facing = 1
	change_state(&"ground")
	_sync_position()

# ------------------------------------------------------------------ 입력

## 입력을 먼저 수집한 뒤 한 틱 진행한다. 타격 정지 중에도 수집은 계속된다.
func step_with_input(inp: PlayerInput) -> void:
	tick_count += 1
	move_input = inp.move
	for a in inp.pressed:
		if BUFFERABLE_ACTIONS.has(a):
			buffered_action = a
			buffer_age = 0
	_tick_cooldowns()
	var frozen := hitstop_ticks > 0
	step()
	# 보관 입력의 나이는 상태가 실제로 진행된 틱에서만 늘어난다(타격 정지 제외).
	if not frozen and buffered_action != &"":
		buffer_age += 1

func _tick_cooldowns() -> void:
	for k in cooldowns.keys():
		if cooldowns[k] > 0:
			cooldowns[k] -= 1
	if dodge_cooldown_ticks > 0:
		dodge_cooldown_ticks -= 1

func buffer_ticks() -> int:
	return Ticks.from_ms(tuning.input_buffer_ms)

func buffer_is_live() -> bool:
	return buffered_action != &"" and buffer_age <= buffer_ticks()

func clear_buffer() -> void:
	buffered_action = &""

## 보관된 입력이 허용 목록에 있고 조건을 만족하면 실행한다.
func _try_buffer(allowed: Array[StringName]) -> bool:
	if buffered_action == &"":
		return false
	if buffer_age > buffer_ticks():
		buffered_action = &""
		return false
	if not allowed.has(buffered_action):
		return false
	var action := buffered_action
	match action:
		ACTION_LIGHT:
			buffered_action = &""
			if state == &"air":
				_start_air_attack()
			else:
				_start_light()
			return true
		ACTION_JUMP:
			buffered_action = &""
			_start_jump()
			return true
		ACTION_DODGE:
			if dodge_cooldown_ticks > 0:
				return false
			buffered_action = &""
			_start_dodge()
			return true
		_:
			if skills_by_action.has(action):
				var sd: SkillData = skills_by_action[action]
				if not sd.implemented:
					buffered_action = &""
					last_event = "미구현 스킬 %s 무시" % sd.display_name
					return false
				if cooldowns.get(sd.id, 0) > 0:
					return false
				buffered_action = &""
				_start_skill(sd)
				return true
	return false

func _all_ground_actions() -> Array[StringName]:
	var a: Array[StringName] = [ACTION_LIGHT, ACTION_JUMP, ACTION_DODGE]
	a.append_array(SKILL_ACTIONS)
	return a

func _chain_actions() -> Array[StringName]:
	var a: Array[StringName] = []
	if light_index < 3:
		a.append(ACTION_LIGHT)
	a.append_array(SKILL_ACTIONS)
	return a

# ------------------------------------------------------------------ 상태

func _step_state() -> void:
	match state:
		&"ground":
			_step_ground()
		&"air":
			_step_air()
		&"dodge":
			_step_dodge()
		&"light", &"skill":
			_step_attack()
		&"air_attack":
			_step_air_attack()
		&"hitstun":
			_step_hitstun()
		&"dead":
			pass

func _on_state_entered(new_state: StringName) -> void:
	if new_state != &"light" and new_state != &"skill" and new_state != &"air_attack":
		end_hitboxes()
		current_hitbox = null
		current_attack = null
		current_skill = null
	if new_state != &"light":
		light_index = 0

func _move_target() -> Vector2:
	var n := move_input
	if n.length() > 1.0:
		n = n.normalized()
	return Vector2(n.x * tuning.move_speed_x, n.y * tuning.move_speed_y)

func _step_ground() -> void:
	if _try_buffer(_all_ground_actions()):
		return
	if move_input.x > 0.05:
		facing = 1
	elif move_input.x < -0.05:
		facing = -1
	approach_velocity(_move_target())
	move_by_velocity()

func _start_jump() -> void:
	vz = tuning.jump_velocity
	height = 0.001
	air_attack_used = false
	change_state(&"air")
	last_event = "점프"

func _step_air() -> void:
	var landed := apply_gravity()
	move_by_velocity()
	if landed:
		velocity = Vector2.ZERO
		change_state(&"ground")
		return
	if not air_attack_used:
		_try_buffer([ACTION_LIGHT])

func _start_dodge() -> void:
	var dir := move_input
	if dir.length() < 0.05:
		dir = Vector2(facing, 0.0)
	else:
		dir = dir.normalized()
		if absf(dir.x) > 0.05:
			facing = 1 if dir.x > 0.0 else -1
	dodge_dir = dir
	dodge_cooldown_ticks = Ticks.from_ms(tuning.dodge_cooldown_ms)
	invuln_ticks = Ticks.from_ms(tuning.dodge_invuln_ms)
	velocity = Vector2.ZERO
	change_state(&"dodge")
	last_event = "회피"

func _step_dodge() -> void:
	var dur := Ticks.from_ms(tuning.dodge_ms)
	var speed_x := tuning.dodge_distance / (float(dur) * Ticks.DT)
	var ratio := tuning.move_speed_y / maxf(tuning.move_speed_x, 1.0)
	velocity = Vector2(dodge_dir.x * speed_x, dodge_dir.y * speed_x * ratio)
	move_by_velocity()
	if state_ticks >= dur:
		velocity = Vector2.ZERO
		change_state(&"ground")

func _start_light() -> void:
	var next := 1
	if state == &"light" and light_index < 3:
		next = light_index + 1
	end_hitboxes()
	current_hitbox = null
	current_skill = null
	light_index = next
	current_attack = light_attacks[next - 1]
	change_state(&"light")
	light_index = next
	last_event = "평타 %d" % next
	_begin_attack_tick()

func _start_skill(sd: SkillData) -> void:
	end_hitboxes()
	current_hitbox = null
	current_skill = sd
	current_attack = sd.attack
	cooldowns[sd.id] = sd.cooldown_ticks()
	change_state(&"skill")
	last_event = sd.display_name
	_begin_attack_tick()

func _start_air_attack() -> void:
	air_attack_used = true
	current_attack = air_attack
	change_state(&"air_attack")
	last_event = "공중 평타"
	_begin_attack_tick()

## 입력을 소비한 틱을 공격의 첫 틱(t=0)으로 삼는다. 준비 0 ms 공격은 이 틱에 바로 판정을 만든다.
func _begin_attack_tick() -> void:
	attack_facing = facing
	attack_advance_done = 0.0
	state_ticks = 1
	_advance_attack_hitbox()

## 공격 구간 인덱스. 0부터 시작.
func attack_t() -> int:
	return state_ticks - 1

func attack_phase() -> StringName:
	if current_attack == null:
		return &""
	var t := attack_t()
	var s := current_attack.startup_ticks()
	var a := current_attack.active_ticks()
	if t < s:
		return &"startup"
	if t < s + a:
		return &"active"
	if t < current_attack.total_ticks():
		return &"recovery"
	return &"done"

func _advance_attack_hitbox() -> void:
	var t := attack_t()
	var s := current_attack.startup_ticks()
	var a := current_attack.active_ticks()
	if t == s:
		current_hitbox = begin_hitbox(current_attack, attack_power * current_attack.damage_mult)
	elif t == s + a:
		end_hitboxes()
		current_hitbox = null

func _step_attack() -> void:
	var atk := current_attack
	var t := attack_t()
	var total := atk.total_ticks()
	var s := atk.startup_ticks()
	var a := atk.active_ticks()
	# 종료: 지상으로 돌아가고 같은 틱에 보관 입력을 적용한다.
	if t >= total:
		change_state(&"ground")
		velocity = Vector2.ZERO
		_step_ground()
		return
	_advance_attack_hitbox()
	var in_active := t >= s and t < s + a
	if atk.dash_distance > 0.0 and in_active:
		# 스킬 돌진: 기존 일정 속도 전진
		velocity = Vector2(attack_facing * atk.dash_distance / (float(a) * Ticks.DT), 0.0)
		move_by_velocity()
	elif atk.advance_px > 0.0 and in_active:
		# 평타 전진: 곡선이 x 이동을 맡고 잔여 x 속도는 더하지 않는다. y 는 기존대로 감속한다.
		velocity.x = 0.0
		approach_velocity(Vector2.ZERO)
		move_by_velocity()
		var stepd := MotionCurve.ease_out_step(atk.advance_px, t - s, a)
		floor_pos.x += attack_facing * stepd
		attack_advance_done += stepd
	else:
		# 준비·회복: 잔여 속도를 감속
		approach_velocity(Vector2.ZERO)
		move_by_velocity()
	# 연결 규칙
	if state == &"light":
		if t >= total - atk.chain_window_ticks():
			if _try_buffer(_chain_actions()):
				return
		if atk.dodge_after_active and t >= s + a:
			if _try_buffer([ACTION_DODGE]):
				return
	else: # skill
		var mc := atk.move_cancel_ticks()
		if mc > 0 and t >= total - mc:
			if _try_buffer([ACTION_DODGE]):
				return
			if move_input.length() > 0.05:
				change_state(&"ground")
				_step_ground()
				return

func _step_air_attack() -> void:
	var landed := apply_gravity()
	move_by_velocity()
	if landed:
		velocity = Vector2.ZERO
		change_state(&"ground")
		return
	var t := attack_t()
	if t >= current_attack.total_ticks():
		change_state(&"air")
		return
	_advance_attack_hitbox()

func _step_hitstun() -> void:
	if knockback_remaining > 0.0:
		var stepd := minf(knockback_remaining, 260.0 * Ticks.DT)
		floor_pos.x += stepd * knockback_dir
		knockback_remaining -= stepd
	if state_ticks >= hitstun_ticks:
		change_state(&"ground")

func _on_hit(info: HitInfo) -> void:
	clear_buffer()
	hitstun_ticks = Ticks.from_ms(tuning.player_hitstun_ms)
	knockback_remaining = info.effective_knockback()
	knockback_dir = info.direction
	velocity = Vector2.ZERO
	if height > 0.0:
		height = 0.0
		vz = 0.0
	change_state(&"hitstun")

func _die() -> void:
	clear_buffer()
	super()

func cooldown_for(sd: SkillData) -> int:
	return cooldowns.get(sd.id, 0)

## 흘려받기 판정(Battle 의 바깥 판정 계층이 receive_hit 전에 호출). HWR-004 4단계에서 구현한다.
func try_parry(_info: HitInfo) -> bool:
	return false

# ------------------------------------------------------------------ 그리기
## 몸 기울기와 검 궤적은 그림에만 적용한다. 발 위치, 그림자, y 정렬, 피격 범위, 높이는 바꾸지 않는다.

func _swing_progress() -> float:
	## 타격 구간 진행도 0~1 (타격 종료 후에는 1 이상, 잔상용)
	var s := current_attack.startup_ticks()
	var a := current_attack.active_ticks()
	return float(attack_t() - s + 1) / float(maxi(1, a))

func _visual_offset() -> Vector2:
	if current_attack == null or current_attack.swing_style == AttackData.Swing.LEGACY:
		return Vector2.ZERO
	var s := current_attack.startup_ticks()
	var a := current_attack.active_ticks()
	var t := attack_t()
	var f := float(attack_facing)
	if t < s:
		# 준비: 짧게 뒤로 당긴다
		return Vector2(-4.0 * f * float(t + 1) / float(maxi(1, s)), 0.0)
	if t < s + a:
		# 타격: 몸이 전방에 실린다
		var lean := 6.0 if current_attack.swing_style != AttackData.Swing.DIAGONAL_DOWN else 9.0
		return Vector2(lean * f, 2.0)
	# 회복: 원래 자세로 돌아온다
	var r := float(t - s - a) / float(maxi(1, current_attack.recovery_ticks()))
	return Vector2(6.0 * f * maxf(0.0, 1.0 - r * 3.0), 0.0)

func _draw_body() -> void:
	var off := _visual_offset()
	if off != Vector2.ZERO:
		draw_set_transform(off, 0.0, Vector2.ONE)
	super()
	if off != Vector2.ZERO:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_sword()

func _draw_sword() -> void:
	if current_attack == null or (state != &"light" and state != &"skill" and state != &"air_attack"):
		return
	var style: int = current_attack.swing_style
	var phase := attack_phase()
	if style == AttackData.Swing.LEGACY:
		# M1 표시: 타격 구간 동안 앞쪽 사각형
		if current_hitbox != null and phase == &"active":
			var top := -height - body_height * 0.5
			var col := Color(1.0, 0.95, 0.6, 0.85)
			if current_skill != null:
				col = Color(1.0, 0.6, 0.2, 0.9)
			draw_rect(Rect2(current_hitbox.x_min, top - 12.0, current_hitbox.x_max - current_hitbox.x_min, 24.0), col)
		return
	var f := float(attack_facing)
	var pivot := Vector2(_visual_offset().x, -height - body_height + 22.0)   # 어깨
	var radius := current_attack.reach_forward - 6.0                          # 실제 판정 폭 안에서 표시
	var a0 := 0.0
	var a1 := 0.0
	match style:
		AttackData.Swing.HORIZONTAL:
			a0 = deg_to_rad(-38.0)
			a1 = deg_to_rad(14.0)
		AttackData.Swing.HORIZONTAL_REVERSE:
			a0 = deg_to_rad(14.0)
			a1 = deg_to_rad(-38.0)
		AttackData.Swing.DIAGONAL_DOWN:
			a0 = deg_to_rad(-105.0)
			a1 = deg_to_rad(32.0)
			radius = current_attack.reach_forward - 4.0
	var col := Color(1.0, 0.96, 0.75, 0.9)
	if phase == &"startup":
		# 검을 뒤로 모은다
		var back := pivot + Vector2(-f * 26.0, -10.0)
		draw_line(pivot, back, Color(0.9, 0.9, 0.95, 0.9), 3.0)
		return
	var u := 0.0
	var alpha := 1.0
	if phase == &"active":
		u = clampf(_swing_progress(), 0.0, 1.0)
	else:
		var past := attack_t() - current_attack.startup_ticks() - current_attack.active_ticks()
		if past >= SWING_TRAIL_TICKS:
			return
		u = 1.0
		alpha = 1.0 - float(past + 1) / float(SWING_TRAIL_TICKS + 1)
	var ang := lerpf(a0, a1, u)
	# 부채꼴 잔상 (지나간 구간)
	var pts := PackedVector2Array([pivot])
	var steps := 10
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var an := lerpf(a0, ang, t)
		pts.append(pivot + Vector2(cos(an) * f, sin(an)) * radius)
	if pts.size() >= 3:
		var fill := Color(1.0, 0.9, 0.5, 0.28 * alpha)
		if style == AttackData.Swing.DIAGONAL_DOWN:
			fill = Color(1.0, 0.75, 0.4, 0.34 * alpha)
		draw_colored_polygon(pts, fill)
	# 검 날 (현재 각도)
	col.a = alpha
	var tip := pivot + Vector2(cos(ang) * f, sin(ang)) * radius
	draw_line(pivot, tip, col, 4.0 if style == AttackData.Swing.DIAGONAL_DOWN else 3.0)
