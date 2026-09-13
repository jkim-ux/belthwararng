@tool
class_name DetailedGardenTree
extends RefCounted
## Authored from the approved single-tree concept, September 13 2026.
## Real leaves, stems, swept bark and roots. No solid canopy proxy or image billboard.
## Indexed vertices and one cached mesh keep the many leaves out of the scene tree.

const SCALE := 0.62
const BARK := Color("a77a44")
const BARK_LIGHT := Color("bd935b")
const OLIVE := Color("506743")
const SAGE := Color("7d9150")
const LIME := Color("b7bd66")

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var lod_indices := PackedInt32Array()
var include_in_lod := true
var rng := RandomNumberGenerator.new()
var leaf_count := 0
var branch_count := 0

static func build(variant: int = 0) -> ArrayMesh:
	var author := DetailedGardenTree.new()
	author.rng.seed = 61473 + posmod(variant, 3) * 31
	author._tree()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = author.vertices
	arrays[Mesh.ARRAY_NORMAL] = author.normals
	arrays[Mesh.ARRAY_COLOR] = author.colors
	arrays[Mesh.ARRAY_INDEX] = author.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {0.008: author.lod_indices})
	mesh.set_meta("lod_triangles", author.lod_indices.size() / 3)
	mesh.set_meta("individual_leaves", author.leaf_count)
	mesh.set_meta("swept_branches", author.branch_count)
	mesh.set_meta("reference", "single-tree-concept-2026-09-13")
	return mesh

func _vertex(p: Vector3, n: Vector3, c: Color) -> int:
	var i := vertices.size()
	vertices.append(p * SCALE)
	normals.append(n.normalized())
	colors.append(c.srgb_to_linear())
	return i

func _tri(a: int, b: int, c: int) -> void:
	var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if cross.length_squared() < 0.0000000000001: return
	# Godot's front faces are clockwise viewed from outside.
	if cross.dot(normals[a] + normals[b] + normals[c]) > 0.0:
		indices.append_array(PackedInt32Array([a, c, b]))
		if include_in_lod: lod_indices.append_array(PackedInt32Array([a, c, b]))
	else:
		indices.append_array(PackedInt32Array([a, b, c]))
		if include_in_lod: lod_indices.append_array(PackedInt32Array([a, b, c]))

func _quad(a: int, b: int, c: int, d: int) -> void:
	_tri(a, b, c)
	_tri(a, c, d)

