class_name EnemyBase
extends BattleActor
## 적 공통 피격 반응: 경직, 짧은 띄우기(1회), 다운, 기상 보호.
## 상태: idle, hitstun, launched, down, getup, dead (+ 하위 클래스 상태)

var can_be_launched: bool = true
var knockback_enabled: bool = true
var launch_dir: int = 1

func _on_hit(info: HitInfo) -> void:
	end_hitboxes()
	if info.attack.launch and can_be_launched and not airborne_by_launch and height <= 0.0:
		# 띄우기: 지상에 있고 아직 띄워지지 않은 대상에게만
		airborne_by_launch = true
		vz = info.attack.launch_velocity
		height = 0.001
		launch_dir = info.direction
		velocity = Vector2.ZERO
		change_state(&"launched")
		return
	if airborne_by_launch or state == &"launched":
		# 이미 떠 있는 대상: 피해만 적용하고 재차 띄우지 않는다. 낙하는 계속.
		return
	if state == &"down" or state == &"getup":
		return
	hitstun_ticks = Ticks.from_ms(info.attack.hitstun_ms)
	knockback_remaining = info.attack.knockback if knockback_enabled else 0.0
	knockback_dir = info.direction
	velocity = Vector2.ZERO
	change_state(&"hitstun")

func _step_hitstun() -> void:
	if knockback_remaining > 0.0:
		var stepd := minf(knockback_remaining, 240.0 * Ticks.DT)
		floor_pos.x += stepd * knockback_dir
		knockback_remaining -= stepd
	if state_ticks >= hitstun_ticks:
		change_state(&"idle")

func _step_launched() -> void:
	var landed := apply_gravity()
	if knockback_enabled:
		floor_pos.x += launch_dir * 60.0 * Ticks.DT
	if landed:
		_on_landed_from_launch()

func _on_landed_from_launch() -> void:
	airborne_by_launch = false
	change_state(&"down")

func _step_down() -> void:
	if state_ticks >= Ticks.from_ms(tuning.enemy_down_ms):
		invuln_ticks = Ticks.from_ms(tuning.enemy_getup_protect_ms)
		change_state(&"getup")

func _step_getup() -> void:
	if state_ticks >= Ticks.from_ms(tuning.enemy_getup_protect_ms):
		change_state(&"idle")

func _die() -> void:
	super()
	velocity = Vector2.ZERO

## 하위 클래스에서 공통 상태를 처리한 뒤 true 를 돌려주면 나머지는 건너뛴다.
func _step_common_reactions() -> bool:
	match state:
		&"hitstun":
			_step_hitstun()
			return true
		&"launched":
			_step_launched()
			return true
		&"down":
			_step_down()
			return true
		&"getup":
			_step_getup()
			return true
		&"dead":
			return true
	return false

func _draw_body() -> void:
	# 머리 위 체력 막대 (일반 플레이 표시)
	if max_hp > 0 and alive:
		var top := -height - body_height - 12.0
		draw_rect(Rect2(-half_width, top, half_width * 2.0, 5.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-half_width, top, half_width * 2.0 * float(hp) / float(max_hp), 5.0), Color(0.9, 0.25, 0.25))
	if state == &"down" and alive:
		# 다운: 납작하게 눕힌다
		var c := body_color.lightened(0.3)
		draw_rect(Rect2(-body_height * 0.5, -half_width * 1.2, body_height, half_width * 1.2), c)
		return
	super()
