class_name BattleActor
extends Node2D
## 전투 개체의 공통 바탕. 바닥 위치(x, y)와 높이(z)를 분리해 관리한다.
## Node2D.position 은 항상 바닥 위치와 같게 두어 Y 정렬(그리기 순서)이 발 위치를 따르게 한다.
## 몸체 그림은 _draw 에서 높이만큼 위(-z)에 그린다.

signal hit_taken(actor: BattleActor, info: HitInfo)
signal died(actor: BattleActor)
signal burn_taken(actor: BattleActor, amount: int)

var tuning: CombatTuning
var battle: Node                       ## Battle (경기장 경계, 타격 처리)

@export var team: StringName = &"enemy"
@export var display_name: String = "개체"
@export var body_color: Color = Color(0.8, 0.3, 0.3)

# --- 공간 ---
var floor_pos: Vector2 = Vector2.ZERO   ## 바닥 x(좌우), y(깊이)
var velocity: Vector2 = Vector2.ZERO    ## 바닥 속도 px/s
var height: float = 0.0                 ## z, 바닥에서 위로
var vz: float = 0.0                     ## 높이 속도 px/s
var facing: int = 1                     ## +1 오른쪽, -1 왼쪽

# --- 피격 판정 범위 (발 위치 기준) ---
var half_width: float = 22.0
var half_depth: float = 10.0
var body_height: float = 70.0

# --- 상태 ---
var max_hp: int = 100
var hp: int = 100
var alive: bool = true
var state: StringName = &"idle"
var state_ticks: int = 0                ## 현재 상태에서 흐른 틱(타격 정지 제외)
var hitstop_ticks: int = 0              ## 남은 타격 정지
var invuln_ticks: int = 0               ## 남은 무적
var hitstun_ticks: int = 0
var knockback_remaining: float = 0.0    ## 경직 동안 밀려날 남은 거리
var knockback_dir: int = 1
var total_damage_taken: int = 0
var airborne_by_launch: bool = false    ## 띄워진 상태(재차 띄우기 금지)

var active_hitboxes: Array[HitBox] = []

func _ready() -> void:
	position = floor_pos
	queue_redraw()

func setup(p_tuning: CombatTuning, p_battle: Node, start: Vector2) -> void:
	tuning = p_tuning
	battle = p_battle
	floor_pos = start
	position = start

## 한 틱 진행. Battle 이 순서대로 호출한다. 타격 정지 중에는 상태가 멈추지만 입력 수집은 하위 클래스가 이전에 처리한다.
func step() -> void:
	if not alive:
		_sync_position()
		return
	if hitstop_ticks > 0:
		hitstop_ticks -= 1
		_sync_position()
		queue_redraw()
		return
	if invuln_ticks > 0:
		invuln_ticks -= 1
	state_ticks += 1
	_step_state()
	_clamp_to_arena()
	_sync_position()
	queue_redraw()

## 하위 클래스가 상태별 논리를 구현한다.
func _step_state() -> void:
	pass

func change_state(new_state: StringName) -> void:
	state = new_state
	state_ticks = 0
	_on_state_entered(new_state)

func _on_state_entered(_new_state: StringName) -> void:
	pass

func is_airborne() -> bool:
	return height > 0.0 or vz > 0.0

## 중력 적용. 착지하면 true 를 돌려준다.
func apply_gravity() -> bool:
	if height <= 0.0 and vz <= 0.0:
		height = 0.0
		return false
	vz -= tuning.gravity * Ticks.DT
	height += vz * Ticks.DT
	if height <= 0.0:
		height = 0.0
		vz = 0.0
		return true
	return false

func move_by_velocity() -> void:
	floor_pos += velocity * Ticks.DT

## 목표 속도로 가속·감속. 시간은 ms 기준(정지↔최대 속도).
func approach_velocity(target: Vector2) -> void:
	var accel_t: float = maxf(tuning.accel_ms, 1.0) / 1000.0
	var decel_t: float = maxf(tuning.decel_ms, 1.0) / 1000.0
	velocity.x = _approach_axis(velocity.x, target.x, tuning.move_speed_x, accel_t, decel_t)
	velocity.y = _approach_axis(velocity.y, target.y, tuning.move_speed_y, accel_t, decel_t)

func _approach_axis(current: float, target: float, max_speed: float, accel_t: float, decel_t: float) -> float:
	var accelerating := absf(target) > 0.0 and (signf(target) == signf(current) or is_zero_approx(current)) and absf(target) > absf(current)
	var rate := max_speed / (accel_t if accelerating else decel_t) * Ticks.DT
	return move_toward(current, target, rate)

