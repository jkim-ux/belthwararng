extends SceneTree
## HWR-GRASS-001 R3 headless checks: ground kit files + manifest, tileable low-contrast textures, the three
## leaf clumps (budget, pivot, shared material), the ground mask (paths, roads, flat zones, river/rock exclusion,
## edge bleed), deterministic clump placement (edges only, restored after demolition), the village stage hookup
## (footprint + door hiding, completed roads -> dirt, construction not yet dirt), and the absence of any
## time-dependent motion. The old R1/R2 tile checks (10k LOD0, 150/192 tiles, wind mask/uniforms) are gone
## on purpose; the legacy tiles are only checked to still import.
##   godot --headless --path game -s tests/run_grass_tests.gd

const SAVE := "user://test_saves/hwr_grass_tests.json"
const GROUND := "res://assets/environment/grass/ground/"
var failed := 0
var passed := 0
var data: CampaignData


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, description: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + description)


func fresh() -> CampaignController:
	var c := CampaignController.new(SAVE, data)
	c.state = CampaignState.new_game(data)
	c.state.sites["ch1_farm"].liberated = true
	c.state.sites["ch1_farm"].management = 60
	c.state.currency = 1000
	c.state.wood = 1000
	c.state.stone = 1000
	c.enter_village(&"ch1_farm")
	c.sim.wander_enabled = false
	return c


func run() -> void:
	data = load(CampaignController.DATA_PATH)
	var template: VillageTemplate = load("res://data/village/ch1_farm_template.tres")
	check_files()
	check_textures()
	check_clump_meshes()
	check_ground_mask(template)
	check_clump_plan(template)
	check_stage_hookup(template)
	check_no_motion()
	await process_frame
	print("grass tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ------------------------------------------------------------------ files, manifest, budgets
func check_files() -> void:
	var manifest_path := ProjectSettings.globalize_path(GROUND + "ground_manifest.json")
	check(FileAccess.file_exists(manifest_path), "manifest exists")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check(manifest is Dictionary and manifest.has("active"), "manifest parses and lists active assets")
	if not (manifest is Dictionary):
		return
	var names := []
	for entry in manifest.active:
		var path := ProjectSettings.globalize_path(GROUND + String(entry.file))
		names.append(String(entry.file))
		check(FileAccess.file_exists(path), "active asset exists: " + entry.file)
		var bytes := FileAccess.get_file_as_bytes(path).size()
		check(bytes == int(entry.bytes) and bytes <= 25_000_000, "%s size %d matches manifest and stays under 25,000,000" % [entry.file, bytes])
		check(FileAccess.get_sha256(path) == String(entry.sha256), "%s sha256 matches manifest" % entry.file)
	for want in ["ground_grass.png", "ground_dirt.png", "ground_variation.png", "grass_clumps.glb"]:
		check(names.has(want), "manifest lists " + want)
	var glb := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(GROUND + "grass_clumps.glb"))
	check(glb.slice(0, 4).get_string_from_ascii() == "glTF", "grass_clumps.glb header is glTF (not an LFS pointer)")
	var src := ProjectSettings.globalize_path("res://../source_assets/environments/tiles/grass block 3d model.glb")
	check(FileAccess.file_exists(src), "source GLB still present (never overwritten)")
	if FileAccess.file_exists(src):
		check(FileAccess.get_sha256(src) == String(manifest.source.sha256), "source sha256 unchanged: " + String(manifest.source.sha256).substr(0, 12))
	check(not FileAccess.file_exists(ProjectSettings.globalize_path(GROUND + "grass_clumps_clump_leaves.png")), "clump texture stays embedded (no extracted copy)")


