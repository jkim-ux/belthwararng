class_name FireZone
extends Node2D
## 바닥 불(장판). 발 위치 기준 타원(반경 rx·ry) 안의 살아 있는 주인공/동료에게 Battle 이 주기 피해를 준다.
## 수명·피해 시계는 고정 전투 틱으로 흐르며 개체 히트스톱과 분리된다. 논리 범위와 그림 범위가 같다.
## 경기장 경계 밖은 예고와 같은 방식으로 잘라 그린다(논리적으로 발이 밖에 있을 수 없으므로 판정은 타원 그대로).

var center: Vector2 = Vector2.ZERO
var rx: float = 56.0
var ry: float = 28.0
var age: int = 0             ## 생성 틱이 0. 마지막 판정 틱(life_ticks)을 처리한 뒤 제거된다.
var life_ticks: int = 240
var clip: Rect2 = Rect2(0, 0, 1280, 720)
var alive: bool = true

func setup(p_center: Vector2, p_rx: float, p_ry: float, p_life_ticks: int, p_clip: Rect2) -> void:
	center = p_center
	rx = p_rx
	ry = p_ry
	life_ticks = p_life_ticks
	clip = p_clip
	position = center

func contains(p: Vector2) -> bool:
	var dx := (p.x - center.x) / maxf(rx, 0.001)
	var dy := (p.y - center.y) / maxf(ry, 0.001)
	return dx * dx + dy * dy <= 1.0

func expired() -> bool:
	return age > life_ticks

func finish() -> void:
	alive = false
	queue_free()

func _process(_delta: float) -> void:
	queue_redraw()

## 경기장 사각형으로 잘라낸 타원 다각형(로컬 좌표). 예고와 실제 불이 같은 함수를 쓴다.
static func clipped_ellipse(p_center: Vector2, p_rx: float, p_ry: float, rect: Rect2, segments: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var w := p_center + Vector2(cos(a) * p_rx, sin(a) * p_ry)
		w.x = clampf(w.x, rect.position.x, rect.end.x)
		w.y = clampf(w.y, rect.position.y, rect.end.y)
		pts.append(w - p_center)
	return pts

static func draw_telegraph(canvas: CanvasItem, p_center: Vector2, p_rx: float, p_ry: float, rect: Rect2, progress: float) -> void:
	var poly := clipped_ellipse(p_center, p_rx, p_ry, rect)
	canvas.draw_colored_polygon(poly, Color(1.0, 0.45, 0.1, 0.18 + 0.3 * progress))
	var outline := poly.duplicate()
	outline.append(poly[0])
	canvas.draw_polyline(outline, Color(1.0, 0.5, 0.1, 0.9), 2.0)

func _draw() -> void:
	var u := float(age) / float(maxi(1, life_ticks))
	var flicker := 0.85 + 0.15 * sin(float(age) * 0.9)
	var poly := clipped_ellipse(center, rx, ry, clip)
	draw_colored_polygon(poly, Color(1.0, 0.35, 0.05, 0.55 * flicker * (1.0 if u < 0.8 else (1.0 - u) * 5.0)))
	var inner := clipped_ellipse(center, rx * 0.55, ry * 0.55, clip)
	draw_colored_polygon(inner, Color(1.0, 0.8, 0.2, 0.6 * flicker))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(1.0, 0.6, 0.15, 0.9), 2.0)
	# 불꽃(그림만): 타원 안 몇 개의 세로 불길
	for i in 5:
		var a := float(i) * 1.257 + float(age) * 0.05
		var base := Vector2(cos(a) * rx * 0.5, sin(a) * ry * 0.5)
		var h := 14.0 + 8.0 * sin(float(age) * 0.3 + float(i))
		draw_line(base, base + Vector2(0, -h), Color(1.0, 0.75, 0.2, 0.8), 3.0)
