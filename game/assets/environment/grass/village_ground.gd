class_name VillageGround
extends RefCounted
## HWR-GRASS-001 R3: shared ground material + blend mask for the village terrain mesh.
## The mask is a data texture (PX texels per logical cell): R = dirt/path weight, G = keep the flat
## vertex colour (fertile, river, cliff, rock, dam/repair sites), B = forest-floor shade.
## Path cells (template 'p'/'e') and completed road/repair buildings are dirt; the dirt bleeds an
## irregular EDGE_OUT band into neighbouring grass and grass nibbles EDGE_IN into the path, so the
## logical cell boundary (pathfinding, clicks, placement) never moves, only the picture does.
## The mask is rebuilt only when the road set changes, never per frame.

const DIR := "res://assets/environment/grass/ground/"
const PX := 32                       ## mask texels per cell, both axes (16x12 cells -> 512x384)
const EDGE_OUT := 0.14               ## world units of dirt bleeding into grass
const EDGE_IN := 0.05                ## world units of grass nibbling into the path
const EDGE_NOISE := 0.05             ## +- world units of edge irregularity
const DIRT_TERRAIN := ["p", "e"]
const FLAT_TERRAIN := ["f", "~", "#", "Q", "d", "x"]
const FOREST_TERRAIN := ["W"]

var material: ShaderMaterial
var mask_image: Image
var mask_texture: ImageTexture
var template: VillageTemplate
var cell_w := 2.0
var cell_d := 0.9
var _roads: Dictionary = {}          ## Vector2i -> true (completed road / repair cells)
var _kinds: Dictionary = {}          ## Vector2i -> "dirt" | "flat" | "forest" | "grass"


func build(p_template: VillageTemplate, p_cell_w: float, p_cell_d: float) -> void:
	template = p_template
	cell_w = p_cell_w
	cell_d = p_cell_d
	_roads.clear()
	material = ShaderMaterial.new()
	material.shader = load(DIR + "../village_ground.gdshader")
	material.set_shader_parameter("grass_tex", load(DIR + "ground_grass.png"))
	material.set_shader_parameter("dirt_tex", load(DIR + "ground_dirt.png"))
	material.set_shader_parameter("variation_tex", load(DIR + "ground_variation.png"))
	material.set_shader_parameter("map_origin", Vector2.ZERO)
	material.set_shader_parameter("map_size", Vector2(VillageTemplate.WIDTH * cell_w, VillageTemplate.HEIGHT * cell_d))
	mask_image = Image.create(VillageTemplate.WIDTH * PX, VillageTemplate.HEIGHT * PX, false, Image.FORMAT_RGBA8)
	_rebuild_mask()
	mask_texture = ImageTexture.create_from_image(mask_image)
	material.set_shader_parameter("mask_tex", mask_texture)


## Completed road/repair cells become dirt. Returns true when the mask actually changed.
func set_road_cells(cells: Array) -> bool:
	var want: Dictionary = {}
	for c in cells:
		if template != null and template.in_bounds(c):
			want[c] = true
	if want.size() == _roads.size():
		var same := true
		for c in want.keys():
			if not _roads.has(c):
				same = false
				break
		if same:
			return false
	_roads = want
	_rebuild_mask()
	if mask_texture != null:
		mask_texture.update(mask_image)
	return true


func road_cells() -> Array:
	return _roads.keys()


func kind_of(c: Vector2i) -> String:
	if not template.in_bounds(c):
		return "flat"
	if _roads.has(c):
		return "dirt"
	var t := template.terrain_at(c)
	if DIRT_TERRAIN.has(t):
		return "dirt"
	if FLAT_TERRAIN.has(t):
		return "flat"
	if FOREST_TERRAIN.has(t):
		return "forest"
	return "grass"


func is_dirt_cell(c: Vector2i) -> bool:
	return kind_of(c) == "dirt"