# ------------------------------------------------------------------ textures: size, tileable, low contrast
func check_textures() -> void:
	for name in ["ground_grass.png", "ground_dirt.png"]:
		var tex: Texture2D = load(GROUND + name)
		check(tex != null and tex.get_size() == Vector2(1024, 1024), "%s imports at 1024x1024" % name)
		var img := Image.load_from_file(ProjectSettings.globalize_path(GROUND + name))
		if img == null:
			check(false, name + " loads as an image")
			continue
		# seam: the wrap-around column/row difference must be no larger than an ordinary neighbour difference
		var wrap_x := _col_diff(img, 0, img.get_width() - 1)
		var inner_x := (_col_diff(img, 300, 301) + _col_diff(img, 700, 701)) * 0.5
		var wrap_y := _row_diff(img, 0, img.get_height() - 1)
		var inner_y := (_row_diff(img, 300, 301) + _row_diff(img, 700, 701)) * 0.5
		check(wrap_x <= inner_x * 1.6 + 0.004 and wrap_y <= inner_y * 1.6 + 0.004, "%s tiles without a seam (wrap %.4f/%.4f vs inner %.4f/%.4f)" % [name, wrap_x, wrap_y, inner_x, inner_y])
		var stats := _luma_stats(img)
		check(stats.std < 0.07, "%s is low contrast (luma std %.3f)" % [name, stats.std])
		check(stats.mean > 0.35 and stats.mean < 0.75, "%s mid-tone mean %.3f" % [name, stats.mean])
	var vtex: Texture2D = load(GROUND + "ground_variation.png")
	check(vtex != null and vtex.get_size() == Vector2(256, 256), "variation texture imports at 256x256")
	var grass := Image.load_from_file(ProjectSettings.globalize_path(GROUND + "ground_grass.png"))
	var dirt := Image.load_from_file(ProjectSettings.globalize_path(GROUND + "ground_dirt.png"))
	if grass != null and dirt != null:
		var g := _mean_color(grass)
		var d := _mean_color(dirt)
		check(g.g > g.r and g.g > g.b, "grass texture is green-dominant %s" % [g])
		check(d.r > d.g and d.g > d.b, "dirt texture is warm %s" % [d])


func _col_diff(img: Image, a: int, b: int) -> float:
	var acc := 0.0
	for y in range(0, img.get_height(), 4):
		var ca := img.get_pixel(a, y)
		var cb := img.get_pixel(b, y)
		acc += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return acc / (img.get_height() / 4)


func _row_diff(img: Image, a: int, b: int) -> float:
	var acc := 0.0
	for x in range(0, img.get_width(), 4):
		var ca := img.get_pixel(x, a)
		var cb := img.get_pixel(x, b)
		acc += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return acc / (img.get_width() / 4)


func _luma_stats(img: Image) -> Dictionary:
	var vals: Array[float] = []
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			vals.append(0.299 * c.r + 0.587 * c.g + 0.114 * c.b)
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var var_acc := 0.0
	for v in vals:
		var_acc += (v - mean) * (v - mean)
	return {"mean": mean, "std": sqrt(var_acc / vals.size())}


func _mean_color(img: Image) -> Color:
	var acc := Color(0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			acc += img.get_pixel(x, y)
			n += 1
	return acc / n


# ------------------------------------------------------------------ clump meshes
func check_clump_meshes() -> void:
	check(GrassClumps.load_meshes(), "grass_clumps.glb imports with all three meshes")
	var heights := {"clump_short": Vector2(0.06, 0.14), "clump_clover": Vector2(0.04, 0.10), "clump_edge": Vector2(0.15, 0.26)}
	var mat := GrassClumps.material()
	check(mat != null and mat.albedo_texture != null, "shared clump material carries the leaf texture")
	check(mat != null and mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "clump material is double sided (thin leaves)")
	for k in GrassClumps.KINDS.size():
		var name: String = GrassClumps.KINDS[k]
		var m := GrassClumps.mesh(k)
		check(m != null, "mesh " + name)
		if m == null:
			continue
		var tris := GrassClumps.triangle_count(k)
		check(tris >= 100 and tris <= 400, "%s %d tris within 100..400" % [name, tris])
		check(m.get_surface_count() == 1, name + " has one surface")
		var aabb := m.get_aabb()
		var hr: Vector2 = heights[name]
		check(aabb.end.y >= hr.x and aabb.end.y <= hr.y, "%s height %.3f within %s" % [name, aabb.end.y, hr])
		check(aabb.position.y > -0.002, "%s roots at y=0 (%.4f)" % [name, aabb.position.y])
		check(absf(aabb.get_center().x) < 0.06 and absf(aabb.get_center().z) < 0.06, "%s pivot at the base centre" % name)
		check(aabb.size.x < 0.6 and aabb.size.z < 0.6, "%s footprint stays small (%s)" % [name, aabb.size])
		var arrays := m.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_NORMAL] != null and arrays[Mesh.ARRAY_TEX_UV] != null, name + " has normals and UVs")
		check(m.surface_get_material(0) != null, name + " imported material present")
	check(GrassClumps.material() == mat, "one material instance shared by every clump MultiMesh")


