class_name EncounterWave
extends Resource
## 방 하나의 적 웨이브. 이전 웨이브가 모두 사망하고 간격(room_wave_gap_ms)이 지난 뒤 위치 예고 후 출현한다.
## enemy_kinds: &"melee"(근접병), &"archer"(궁수), &"thrower"(화염 투척병), &"boss"(거점 보스; 이름·체력은 DungeonDef).
## spawn_positions 는 같은 순서의 바닥 위치. 근접은 앞쪽, 원거리는 서로 다른 깊이의 뒤쪽에 둔다.

@export var enemy_kinds: Array[StringName] = []
@export var spawn_positions: Array[Vector2] = []
## 출현 예고 표시 시간
@export var spawn_delay_ms: float = 700.0