func _clamp_to_arena() -> void:
	if battle == null or not battle.has_method("arena_rect"):
		return
	var r: Rect2 = battle.arena_rect()
	var nx := clampf(floor_pos.x, r.position.x + half_width, r.end.x - half_width)
	var ny := clampf(floor_pos.y, r.position.y, r.end.y)
	if nx != floor_pos.x:
		velocity.x = 0.0
	if ny != floor_pos.y:
		velocity.y = 0.0
	floor_pos = Vector2(nx, ny)

func _sync_position() -> void:
	position = floor_pos

# --- 피격 판정 ---
func hurt_x_range() -> Vector2:
	return Vector2(floor_pos.x - half_width, floor_pos.x + half_width)

func hurt_y_range() -> Vector2:
	return Vector2(floor_pos.y - half_depth, floor_pos.y + half_depth)

func hurt_z_range() -> Vector2:
	return Vector2(height, height + body_height)

func can_be_hit() -> bool:
	return alive and invuln_ticks <= 0

## 적중 확정 후 호출. 하위 클래스가 반응(경직·띄우기)을 결정한다. 실제 피해 적용 여부를 돌려준다.
func receive_hit(info: HitInfo) -> bool:
	if not can_be_hit():
		return false
	var dmg := maxi(1, roundi(info.damage))
	hp = maxi(0, hp - dmg)
	total_damage_taken += dmg
	hitstop_ticks = maxi(hitstop_ticks, _victim_hitstop(info))
	_on_hit(info)
	hit_taken.emit(self, info)
	if hp <= 0 and max_hp > 0:
		_die()
	return true

func _on_hit(_info: HitInfo) -> void:
	pass

## 피격 대상 쪽 타격 정지. 기본은 공격의 값이며 강인병(항상 0)·보스(패턴 중 0)가 재정의한다. 공격자 쪽 정지와 별개다.
func _victim_hitstop(info: HitInfo) -> int:
	return info.hitstop_ticks

## 지속 피해(바닥 불): 경직·밀림·타격 정지·현재 행동 취소 없이 체력·무적·사망만 처리한다. 적용한 피해를 돌려준다.
func receive_burn(dmg: int) -> int:
	if not can_be_hit() or dmg <= 0:
		return 0
	var applied := mini(hp, dmg)
	hp -= applied
	total_damage_taken += applied
	burn_taken.emit(self, applied)
	if hp <= 0 and max_hp > 0:
		_die()
	return applied

## 공격자가 적중을 확인했을 때. 타격 정지는 합산하지 않고 최댓값만 유지한다.
func on_hit_confirmed(hitstop: int) -> void:
	hitstop_ticks = maxi(hitstop_ticks, hitstop)

func _die() -> void:
	alive = false
	active_hitboxes.clear()
	change_state(&"dead")
	died.emit(self)

func begin_hitbox(attack: AttackData, damage: float, hit_index: int = 0) -> HitBox:
	var hs := Ticks.from_ms(tuning.hitstop_strong_ms if attack.strong else tuning.hitstop_light_ms)
	var hb := HitBox.new(self, team, attack, damage, hs, facing)
	hb.hit_index = hit_index
	active_hitboxes.append(hb)
	return hb

## 판정을 거둔다. 이미 복사된 배열(Battle 의 순회)에서도 적용되지 않도록 취소 표시를 남긴다.
func end_hitboxes() -> void:
	for hb in active_hitboxes:
		hb.cancelled = true
	active_hitboxes.clear()

# --- 그리기 (임시 도형) ---
func _draw() -> void:
	# 바닥 그림자: 발 위치(원점)에 그린다.
	var shadow_alpha := clampf(0.45 - height / 400.0, 0.12, 0.45)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, half_width + 4.0, Color(0, 0, 0, shadow_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_body()

func _draw_body() -> void:
	var c := body_color
	if not alive:
		c = c.darkened(0.6)
	elif hitstun_ticks > 0 or state == &"hitstun" or state == &"launched" or state == &"down":
		c = c.lightened(0.5)
	if invuln_ticks > 0 and alive:
		c.a = 0.55
	var top := -height - body_height
	draw_rect(Rect2(-half_width, top, half_width * 2.0, body_height), c)
	# 바라보는 방향 표시
	var eye_x := half_width * 0.5 * facing
	draw_rect(Rect2(eye_x - 4.0, top + 12.0, 8.0, 8.0), Color(0.1, 0.1, 0.1))
