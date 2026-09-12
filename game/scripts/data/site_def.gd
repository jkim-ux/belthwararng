class_name SiteDef
extends Resource
## 거점 정의. village 는 관리도/정비/시설이 있고 fort 는 전투·해방 거점이다.

@export var id: StringName = &""
@export var display_name: String = ""
@export var chapter_id: StringName = &""
@export var kind: StringName = &"village"          ## &"village" / &"fort"
@export var implemented: bool = true
@export_multiline var description: String = ""

@export_group("진입 조건")
@export var prerequisite_site_id: StringName = &""  ## 비어 있으면 새 게임에서 공략 가능
@export var prerequisite_management: int = 60       ## 선행 마을의 최소 관리도

@export_group("전투")
@export var waves: Array[EncounterWave] = []
@export var player_start: Vector2 = Vector2(260, 560)

@export_group("보상")
@export var first_reward: int = 100
@export var repeat_reward: int = 20

@export_group("마을 (village 만)")
@export var management_on_liberate: int = 40
@export var management_on_repair: int = 60
@export var repair_cost: int = 40
@export var facility: FacilityDef
## 전경 문구: 점령 중 / 해방 후 / 정비 후
@export var scene_occupied: String = ""
@export var scene_liberated: String = ""
@export var scene_repaired: String = ""

func is_village() -> bool:
	return kind == &"village"

func enemy_count() -> int:
	var n := 0
	for w in waves:
		n += w.enemy_kinds.size()
	return n
