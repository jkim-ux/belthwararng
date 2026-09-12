class_name ChapterDef
extends Resource
## 챕터 정의. 필수 거점을 모두 해방하면 클리어되고 보상 동료가 해금된다.

@export var id: StringName = &""
@export var index: int = 1
@export var display_name: String = ""
@export var prerequisite_chapter_id: StringName = &""
@export var site_ids: Array[StringName] = []
@export var reward_companion_id: StringName = &""
@export var implemented: bool = false
@export_multiline var summary: String = ""
