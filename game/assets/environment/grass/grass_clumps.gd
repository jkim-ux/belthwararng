class_name GrassClumps
extends Node3D
## HWR-GRASS-001 R3: sparse static leaf clumps (three small opaque meshes from grass_clumps.glb) placed
## along the edges of open ground: beside paths, under the forest trees, below the fence row, by the
## water and rocks. Cell interiors stay empty so spirits and buildings keep their space.
## Placement is a pure function of (template, seed): the same village always gets the same clumps, and a
## clump hidden under a building comes back in exactly the same place after demolition.
## Regional MultiMeshes share one material. No wind, no time-dependent motion. Pure presentation.

const GLB := "res://assets/environment/grass/ground/grass_clumps.glb"
const KINDS := ["clump_short", "clump_clover", "clump_edge"]
const REGION := Vector2i(4, 4)                 ## cells per MultiMesh region
const CLUSTER_CHANCE := 0.7
const INSET_MIN := 0.12                        ## world distance from the cell edge (into the grass)
const INSET_MAX := 0.32
const EMPTY_TERRAIN := ["p", "e", "~", "#", "Q", "d", "x", "f"]   ## never decorated
const BRIGHTNESS_VARIATION := 0.08

static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D

var cell_w := 2.0
var cell_d := 0.9
var _entries: Array = []                       ## {cell: Vector2i, kind: int, xform: Transform3D, mmi, index}
var _by_cell: Dictionary = {}                  ## Vector2i -> Array[int] (entry indices)
var _hidden: Dictionary = {}                   ## Vector2i -> true
var _mmis: Array[MultiMeshInstance3D] = []


static func load_meshes() -> bool:
	if not _meshes.is_empty():
		return true
	var packed: PackedScene = load(GLB)
	if packed == null:
		push_error("GrassClumps: missing " + GLB)
		return false
	var root := packed.instantiate()
	var tex: Texture2D = null
	for kind in KINDS:
		var mi := _find(root, kind)
		if mi == null or mi.mesh == null:
			push_error("GrassClumps: mesh %s not found in %s" % [kind, GLB])
			root.free()
			_meshes.clear()
			return false
		_meshes[kind] = mi.mesh
		var std := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if std != null and std.albedo_texture != null:
			tex = std.albedo_texture
	root.free()
	_material = StandardMaterial3D.new()
	_material.albedo_texture = tex
	_material.vertex_color_use_as_albedo = true     ## per-instance brightness (MultiMesh colour)
	_material.roughness = 0.9
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return true


static func _find(n: Node, kind: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name).begins_with(kind):
		return n
	for c in n.get_children():
		var r := _find(c, kind)
		if r != null:
			return r
	return null


static func mesh(kind: int) -> Mesh:
	return _meshes.get(KINDS[kind], null) if load_meshes() else null


static func material() -> StandardMaterial3D:
	return _material if load_meshes() else null


static func triangle_count(kind: int) -> int:
	var m := mesh(kind)
	return m.surface_get_array_index_len(0) / 3 if m != null else 0


static func _hash(cell: Vector2i, salt: int, seed_value: int) -> int:
	var h := int(cell.x) * 73856093 ^ int(cell.y) * 19349663 ^ (seed_value + salt * 7919) * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


static func _rand(cell: Vector2i, salt: int, seed_value: int) -> float:
	return float(_hash(cell, salt, seed_value) % 10007) / 10006.0


## Deterministic plan: Array of {cell, kind, xform}. Pure function of (template, cell size, seed).
static func plan(template: VillageTemplate, p_cell_w: float, p_cell_d: float, seed_value: int = 7) -> Array:
	var out: Array = []
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			var t := template.terrain_at(c)
			if EMPTY_TERRAIN.has(t):
				continue
			if t == "W":
				_plan_forest_floor(c, p_cell_w, p_cell_d, seed_value, out)
				continue
			var salt := 0
			var path_sides: Array[Vector2i] = []
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				if _edge_source(template, c, d) == "path":
					path_sides.append(d)
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				salt += 1
				var src := _edge_source(template, c, d)
				if src == "":
					continue
				if _rand(c, salt * 10 + 1, seed_value) > CLUSTER_CHANCE:
					continue
				_plan_cluster(c, d, src, path_sides, salt, p_cell_w, p_cell_d, seed_value, out)
	return out


## What lies across this cell edge, or "" when it is open ground / nothing to decorate.
static func _edge_source(template: VillageTemplate, c: Vector2i, d: Vector2i) -> String:
	var n := c + d
	if not template.in_bounds(n):
		return "fence" if d == Vector2i(0, -1) else ""
	var t := template.terrain_at(n)
	if t == "p" or t == "e":
		return "path"
	if t == "W":
		return "forest"
	if t == "~":
		return "water"
	if t == "Q" or t == "#":
		return "rock"
	return ""


static func _kind_for(src: String, r: float) -> int:
	match src:
		"path": return 2 if r < 0.45 else (0 if r < 0.8 else 1)
		"forest": return 1 if r < 0.6 else 0
		"water": return 0 if r < 0.5 else 1
		"rock": return 0 if r < 0.6 else 1
	return 0 if r < 0.5 else (2 if r < 0.8 else 1)      # fence


