class_name FacilityDef
extends Resource
## 마을 시설 1개의 정의. 구매는 마을당 1회이며 효과는 저장된 구매 플래그에서 계산한다.

@export var id: StringName = &""
@export var display_name: String = ""
@export var cost: int = 60
## &"attack_mult": 주인공 기본 공격력 × value, &"max_hp_add": 주인공 최대 체력 + value
@export var effect_kind: StringName = &"attack_mult"
@export var value: float = 1.05
@export_multiline var description: String = ""
## 주민의 역할 설명(관리 화면 표시)
@export_multiline var villagers_text: String = ""
