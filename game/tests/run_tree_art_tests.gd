extends SceneTree
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
	for variant in 3:
		var tree := GardenAssets.make("tree", variant)
		var same := GardenAssets.make("flower_tree", variant)
		check(tree.mesh == same.mesh, "village aliases reuse the same tree mesh")
		check(tree.mesh.get_meta("individual_leaves", 0) >= 1400, "canopy is individual leaves")
		check(tree.material_override.cull_mode == BaseMaterial3D.CULL_DISABLED, "leaves visible on both sides")
		check(tree.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque leaf geometry needs no alpha sorting")
		var arrays := tree.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var valid := v.size() == n.size() and c.size() == v.size()
		for j in v.size():
			if not v[j].is_finite() or not n[j].is_finite() or n[j].length_squared() < 0.9: valid = false
		for j in idx:
			if j < 0 or j >= v.size(): valid = false
		check(valid, "finite indexed geometry with unit normals")
		check(idx.size() / 3 < 400000, "close-up geometry budget")
		check(tree.mesh.get_meta("lod_triangles", 999999) < 150000, "village distance geometry budget")
		var surface := RenderingServer.mesh_get_surface(tree.mesh.get_rid(), 0)
		check(surface.has("lods") and surface.lods.size() == 1, "distance LOD submitted to rendering server")
		print("Distance LOD: %d triangles" % tree.mesh.get_meta("lod_triangles"))
		var bounds := tree.mesh.get_aabb()
		check(bounds.size.x < 3.6 and bounds.size.y < 3.3 and bounds.position.y > -0.18, "live village scale and root origin")
		print("Tree %d: %d leaves, %d triangles, %d vertices, bounds %s" % [variant, tree.mesh.get_meta("individual_leaves"), idx.size() / 3, v.size(), bounds])
		tree.free()
		same.free()
	print("Cold cache for all three tree variants: %d ms" % (Time.get_ticks_msec() - start))
	var scene: PackedScene = load("res://assets/garden_v1/scenes/tree_review.tscn")
	var review := scene.instantiate()
	root.add_child(review)
	await process_frame
	check(review.get_child(0).mesh == GardenAssets._cache["detailed_tree/0"], "review and live village share actual geometry")
	var output := OS.get_environment("TREE_PREVIEW_DIR")
	if output != "":
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_scene(review, state)
		if err == OK: err = doc.write_to_filesystem(state, output.path_join("tree_review.glb"))
		check(err == OK, "export actual review scene")
	review.free()
	print("TREE ART: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
