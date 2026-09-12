class_name HitFlash
extends Node2D
## 실제 적중(hit_confirm)마다 대상 위치에 짧게 나타나는 섬광. 연출 전용이며 판정과 무관하다.
## 대상마다 하나씩 만들며 화면 전체 효과는 합산하지 않는다.

var life: float = 0.14
var age: float = 0.0
var strong: bool = false
var color: Color = Color(1.0, 0.95, 0.7)

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var u := clampf(age / life, 0.0, 1.0)
	var r := (18.0 if strong else 12.0) * (0.6 + u * 0.9)
	var c := color
	c.a = 1.0 - u
	# 네 방향 빛살 + 고리
	for i in 4:
		var an := deg_to_rad(45.0 + 90.0 * i)
		draw_line(Vector2.ZERO, Vector2(cos(an), sin(an)) * r * 1.5, c, 2.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, c, 2.0)
