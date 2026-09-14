class_name BuildingDef
extends Resource
## 마을 건물 1종의 정의(공유 데이터). 실행 중 인스턴스 상태(위치·공사량·진행)는 VillageState 가 갖는다.
## 실행 중에는 이 Resource 를 수정하지 않는다. 수치는 VILLAGE_BUILDING 5절의 초기값이다.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## 종류: &"farm" 농장, &"well" 우물, &"canal" 수로, &"dam" 작은 보, &"lumber" 벌목소, &"quarry" 채석장,
## &"house" 주택, &"road" 길, &"repair" 경로 복구 현장, &"facility" 특수 시설(훈련장/보급창)
@export var kind: StringName = &"farm"
@export var size: Vector2i = Vector2i(1, 1)       ## 회전 0 기준 점유 칸(가로, 세로)

@export_group("비용·공사")
@export var cost_currency: int = 0
@export var cost_wood: int = 0
@export var cost_stone: int = 0
@export var work_required: float = 30.0           ## 공사량(작업 단위). 0 이면 즉시 완공(길)

@export_group("배치")
## &"land" 개간된 땅(일반·비옥), &"fertile" 3×3 비옥지, &"forest_adjacent" 숲 작업 구역 접함,
## &"rock_adjacent" 암반 작업 구역 접함, &"dam_site" 템플릿 강가 부지, &"repair_site" 템플릿 복구 현장
@export var placement: StringName = &"land"
@export var rotatable: bool = true
@export var movable: bool = true
@export var demolishable: bool = true
@export var walkable: bool = false                ## 농장·수로·길은 통행 가능
@export var needs_door: bool = true               ## 작업 위치(문) 칸 필요 여부
@export var max_per_village: int = 0              ## 0 이면 제한 없음
@export var requires_management: int = 0          ## 특수 시설: 마을 관리도 조건
@export var site_id: StringName = &""             ## 특정 마을에서만 건설 가능(비어 있으면 모두)

@export_group("기능")
@export var water_capacity: int = 0               ## 수원 공급 용량(우물 2, 보 4)
@export var produce_kind: StringName = &""        ## &"food" / &"wood" / &"stone"
@export var produce_amount: int = 0               ## 정상 생산량
@export var produce_amount_unfed: int = 0         ## 식량 없이 시작한 주기 생산량(벌목/채석)
@export var cycle_seconds: float = 0.0            ## 생산 주기(유효 작업초)
@export var eats_food: bool = false               ## 주기 시작 시 식량 1 소비 시도
@export var needs_water: bool = false             ## 농장: 물 공급 필요
@export var villagers_on_complete: int = 0        ## 주택: 완공 시 귀환 주민 수
@export var facility_id: StringName = &""         ## 특수 시설: 기존 FacilityDef id (효과 플래그)
@export var management_on_complete: int = 0       ## 복구 현장: 완공 시 관리도

func footprint(rot: int) -> Vector2i:
	return Vector2i(size.y, size.x) if (rot % 2) == 1 else size

func is_source() -> bool:
	return water_capacity > 0

func is_producer() -> bool:
	return produce_kind != &"" and cycle_seconds > 0.0

func cost_text() -> String:
	var parts: Array[String] = []
	if cost_currency > 0:
		parts.append("군자금 %d" % cost_currency)
	if cost_wood > 0:
		parts.append("목재 %d" % cost_wood)
	if cost_stone > 0:
		parts.append("석재 %d" % cost_stone)
	return "무료" if parts.is_empty() else " · ".join(parts)
