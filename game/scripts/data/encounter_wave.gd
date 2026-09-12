class_name EncounterWave
extends Resource
## 거점 전투의 적 묶음 하나. 이전 묶음이 모두 사망한 뒤에만 출현한다.
## enemy_kinds: &"melee"(근접 적), &"captain"(초소 대장). spawn_positions 는 같은 순서의 바닥 위치.

@export var enemy_kinds: Array[StringName] = []
@export var spawn_positions: Array[Vector2] = []
## 출현 예고 표시 시간
@export var spawn_delay_ms: float = 700.0