static func _plan_cluster(c: Vector2i, d: Vector2i, src: String, path_sides: Array[Vector2i], salt: int, cw: float, cd: float, seed_value: int, out: Array) -> void:
	var count := 2 + int(_rand(c, salt * 10 + 2, seed_value) * 3.0)        # 2..4
	var along_axis := Vector2(1, 0) if d.y != 0 else Vector2(0, 1)          # along the edge
	var span := cw if d.y != 0 else cd
	var base := _rand(c, salt * 10 + 3, seed_value)
	for i in count:
		var s := salt * 100 + i * 7
		var u := clampf(base + (_rand(c, s + 4, seed_value) - 0.5) * 0.55, 0.10, 0.90)
		var inset := INSET_MIN + (INSET_MAX - INSET_MIN) * _rand(c, s + 5, seed_value)
		var local := along_axis * (u * span)
		match d:
			Vector2i(0, -1): local.y = inset
			Vector2i(0, 1): local.y = cd - inset
			Vector2i(-1, 0): local.x = inset
			Vector2i(1, 0): local.x = cw - inset
		local = _keep_off_paths(local, path_sides, cw, cd)
		var kind := _kind_for(src, _rand(c, s + 6, seed_value))
		out.append(_entry(c, kind, Vector2(c.x * cw, c.y * cd) + local, s, seed_value))


## A cluster that runs along one edge must still stay INSET_MIN away from every edge that faces a path.
static func _keep_off_paths(local: Vector2, path_sides: Array[Vector2i], cw: float, cd: float) -> Vector2:
	for d in path_sides:
		match d:
			Vector2i(0, -1): local.y = maxf(local.y, INSET_MIN)
			Vector2i(0, 1): local.y = minf(local.y, cd - INSET_MIN)
			Vector2i(-1, 0): local.x = maxf(local.x, INSET_MIN)
			Vector2i(1, 0): local.x = minf(local.x, cw - INSET_MIN)
	return local


static func _plan_forest_floor(c: Vector2i, cw: float, cd: float, seed_value: int, out: Array) -> void:
	if _rand(c, 900, seed_value) > 0.55:
		return
	var count := 1 + int(_rand(c, 901, seed_value) * 2.0)
	for i in count:
		var s := 910 + i * 3
		var local := Vector2(cw * (0.15 + 0.7 * _rand(c, s, seed_value)), cd * (0.5 + 0.45 * _rand(c, s + 1, seed_value)))
		out.append(_entry(c, 1 if _rand(c, s + 2, seed_value) < 0.7 else 0, Vector2(c.x * cw, c.y * cd) + local, s, seed_value))


static func _entry(c: Vector2i, kind: int, world_xz: Vector2, salt: int, seed_value: int) -> Dictionary:
	var yaw := TAU * _rand(c, salt + 50, seed_value)
	var sc := 0.85 + 0.35 * _rand(c, salt + 51, seed_value)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
	var bright := 1.0 + BRIGHTNESS_VARIATION * (_rand(c, salt + 52, seed_value) - 0.5) * 2.0
	return {"cell": c, "kind": kind, "xform": Transform3D(basis, Vector3(world_xz.x, 0.0, world_xz.y)), "bright": bright}


func build(template: VillageTemplate, p_cell_w: float, p_cell_d: float, seed_value: int = 7) -> void:
	cell_w = p_cell_w
	cell_d = p_cell_d
	clear()
	if not load_meshes():
		return
	var entries := plan(template, cell_w, cell_d, seed_value)
	var groups: Dictionary = {}
	for e in entries:
		var cell: Vector2i = e.cell
		var key := Vector3i(floori(float(cell.x) / REGION.x), floori(float(cell.y) / REGION.y), e.kind)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(e)
	for key in groups.keys():
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh(key.z)
		mm.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Clumps_%d_%d_%s" % [key.x, key.y, KINDS[key.z]]
		mmi.multimesh = mm
		mmi.material_override = material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_mmis.append(mmi)
		for i in list.size():
			var e: Dictionary = list[i]
			mm.set_instance_transform(i, e.xform)
			mm.set_instance_color(i, Color(e.bright, e.bright, e.bright, 1.0))
			var idx := _entries.size()
			_entries.append({"cell": e.cell, "kind": e.kind, "xform": e.xform, "mmi": mmi, "index": i})
			if not _by_cell.has(e.cell):
				_by_cell[e.cell] = []
			_by_cell[e.cell].append(idx)


func clear() -> void:
	for m in _mmis:
		m.queue_free()
	_mmis.clear()
	_entries.clear()
	_by_cell.clear()
	_hidden.clear()


## Hide every clump on these cells (building footprints, door cells, construction) and restore the rest.
func set_hidden_cells(cells: Array) -> void:
	var want: Dictionary = {}
	for c in cells:
		want[c] = true
	for c in _hidden.keys():
		if not want.has(c):
			_apply(c, false)
	for c in want.keys():
		if not _hidden.has(c):
			_apply(c, true)
	_hidden = want


func _apply(cell: Vector2i, hidden: bool) -> void:
	for idx in _by_cell.get(cell, []):
		var e: Dictionary = _entries[idx]
		var mm: MultiMesh = e.mmi.multimesh
		if hidden:
			mm.set_instance_transform(e.index, Transform3D(Basis().scaled(Vector3.ZERO), e.xform.origin))
		else:
			mm.set_instance_transform(e.index, e.xform)


func is_hidden(cell: Vector2i) -> bool:
	return _hidden.has(cell)


func entries_in(cell: Vector2i) -> Array:
	var out: Array = []
	for idx in _by_cell.get(cell, []):
		out.append(_entries[idx])
	return out


func clump_count() -> int:
	return _entries.size()


func multimesh_count() -> int:
	return _mmis.size()


func kind_counts() -> Dictionary:
	var out := {}
	for k in KINDS:
		out[k] = 0
	for e in _entries:
		out[KINDS[e.kind]] += 1
	return out
