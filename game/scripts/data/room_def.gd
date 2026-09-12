class_name RoomDef
extends Resource
## 던전의 방 하나. kind: &"entry"(입구, 안전) / &"battle"(일반 전투, 웨이브 2) / &"treasure"(선택 보물방, 안전) / &"boss"(보스 1명).
## connections 는 문으로 이어진 방 ID 목록이며 격자 좌표의 인접 방향(동·서·남·북)으로 문 위치가 정해진다.
## 같은 연결 데이터를 방 이동과 미니맵이 함께 사용한다.

@export var id: StringName = &""
@export var display_name: String = ""
@export var grid: Vector2i = Vector2i.ZERO
@export var kind: StringName = &"battle"
@export var connections: Array[StringName] = []
## 일반 전투방은 2웨이브, 보스방은 [&"boss"] 1웨이브, 입구·보물방은 0웨이브
@export var waves: Array[EncounterWave] = []

func is_safe() -> bool:
	return kind == &"entry" or kind == &"treasure"

func is_combat() -> bool:
	return kind == &"battle" or kind == &"boss"

func enemy_count() -> int:
	var n := 0
	for w in waves:
		n += w.enemy_kinds.size()
	return n
