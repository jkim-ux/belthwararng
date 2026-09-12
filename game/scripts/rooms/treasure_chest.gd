class_name TreasureChest
extends Node2D
## 보물방 중앙의 상자. 개봉 여부는 출정 상태(Battle)가 보관하며 이 노드는 표시와 상호작용 위치만 맡는다.

var floor_pos: Vector2 = Vector2(640, 545)
var opened: bool = false
var interact_radius: float = 70.0

func setup(at: Vector2, p_opened: bool) -> void:
	floor_pos = at
	opened = p_opened
	position = at

func near(p: Vector2) -> bool:
	return absf(p.x - floor_pos.x) <= interact_radius and absf(p.y - floor_pos.y) <= 40.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var body := Color(0.55, 0.35, 0.15)
	draw_rect(Rect2(-26, -30, 52, 30), body)
	draw_rect(Rect2(-26, -30, 52, 30), Color(0.9, 0.75, 0.3), false, 2.0)
	if opened:
		draw_rect(Rect2(-26, -50, 52, 12), body.lightened(0.15))
		draw_rect(Rect2(-20, -32, 40, 6), Color(1.0, 0.9, 0.4, 0.6))
	else:
		draw_rect(Rect2(-26, -42, 52, 14), body.darkened(0.1))
		draw_rect(Rect2(-5, -38, 10, 10), Color(0.95, 0.85, 0.35))
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.005)
		draw_arc(Vector2(0, -20), 44.0 + 4.0 * pulse, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, 0.25 + 0.2 * pulse), 2.0)