# ------------------------------------------------------------------ ground mask
func check_ground_mask(template: VillageTemplate) -> void:
	var ground := VillageGround.new()
	var t0 := Time.get_ticks_msec()
	ground.build(template, VillageStage3D.CELL_W, VillageStage3D.CELL_D)
	var build_ms := Time.get_ticks_msec() - t0
	print("ground mask build: %d ms (%dx%d)" % [build_ms, ground.mask_image.get_width(), ground.mask_image.get_height()])
	check(build_ms < 1500, "mask build under 1.5 s (%d ms)" % build_ms)
	check(ground.material != null and ground.material.shader != null, "ground ShaderMaterial built")
	check(ground.mask_image.get_width() == 16 * VillageGround.PX and ground.mask_image.get_height() == 12 * VillageGround.PX, "mask is PX texels per cell")
	var cw := VillageStage3D.CELL_W
	var cd := VillageStage3D.CELL_D
	var centre := func(c: Vector2i) -> Vector2: return Vector2((c.x + 0.5) * cw, (c.y + 0.5) * cd)
	var s: Dictionary = ground.sample(centre.call(Vector2i(3, 8)))
	check(s.dirt > 0.99 and s.flat < 0.01, "path row centre is dirt %s" % [s])
	s = ground.sample(centre.call(Vector2i(7, 11)))
	check(s.dirt > 0.99, "entrance cell is dirt %s" % [s])
	s = ground.sample(centre.call(Vector2i(3, 4)))
	check(s.dirt < 0.01 and s.flat < 0.01 and s.forest < 0.01, "open ground centre is plain grass %s" % [s])
	s = ground.sample(centre.call(Vector2i(15, 3)))
	check(s.flat > 0.99 and s.dirt < 0.01, "river keeps its flat colour %s" % [s])
	s = ground.sample(centre.call(Vector2i(15, 8)))
	check(s.flat > 0.99 and s.dirt < 0.01, "river next to the path row gets no dirt bleed %s" % [s])
	s = ground.sample(Vector2(15.0 * cw + 0.01, 8.5 * cd))
	check(s.flat > 0.99, "river texel at the path boundary stays flat %s" % [s])
	s = ground.sample(centre.call(Vector2i(10, 0)))
	check(s.flat > 0.99, "rock zone keeps its flat colour %s" % [s])
	s = ground.sample(centre.call(Vector2i(12, 2)))
	check(s.flat > 0.99, "dam site keeps its flat colour %s" % [s])
	s = ground.sample(centre.call(Vector2i(7, 1)))
	check(s.flat > 0.99, "repair site keeps its flat colour %s" % [s])
	s = ground.sample(centre.call(Vector2i(0, 3)))
	check(s.forest > 0.99 and s.dirt < 0.01, "forest floor flagged for shade %s" % [s])
	# bleed: grass cell (3,7) just above the path row -> dirt near its south edge, none at its centre
	s = ground.sample(Vector2(3.5 * cw, 8.0 * cd - 0.03))
	check(s.dirt > 0.3, "dirt bleeds ~0.1 into the grass edge %s" % [s])
	s = ground.sample(Vector2(3.5 * cw, 8.0 * cd - 0.30))
	check(s.dirt < 0.02, "bleed stops well inside the grass cell %s" % [s])
	s = ground.sample(Vector2(3.5 * cw, 8.0 * cd + 0.25))
	check(s.dirt > 0.98, "path centre band stays full dirt %s" % [s])
	# roads: only when the set changes, dirt at the cell, restored on removal
	check(ground.set_road_cells([Vector2i(5, 7)]), "road set changes the mask")
	s = ground.sample(centre.call(Vector2i(5, 7)))
	check(s.dirt > 0.99, "completed road cell is dirt %s" % [s])
	check(not ground.set_road_cells([Vector2i(5, 7)]), "same road set does not rebuild")
	check(ground.set_road_cells([]), "removing the road changes the mask")
	s = ground.sample(centre.call(Vector2i(5, 7)))
	check(s.dirt < 0.01, "road cell is grass again %s" % [s])
	check(ground.set_road_cells([Vector2i(-1, 3), Vector2i(99, 99)]) == false, "out-of-bounds road cells are ignored")


