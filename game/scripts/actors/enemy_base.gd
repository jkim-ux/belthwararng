class_name EnemyBase
extends BattleActor
## 적 공통 피격 반응: 경직, 짧은 띄우기(1회), 다운, 기상 보호.
## 상태: idle, hitstun, launched, down, getup, dead (+ 하위 클래스 상태)
## R1: 밀림은 AttackData.knockback_ms 가 양수면 그 기간 동안 감속 곡선(MotionCurve)으로 총 거리를 소모하고,
## 0 이면 M1 방식(매초 240 px 일정 속도)이다. 경직 시간과 밀림 시간은 분리되며 새 타격이 오면 밀림을 교체한다.

const LEGACY_KNOCKBACK_SPEED := 240.0

var can_be_launched: bool = true
var knockback_enabled: bool = true
var launch_dir: int = 1
var knockback_total: float = 0.0     ## 이번 밀림의 총 거리
var knockback_ticks: int = 0         ## 곡선 밀림 기간(0 = 일정 속도)
var knockback_t: int = 0             ## 곡선 밀림 진행 틱
var required_for_victory: bool = true   ## 캠페인 승리 조건에 세는 적인지(허수아비는 false)
var falling_by_knockdown: bool = false  ## 공중에서 내려베기를 맞아 강제 하강 중(착지 전 추가 띄우기 금지)

func _on_hit(info: HitInfo) -> void:
	# HWR-004 내려베기(D): '이미 공중이면 피해만' 보다 먼저 검사한다. 강인병/보스는 이 경로에 들어오지 않는다(재정의).
	if info.attack.knockdown and can_be_launched:
		_apply_knockdown(info)
		return
	if info.attack.hitstun_ms <= 0.0 and not info.attack.launch:
		# 경직 0 인 공격(지원 사격 등): 피해만 적용하고 상태·밀림을 바꾸지 않는다.
		return
	end_hitboxes()
	if info.attack.launch and can_be_launched and not airborne_by_launch and not falling_by_knockdown and height <= 0.0:
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
	if info.attack.hitstun_ms <= 0.0:
		return
	hitstun_ticks = Ticks.from_ms(info.attack.hitstun_ms)
	_set_knockback(info)
	velocity = Vector2.ZERO
	change_state(&"hitstun")

## 내려베기: 지상이면 즉시 다운, 공중이면 z 를 옮기지 않고 하강 속도를 최소 500 으로 바꿔 기존 중력·착지 경로로 다운.
## 이미 down/getup 이면 피해만(타이머 재시작 없음). 추가 수평 밀림 없음.
func _apply_knockdown(_info: HitInfo) -> void:
	if state == &"down" or state == &"getup":
		return
	end_hitboxes()
	velocity = Vector2.ZERO
	knockback_remaining = 0.0
	if is_airborne():
		vz = minf(vz, -500.0)
		airborne_by_launch = true
		falling_by_knockdown = true
		if state != &"launched":
			change_state(&"launched")
		return
	change_state(&"down")

## 새 타격의 밀림으로 교체한다(합산하지 않음). 같은 틱에 여러 타격이 오면 마지막 적용이 남는다.
func _set_knockback(info: HitInfo) -> void:
	knockback_remaining = info.effective_knockback() if knockback_enabled else 0.0
	knockback_total = knockback_remaining
	knockback_ticks = info.attack.knockback_ticks() if knockback_enabled else 0
	knockback_t = 0
	knockback_dir = info.direction

func _step_knockback() -> void:
	if knockback_remaining <= 0.0:
		return
	var stepd := 0.0
	if knockback_ticks > 0:
		stepd = MotionCurve.ease_out_step(knockback_total, knockback_t, knockback_ticks)
		knockback_t += 1
		stepd = minf(stepd, knockback_remaining)
	else:
		stepd = minf(knockback_remaining, LEGACY_KNOCKBACK_SPEED * Ticks.DT)
	floor_pos.x += stepd * knockback_dir
	knockback_remaining -= stepd
	if knockback_ticks > 0 and knockback_t >= knockback_ticks:
		knockback_remaining = 0.0

func _step_hitstun() -> void:
	_step_knockback()
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
	falling_by_knockdown = false
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
	knockback_remaining = 0.0
	falling_by_knockdown = false

## 강인병/보스처럼 경직 면역인 적인가(HUD·자동 플레이 판단용)
func is_stagger_immune() -> bool:
	return false

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
