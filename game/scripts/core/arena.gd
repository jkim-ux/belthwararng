class_name Arena
extends Node2D
## 평평한 전투 공간. 바닥 범위와 벽을 그린다. 실제 경계 처리는 Battle.arena_rect() 로 한다.
var rect: Rect2 = Rect2(60, 400, 1160, 290)

func _draw() -> void:
	# 하늘/먼 산 (일본풍 섬의 저녁)
	draw_rect(Rect2(0, 0, 1280, rect.position.y), Color(0.20, 0.17, 0.24))
	draw_rect(Rect2(0, rect.position.y - 200, 1280, 130), Color(0.26, 0.24, 0.32))
	for i in range(0, 1280, 160):
		draw_colored_polygon(PackedVector2Array([Vector2(i, rect.position.y - 70), Vector2(i + 80, rect.position.y - 190), Vector2(i + 160, rect.position.y - 70)]), Color(0.23, 0.22, 0.30))
	# 뒤쪽 대나무 울타리와 흰 벽
	draw_rect(Rect2(0, rect.position.y - 70, 1280, 70), Color(0.78, 0.74, 0.64))
	draw_rect(Rect2(0, rect.position.y - 70, 1280, 10), Color(0.25, 0.20, 0.18))
	for i in range(0, 1280, 26):
		draw_rect(Rect2(i + 4, rect.position.y - 60, 6, 60), Color(0.45, 0.52, 0.30))
	# 바닥
	draw_rect(Rect2(0, rect.position.y, 1280, 720 - rect.position.y), Color(0.42, 0.38, 0.28))
	draw_rect(rect, Color(0.50, 0.45, 0.32))
	# 깊이 선 (y) 과 좌우 선 (x)
	var y := rect.position.y
	while y <= rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0, 0, 0, 0.08))
		y += 29.0
	var x := rect.position.x
	while x <= rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0, 0, 0, 0.06))
		x += 58.0
	# 좌우 벽 (이동 한계)
	draw_rect(Rect2(0, rect.position.y - 70, rect.position.x, rect.size.y + 70), Color(0.22, 0.18, 0.14))
	draw_rect(Rect2(rect.end.x, rect.position.y - 70, 1280 - rect.end.x, rect.size.y + 70), Color(0.22, 0.18, 0.14))
	draw_rect(rect, Color(0.95, 0.9, 0.7, 0.5), false, 2.0)
