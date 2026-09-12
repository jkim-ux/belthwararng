class_name SpawnMarker
extends Node2D
## 적 출현 예고 표시. 바닥 위치에서 짧게 깜박이다가 출현 시 제거된다.

var ticks_total: int = 42
var ticks_left: int = 42

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var u := 1.0 - float(ticks_left) / float(maxi(1, ticks_total))
	var pulse := 0.5 + 0.5 * sin(u * TAU * 3.0)
	var c := Color(1.0, 0.35, 0.2, 0.35 + 0.4 * pulse)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_arc(Vector2.ZERO, 26.0 + 10.0 * u, 0.0, TAU, 24, c, 3.0)
	draw_circle(Vector2.ZERO, 6.0, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(Vector2(0, -40), Vector2(0, -8), c, 2.0)
