class_name DamageNumber
extends Node2D
## 적중 시 떠오르는 피해 숫자. 연출 전용이며 판정과 무관하다.
var text: String = ""
var color: Color = Color.WHITE
var life: float = 0.7
var age: float = 0.0
var rise: float = 50.0

func _process(delta: float) -> void:
	age += delta
	position.y -= rise * delta
	if age >= life:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var a := clampf(1.0 - age / life, 0.0, 1.0)
	var c := color
	c.a = a
	draw_string(UiFont.FONT, Vector2(-14, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c)
