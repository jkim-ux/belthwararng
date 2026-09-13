class_name VillageLayoutMigration
extends RefCounted
## 32×24 저장을 16×12로 한 번 이전한다. 들어가지 않는 건물도 지우지 않는다.
## ID·공사량·수확 진행·일회성 효과는 그대로, 보관된 건물은 기존 설치 UI로 무료 복원한다.

static func compact(cs: CampaignState, vs: VillageState, data: CampaignData) -> void:
	if vs.layout_version != 0:
		return
	vs.previous_layout = vs.to_dict().duplicate(true)
	vs.previous_layout.erase("previous_layout")
	vs.layout_version = VillageTemplate.LAYOUT_VERSION
	vs.cleared.clear()
	vs.clearing.clear()
	vs.stored_buildings.merge(vs.buildings, false)
	vs.buildings.clear()
	var sim := VillageSim.new(data, StringName(vs.site_id))
	var tpl := sim.template
	var ids := vs.stored_buildings.keys()
	ids.sort_custom(func(a, b):
		var pa := _priority(data.building(StringName(vs.stored_buildings[a].def_id)))
		var pb := _priority(data.building(StringName(vs.stored_buildings[b].def_id)))
		return pa < pb if pa != pb else int(a) < int(b))
	for id in ids:
		var b: Dictionary = vs.stored_buildings[id]
		var def := sim.def_of(b)
		var wanted := Vector2(float(b.x) * 0.5, float(b.y) * 0.5)
		var candidates: Array[Vector2i] = []
		if def.placement == &"repair_site":
			candidates.append(tpl.repair_site().position)
		elif def.placement == &"dam_site":
			candidates.append(tpl.dam_site().position)
		else:
			for y in VillageTemplate.HEIGHT:
				for x in VillageTemplate.WIDTH:
					if tpl.is_land(Vector2i(x, y)):
						candidates.append(Vector2i(x, y))
			candidates.sort_custom(func(a, c):
				var da := Vector2(a).distance_squared_to(wanted)
				var dc := Vector2(c).distance_squared_to(wanted)
				return da < dc if da != dc else (a.y < c.y if a.y != c.y else a.x < c.x))
		var placed := false
		for cell in candidates:
			for i in (4 if def.rotatable else 1):
				var rot := posmod(int(b.rot) + i, 4) if def.rotatable else 0
				if sim.can_place(cs, vs, def, cell.x, cell.y, rot).ok:
					vs.restore_building(id, cell.x, cell.y, rot)
					placed = true
					break
			if placed:
				break
	for vid in vs.villagers:
		var vl: Dictionary = vs.villagers[vid]
		if vl.job_kind == "clear" or (int(vl.job_building) != 0 and not vs.buildings.has(int(vl.job_building))):
			vs.unassign(vid)

static func _priority(def: BuildingDef) -> int:
	return int({"repair": 0, "dam": 1, "facility": 2, "house": 3, "lumber": 4, "quarry": 4, "well": 5, "farm": 6, "canal": 7, "road": 8}.get(String(def.kind), 9))
