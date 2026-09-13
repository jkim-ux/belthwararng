@tool
class_name GardenAssets
extends RefCounted
## C / CLOUD GREENHOUSE: reusable, authored 3D meshes in cream wood, sage and lavender.
## Each prop is one cached mesh/material, not dozens of runtime primitive draw calls.
## Pure presentation: no physics, jobs, placement conditions or save state.

const WOOD := Color("ac8761")
const WOOD_LIGHT := Color("ceb18a")
const WOOD_DARK := Color("81674d")
const CREAM := Color("ebddbd")
const IVORY := Color("f8edd7")
const LEAF := Color("819369")
const LEAF_DARK := Color("617451")
const LEAF_LIGHT := Color("a0ad82")
const LAVENDER := Color("aaa0bc")
const STONE := Color("b8b299")
const SOIL := Color("95734b")
const WATER := Color("85b9c2")
const FRUIT := Color("db9070")
const IDS := ["tree", "flower_tree", "rock", "fence", "planter", "lantern", "cloud_sign", "basket", "well", "cottage", "greenhouse", "shed", "farm_0", "farm_1", "farm_2", "farm_3", "lumber", "quarry", "road", "repair", "training", "dam", "wheel"]

static var _cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _primitives: Dictionary = {}
var _surface: SurfaceTool
var _variant: int = 0
var _crown_lobes: Array[Vector3] = []

