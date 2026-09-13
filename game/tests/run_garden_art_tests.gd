extends SceneTree
## Geometry and presentation integration only; no user saves touched.
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)

func _initialize() -> void:
	await process_frame
	var start := Time.get_ticks_msec()
	var triangle_count := 0
	for id in GardenAssets.IDS:
		var scene: PackedScene = load("res://assets/garden_v1/scenes/%s.tscn" % id)
		check(scene != null, "reusable scene exists: " + id)
		var node := scene.instantiate()
		root.add_child(node)
		await process_frame
		var m: MeshInstance3D = node.get_child(0)
		check(m.mesh.get_surface_count() == 1 and m.mesh.get_aabb().size.length() > 0.1, "combined model geometry: " + id)
		var duplicate := GardenAssets.make(id)
		check(duplicate.mesh == m.mesh, "shared geometry cache: " + id)
		var arrays := m.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var valid := true
		for i in vertices.size():
			if not vertices[i].is_finite() or not normals[i].is_finite(): valid = false
		check(valid, "finite mesh attributes: " + id)
		triangle_count += vertices.size() / 3
		duplicate.free()
		node.free()
	print("Garden assets: %d types, %d source triangles, cold build %d ms" % [GardenAssets.IDS.size(), triangle_count, Time.get_ticks_msec() - start])
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 580)
	root.add_child(viewport)
	var data: CampaignData = load(CampaignController.DATA_PATH)
	var stage := VillageStage3D.new()
	viewport.add_child(stage)
	stage.setup(data.village_template(&"ch1_farm"), data)
	# New fitted meshes stay inside the logical footprint for every legal rotation.
	for def in data.buildings_for_site(&"ch1_farm"):
		for rot in (4 if def.rotatable else 1):
			var b := {"id": 90, "def_id": String(def.id), "x": 2, "y": 4, "rot": rot, "state": "complete", "work_done": def.work_required, "progress": 24.0, "fed": -1}
			var n := stage.build_building_visual(def, b, {})
			stage.building_root.add_child(n)
			var fp := def.footprint(rot)
			for m in n.get_children():
				if not m is MeshInstance3D or not m.has_meta("garden_asset"): continue
				var bounds: AABB = m.transform * m.mesh.get_aabb()
				check(bounds.position.x >= -fp.x * VillageStage3D.CELL_W * 0.5 - 0.02 and bounds.end.x <= fp.x * VillageStage3D.CELL_W * 0.5 + 0.02 and bounds.position.z >= -fp.y * VillageStage3D.CELL_D * 0.5 - 0.02 and bounds.end.z <= fp.y * VillageStage3D.CELL_D * 0.5 + 0.02, "asset footprint: %s/%d" % [def.id, rot])
				check(bounds.end.y <= stage.kind_height(def) + 0.02, "selection covers model height: " + String(def.id))
			stage._apply_fade(n, true)
			for m in n.get_children():
				if m is MeshInstance3D and m.has_meta("garden_asset"):
					check(m.material_override.vertex_color_use_as_albedo and is_equal_approx(m.material_override.albedo_color.a, 0.3), "fading preserves authored colors")
			stage._apply_fade(n, false)
			stage._remove_dam_wheels(n)
			n.free()
	var preview_def := data.building(&"house")
	stage.sync_preview(preview_def, 3, 3, 0, {"ok": true, "cells": [], "door": Vector2i(4, 5)}, {}, "place", [])
	var model_count := 0
	for n in stage.preview_root.get_children():
		for m in n.get_children():
			if m is MeshInstance3D and m.has_meta("garden_asset"):
				model_count += 1
				check(is_equal_approx(m.material_override.albedo_color.a, 0.5), "placement preview transparency")
	check(model_count == 1, "preview uses the same cottage model")
	stage._clear_children(stage.preview_root)
	# A completed, watered sample layout for asset review; uses live stage and building factories.
	var vs := VillageState.create("ch1_farm")
	vs.add_building(data.building(&"house"), 2, 1, 0, true)
	vs.add_building(data.building(&"well"), 6, 4, 0, true)
	for x in [5, 8]: vs.add_building(data.building(&"canal"), x, 4, 0, true)
	var first := vs.add_building(data.building(&"farm"), 2, 4, 0, true)
	var second := vs.add_building(data.building(&"farm"), 9, 4, 0, true)
	vs.buildings[first].progress = 24.0
	vs.buildings[second].progress = 14.0
	var sim := VillageSim.new(data, &"ch1_farm")
	sim.spawn_all(vs)
	var water := sim.compute_water(vs)
	check(water.farms[first].watered and water.farms[second].watered, "sample farms have real water connectivity")
	stage.sync_buildings(vs, sim, water)
	var i := 0
	for id in vs.sorted_villager_ids():
		sim.actors[id].pos = Vector2(5.6 + i * 2.8, 8.1 + (i % 2) * 0.6)
		i += 1
	stage.sync_actors(vs, sim, 0.1)
	stage.player_node.free()  # Review only: exclude the unchanged protagonist placeholder from GLTF.
	stage.set_camera(15.8, false, true)
	var output := OS.get_environment("GARDEN_PREVIEW_DIR")
	if output != "":
		export_scene(stage, output.path_join("compact_village.glb"))
		var f := FileAccess.open(output.path_join("camera.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"position": [stage.camera.position.x, stage.camera.position.y, stage.camera.position.z], "pitch": VillageStage3D.PITCH_DEG, "size": stage.camera.size, "aspect": stage.viewport_size().aspect()}))
		f.close()
		var lineup := Node3D.new()
		viewport.add_child(lineup)
		stage.box(lineup, Vector3(24, 0.1, 18), Vector3(0, -0.075, 0), Color("88aaa0"))
		var specs := [["flower_tree", Vector3(-3.4, 0, -0.2)], ["fence", Vector3(-0.45, 0, -0.55)], ["lantern", Vector3(1.2, 0, -0.65)], ["cloud_sign", Vector3(3.0, 0, -0.45)], ["rock", Vector3(-3.7, 0, 1.15)], ["planter", Vector3(-1.6, 0, 1.05)], ["basket", Vector3(0, 0, 1.1)], ["well", Vector3(1.8, 0, 1.0)]]
		for spec in specs:
			var m := GardenAssets.make(spec[0])
			m.position = spec[1]
			lineup.add_child(m)
		export_scene(lineup, output.path_join("garden_assets.glb"))
		lineup.free()
	viewport.free()
	print("GARDEN ART: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func export_scene(node: Node3D, path: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(node, state)
	if err == OK: err = doc.write_to_filesystem(state, path)
	check(err == OK, "export actual geometry: " + path.get_file())