func _sample(path: Array[Vector3], t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (path.size() - 1)
	var i := mini(int(f), path.size() - 2)
	var u := f - i
	var p0 := path[maxi(0, i - 1)]
	var p1 := path[i]
	var p2 := path[i + 1]
	var p3 := path[mini(path.size() - 1, i + 2)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)

func _radius(radii: Array[float], t: float) -> float:
	var f := clampf(t, 0.0, 1.0) * (radii.size() - 1)
	var i := mini(int(f), radii.size() - 2)
	return lerpf(radii[i], radii[i + 1], smoothstep(0.0, 1.0, f - i))

## Longitudinal ridges follow the curved wood instead of straight cylinder stripes.
func _tube(path: Array[Vector3], radii: Array[float], rings: int, sides: int, phase: float, bark: bool = true) -> void:
	branch_count += 1
	var previous_lod := include_in_lod
	if radii[0] < 0.009: include_in_lod = false
	var start := vertices.size()
	var centers := PackedVector3Array()
	var ups := PackedVector3Array()
	var frames: Array[Basis] = []
	for j in rings + 1:
		var t := float(j) / rings
		var p := _sample(path, t)
		var tangent := (_sample(path, minf(1.0, t + 0.005)) - _sample(path, maxf(0.0, t - 0.005))).normalized()
		var right := tangent.cross(Vector3.FORWARD).normalized()
		if right.length_squared() < 0.1: right = tangent.cross(Vector3.RIGHT).normalized()
		var other := right.cross(tangent).normalized()
		frames.append(Basis(right, tangent, other))
		centers.append(p)
		ups.append(tangent)
		for k in sides + 1:
			var a := TAU * k / sides
			var wind := a + 0.22 * sin(t * 4.4 + phase) + 0.1 * sin(t * 12.0 + phase)
			var grooves := 0.0
			if bark:
				grooves = sin(wind * 13.0 + sin(t * 9.0 + a * 3.0) * 0.7) * 0.042 + sin(wind * 27.0 + t * 17.0) * 0.017
			var r := _radius(radii, t) * (1.0 + sin(a * 5.0 + t * 2.0 + phase) * 0.09 + grooves)
			var n := right * cos(a) + other * sin(a)
			var shade := clampf(0.45 + grooves * 5.0 + 0.10 * sin(a * 7.0 + t * 32.0), 0.0, 1.0)
			var color := BARK.lerp(BARK_LIGHT, shade)
			if bark:
				var crevice := pow(maxf(0.0, -sin(wind * 13.0 + sin(t * 9.0 + a * 3.0) * 0.7)), 6.0)
				color = color.darkened(crevice * 0.19)
			else: color = BARK.lerp(OLIVE, 0.12)
			_vertex(p + n * r, n, color)
	# Surface normals from the actual ridged surface, including taper.
	for j in rings + 1:
		for k in sides + 1:
			var idx := start + j * (sides + 1) + k
			var left := start + j * (sides + 1) + posmod(k - 1, sides)
			var right := start + j * (sides + 1) + posmod(k + 1, sides)
			var below := start + maxi(0, j - 1) * (sides + 1) + k
			var above := start + mini(rings, j + 1) * (sides + 1) + k
			var n := (vertices[right] - vertices[left]).cross(vertices[above] - vertices[below]).normalized()
			if n.dot(normals[idx]) < 0.0: n = -n
			normals[idx] = n
			if j < rings and k < sides: _quad(idx, idx + 1, idx + sides + 2, idx + sides + 1)
	for end in [0, rings]:
		var normal: Vector3 = ups[end] * (-1.0 if end == 0 else 1.0)
		var center := _vertex(centers[end], normal, BARK)
		for k in sides:
			_tri(center, start + end * (sides + 1) + k, start + end * (sides + 1) + k + 1)

	include_in_lod = previous_lod

func _leaf_point(t: float, s: float, length: float, width: float, phase: float) -> Vector3:
	var profile := pow(maxf(0.0, sin(PI * t)), 0.86) * (1.0 - t * 0.18)
	var x := width * s * profile * (1.0 + 0.022 * sin(t * 43.0 + phase))
	var y := length * (-0.24 * t * t + 0.12 * sin(t * PI) - 0.12 * pow(absf(s), 1.3) * sin(t * PI))
	y += length * 0.033 * sin(t * 7.0 + phase) * s * t
	return Vector3(x, y, t * length)

func _leaf_normal(t: float, s: float, length: float, width: float, phase: float) -> Vector3:
	var du := _leaf_point(t, s + 0.002, length, width, phase) - _leaf_point(t, s - 0.002, length, width, phase)
	var dv := _leaf_point(t + 0.002, s, length, width, phase) - _leaf_point(t - 0.002, s, length, width, phase)
	var n := dv.cross(du).normalized()
	return Vector3.UP if n.length_squared() < 0.1 else n

func _vein(p: Vector3, basis: Basis, length: float, width: float, phase: float, a: Vector2, b: Vector2, color: Color, thickness: float) -> void:
	var previous_lod := include_in_lod
	include_in_lod = false
	var start := vertices.size()
	for i in 4:
		var f := float(i) / 3.0
		var q := a.lerp(b, f)
		q.y += sin(f * PI) * signf(b.y) * 0.04
		for side in [-1.0, 1.0]:
			var s: float = q.y + side * thickness * (1.0 - f * 0.78)
			var n := _leaf_normal(q.x, s, length, width, phase)
			_vertex(p + basis * (_leaf_surface(q.x, s, length, width, phase) + n * 0.0012), basis * n, color)
	for i in 3: _quad(start + i * 2, start + i * 2 + 1, start + i * 2 + 3, start + i * 2 + 2)

	include_in_lod = previous_lod

func _leaf(p: Vector3, direction: Vector3, length: float, width: float, color: Color, roll: float) -> void:
	leaf_count += 1
	var z := direction.normalized()
	var x := Vector3.UP.cross(z).normalized()
	if x.length_squared() < 0.1: x = Vector3.RIGHT
	var y := z.cross(x).normalized()
	var basis := Basis(x, y, z) * Basis(Vector3.FORWARD, roll)
	var phase := rng.randf_range(0.0, TAU)
	var start := vertices.size()
	for row in 9:
		var t := clampf(float(row) / 8.0, 0.002, 0.998)
		for col in 5:
			var s := (col - 2) * 0.5
			var n := _leaf_normal(t, s, length, width, phase)
			var c := color.lerp(LIME, 0.065 * (1.0 - absf(s)))
			c = c.darkened(absf(s) * 0.035 + (1.0 - t) * 0.035)
			_vertex(p + basis * _leaf_point(t, s, length, width, phase), basis * n, c)
	include_in_lod = false
	for row in 8:
		for col in 4:
			var i := start + row * 5 + col
			_quad(i, i + 1, i + 6, i + 5)
	include_in_lod = true
	for row in range(0, 8, 2):
		for col in range(0, 4, 2):
			var i := start + row * 5 + col
			_lod_tri(i, i + 2, i + 12)
			_lod_tri(i, i + 12, i + 10)
	var vein := color.lerp(Color("d3ca85"), 0.28)
	_vein(p, basis, length, width, phase, Vector2(0.015, 0), Vector2(0.96, 0), vein, 0.038)
	for row in 5:
		var t := 0.16 + row * 0.135
		for side in [-1.0, 1.0]:
			_vein(p, basis, length, width, phase, Vector2(t, 0.02 * side), Vector2(t + 0.14, 0.91 * side), vein.darkened(0.03), 0.022)
	# Tiny petiole is part of the combined geometry.
	_tube([p - z * length * 0.12, p + z * length * 0.04], [0.0045, 0.0025], 1, 5, phase, false)

func _spray(anchor: Vector3, tip: Vector3, richness: float) -> void:
	var d := (tip - anchor).normalized()
	var x := d.cross(Vector3.UP).normalized()
	if x.length_squared() < 0.1: x = Vector3.RIGHT
	var other := d.cross(x).normalized()
	_tube([anchor, anchor.lerp(tip, 0.6) + Vector3(0, 0.08, 0), tip], [0.017, 0.009, 0.002], 6, 7, rng.randf() * TAU, false)
	for row in 4:
		var u := 0.22 + row * 0.21
		var p := anchor.lerp(tip, u) + Vector3(0, sin(u * PI) * 0.08, 0)
		for side in [-1.0, 1.0]:
			var dir: Vector3 = (d * 0.50 + x * side * 0.9 + other * rng.randf_range(-0.32, 0.32) + Vector3(0, -0.15, 0)).normalized()
			var length := rng.randf_range(0.27, 0.43) * (1.12 - row * 0.05)
			var c := OLIVE.lerp(SAGE, clampf(richness + rng.randf_range(-0.35, 0.35), 0.0, 1.0))
			c = c.lerp(LIME, clampf((p.y - 3.0) * 0.10 + rng.randf_range(-0.12, 0.34) - p.x * 0.035, 0.0, 0.45))
			_leaf(p, dir, length, length * rng.randf_range(0.22, 0.30), c, rng.randf_range(-0.5, 0.5))
	_leaf(tip, d + Vector3(0, -0.18, 0), 0.30, 0.081, SAGE.lerp(LIME, richness * 0.3), rng.randf_range(-0.4, 0.4))

func _tree() -> void:
	_append_sculpted_bark()
	var leaders: Array[Vector3] = [Vector3(-1.37, 2.51, 0.13), Vector3(1.08, 2.63, 0.03), Vector3(0.70, 3.54, -0.22), Vector3(-1.00, 3.47, -0.30), Vector3(0.32, 2.94, -0.90)]
	# Deliberately placed tiered masses, populated only by twig/leaf geometry.
	var crowns := [
		[Vector3(-1.55, 2.41, 0.25), Vector3(0.60, 0.40, 0.55), 0],
		[Vector3(-1.68, 2.91, -0.05), Vector3(0.62, 0.40, 0.60), 0],
		[Vector3(-1.30, 3.38, 0.05), Vector3(0.72, 0.46, 0.65), 3],
		[Vector3(-0.82, 3.77, -0.05), Vector3(0.68, 0.43, 0.62), 3],
		[Vector3(-0.08, 4.02, -0.17), Vector3(0.70, 0.48, 0.67), 2],
		[Vector3(0.59, 4.05, -0.18), Vector3(0.69, 0.43, 0.62), 2],
		[Vector3(1.08, 3.60, 0.03), Vector3(0.70, 0.46, 0.61), 2],
		[Vector3(1.58, 3.19, 0.12), Vector3(0.67, 0.42, 0.61), 1],
		[Vector3(1.58, 2.64, 0.30), Vector3(0.60, 0.40, 0.58), 1],
		[Vector3(1.13, 2.35, 0.48), Vector3(0.53, 0.35, 0.52), 1],
		[Vector3(-0.61, 3.30, -0.86), Vector3(0.63, 0.46, 0.55), 4],
		[Vector3(0.19, 3.63, -0.92), Vector3(0.66, 0.48, 0.59), 4],
		[Vector3(0.95, 3.16, -0.80), Vector3(0.57, 0.43, 0.58), 4],
		[Vector3(-0.41, 3.28, 0.41), Vector3(0.56, 0.36, 0.44), 3],
		[Vector3(0.35, 3.37, 0.49), Vector3(0.48, 0.35, 0.48), 2]]
	for entry in crowns:
		var center: Vector3 = entry[0]
		var extent: Vector3 = entry[1]
		var leader: Vector3 = leaders[entry[2]]
		_tube([leader, leader.lerp(center, 0.55) - Vector3(0, 0.10, 0), center], [0.037, 0.022, 0.005], 12, 12, rng.randf() * TAU)
		for j in 13:
			var a := j * 2.39996 + rng.randf_range(-0.20, 0.20)
			var h := -0.58 + float(j) / 12.0 * 1.48
			var radial := sqrt(maxf(0.05, 1.0 - h * h))
			var direction := Vector3(cos(a) * radial, h, sin(a) * radial)
			var end := center + direction * extent
			var begin := center + direction * extent * 0.30 - Vector3(0, 0.06, 0)
			_spray(begin, end, clampf(0.54 + h * 0.25 + (-end.x) * 0.045, 0.0, 1.0))
	# Sparse root leaves, sized as small shoots rather than a decorative base plinth.
	for i in 18:
		var a := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.62, 1.12)
		var p := Vector3(cos(a) * radius, 0.035, sin(a) * radius)
		_leaf(p, Vector3(cos(a + 0.6), 0.3, sin(a + 0.6)), rng.randf_range(0.13, 0.24), 0.055, SAGE, 0.1)

