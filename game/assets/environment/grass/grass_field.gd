class_name GrassField
extends Node3D
## HWR-GRASS-001: grass ground for a set of village cells, drawn with MultiMesh.
## Instances are grouped per (region, variant) so culling and mesh LOD stay regional instead of
## one village-wide draw. Tiles under placed buildings are hidden by zeroing their transform.
## Pure presentation: no collision, no jobs, no save data.

const REGION := Vector2i(4, 4)                ## cells per MultiMesh region
const TINT_VARIATION := 0.045                 ## +-brightness per tile (breaks the repeat)
const ROTATE_HALF := true                     ## allow 180 deg rotated tiles

var cell_w := 2.0
var cell_d := 0.9
var cast_shadows := true
var _entries: Dictionary = {}                 ## Vector2i -> {mmi: MultiMeshInstance3D, index: int, xform: Transform3D}
var _hidden: Dictionary = {}                  ## Vector2i -> true
var _mmis: Array[MultiMeshInstance3D] = []


## cells: Array of Vector2i logical cells. Cell (qx, qy) covers world x [qx*cell_w, (qx+1)*cell_w), z likewise.
func build(cells: Array, p_cell_w: float, p_cell_d: float, seed_value: int = 7) -> void:
	cell_w = p_cell_w
	cell_d = p_cell_d
	clear()
	if GrassTile.mesh(0) == null:
		return
	var groups: Dictionary = {}
	for c in cells:
		var cell: Vector2i = c
		var h := _hash(cell, seed_value)
		var variant := int(h % GrassTile.variant_count())
		var key := Vector3i(floori(float(cell.x) / REGION.x), floori(float(cell.y) / REGION.y), variant)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(cell)
	for key in groups.keys():
		var list: Array = groups[key]
		var variant: int = key.z
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = GrassTile.mesh(variant)
		mm.instance_count = list.size()
		for i in list.size():
			var cell: Vector2i = list[i]
			var xform := _tile_transform(cell, seed_value)
			mm.set_instance_transform(i, xform)
			var h := _hash(cell, seed_value + 101)
			var t := 1.0 + TINT_VARIATION * (float(h % 1000) / 500.0 - 1.0)
			var g := 1.0 + 0.5 * TINT_VARIATION * (float((h / 1000) % 1000) / 500.0 - 1.0)
			mm.set_instance_custom_data(i, Color(t, t * g, t, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%d_%d_%s" % [key.x, key.y, GrassTile.variant_key(variant)]
		mmi.multimesh = mm
		mmi.material_override = GrassTile.material(variant)
		mmi.extra_cull_margin = GrassTile.CULL_MARGIN
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mmis.append(mmi)
		for i in list.size():
			_entries[list[i]] = {"mmi": mmi, "index": i, "xform": _tile_transform(list[i], seed_value)}


func clear() -> void:
	for m in _mmis:
		m.queue_free()
	_mmis.clear()
	_entries.clear()
	_hidden.clear()


func _tile_transform(cell: Vector2i, seed_value: int) -> Transform3D:
	var origin := Vector3((cell.x + 0.5) * cell_w, 0.0, (cell.y + 0.5) * cell_d)
	var basis := Basis.IDENTITY
	if ROTATE_HALF and (_hash(cell, seed_value + 37) % 2) == 1:
		basis = Basis(Vector3.UP, PI)
	return Transform3D(basis, origin)


static func _hash(cell: Vector2i, seed_value: int) -> int:
	var h := int(cell.x) * 73856093 ^ int(cell.y) * 19349663 ^ seed_value * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


## Hide the tiles under these cells (buildings, construction) and show every other tile again.
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
	if not _entries.has(cell):
		return
	var e: Dictionary = _entries[cell]
	var mm: MultiMesh = e.mmi.multimesh
	if hidden:
		mm.set_instance_transform(e.index, Transform3D(Basis().scaled(Vector3.ZERO), e.xform.origin))
	else:
		mm.set_instance_transform(e.index, e.xform)


func set_cast_shadows(on: bool) -> void:
	cast_shadows = on
	for m in _mmis:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func is_hidden(cell: Vector2i) -> bool:
	return _hidden.has(cell)


func tile_count() -> int:
	return _entries.size()


func multimesh_count() -> int:
	return _mmis.size()