static func material(alpha: float = 1.0, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%.2f" % [tint.to_html(), alpha]
	if _material_cache.has(key): return _material_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.roughness = 0.92
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_cache[key] = m
	return m

static func make(id: String, variant: int = 0, alpha: float = 1.0, tint: Color = Color.WHITE) -> MeshInstance3D:
	var key := "%s/%d" % [id, posmod(variant, 3)]
	if not _cache.has(key):
		var author := GardenAssets.new()
		author._variant = posmod(variant, 3)
		author._surface = SurfaceTool.new()
		author._surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		author._build(id)
		_cache[key] = author._surface.commit()
	var node := MeshInstance3D.new()
	node.name = "Garden_" + id
	node.mesh = _cache[key]
	node.material_override = material(alpha, tint)
	node.set_meta("garden_asset", id)
	node.set_meta("base_material", node.material_override)
	return node

func _build(id: String) -> void:
	match id:
		"tree": _tree(false)
		"flower_tree": _tree(true)
		"rock": _rocks()
		"fence": _fence()
		"planter": _planter()
		"lantern": _lantern()
		"cloud_sign": _sign()
		"basket": _basket(Vector3.ZERO, true)
		"well": _well()
		"cottage", "greenhouse", "shed": _cottage(id)
		"lumber": _workshop(false)
		"quarry": _workshop(true)
		"road", "repair": _path(id == "repair")
		"training": _training()
		"dam": _dam()
		"wheel": _wheel()
		_:
			if id.begins_with("farm_"): _farm(id.trim_prefix("farm_").to_int())
			else: push_error("Unknown garden asset: " + id)

# ------------------------------------------------------------------ Shared geometry authoring

func _mesh(mesh: Mesh, pos: Vector3, scale: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(rotation).scaled_local(scale)
	var normal_basis := basis.inverse().transposed()
	_surface.set_color(color.srgb_to_linear())
	for i in indices:
		_surface.set_normal((normal_basis * normals[i]).normalized())
		_surface.add_vertex(pos + basis * vertices[i])

func _blob(pos: Vector3, scale: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	if not _primitives.has("sphere"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 16
		s.rings = 9
		_primitives.sphere = s
	_mesh(_primitives.sphere, pos, scale, color, rot)

func _beam(a: Vector3, b: Vector3, radius: float, color: Color, end_radius: float = -1.0) -> void:
	var length := a.distance_to(b)
	if length < 0.001: return
	var top := radius if end_radius < 0.0 else end_radius
	var key := "cyl|%.3f|%.3f" % [radius, top]
	if not _primitives.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = radius
		c.height = 1.0
		c.radial_segments = 12
		_primitives[key] = c
	var rot := Basis(Quaternion(Vector3.UP, (b - a).normalized())).get_euler()
	_mesh(_primitives[key], (a + b) * 0.5, Vector3(1.0, length, 1.0), color, rot)

func _ring(pos: Vector3, radius: float, tube: float, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var key := "ring|%.3f|%.3f" % [radius, tube]
	if not _primitives.has(key):
		var t := TorusMesh.new()
		t.inner_radius = radius - tube
		t.outer_radius = radius + tube
		t.rings = 24
		t.ring_segments = 6
		_primitives[key] = t
	_mesh(_primitives[key], pos, Vector3.ONE, color, rot)

func _triangle(p: Array, normals: Array, color: Color) -> void:
	var order := [0, 1, 2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(normals[0] + normals[1] + normals[2]) > 0.0:
		order = [0, 2, 1]  # Godot clockwise front face
	_surface.set_color(color.srgb_to_linear())
	for i in order:
		_surface.set_normal(normals[i])
		_surface.add_vertex(p[i])

## Rounded edges with smooth normals; plank dimensions are not changed by beveling.
func _box(pos: Vector3, size: Vector3, color: Color, bevel: float = 0.045, rot: Vector3 = Vector3.ZERO) -> void:
	var h := size * 0.5
	var r := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.8)
	var core := h - Vector3.ONE * r
	var basis := Basis.from_euler(rot)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var us := [-h[u], -core[u], core[u], h[u]]
		var vs := [-h[v], -core[v], core[v], h[v]]
		for side in [-1.0, 1.0]:
			for j in 3:
				for k in 3:
					var points := []
					var normals := []
					for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var q := Vector3.ZERO
						q[axis] = h[axis] * side
						q[u] = us[j + off.x]
						q[v] = vs[k + off.y]
						var inner := q.clamp(-core, core)
						var n := (q - inner).normalized()
						points.append(pos + basis * (inner + n * r))
						normals.append(basis * n)
					_triangle([points[0], points[1], points[2]], [normals[0], normals[1], normals[2]], color)
					_triangle([points[0], points[2], points[3]], [normals[0], normals[2], normals[3]], color)

func _leaf(pos: Vector3, length: float, width: float, angle: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, angle)
	for i in 6:
		var t0 := float(i) / 6.0
		var t1 := float(i + 1) / 6.0
		for side in [-1.0, 1.0]:
			var p0 := Vector3(0, 0.1 * sin(t0 * PI), t0 * length)
			var p1 := Vector3(side * width * sin(t0 * PI), 0.0, t0 * length)
			var p2 := Vector3(side * width * sin(t1 * PI), 0.0, t1 * length)
			var p3 := Vector3(0, 0.1 * sin(t1 * PI), t1 * length)
			var q := [pos + basis * p0, pos + basis * p1, pos + basis * p2, pos + basis * p3]
			var n := Vector3.UP
			_triangle([q[0], q[1], q[2]], [n, n, n], color)
			_triangle([q[0], q[2], q[3]], [n, n, n], color)
			_triangle([q[2], q[1], q[0]], [-n, -n, -n], color.darkened(0.04))
			_triangle([q[3], q[2], q[0]], [-n, -n, -n], color.darkened(0.04))
	_beam(pos + Vector3(0, 0.014, 0), pos + basis * Vector3(0, 0.065, length * 0.85), 0.009, LEAF_LIGHT)

func _flower(pos: Vector3, size: float = 0.13, lavender: bool = false) -> void:
	_beam(pos - Vector3(0, 0.22, 0), pos, 0.014, LEAF_DARK)
	for i in 5:
		var a := TAU * i / 5.0
		_blob(pos + Vector3(cos(a) * size * 0.62, sin(a) * size * 0.5, 0), Vector3(size * 0.48, size * 0.46, size * 0.24), LAVENDER if lavender else IVORY)
	_blob(pos + Vector3(0, 0, size * 0.15), Vector3.ONE * size * 0.25, Color("dbc274"))

# ------------------------------------------------------------------ Tree, rock and garden border

func _tree(blossom: bool) -> void:
	var shift := (_variant - 1) * 0.07
	_beam(Vector3(0, 0, 0), Vector3(-0.09, 0.8, 0), 0.22, WOOD_DARK, 0.15)
	_beam(Vector3(-0.09, 0.7, 0), Vector3(0.12 + shift, 1.65, 0), 0.15, WOOD, 0.085)
	for side in [-1.0, 1.0]:
		_beam(Vector3(0, 0.75, 0), Vector3(side * 0.68, 1.5, 0.02), 0.1, WOOD, 0.035)
		_beam(Vector3(0, 0.12, 0), Vector3(side * 0.35, 0.015, 0.2), 0.09, WOOD_DARK, 0.022)
	for i in 4:
		_beam(Vector3(-0.12 + i * 0.065, 0.2, 0.165), Vector3(-0.16 + i * 0.065, 0.66, 0.12), 0.012, WOOD_LIGHT)
	# One smooth union surface avoids visible sphere intersections in the canopy.
	_crown_lobes.clear()
	for i in 9:
		var a := i * 2.39996 + _variant * 0.37
		var ring := 0.25 if i > 5 else 0.74
		_crown_lobes.append(Vector3(cos(a) * ring, -0.22 + (i % 3) * 0.23, sin(a) * ring * 0.6))
	_crown(Vector3(0, 1.94, 0))
	for i in 8:
		var a := float(i) * 2.4
		_leaf(Vector3(cos(a) * 0.9, 1.58 + (i % 3) * 0.24, 0.4 + sin(a) * 0.3), 0.28, 0.12, a, LEAF_LIGHT)
	if blossom:
		for p in [Vector3(-0.65, 1.77, 0.8), Vector3(0.48, 2.22, 0.66), Vector3(0.77, 1.75, 0.71)]:
			_flower(p, 0.13)

func _crown_point(direction: Vector3) -> Vector3:
	var radius := 0.38
	for center in _crown_lobes:
		var along := direction.dot(center)
		var disc := 0.62 * 0.62 - center.length_squared() + along * along
		if disc <= 0.0: continue
		var r := along + sqrt(disc)
		var h := maxf(0.13 - absf(radius - r), 0.0) / 0.13
		radius = maxf(radius, r) + h * h * 0.0325
	# Low-amplitude leaf irregularity, rather than separate bead-shaped bumps.
	radius += 0.017 * sin(direction.x * 22.0 + _variant) * sin(direction.y * 19.0) * cos(direction.z * 21.0)
	return direction * radius

func _crown(origin: Vector3) -> void:
	if not _primitives.has("canopy"):
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 40
		sphere.rings = 26
		_primitives.canopy = sphere
	var arrays: Array = _primitives.canopy.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for v in vertices:
		var direction := v.normalized()
		var tangent := Vector3.UP.cross(direction).normalized()
		if tangent.length_squared() < 0.1: tangent = Vector3.RIGHT
		var bitangent := direction.cross(tangent)
		var p := _crown_point(direction)
		var pu := _crown_point((direction + tangent * 0.002).normalized())
		var pv := _crown_point((direction + bitangent * 0.002).normalized())
		points.append(origin + p)
		normals.append((pu - p).cross(pv - p).normalized())
		var variation := 0.12 + 0.11 * direction.y + 0.07 * sin(p.x * 23.0) * sin(p.z * 25.0 + p.y * 14.0)
		colors.append(LEAF.lerp(LEAF_LIGHT, clampf(variation, 0.0, 0.4)).srgb_to_linear())
	for i in indices:
		_surface.set_color(colors[i])
		_surface.set_normal(normals[i])
		_surface.add_vertex(points[i])

func _rocks() -> void:
	for i in 4:
		var p := Vector3(-0.45 + i * 0.28, 0.18 + (i % 2) * 0.08, sin(i * 2.3) * 0.22)
		_box(p, Vector3(0.62, 0.44 + (i % 2) * 0.13, 0.53), STONE.lerp(CREAM, i * 0.08), 0.17, Vector3(0.15, i * 0.71, 0.13))
		_blob(p + Vector3(-0.04, 0.2, -0.03), Vector3(0.23, 0.055, 0.19), LEAF_DARK.lerp(LEAF, 0.3))
	_leaf(Vector3(-0.66, 0.08, 0.12), 0.34, 0.12, 1.0, LEAF)

func _fence() -> void:
	for x in [-1.0, 1.0]:
		_box(Vector3(x, 0.42, 0), Vector3(0.17, 0.84, 0.17), WOOD, 0.05)
		_box(Vector3(x, 0.84, 0), Vector3(0.2, 0.08, 0.2), WOOD_LIGHT, 0.035)
	for y in [0.25, 0.6]:
		_box(Vector3(0, y, -0.025), Vector3(2.05, 0.16, 0.12), WOOD_LIGHT, 0.025, Vector3(0, 0, 0.015 if y > 0.5 else -0.01))
		_beam(Vector3(-0.75, y + 0.03, 0.047), Vector3(0.73, y + 0.015, 0.047), 0.008, WOOD)
	for x in [-1.0, 1.0]:
		for y in [0.25, 0.6]: _blob(Vector3(x, y, 0.1), Vector3.ONE * 0.025, WOOD_DARK)

func _planter() -> void:
	_box(Vector3(0, 0.13, 0), Vector3(1.14, 0.26, 0.62), WOOD_LIGHT, 0.04)
	_box(Vector3(0, 0.27, 0), Vector3(1.04, 0.03, 0.5), SOIL, 0.025)
	for x in [-0.48, 0.48]: _box(Vector3(x, 0.19, 0.33), Vector3(0.095, 0.34, 0.055), WOOD, 0.015)
	for i in 7:
		var x := -0.44 + float(i % 4) * 0.28
		var z := -0.11 + float(i / 4) * 0.24
		for j in 3: _leaf(Vector3(x, 0.29, z), 0.32, 0.13, i * 2.0 + j * 2.1, LEAF if j % 2 else LEAF_LIGHT)
		_flower(Vector3(x, 0.55 + (i % 3) * 0.07, z + 0.1), 0.095, i % 4 == 0)

func _lantern() -> void:
	_box(Vector3(0, 1.05, 0), Vector3(0.18, 2.1, 0.18), WOOD, 0.035)
	_box(Vector3(0.36, 2.02, 0), Vector3(0.95, 0.14, 0.14), WOOD_LIGHT, 0.035)
	_beam(Vector3(0.05, 1.58, 0), Vector3(0.55, 2.0, 0), 0.065, WOOD)
	_ring(Vector3(0.64, 1.89, 0), 0.073, 0.015, WOOD_DARK, Vector3(PI / 2.0, 0, 0))
	var p := Vector3(0.64, 1.57, 0)
	_box(p, Vector3(0.25, 0.38, 0.24), Color("efd39a"), 0.025)
	for x in [-0.135, 0.135]:
		for z in [-0.13, 0.13]: _beam(p + Vector3(x, -0.2, z), p + Vector3(x, 0.2, z), 0.018, WOOD_DARK)
	_box(p + Vector3(0, -0.23, 0), Vector3(0.33, 0.07, 0.32), WOOD_DARK, 0.03)
	_blob(p + Vector3(0, 0.25, 0), Vector3(0.22, 0.13, 0.2), WOOD_DARK)

func _cloud(pos: Vector3, size: float) -> void:
	for d in [Vector3(-0.23, 0, 0), Vector3(0, 0.11, 0), Vector3(0.23, 0, 0)]:
		_blob(pos + d * size, Vector3(0.22, 0.2, 0.032) * size, IVORY)
	_box(pos + Vector3(0, -0.08, 0) * size, Vector3(0.75, 0.2, 0.05) * size, IVORY, 0.04 * size)

func _sign() -> void:
	_box(Vector3(0, 0.95, 0), Vector3(0.15, 1.9, 0.15), WOOD, 0.04)
	_box(Vector3(0.35, 1.8, 0), Vector3(0.94, 0.13, 0.13), WOOD_LIGHT, 0.03)
	for x in [0.1, 0.59]: _ring(Vector3(x, 1.7, 0), 0.06, 0.012, WOOD_DARK, Vector3(PI / 2, 0, 0))
	_box(Vector3(0.35, 1.36, 0), Vector3(0.74, 0.53, 0.1), WOOD, 0.065)
	_box(Vector3(0.35, 1.36, 0.06), Vector3(0.61, 0.41, 0.035), LAVENDER, 0.04)
	_cloud(Vector3(0.35, 1.35, 0.09), 0.55)

# ------------------------------------------------------------------ Farm / production props

func _basket(pos: Vector3, filled: bool) -> void:
	for i in 20:
		var a := TAU * i / 20.0
		_beam(pos + Vector3(cos(a) * 0.21, 0.04, sin(a) * 0.21), pos + Vector3(cos(a) * 0.3, 0.37, sin(a) * 0.3), 0.02, WOOD_LIGHT)
	for i in 5: _ring(pos + Vector3(0, 0.07 + i * 0.075, 0), 0.22 + i * 0.02, 0.017, WOOD)
	_ring(pos + Vector3(0, 0.39, 0), 0.31, 0.026, CREAM)
	if filled:
		for i in 5:
			var a := i * 2.4
			_blob(pos + Vector3(cos(a) * 0.16, 0.38 + (i % 2) * 0.07, sin(a) * 0.15), Vector3.ONE * 0.095, FRUIT)

func _farm(stage: int) -> void:
	var w := 5.65
	var d := 2.45
	_box(Vector3(0, 0.11, 0), Vector3(w, 0.2, d), SOIL, 0.09)
	for z in [-d * 0.5, d * 0.5]: _box(Vector3(0, 0.2, z), Vector3(w + 0.1, 0.34, 0.13), WOOD_LIGHT, 0.04)
	for x in [-w * 0.5, w * 0.5]:
		_box(Vector3(x, 0.2, 0), Vector3(0.14, 0.34, d), WOOD_LIGHT, 0.04)
		for z in [-d * 0.5, d * 0.5]: _box(Vector3(x, 0.27, z), Vector3(0.2, 0.5, 0.2), CREAM, 0.065)
	for row in 3:
		var z := (row - 1) * 0.69
		_box(Vector3(0, 0.24, z), Vector3(w - 0.28, 0.09, 0.43), SOIL.lightened(0.09), 0.045)
		for col in 5:
			var p := Vector3(-2.18 + col * 1.03, 0.28, z)
			if stage == 0:
				_blob(p, Vector3(0.045, 0.028, 0.035), CREAM)
			else:
				var h := 0.1 + stage * 0.12
				_beam(p, p + Vector3(0, h, 0), 0.018, LEAF_DARK)
				for j in (2 if stage == 1 else 4):
					_leaf(p + Vector3(0, h * (0.35 if j < 2 else 0.82), 0), 0.2 + stage * 0.09, 0.1 + stage * 0.018, col + j * 2.3, LEAF_LIGHT if j % 2 else LEAF)
				if stage >= 3:
					for side in [-1.0, 1.0]:
						_blob(p + Vector3(side * 0.14, h * 0.68, 0.14), Vector3.ONE * 0.125, FRUIT if col % 2 else Color("d6ad70"))
	_basket(Vector3(w * 0.5 - 0.36, 0.02, d * 0.5 - 0.35), stage >= 3)

func _well() -> void:
	for row in 3:
		for i in 12:
			var a := TAU * (i + (row % 2) * 0.5) / 12.0
			_box(Vector3(sin(a) * 0.61, 0.13 + row * 0.23, cos(a) * 0.61), Vector3(0.33, 0.22, 0.22), STONE.lerp(CREAM, (i % 3) * 0.12), 0.035, Vector3(0, a, 0))
	_ring(Vector3(0, 0.73, 0), 0.62, 0.13, CREAM)
	_blob(Vector3(0, 0.65, 0), Vector3(0.52, 0.015, 0.52), WATER)
	for x in [-0.84, 0.84]: _box(Vector3(x, 0.85, 0), Vector3(0.16, 1.7, 0.16), WOOD, 0.04)
	_box(Vector3(0, 1.71, 0), Vector3(1.95, 0.17, 0.21), WOOD_LIGHT, 0.05)
	_beam(Vector3(-0.91, 1.37, 0), Vector3(0.91, 1.37, 0), 0.065, WOOD_DARK)
	for i in 7: _ring(Vector3(-0.08 + i * 0.028, 1.37, 0), 0.08, 0.012, CREAM, Vector3(0, 0, PI / 2))
	_beam(Vector3(0, 1.33, 0.07), Vector3(0, 0.84, 0.07), 0.018, CREAM)
	_basket(Vector3(0.81, 0, 0.51), false)

func _cottage(kind: String) -> void:
	# Local dimensions 3.4 × 1.5, height 2.55. Fits the unchanged building footprint.
	var w := 3.35
	var d := 1.46
	var front := d * 0.5
	_box(Vector3(0, 0.85, 0), Vector3(w, 1.7, d), CREAM, 0.1)
	# Barrel roof: cream ribs and curved lavender slats, matching the source greenhouse.
	for k in 15:
		var a := PI * k / 14.0
		var p := Vector3(cos(a) * 1.79, 1.61 + sin(a) * 0.9, 0)
		_box(p, Vector3(0.43, 0.12, d + 0.28), LAVENDER.lerp(IVORY, (k % 3) * 0.13), 0.035, Vector3(0, 0, a - PI / 2))
	for z in [-front - 0.1, front + 0.1]:
		for k in 20:
			var a := PI * k / 20.0
			var b := PI * (k + 1) / 20.0
			_beam(Vector3(cos(a) * 1.79, 1.61 + sin(a) * 0.91, z), Vector3(cos(b) * 1.79, 1.61 + sin(b) * 0.91, z), 0.055, IVORY)
	# Fill the arched gable with blue glass, then lay cream mullions over it.
	for side in [-1.0, 1.0]:
		var z: float = side * (front + 0.028)
		for i in 24:
			var a := PI * i / 24.0
			var b := PI * (i + 1) / 24.0
			var normal := Vector3(0, 0, side)
			_triangle([Vector3(0, 1.63, z), Vector3(cos(a) * 1.72, 1.63 + sin(a) * 0.85, z), Vector3(cos(b) * 1.72, 1.63 + sin(b) * 0.85, z)], [normal, normal, normal], Color("aec3c7"))
	for x in [-0.9, 0.0, 0.9]:
		var h := sqrt(1.0 - pow(x / 1.72, 2.0)) * 0.83
		_box(Vector3(x, 1.63 + h * 0.5, front + 0.065), Vector3(0.08, h, 0.065), IVORY, 0.015)
	_box(Vector3(0, 1.64, front + 0.065), Vector3(3.44, 0.09, 0.08), IVORY, 0.02)

	for x in [-1.53, -0.79, 0.79, 1.53]:
		_box(Vector3(x, 0.95, front + 0.015), Vector3(0.12, 1.7, 0.12), WOOD_LIGHT, 0.025)
	for x in [-1.14, 1.14]:
		_box(Vector3(x, 1.07, front + 0.01), Vector3(0.56, 0.96, 0.055), Color("aec3c7") if kind != "shed" else WOOD_LIGHT, 0.035)
		_box(Vector3(x, 0.64, front + 0.045), Vector3(0.66, 0.08, 0.13), IVORY, 0.02)
		_box(Vector3(x, 1.12, front + 0.06), Vector3(0.06, 0.86, 0.09), IVORY, 0.015)
	_box(Vector3(0, 0.68, front + 0.045), Vector3(1.15, 1.36, 0.13), WOOD, 0.16)
	for i in 6: _box(Vector3(-0.46 + i * 0.185, 0.7, front + 0.12), Vector3(0.17, 1.27, 0.05), WOOD_LIGHT.lerp(WOOD, (i % 2) * 0.13), 0.025)
	_blob(Vector3(0.38, 0.61, front + 0.18), Vector3.ONE * 0.047, WOOD_DARK)
	_cloud(Vector3(0, 1.03, front + 0.16), 0.66)
	# Scalloped canvas, projecting toward the viewer, plus side planters.
	_box(Vector3(0, 1.6, front + 0.27), Vector3(3.04, 0.07, 0.64), IVORY, 0.035, Vector3(-0.13, 0, 0))
	for i in 7: _blob(Vector3(-1.27 + i * 0.425, 1.53, front + 0.58), Vector3(0.24, 0.15, 0.045), IVORY)
	for x in [-1.39, 1.39]:
		_box(Vector3(x, 0.39, front + 0.1), Vector3(0.45, 0.22, 0.3), WOOD_LIGHT, 0.035)
		for j in 3:
			_leaf(Vector3(x, 0.51, front + 0.13), 0.3, 0.13, j * 2.1, LEAF)
		_flower(Vector3(x, 0.75, front + 0.17), 0.12)

func _workshop(quarry: bool) -> void:
	_box(Vector3(0, 0.08, 0), Vector3(3.45, 0.15, 1.46), CREAM, 0.05)
	for x in [-1.45, 1.45]: _box(Vector3(x, 0.7, -0.48), Vector3(0.12, 1.4, 0.12), WOOD, 0.03)
	_box(Vector3(0, 1.38, -0.34), Vector3(3.45, 0.1, 0.78), LAVENDER, 0.04, Vector3(-0.12, 0, 0))
	for i in 7: _blob(Vector3(-1.42 + i * 0.47, 1.31, 0.06), Vector3(0.25, 0.13, 0.03), CREAM)
	if quarry:
		_rocks()
		_box(Vector3(1.0, 0.3, 0.3), Vector3(0.57, 0.5, 0.5), WOOD_LIGHT, 0.04)
	else:
		for i in 5:
			var y := 0.25 + (i / 3) * 0.33
			var z := -0.05 + (i % 3) * 0.34
			_beam(Vector3(-1.15, y, z), Vector3(0.92, y, z), 0.16, WOOD_DARK)
			_blob(Vector3(0.94, y, z), Vector3(0.025, 0.14, 0.14), WOOD_LIGHT)
			_ring(Vector3(0.97, y, z), 0.075, 0.008, WOOD, Vector3(0, 0, PI / 2))

func _path(repaired: bool) -> void:
	for i in 5:
		_blob(Vector3(-0.62 + (i % 3) * 0.55, 0.045, -0.22 + (i / 3) * 0.5), Vector3(0.32, 0.06, 0.21), STONE.lerp(CREAM, (i % 3) * 0.12))
	if repaired:
		_box(Vector3(1.45, 0.56, -0.44), Vector3(0.12, 1.12, 0.12), WOOD, 0.03)
		_box(Vector3(1.45, 1.04, -0.43), Vector3(0.55, 0.33, 0.08), LAVENDER, 0.035)
		_cloud(Vector3(1.45, 1.04, -0.38), 0.44)

func _training() -> void:
	_box(Vector3(0, 0.07, 0), Vector3(5.45, 0.14, 1.43), WOOD_LIGHT, 0.05)
	for i in 3:
		var x := -1.45 + i * 1.45
		_beam(Vector3(x, 0.14, 0), Vector3(x, 1.12, 0), 0.085, WOOD)
		_beam(Vector3(x - 0.28, 0.77, 0), Vector3(x + 0.28, 0.77, 0), 0.07, WOOD)
		_blob(Vector3(x, 1.2, 0), Vector3(0.2, 0.23, 0.18), CREAM)
		_ring(Vector3(x, 0.78, 0.07), 0.18, 0.025, LAVENDER, Vector3(PI / 2, 0, 0))

func _dam() -> void:
	for i in 10: _box(Vector3(-2.24 + i * 0.5, 0.4, -0.13), Vector3(0.48, 0.8, 0.5), STONE.lerp(CREAM, (i % 3) * 0.07), 0.05)
	_box(Vector3(0, 0.85, -0.13), Vector3(5.25, 0.12, 0.63), WOOD_LIGHT, 0.04)
	_box(Vector3(0, 0.05, 0.38), Vector3(5.2, 0.055, 0.68), WATER, 0.035)

func _wheel() -> void:
	_ring(Vector3.ZERO, 0.56, 0.065, WOOD_DARK, Vector3(PI / 2, 0, 0))
	for i in 10:
		var a := TAU * i / 10.0
		_beam(Vector3.ZERO, Vector3(cos(a) * 0.55, sin(a) * 0.55, 0), 0.035, WOOD_LIGHT)
		_box(Vector3(cos(a) * 0.56, sin(a) * 0.56, 0), Vector3(0.22, 0.08, 0.38), WOOD, 0.025, Vector3(0, 0, a))
	_blob(Vector3.ZERO, Vector3.ONE * 0.11, CREAM)