## Veins sit on the triangulated leaf surface; no z-fighting against an analytic curve.
func _leaf_surface(t: float, s: float, length: float, width: float, phase: float) -> Vector3:
	var row := clampi(int(t * 8.0), 0, 7)
	var col := clampi(int((s + 1.0) * 2.0), 0, 3)
	var y := clampf(t * 8.0 - row, 0.0, 1.0)
	var x := clampf((s + 1.0) * 2.0 - col, 0.0, 1.0)
	var t0 := clampf(row / 8.0, 0.002, 0.998)
	var t1 := clampf((row + 1) / 8.0, 0.002, 0.998)
	var s0 := col * 0.5 - 1.0
	var a := _leaf_point(t0, s0, length, width, phase)
	var b := _leaf_point(t0, s0 + 0.5, length, width, phase)
	var c := _leaf_point(t1, s0 + 0.5, length, width, phase)
	var d := _leaf_point(t1, s0, length, width, phase)
	return a * (1.0 - x) + b * (x - y) + c * y if y <= x else a * (1.0 - y) + c * x + d * (y - x)

func _append_sculpted_bark() -> void:
	# Small native resources keep transfer/import bounded; assembled as one draw surface.
	const PARTS = preload("res://assets/garden_v1/models/bark_parts.gd")
	for mesh in PARTS.MESHES:
		var a: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var offset := vertices.size()
		for i in v.size():
			vertices.append(v[i] * SCALE)
			normals.append(n[i])
			colors.append(c[i])
		for index in idx:
			indices.append(index + offset)
			lod_indices.append(index + offset)

func _lod_tri(a: int, b: int, c: int) -> void:
	var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if cross.length_squared() < 0.0000000000001: return
	if cross.dot(normals[a] + normals[b] + normals[c]) > 0.0:
		lod_indices.append_array(PackedInt32Array([a, c, b]))
	else:
		lod_indices.append_array(PackedInt32Array([a, b, c]))
