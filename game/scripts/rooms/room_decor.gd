class_name RoomDecor
extends Node2D
## 현재 방의 문을 그린다: 방향·목적지, 잠김(빨강+자물쇠)/열림(초록), 플레이어가 문 앞에 있을 때 안내.
## 문 위치·구역은 Battle.door_zone/door_point 를 그대로 사용해 그림과 판정이 어긋나지 않게 한다.

var battle: Battle

func _process(_delta: float) -> void:
	queue_redraw()

const DIR_TEXT := {&"east": "동", &"west": "서", &"north": "북", &"south": "남"}
const DIR_ARROW := {&"east": "→", &"west": "←", &"north": "↑", &"south": "↓"}

func _draw() -> void:
	if battle == null or battle.mode != &"campaign" or battle.room == null or battle.dungeon == null:
		return
	var f := UiFont.FONT
	for door in battle.dungeon.doors_of(battle.room):
		var dir: StringName = door.dir
		var zone: Rect2 = battle.door_zone(dir)
		var pt: Vector2 = battle.door_point(dir)
		var locked: bool = battle.doors_locked
		var target: RoomDef = battle.dungeon.room(door.target_id)
		var col := Color(0.85, 0.2, 0.15, 0.8) if locked else Color(0.3, 0.9, 0.45, 0.8)
		# 문 구역(바닥)과 문틀
		draw_rect(zone, Color(col.r, col.g, col.b, 0.12))
		draw_rect(zone, Color(col.r, col.g, col.b, 0.5), false, 1.5)
		var gate := Rect2(pt.x - 14, pt.y - 90, 28, 90)
		if dir == &"north" or dir == &"south":
			gate = Rect2(pt.x - 60, pt.y - 14, 120, 14)
		draw_rect(gate, Color(0.25, 0.18, 0.12))
		draw_rect(gate, col, false, 3.0)
		if locked:
			# 자물쇠: 고리 + 몸통
			var lc := gate.get_center()
			draw_arc(lc + Vector2(0, -6), 7.0, PI, TAU, 10, Color(1, 0.85, 0.3), 3.0)
			draw_rect(Rect2(lc.x - 9, lc.y - 4, 18, 14), Color(1, 0.85, 0.3))
		var label := "%s %s문 → %s" % [DIR_ARROW[dir], DIR_TEXT[dir], target.display_name if target else String(door.target_id)]
		if locked:
			label += "  (잠김)"
		var lp := Vector2(zone.position.x, zone.position.y - 8)
		if dir == &"east":
			lp.x = zone.end.x - 200
		elif dir == &"south":
			lp.y = zone.position.y - 12
		draw_string(f, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.3))
	var prompt := battle.interact_prompt()
	if prompt != "":
		var p := battle.player.floor_pos + Vector2(-90, -battle.player.body_height - 40)
		draw_rect(Rect2(p.x - 6, p.y - 16, 210, 22), Color(0, 0, 0, 0.6))
		draw_string(f, p, prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.7))
