class_name GrassTile
extends RefCounted
## HWR-GRASS-001: shared meshes and wind materials for the baked grass tiles.
## One tile = one village cell (VillageStage3D.CELL_W x CELL_D), pivot at the tile centre,
## y = 0 on the lowest turf point, dirt wall down to -WALL_DEPTH. Meshes and textures are
## loaded once and shared by every MultiMesh; nothing here touches game state.

const DIR := "res://assets/environment/grass/"
const VARIANTS := ["a", "b"]
const FOOTPRINT := Vector2(2.0, 0.9)
const WALL_DEPTH := 0.2
const GRASS_HEIGHT := 0.19          ## tallest turf vertex above y = 0 (fins reach ~0.21)
const CULL_MARGIN := 0.35           ## wind displacement + fin overhang, added to every instance AABB

static var _mesh: Dictionary = {}
static var _material: Dictionary = {}


static func variant_count() -> int:
	return VARIANTS.size()


static func variant_key(variant: int) -> String:
	return VARIANTS[posmod(variant, VARIANTS.size())]


static func glb_path(variant: int) -> String:
	return DIR + "grass_tile_%s.glb" % variant_key(variant)


## Imported LOD0 mesh (Godot import adds its own LOD chain). Null if the asset is missing.
static func mesh(variant: int) -> ArrayMesh:
	var key := variant_key(variant)
	if _mesh.has(key):
		return _mesh[key]
	var packed: PackedScene = load(glb_path(variant))
	if packed == null:
		push_error("GrassTile: missing %s" % glb_path(variant))
		return null
	var root := packed.instantiate()
	var mi := _find_mesh_instance(root)
	if mi == null or mi.mesh == null:
		push_error("GrassTile: no mesh in %s" % glb_path(variant))
		root.free()
		return null
	var m: ArrayMesh = mi.mesh
	var std := m.surface_get_material(0) as StandardMaterial3D
	var sm := ShaderMaterial.new()
	sm.shader = load(DIR + "grass_wind.gdshader")
	if std != null:
		sm.set_shader_parameter("albedo_tex", std.albedo_texture)
		sm.set_shader_parameter("normal_tex", std.normal_texture)
	_mesh[key] = m
	_material[key] = sm
	root.free()
	return m


static func material(variant: int) -> ShaderMaterial:
	if mesh(variant) == null:
		return null
	return _material[variant_key(variant)]


static func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r != null:
			return r
	return null


## Wind uniforms are shared by all tiles of all variants (one continuous world wave).
static func set_wind(strength: float, dir: Vector2 = Vector2(1.0, 0.35)) -> void:
	for v in VARIANTS.size():
		var m := material(v)
		if m != null:
			m.set_shader_parameter("wind_strength", strength)
			m.set_shader_parameter("wind_dir", dir)


static func set_wind_param(name: String, value: Variant) -> void:
	for v in VARIANTS.size():
		var m := material(v)
		if m != null:
			m.set_shader_parameter(name, value)


## Triangle counts of LOD0 followed by the importer-generated LOD levels.
static func lod_triangles(variant: int) -> Array[int]:
	var out: Array[int] = []
	var m := mesh(variant)
	if m == null:
		return out
	out.append(m.surface_get_array_index_len(0) / 3)
	var sd: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), 0)
	for lod in sd.get("lods", []):
		out.append(int(lod["index_data"].size() / 4 / 3))
	return out
