class_name FirePot
extends Node2D
## 투척병이 던진 항아리. 착탄점은 준비 시작 때 고정되며 비행 곡선은 시각 연출이다(유도 아님).
## 비행 중에도 착탄 예고를 바닥에 계속 표시하고, 손을 떠난 뒤에는 투척병이 죽어도 착탄한다.

var start: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var flight_ticks: int = 30
var t: int = 0
var rx: float = 56.0
var ry: float = 28.0
var clip: Rect2 = Rect2(0, 0, 1280, 720)
var alive: bool = true

func setup(p_start: Vector2, p_target: Vector2, p_flight_ticks: int, p_rx: float, p_ry: float, p_clip: Rect2) -> void:
	start = p_start
	target = p_target
	flight_ticks = maxi(1, p_flight_ticks)
	rx = p_rx
	ry = p_ry
	clip = p_clip
	position = target

## 한 틱 비행. 착탄하면 true.
func step() -> bool:
	t += 1
	queue_redraw()
	return t >= flight_ticks

func finish() -> void:
	alive = false
	queue_free()

func _draw() -> void:
	var u := clampf(float(t) / float(flight_ticks), 0.0, 1.0)
	FireZone.draw_telegraph(self, target, rx, ry, clip, u)
	# 항아리: 바닥 위치는 시작→목표 직선, 높이는 포물선(그림)
	var foot := start.lerp(target, u) - target
	var h := 120.0 * 4.0 * u * (1.0 - u)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2(foot.x, foot.y / 0.45), 6.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(foot + Vector2(0, -h), 7.0, Color(0.55, 0.35, 0.2))
	draw_line(foot + Vector2(0, -h - 6.0), foot + Vector2(0, -h - 14.0), Color(1.0, 0.7, 0.2), 2.0)
