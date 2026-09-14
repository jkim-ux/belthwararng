extends SceneTree
## HWR-GRASS-001 headless checks: asset files, Godot import, budgets, wind material, MultiMesh field,
## and the village hookup (grass under open ground, hidden under buildings).
##   godot --headless --path game -s tests/run_grass_tests.gd

var failed := 0
var passed := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, description: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + description)


func run() -> void:
	# --- files and budgets
	for v in GrassTile.variant_count():
		var path := ProjectSettings.globalize_path(GrassTile.glb_path(v))
		check(FileAccess.file_exists(path), "glb exists: " + path)
		var size := FileAccess.get_file_as_bytes(path).size()
		check(size > 1_000_000 and size <= 25_000_000, "glb %s size %d within 25,000,000" % [GrassTile.variant_key(v), size])
		var head := FileAccess.get_file_as_bytes(path).slice(0, 4).get_string_from_ascii()
		check(head == "glTF", "glb %s header is glTF (not an LFS pointer)" % GrassTile.variant_key(v))
		var m := GrassTile.mesh(v)
		check(m != null, "mesh %s imports" % GrassTile.variant_key(v))
		if m == null:
			continue
		check(m.get_surface_count() == 1, "one surface (one draw per MultiMesh)")
		var tris := m.surface_get_array_index_len(0) / 3
		check(tris >= 10_000 and tris <= 25_000, "LOD0 %d tris within 10k..25k" % tris)
		var lods := GrassTile.lod_triangles(v)
		check(lods.size() >= 3, "importer generated LOD levels: %s" % [lods])
		var has_mid := false
		var has_far := false
		for i in range(1, lods.size()):
			if lods[i] >= 2_000 and lods[i] <= 5_000: has_mid = true
			if lods[i] >= 100 and lods[i] <= 500: has_far = true
		check(has_mid, "a LOD level falls in 2k..5k tris: %s" % [lods])
		check(has_far, "a LOD level falls in 100..500 tris: %s" % [lods])
		var aabb := m.get_aabb()
		check(absf(aabb.size.x - GrassTile.FOOTPRINT.x) < 0.02 and absf(aabb.size.z - GrassTile.FOOTPRINT.y) < 0.02, "footprint %s ~ 2.0 x 0.9" % [aabb.size])
		check(absf(aabb.position.y + GrassTile.WALL_DEPTH) < 0.001, "wall bottom at -%.2f" % GrassTile.WALL_DEPTH)
		check(aabb.end.y > 0.15 and aabb.end.y < 0.3, "grass tips %.3f above the ground plane" % aabb.end.y)
		check(absf(aabb.get_center().x) < 0.01 and absf(aabb.get_center().z) < 0.01, "pivot at the tile centre")
		var arrays := m.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_TEX_UV2] != null, "UV2 wind mask present")
		check(arrays[Mesh.ARRAY_TANGENT] != null, "tangents present")
		check(arrays[Mesh.ARRAY_NORMAL] != null, "normals present")
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var wall_moving := 0
		var tips := 0
		for i in pos.size():
			if pos[i].y <= -GrassTile.WALL_DEPTH + 0.001 and uv2[i].x > 0.001:
				wall_moving += 1
			if uv2[i].x > 0.9:
				tips += 1
		check(wall_moving == 0, "wall bottom vertices have bend mask 0")
		check(tips > 50, "there are tip vertices with bend mask ~1 (%d)" % tips)
		var std := m.surface_get_material(0) as StandardMaterial3D
		check(std != null and std.albedo_texture != null and std.normal_texture != null, "imported material carries albedo + normal textures")
		if std != null and std.albedo_texture != null:
			check(std.albedo_texture.get_size() == Vector2(2048, 1536), "atlas 2048x1536: %s" % [std.albedo_texture.get_size()])
		var mat := GrassTile.material(v)
		check(mat != null and mat.shader != null, "wind ShaderMaterial built")
		if mat != null and mat.shader != null:
			var names := []
			for u in mat.shader.get_shader_uniform_list():
				names.append(u.name)
			check(names.has("wind_strength") and names.has("albedo_tex"), "shader exposes wind_strength/albedo_tex: %s" % [names])
			check(mat.get_shader_parameter("albedo_tex") != null, "shader albedo bound")
	# --- field
	var field := GrassField.new()
	root.add_child(field)
	var cells: Array = []
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			cells.append(Vector2i(x, y))
	field.build(cells, VillageStage3D.CELL_W, VillageStage3D.CELL_D)
	check(field.tile_count() == 192, "192 instances for the full 16x12 village")
	check(field.multimesh_count() >= 12 and field.multimesh_count() <= 24, "regional MultiMeshes (%d), not one per tile" % field.multimesh_count())
	var e: Dictionary = field._entries[Vector2i(3, 5)]
	var xf: Transform3D = e.xform
	check(xf.origin.is_equal_approx(Vector3(3.5 * VillageStage3D.CELL_W, 0.0, 5.5 * VillageStage3D.CELL_D)), "tile origin at the cell centre")
	var rotated := 0
	for c in field._entries.keys():
		if not field._entries[c].xform.basis.is_equal_approx(Basis.IDENTITY):
			rotated += 1
	check(rotated > 40 and rotated < 152, "a mix of 0 and 180 degree tiles (%d rotated)" % rotated)
	# MultiMesh instance transforms cannot be read back from the headless dummy renderer; hidden state is tracked here.
	field.set_hidden_cells([Vector2i(3, 5), Vector2i(4, 5)])
	check(field.is_hidden(Vector2i(3, 5)) and not field.is_hidden(Vector2i(2, 5)), "hidden cells tracked")
	field.set_hidden_cells([])
	check(not field.is_hidden(Vector2i(3, 5)), "unhidden tile tracked")
	GrassTile.set_wind(0.0)
	check(is_equal_approx(float(GrassTile.material(0).get_shader_parameter("wind_strength")), 0.0), "wind 0 applies to the shared material")
	GrassTile.set_wind(1.0)
	field.queue_free()
	# --- village stage hookup
	var stage := VillageStage3D.new()
	root.add_child(stage)
	var template: VillageTemplate = load("res://data/village/ch1_farm_template.tres")
	var data := CampaignData.new()
	stage.setup(template, data)
	check(stage.grass != null and stage.grass.tile_count() > 0, "village stage builds grass")
	var expected := 0
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			if VillageStage3D.GRASS_TERRAIN.has(template.terrain_at(Vector2i(x, y))):
				expected += 1
	check(stage.grass.tile_count() == expected, "grass on %d open/forest/entrance cells (got %d)" % [expected, stage.grass.tile_count()])
	check(not stage.grass._entries.has(Vector2i(15, 0)), "no grass on the river column")
	check(not stage.grass._entries.has(Vector2i(1, 8)), "no grass on the path row")
	stage.queue_free()
	await process_frame
	print("grass tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