# ------------------------------------------------------------------ clump placement
func check_clump_plan(template: VillageTemplate) -> void:
	var cw := VillageStage3D.CELL_W
	var cd := VillageStage3D.CELL_D
	var a := GrassClumps.plan(template, cw, cd)
	var b := GrassClumps.plan(template, cw, cd)
	check(a.size() >= 60 and a.size() <= 400, "%d clumps for the whole village (sparse)" % a.size())
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		if not a[i].xform.is_equal_approx(b[i].xform) or a[i].cell != b[i].cell or a[i].kind != b[i].kind:
			same = false
	check(same, "placement is deterministic for the same template and seed")
	var kinds := {0: 0, 1: 0, 2: 0}
	var interior := 0
	var on_forbidden := 0
	var outside_cell := 0
	var too_close := 0
	for e in a:
		kinds[e.kind] += 1
		var c: Vector2i = e.cell
		var t := template.terrain_at(c)
		if GrassClumps.EMPTY_TERRAIN.has(t):
			on_forbidden += 1
		var o: Vector3 = e.xform.origin
		if o.x < c.x * cw or o.x > (c.x + 1) * cw or o.z < c.y * cd or o.z > (c.y + 1) * cd:
			outside_cell += 1
		if t == ".":
			var edge := c.y == 0
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n: Vector2i = c + d
				if template.in_bounds(n) and template.terrain_at(n) != ".":
					edge = true
			if not edge:
				interior += 1
			# never on the dirt itself: at least INSET_MIN from a path neighbour's edge
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n: Vector2i = c + d
				if template.in_bounds(n) and (template.terrain_at(n) == "p" or template.terrain_at(n) == "e"):
					var dist := INF
					match d:
						Vector2i(0, -1): dist = o.z - c.y * cd
						Vector2i(0, 1): dist = (c.y + 1) * cd - o.z
						Vector2i(-1, 0): dist = o.x - c.x * cw
						Vector2i(1, 0): dist = (c.x + 1) * cw - o.x
					if dist < GrassClumps.INSET_MIN - 0.001:
						too_close += 1
	check(kinds[0] > 0 and kinds[1] > 0 and kinds[2] > 0, "all three clump kinds are used %s" % [kinds])
	check(on_forbidden == 0, "no clump on path/entrance/water/rock/site/fertile cells")
	check(interior == 0, "no clump in the interior of open ground (movement/build space stays clear)")
	check(outside_cell == 0, "every clump lies inside its own cell")
	check(too_close == 0, "clumps keep %.2f from the path edge" % GrassClumps.INSET_MIN)
	# one path-side row must carry clumps while some of its cells stay empty (clusters + gaps)
	var row7 := 0
	var empty7 := 0
	for x in range(1, 15):
		var n := 0
		for e in a:
			if e.cell == Vector2i(x, 7):
				n += 1
		if n > 0: row7 += 1
		else: empty7 += 1
	check(row7 >= 5 and empty7 >= 2, "path-side row mixes clusters (%d cells) and gaps (%d cells)" % [row7, empty7])
	# runtime field: hide/restore
	var field := GrassClumps.new()
	root.add_child(field)
	field.build(template, cw, cd)
	check(field.clump_count() == a.size(), "field instances equal the plan")
	check(field.multimesh_count() > 0 and field.multimesh_count() <= 48, "regional MultiMeshes (%d), one per region and kind" % field.multimesh_count())
	var cell_with := Vector2i(-1, -1)
	for e in a:
		if template.terrain_at(e.cell) == ".":
			cell_with = e.cell
			break
	var before := field.entries_in(cell_with).duplicate(true)
	field.set_hidden_cells([cell_with])
	check(field.is_hidden(cell_with) and not field.is_hidden(cell_with + Vector2i(9, 0)), "hidden cell tracked")
	field.set_hidden_cells([])
	var after := field.entries_in(cell_with)
	var restored := before.size() == after.size() and before.size() > 0
	for i in mini(before.size(), after.size()):
		if not before[i].xform.is_equal_approx(after[i].xform):
			restored = false
	check(restored, "clumps restore to the same transforms after unhide")
	field.queue_free()


