class_name SkillData
extends Resource
## 액티브 스킬 1개의 정의. 8개 슬롯을 같은 형식으로 확장한다.
## implemented=false 인 슬롯은 HUD에 "미구현"으로 표시되고 입력을 무시한다.

@export var id: StringName = &""
@export var display_name: String = ""
@export var key_label: String = ""             ## HUD에 표시할 키 (A, S, ...)
@export var action_name: StringName = &""      ## 입력 맵 액션 이름 (skill_a ...)
@export var cooldown_ms: float = 4000.0
@export var implemented: bool = false
@export var ground_only: bool = true           ## 첫 버전의 8개 스킬은 지상 전용
@export var attack: AttackData

func cooldown_ticks() -> int:
	return Ticks.from_ms(cooldown_ms)
