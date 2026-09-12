class_name CampaignData
extends Resource
## 캠페인 정의 묶음. 실행 중 상태(CampaignState)와 분리된다.

@export var chapters: Array[ChapterDef] = []
@export var sites: Array[SiteDef] = []
@export var companions: Array[CompanionDef] = []

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
