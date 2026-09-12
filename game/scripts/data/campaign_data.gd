class_name CampaignData
extends Resource
## 캠페인 정의 묶음. 실행 중 상태(CampaignState)와 분리된다.

@export var chapters: Array[ChapterDef] = []
@export var sites: Array[SiteDef] = []
@export var companions: Array[CompanionDef] = []
@export var buildings: Array[BuildingDef] = []            ## 마을 건물 정의(HWR-005)
@export var village_templates: Array[VillageTemplate] = []  ## 마을 지형 템플릿(HWR-005)

func chapter(id: StringName) -> ChapterDef:
	for c in chapters:
		if c.id == id:
			return c
	return null

func site(id: StringName) -> SiteDef:
	for s in sites:
		if s.id == id:
			return s
	return null

func companion(id: StringName) -> CompanionDef:
	for c in companions:
		if c.id == id:
			return c
	return null

func chapter_of_site(site_id: StringName) -> ChapterDef:
	var s := site(site_id)
	return chapter(s.chapter_id) if s != null else null

func sites_of_chapter(chapter_id: StringName) -> Array[SiteDef]:
	var out: Array[SiteDef] = []
	var c := chapter(chapter_id)
	if c == null:
		return out
	for sid in c.site_ids:
		var s := site(sid)
		if s != null:
			out.append(s)
	return out

func facility_site(facility_id: StringName) -> SiteDef:
	for s in sites:
		if s.facility != null and s.facility.id == facility_id:
			return s
	return null

func building(id: StringName) -> BuildingDef:
	for b in buildings:
		if b.id == id:
			return b
	return null

func village_template(site_id: StringName) -> VillageTemplate:
	for t in village_templates:
		if t.site_id == site_id:
			return t
	return null

## 특정 마을에서 건설 목록에 보일 건물(마을 제한이 있으면 해당 마을만)
func buildings_for_site(site_id: StringName) -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for b in buildings:
		if b.site_id == &"" or b.site_id == site_id:
			out.append(b)
	return out

## 특수 시설 정의(기존 FacilityDef id 로 찾기)
func building_for_facility(facility_id: StringName) -> BuildingDef:
	for b in buildings:
		if b.facility_id == facility_id:
			return b
	return null