# ------------------------------------------------------------------ stage hookup with real placement rules
func check_stage_hookup(template: VillageTemplate) -> void:
	var c := fresh()
	var stage := VillageStage3D.new()
	root.add_child(stage)
	stage.setup(template, data)
	check(stage.ground != null and stage.clumps != null, "village stage builds ground + clumps")
	check(stage.get("grass") == null, "old tile field is no longer a stage member")
	var ground_mi: MeshInstance3D = stage.terrain_root.get_node_or_null("Ground")
	check(ground_mi != null and ground_mi.material_override == stage.ground.material, "terrain mesh uses the shared ground material")
	check(stage.terrain_root.get_node_or_null("GroundSkirt") != null, "near-edge dirt skirt present")
	var plain: MeshInstance3D = null
	for n in stage.backdrop_root.get_children():
		if n is MeshInstance3D and n.material_override == stage.ground.material:
			plain = n
	check(plain != null, "backdrop meadow plane shares the ground material (no cut-out grid edge)")
	var sim := c.sim
	var water: Dictionary = sim.compute_water(c.active_village_state())
	# rotated house (needs a door): footprint + door cell hidden while under construction and when complete
	var house := c.village_place(&"house", 3, 3, 1)
	check(house.ok, "house placed with the real rules (rot 1)")
	stage.sync_buildings(c.active_village_state(), sim, water)
	var hb: Dictionary = c.active_village_state().buildings[house.id]
	var fp := sim.cells_of(hb)
	var door := sim.work_cell(hb)
	var all_hidden := true
	for cell in fp:
		if not stage.clumps.is_hidden(cell):
			all_hidden = false
	check(all_hidden, "clumps hidden under the rotated footprint %s" % [fp])
	check(stage.clumps.is_hidden(door), "clumps hidden on the door cell %s (rot 1 = west)" % [door])
	check(door == Vector2i(2, 4) and not fp.has(door), "door cell lies outside the footprint")
	check(not stage.clumps.is_hidden(Vector2i(10, 5)), "unrelated cell not hidden")
	# road: under construction -> not dirt; complete -> dirt; demolished -> grass and clumps back
	var road := c.village_place(&"road", 5, 7, 0)
	check(road.ok, "road placed")
	var rb: Dictionary = c.active_village_state().buildings[road.id]
	if String(rb.state) != "complete":
		stage.sync_buildings(c.active_village_state(), sim, water)
		check(not stage.ground.road_cells().has(Vector2i(5, 7)), "road under construction is not dirt yet")
		var vid: int = c.active_village_state().sorted_villager_ids()[0]
		c.village_assign(vid, road.id)
		for i in 600:
			c.village_tick(0.1)
			if c.active_village_state().building(road.id).state == "complete":
				break
		c.village_assign(vid, 0)
	check(String(c.active_village_state().building(road.id).state) == "complete", "road completes")
	stage.sync_buildings(c.active_village_state(), sim, water)
	check(stage.ground.road_cells().has(Vector2i(5, 7)), "completed road cell is dirt in the mask")
	check(stage.ground.sample(Vector2(5.5 * VillageStage3D.CELL_W, 7.5 * VillageStage3D.CELL_D)).dirt > 0.99, "mask texel under the road is dirt")
	var before := stage.clumps.entries_in(Vector2i(5, 7)).duplicate(true)
	check(stage.clumps.is_hidden(Vector2i(5, 7)), "clumps hidden under the road")
	check(c.village_demolish(road.id).ok, "road demolished")
	stage.sync_buildings(c.active_village_state(), sim, water)
	check(not stage.ground.road_cells().has(Vector2i(5, 7)), "demolished road is grass again")
	check(not stage.clumps.is_hidden(Vector2i(5, 7)), "clumps visible again after demolition")
	var after := stage.clumps.entries_in(Vector2i(5, 7))
	var same := before.size() == after.size()
	for i in mini(before.size(), after.size()):
		if not before[i].xform.is_equal_approx(after[i].xform):
			same = false
	check(same, "clumps restored deterministically after demolition (%d)" % before.size())
	var hd := c.village_cancel(house.id)   # still under construction: cancel is the real rule
	check(hd.ok, "house construction cancelled: %s" % [hd.reason])
	stage.sync_buildings(c.active_village_state(), sim, water)
	check(not stage.clumps.is_hidden(door) and not stage.clumps.is_hidden(fp[0]), "door and footprint cells restored")
	# logic untouched: placement on a decorated edge cell is still allowed, path cells still blocked
	var farm := c.village_can_place(data.building(&"farm"), 2, 5, 0)
	check(farm.ok, "farm still placeable on decorated edge cells (clumps never reduce buildable area)")
	check(not c.village_can_place(data.building(&"farm"), 3, 8, 0).ok, "path row still rejects buildings")
	stage.queue_free()
	SaveStore.new(SAVE).delete_all()


# ------------------------------------------------------------------ no wind / no time dependence, legacy still imports
func check_no_motion() -> void:
	var shader := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://assets/environment/grass/village_ground.gdshader"))
	check(not shader.contains("TIME") and not shader.contains("wind"), "ground shader has no TIME / wind")
	check(not shader.contains("VERTEX +=") and not shader.contains("VERTEX="), "ground shader never displaces vertices")
	var stage_src := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://scripts/village/village_stage_3d.gd"))
	check(not stage_src.contains("GrassField") and not stage_src.contains("grass_wind") and not stage_src.contains("GrassTile"), "village stage references no legacy tile/wind resource")
	check(GrassClumps.material() is StandardMaterial3D, "clump material is a plain StandardMaterial3D (no shader, no motion)")
	var legacy: PackedScene = load("res://assets/environment/grass/grass_tile_a.glb")
	check(legacy != null, "legacy grass_tile_a.glb still imports (kept for reference only)")