## Mask values at a world XZ position: {dirt, flat, forest} in 0..1 (nearest texel; for tests/tools).
func sample(world_xz: Vector2) -> Dictionary:
	var px := clampi(int(floor(world_xz.x / cell_w * PX)), 0, mask_image.get_width() - 1)
	var py := clampi(int(floor(world_xz.y / cell_d * PX)), 0, mask_image.get_height() - 1)
	var c := mask_image.get_pixel(px, py)
	return {"dirt": c.r, "flat": c.g, "forest": c.b}


func _rebuild_mask() -> void:
	_kinds.clear()
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			var k := kind_of(c)
			_kinds[c] = k
			mask_image.fill_rect(Rect2i(x * PX, y * PX, PX, PX), _base_color(k))
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			match _kinds[c]:
				"grass", "forest":
					_soften_grass_cell(c)
				"dirt":
					_soften_dirt_cell(c)


static func _base_color(kind: String) -> Color:
	match kind:
		"dirt": return Color(1, 0, 0, 1)
		"flat": return Color(0, 1, 0, 1)
		"forest": return Color(0, 0, 1, 1)
	return Color(0, 0, 0, 1)


## Grass/forest cell next to dirt: dirt bleeds in from the neighbouring dirt rectangles.
func _soften_grass_cell(c: Vector2i) -> void:
	var rects: Array[Rect2] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := c + Vector2i(dx, dy)
			if _kinds.get(n, "flat") == "dirt":
				rects.append(Rect2(n.x * cell_w, n.y * cell_d, cell_w, cell_d))
	if rects.is_empty():
		return
	var forest: bool = _kinds[c] == "forest"
	for py in PX:
		for px in PX:
			var w := _texel_world(c, px, py)
			var d := INF
			for r in rects:
				d = minf(d, _rect_distance(r, w))
			var dirt := _edge_weight(d + _edge_noise(w))
			if dirt > 0.002:
				mask_image.set_pixel(c.x * PX + px, c.y * PX + py, Color(dirt, 0.0, 1.0 if forest else 0.0, 1.0))


## Dirt cell: grass nibbles a little into the edges that face grass/forest (never into other dirt or flat cells).
func _soften_dirt_cell(c: Vector2i) -> void:
	var open: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k: String = _kinds.get(c + d, "flat")
		if k == "grass" or k == "forest":
			open.append(d)
	if open.is_empty():
		return
	var x0 := c.x * cell_w
	var z0 := c.y * cell_d
	for py in PX:
		for px in PX:
			var w := _texel_world(c, px, py)
			var inside := INF
			for d in open:
				match d:
					Vector2i(1, 0): inside = minf(inside, x0 + cell_w - w.x)
					Vector2i(-1, 0): inside = minf(inside, w.x - x0)
					Vector2i(0, 1): inside = minf(inside, z0 + cell_d - w.y)
					Vector2i(0, -1): inside = minf(inside, w.y - z0)
			var dirt := _edge_weight(-inside + _edge_noise(w))
			if dirt < 0.998:
				mask_image.set_pixel(c.x * PX + px, c.y * PX + py, Color(dirt, 0.0, 0.0, 1.0))


func _texel_world(c: Vector2i, px: int, py: int) -> Vector2:
	return Vector2((c.x + (px + 0.5) / PX) * cell_w, (c.y + (py + 0.5) / PX) * cell_d)


## 1 well inside the dirt, 0 EDGE_OUT into the grass; d = signed distance from the cell boundary (+ outside dirt).
static func _edge_weight(d: float) -> float:
	return 1.0 - smoothstep(-EDGE_IN, EDGE_OUT, d)


static func _edge_noise(w: Vector2) -> float:
	return EDGE_NOISE * (0.6 * sin(w.x * 9.1 + w.y * 2.0) * cos(w.y * 12.7 - w.x * 1.3) + 0.4 * sin(w.x * 21.0 + w.y * 15.0 + 1.0))


static func _rect_distance(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)
