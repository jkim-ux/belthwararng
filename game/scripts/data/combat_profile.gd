class_name CombatProfile
extends Resource
## 수련장 A/B 비교용 전투 프로필. 지상 평타 3타의 정의 리소스를 묶는다.
## 프로필 전환은 참조만 바꾸며 공유 Resource 의 값을 수정하지 않는다.
## 캠페인은 항상 새 모멘텀 프로필(data/profiles/r1_momentum.tres)을 쓴다.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var light_attacks: Array[AttackData] = []
