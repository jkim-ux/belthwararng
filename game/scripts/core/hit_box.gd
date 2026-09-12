class_name HitBox
extends RefCounted
## 한 번의 공격 인스턴스가 만드는 판정. 바닥 좌표(x, y)와 높이(z)로 표현한다.
## 같은 인스턴스·같은 대상 조합에는 피해가 한 번만 적용된다(applied_targets).
## 다단히트 스킬은 hit_index 를 올려 새 HitBox 를 만든다.

static var _next_instance_id: int = 1

var instance_id: int
var hit_index: int = 0
var owner: Node            ## BattleActor
var team: StringName
var attack: AttackData
var damage: float
var hitstop_ticks: int
var facing: int = 1
## 공격자 발 위치 기준 상대 범위. 매 틱 공격자 위치로 절대 범위를 계산한다.
var x_min: float
var x_max: float
var depth: float
var z_min: float
var z_max: float
var applied_targets: Array = []
var active: bool = false

func _init(p_owner: Node, p_team: StringName, p_attack: AttackData, p_damage: float, p_hitstop_ticks: int, p_facing: int) -> void:
	instance_id = _next_instance_id
	_next_instance_id += 1
	owner = p_owner
	team = p_team
	attack = p_attack
	damage = p_damage
	hitstop_ticks = p_hitstop_ticks
	facing = p_facing
	if facing >= 0:
		x_min = -attack.reach_back
		x_max = attack.reach_forward
	else:
		x_min = -attack.reach_forward
		x_max = attack.reach_back
	depth = attack.depth_tolerance
	z_min = attack.z_min
	z_max = attack.z_max

## 절대 좌표 범위 (디버그 표시와 판정에 공통 사용)
func world_x_range(origin: Vector2) -> Vector2:
	return Vector2(origin.x + x_min, origin.x + x_max)

func world_y_range(origin: Vector2) -> Vector2:
	return Vector2(origin.y - depth, origin.y + depth)

func world_z_range(origin_z: float) -> Vector2:
	return Vector2(origin_z + z_min, origin_z + z_max)

func already_hit(target: Node) -> bool:
	return applied_targets.has(target)

func mark_hit(target: Node) -> void:
	applied_targets.append(target)
