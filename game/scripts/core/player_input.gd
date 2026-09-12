class_name PlayerInput
extends RefCounted
## 한 틱 동안 수집한 플레이어 입력. Battle 이 Input 싱글톤에서 읽거나 테스트가 직접 만든다.
var move: Vector2 = Vector2.ZERO          ## 방향키 (정규화 전)
var pressed: Array[StringName] = []       ## 이번 틱에 새로 눌린 행동 이름
var interact: bool = false                ## 상호작용(Enter) 새 누름. 문 이동·상자 개봉. 보관하지 않는다.

static func from_input() -> PlayerInput:
	var p := PlayerInput.new()
	p.move = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down", 0.2)
	for a in Player.BUFFERABLE_ACTIONS:
		if Input.is_action_just_pressed(a):
			p.pressed.append(a)
	p.interact = Input.is_action_just_pressed(&"interact")
	return p

static func make(move: Vector2 = Vector2.ZERO, actions: Array = []) -> PlayerInput:
	var p := PlayerInput.new()
	p.move = move
	for a in actions:
		if String(a) == "interact":
			p.interact = true
		else:
			p.pressed.append(StringName(a))
	return p
