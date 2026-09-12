class_name Projectile
extends Node2D
## 실제 투사체(화살). 바닥 x·깊이 y·높이 z 를 가지며 수평으로 날아간다.
## 적/경기장 끝/최대 사거리/수명에서 종료하고 아군은 관통한다. 명중 시 단일 대상 피해 후 제거된다.

var team: StringName = &"player"
var shooter: Node
var attack: AttackData
var damage: float = 7.0
var floor_pos: Vector2 = Vector2.ZERO
var height: float = 35.0
var vx: float = 600.0
var facing: int = 1
var half_height: float = 4.0
var half_depth: float = 4.0
var half_length: float = 10.0
var max_distance: float = 360.0
var life_ticks: int = 36
var traveled: float = 0.0
var alive: bool = true

func setup(p_team: StringName, p_shooter: Node, p_attack: AttackData, p_damage: float, start: Vector2, p_height: float, p_facing: int, speed: float, p_max_distance: float, p_life_ticks: int, p_half_height: float, p_half_depth: float) -> void:
	team = p_team
	shooter = p_shooter
	attack = p_attack
	damage = p_damage
	floor_pos = start
	height = p_height
	facing = p_facing
	vx = speed * float(p_facing)
	max_distance = p_max_distance
	life_ticks = p_life_ticks
	half_height = p_half_height
	half_depth = p_half_depth
	position = floor_pos

## 한 틱 이동. 사거리·수명·경기장 밖이면 종료한다.
func step(arena: Rect2) -> void:
	if not alive:
		return
	var d := vx * Ticks.DT
	floor_pos.x += d
	traveled += absf(d)
	life_ticks -= 1
	position = floor_pos
	if traveled >= max_distance or life_ticks <= 0 or floor_pos.x < arena.position.x or floor_pos.x > arena.end.x:
		finish()
	queue_redraw()

func finish() -> void:
	alive = false
	queue_free()

func x_range() -> Vector2:
	return Vector2(floor_pos.x - half_length, floor_pos.x + half_length)

func y_range() -> Vector2:
	return Vector2(floor_pos.y - half_depth, floor_pos.y + half_depth)

func z_range() -> Vector2:
	return Vector2(height - half_height, height + half_height)

func _draw() -> void:
	# 그림자와 화살대
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var y := -height
	draw_line(Vector2(-half_length * facing, y), Vector2(half_length * facing, y), Color(0.92, 0.85, 0.6), 2.0)
	draw_line(Vector2(half_length * facing, y), Vector2((half_length - 5.0) * facing, y - 3.0), Color(0.8, 0.8, 0.85), 2.0)
	draw_line(Vector2(half_length * facing, y), Vector2((half_length - 5.0) * facing, y + 3.0), Color(0.8, 0.8, 0.85), 2.0)
