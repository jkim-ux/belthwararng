class_name Player
extends BattleActor
## 화랑 조작. 입력 보관, 지상 이동, 점프 높이, 회피, 평타 3연격, 스킬 실행을 담당한다.
## 상태: ground, air, dodge, light, air_attack, skill, hitstun, dead

const ACTION_LIGHT: StringName = &"attack_light"
const ACTION_JUMP: StringName = &"jump"
const ACTION_DODGE: StringName = &"dodge"
const SKILL_ACTIONS: Array[StringName] = [&"skill_a", &"skill_s", &"skill_d", &"skill_f", &"skill_q", &"skill_w", &"skill_e", &"skill_r"]
const BUFFERABLE_ACTIONS: Array[StringName] = [&"attack_light", &"jump", &"dodge", &"skill_a", &"skill_s", &"skill_d", &"skill_f", &"skill_q", &"skill_w", &"skill_e", &"skill_r"]

var light_attacks: Array[AttackData] = []
var air_attack: AttackData
var skill_set: SkillSet
var skills_by_action: Dictionary = {}     ## action_name -> SkillData
var cooldowns: Dictionary = {}            ## skill id -> 남은 틱
var dodge_cooldown_ticks: int = 0
var attack_power: float = 20.0

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
var last_event: String = ""               ## 디버그 표시용

func _init() -> void:
	team = &"player"
	display_name = "화랑"
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
	# 이동: 돌진 구간이면 전진, 아니면 감속
	if atk.dash_distance > 0.0 and t >= s and t < s + a:
		velocity = Vector2(facing * atk.dash_distance / (float(a) * Ticks.DT), 0.0)
	else:
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
	knockback_remaining = info.attack.knockback
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

func _draw_body() -> void:
	super()
	# 검 궤적: 타격 구간 동안 앞쪽에 표시
	if current_hitbox != null and current_attack != null and attack_phase() == &"active":
		var top := -height - body_height * 0.5
		var col := Color(1.0, 0.95, 0.6, 0.85)
		if current_skill != null:
			col = Color(1.0, 0.6, 0.2, 0.9)
		var x0 := current_hitbox.x_min
		var x1 := current_hitbox.x_max
		draw_rect(Rect2(x0, top - 12.0, x1 - x0, 24.0), col)
