class_name VillageStage3D
extends Node3D
## 마을 표시 계층(HWR-006): 낮은 측면(벨트스크롤) 카툰 3D. VillageSim 의 16×12 논리 격자·점유·주민 위치를 단일 원본으로 두고
## 지형·장애물·건물·정령·플레이어·미리보기·바람 효과를 단순 메시로 그린다. 판정(점유·문·통행)은 격자가 담당하며 여기에는 물리가 없다.
##
## 좌표 계약: 논리 칸 q=(qx,qy) → 바닥 (CELL_W*qx, 0, CELL_D*qy). 바닥 y(깊이)는 3D Z, 모델 높이는 3D Y.
## 카메라는 +Z 쪽에서 -Z 를 보며 수평에서 PITCH_DEG 내려다보는 직교 카메라(좌우 축과 평행, 방위 회전 없음).
## 마우스 → 바닥 칸: 화면 픽셀 → Camera3D 레이 → Y=0 평면 교차 → 역변환 → floor. (screen_to_cell)
## 이 노드는 SubViewport 안에 놓이며, 입력은 부모 VillageView 가 한 번만 해석한다.

const CELL_W := 2.0            ## 논리 칸 1 → 가로(X) 단위
const CELL_D := 0.9            ## 논리 칸 1 → 깊이(Z) 단위 (표시에서만 깊이를 압축)
const PITCH_DEG := 20.0
const ORTHO_SIZE := 8.5        ## 작은 정원: 기존 12 대비 약 1.41배 가까운 직교 줌
const CAM_DIST := 60.0
const BACKGROUND_COLOR := Color("b5cddd")
const MAP_W_UNITS := VillageTemplate.WIDTH * CELL_W
const MAP_D_UNITS := VillageTemplate.HEIGHT * CELL_D

## 건물 종류별 대략 높이(선택 영역·가림 계산용)
const KIND_HEIGHT := {"farm": 0.95, "well": 1.85, "canal": 0.3, "dam": 1.6, "lumber": 1.6, "quarry": 1.6, "house": 2.7, "road": 0.15, "repair": 1.25, "facility": 2.7}

var template: VillageTemplate
var data: CampaignData
var camera: Camera3D
var light: DirectionalLight3D
var backdrop_root: Node3D
var terrain_root: Node3D
var obstacle_root: Node3D
var building_root: Node3D
var actor_root: Node3D
var preview_root: Node3D
var fx_root: Node3D
var water_root: Node3D
var select_root: Node3D
var obstacle_nodes: Dictionary = {}     ## oid -> Node3D
var building_nodes: Dictionary = {}     ## id -> {node: Node3D, sig: String, meshes: Array}
var actor_nodes: Dictionary = {}        ## villager id -> SpiritActor3D
var player_node: Node3D
var player_body: Node3D
var preview_sig: String = ""
var select_sig: String = ""
var water_sig: String = ""
var cam_x: float = 0.0                  ## 카메라 목표 X(단위)
var overview: bool = false
var anim_t: float = 0.0
var harvest_fx: Array = []              ## [{items: Array[MeshInstance3D], from: Array[Vector3], to: Vector3, t: float}]
var wind_ribbons: Dictionary = {}       ## villager id -> MeshInstance3D(ImmediateMesh)
var wind_particles: Dictionary = {}     ## villager id -> Array[MeshInstance3D]
var faded_ids: Dictionary = {}          ## 현재 옅게 그리는 건물 id -> true
var _mat_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}
var dam_wheels: Array = []

# ------------------------------------------------------------------ 준비

func setup(p_template: VillageTemplate, p_data: CampaignData) -> void:
	template = p_template
	data = p_data
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = ORTHO_SIZE
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	camera.current = true
	light = DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	light.light_color = Color(1.0, 0.97, 0.9)
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.93, 0.91, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	for n in ["backdrop", "terrain", "obstacle", "building", "water", "select", "actor", "preview", "fx"]:
		var r := Node3D.new()
		r.name = n
		add_child(r)
		set(n + "_root", r)
	_build_backdrop()
	_build_terrain()
	_build_player()
	cam_x = MAP_W_UNITS / 2.0
	set_camera(cam_x, false, true)

# ------------------------------------------------------------------ 좌표 변환

static func cell_to_world(q: Vector2) -> Vector3:
	return Vector3(q.x * CELL_W, 0.0, q.y * CELL_D)

static func world_to_cell(p: Vector3) -> Vector2:
	return Vector2(p.x / CELL_W, p.z / CELL_D)

static func cell_center_world(c: Vector2i) -> Vector3:
	return cell_to_world(Vector2(c) + Vector2(0.5, 0.5))

## SubViewport 픽셀 → Y=0 바닥의 논리 좌표(칸 단위 실수). 레이가 바닥과 만나지 않으면 null.
func screen_to_ground(px: Vector2) -> Variant:
	if camera == null or not camera.is_inside_tree():
		return null
	var vp := camera.get_viewport()
	if vp == null:
		return null
	var rect := vp.get_visible_rect()
	if px.x < 0.0 or px.y < 0.0 or px.x > rect.size.x or px.y > rect.size.y:
		return null
	var o := camera.project_ray_origin(px)
	var n := camera.project_ray_normal(px)
	if absf(n.y) < 1e-6:
		return null
	var t := -o.y / n.y
	if t < 0.0:
		return null
	return world_to_cell(o + n * t)

## SubViewport 픽셀 → 논리 칸. 화면 밖/교차 실패/경계 밖은 (-1,-1).
func screen_to_cell(px: Vector2) -> Vector2i:
	var g: Variant = screen_to_ground(px)
	if g == null:
		return Vector2i(-1, -1)
	var q: Vector2 = g
	var c := Vector2i(floori(q.x), floori(q.y))
	if not template.in_bounds(c):
		return Vector2i(-1, -1)
	return c

## 논리 좌표(칸 단위 실수)와 높이 → SubViewport 픽셀
func ground_to_screen(q: Vector2, height: float = 0.0) -> Vector2:
	var p := cell_to_world(q)
	p.y = height
	return camera.unproject_position(p)

func viewport_size() -> Vector2:
	var vp := camera.get_viewport() if camera != null else null
	return vp.get_visible_rect().size if vp != null else Vector2(1280, 580)

## 카메라: 가로만 따라가고 세로는 마을 깊이 가운데 고정. 전체 보기는 각도 유지, 줌만 바꾼다.
func set_camera(target_x_units: float, p_overview: bool, snap: bool) -> void:
	overview = p_overview
	var vs := viewport_size()
	var aspect := vs.x / maxf(vs.y, 1.0)
	var size := ORTHO_SIZE
	if overview:
		size = maxf(ORTHO_SIZE, MAP_W_UNITS / aspect + 1.0)
	camera.size = size
	var half_w := size * aspect / 2.0
	var tx := MAP_W_UNITS / 2.0 if half_w * 2.0 >= MAP_W_UNITS else clampf(target_x_units, half_w, MAP_W_UNITS - half_w)
	if overview:
		tx = MAP_W_UNITS / 2.0
	cam_x = tx if snap else lerpf(cam_x, tx, 0.15)
	var pitch := deg_to_rad(PITCH_DEG)
	var zc := MAP_D_UNITS / 2.0 - 1.2   # 마을 띠를 화면 가운데보다 조금 아래에 두어 건물 높이가 위쪽 여백에 들어오게
	var target := Vector3(cam_x, 1.5, zc)
	camera.position = target + Vector3(0.0, CAM_DIST * sin(pitch), CAM_DIST * cos(pitch))
	camera.rotation = Vector3(-pitch, 0.0, 0.0)

## 화면 가로 1px 가 논리 칸 몇 칸인지 (플레이어 화면 속도 → 논리 속도 환산용): {x: 칸/px, y: 칸/px}
func cells_per_pixel() -> Vector2:
	var a := ground_to_screen(Vector2(10.0, 10.0))
	var bx := ground_to_screen(Vector2(11.0, 10.0))
	var by := ground_to_screen(Vector2(10.0, 11.0))
	return Vector2(1.0 / maxf(absf(bx.x - a.x), 1e-3), 1.0 / maxf(absf(by.y - a.y), 1e-3))

# ------------------------------------------------------------------ 재질·메시 도우미

func mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(true), str(unshaded)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	m.metallic = 0.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m

func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box|%s" % str(size)
	if not _mesh_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_mesh_cache[key] = bm
	return _mesh_cache[key]

func _sphere_mesh(r: float) -> SphereMesh:
	var key := "sph|%.3f" % r
	if not _mesh_cache.has(key):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 14
		sm.rings = 7
		_mesh_cache[key] = sm
	return _mesh_cache[key]

func _cyl_mesh(r_top: float, r_bottom: float, h: float) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%.3f" % [r_top, r_bottom, h]
	if not _mesh_cache.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bottom
		cm.height = h
		cm.radial_segments = 14
		_mesh_cache[key] = cm
	return _mesh_cache[key]

func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation = rot
	mi.set_meta("color", c)
	parent.add_child(mi)
	return mi

func sphere(parent: Node3D, r: float, pos: Vector3, c: Color, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(r)
	mi.material_override = mat(c)
	mi.position = pos
	mi.scale = sc
	mi.set_meta("color", c)
	parent.add_child(mi)
	return mi

func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, c: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl_mesh(r_top, r_bottom, h)
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation = rot
	mi.set_meta("color", c)
	parent.add_child(mi)
	return mi

func _clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

## One combined mesh per prop, shared by background, workshop and editor scenes.
func _art(parent: Node3D, id: String, pos: Vector3 = Vector3.ZERO, sc: Vector3 = Vector3.ONE, variant: int = 0, alpha: float = 1.0, tint: Color = Color.WHITE) -> MeshInstance3D:
	var m := GardenAssets.make(id, variant, alpha, tint)
	m.position = pos
	m.scale = sc
	parent.add_child(m)
	return m

## Rotate in logical directions, then fit X/Z to the unchanged compressed-depth footprint.
func _fit_art(parent: Node3D, id: String, w: float, d: float, rot: int, alpha: float, tint: Color) -> MeshInstance3D:
	var m := _art(parent, id, Vector3.ZERO, Vector3.ONE, 0, alpha, tint)
	var aabb := m.mesh.get_aabb()
	var rb := Basis(Vector3.UP, -posmod(rot, 4) * PI / 2.0)
	var rotated := Transform3D(rb, Vector3.ZERO) * aabb
	var scale_x := (w - 0.25) / maxf(rotated.size.x, 0.01)
	var scale_z := (d - 0.12) / maxf(rotated.size.z, 0.01)
	var basis := rb.scaled(Vector3(scale_x, 1.0, scale_z))
	var center := basis * aabb.get_center()
	m.transform = Transform3D(basis, Vector3(-center.x, 0.0, -center.z))
	return m

# ------------------------------------------------------------------ 지형

const COL_GROUND := Color("98a875")
const COL_FERTILE := Color(0.5, 0.38, 0.24)
const COL_RIVER := Color(0.36, 0.62, 0.86)
const COL_CLIFF := Color(0.56, 0.54, 0.5)
const COL_PATH := Color("c6af87")
const COL_FOREST := Color(0.3, 0.5, 0.3)
const COL_ROCK := Color(0.6, 0.58, 0.55)
const COL_DAM_SITE := Color(0.55, 0.64, 0.7)
const COL_REPAIR_SITE := Color(0.62, 0.52, 0.42)

func _terrain_color(t: String) -> Color:
	match t:
		"f": return COL_FERTILE
		"~": return COL_RIVER
		"#": return COL_CLIFF
		"e", "p": return COL_PATH
		"W": return COL_FOREST
		"Q": return COL_ROCK
		"d": return COL_DAM_SITE
		"x": return COL_REPAIR_SITE
	return COL_GROUND

## 바닥은 한 메시(정점 색), 절벽·숲·암반은 위에 단순 메시를 얹는다.
func _build_terrain() -> void:
	_clear_children(terrain_root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			var t := template.terrain_at(c)
			var col := _terrain_color(t)
			# 칸마다 아주 옅은 명암 차이로 격자가 읽히게
			if (x + y) % 2 == 1:
				col = col.darkened(0.012)
			var h := -0.12 if t == "~" else 0.0
			var p0 := Vector3(x * CELL_W, h, y * CELL_D)
			var p1 := Vector3((x + 1) * CELL_W, h, y * CELL_D)
			var p2 := Vector3((x + 1) * CELL_W, h, (y + 1) * CELL_D)
			var p3 := Vector3(x * CELL_W, h, (y + 1) * CELL_D)
			for v in [p0, p1, p2, p0, p2, p3]:
				st.set_color(col.srgb_to_linear())  # 정점 색은 선형 공간; 주변 잔디 재질과 같은 명도로 표시
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_BACK   # Godot 앞면은 시계 방향. 윗면이 조명을 받아야 한다.
	mi.material_override = m
	terrain_root.add_child(mi)
	# 강 반짝임 줄(정적)
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			var t := template.terrain_at(c)
			var center := cell_center_world(c)
			match t:
				"~":
					if (x + y) % 2 == 0:
						box(terrain_root, Vector3(CELL_W * 0.5, 0.02, 0.08), center + Vector3(0.0, -0.1, -0.15), Color(0.7, 0.85, 1.0))
				"W":
					# Individual crowns need breathing room in the compressed depth view.
					# Forest production tiles remain unchanged; this is decoration density only.
					if y % 4 == 0 or template.terrain_at(c + Vector2i(0, -1)) != "W":
						_art(terrain_root, "tree", center + Vector3(sin(y) * 0.13, 0, 0), Vector3.ONE * 0.46, x + y)
				"Q", "#":
					_art(terrain_root, "rock", center, Vector3(1.0, 1.0, 0.8), x + y)
				"x":
					# 끊긴 길: 기울어진 널빤지
					box(terrain_root, Vector3(1.2, 0.06, 0.25), center + Vector3(0.0, 0.05, 0.0), Color(0.45, 0.33, 0.22), Vector3(0.0, 0.5, 0.15))
				"d":
					box(terrain_root, Vector3(CELL_W * 0.9, 0.05, 0.1), center + Vector3(0.0, 0.03, 0.0), Color(0.4, 0.5, 0.6))
				"e":
					box(terrain_root, Vector3(0.12, 0.9, 0.12), center + Vector3(-0.8, 0.45, 0.3), Color(0.5, 0.36, 0.22))
					box(terrain_root, Vector3(0.12, 0.9, 0.12), center + Vector3(0.8, 0.45, 0.3), Color(0.5, 0.36, 0.22))

# ------------------------------------------------------------------ 장애물

func _build_obstacle(c: Vector2i, ch: String) -> Node3D:
	var n := Node3D.new()
	n.position = cell_center_world(c)
	var seed_v := float(c.x * 7 + c.y * 13)
	match ch:
		"b":
			sphere(n, 0.34, Vector3(0.0, 0.28, 0.0), Color(0.36, 0.62, 0.3), Vector3(1.2, 0.8, 1.0))
			sphere(n, 0.22, Vector3(0.35, 0.22, 0.12), Color(0.42, 0.68, 0.34))
		"t":
			cyl(n, 0.1, 0.14, 0.7, Vector3(0.0, 0.35, 0.0), Color(0.45, 0.3, 0.17))
			sphere(n, 0.5, Vector3(0.0, 1.0, 0.0), Color(0.24, 0.55, 0.26), Vector3(1.0, 0.9, 0.9))
		"r":
			box(n, Vector3(1.0, 0.55, 0.5), Vector3(0.0, 0.27, 0.0), Color(0.58, 0.57, 0.55), Vector3(0.0, fmod(seed_v, 1.2), 0.0))
			box(n, Vector3(0.5, 0.35, 0.35), Vector3(0.45, 0.17, 0.1), Color(0.66, 0.64, 0.6), Vector3(0.0, 0.7, 0.0))
	return n

## 장애물: 남아 있는 것만 두고 정돈된 것은 제거한다.
func sync_obstacles(vs: VillageState, sim: VillageSim) -> void:
	var live := {}
	for y in VillageTemplate.HEIGHT:
		for x in VillageTemplate.WIDTH:
			var c := Vector2i(x, y)
			if not sim.has_obstacle(vs, c):
				continue
			var oid := VillageTemplate.obstacle_id(c)
			live[oid] = true
			if not obstacle_nodes.has(oid):
				var n := _build_obstacle(c, template.obstacle_at(c))
				obstacle_root.add_child(n)
				obstacle_nodes[oid] = n
	for oid in obstacle_nodes.keys():
		if not live.has(oid):
			obstacle_nodes[oid].queue_free()
			obstacle_nodes.erase(oid)

# ------------------------------------------------------------------ 건물

func kind_height(def: BuildingDef) -> float:
	return float(KIND_HEIGHT.get(String(def.kind), 1.0))

## 문 방향(회전): 0 남(+Z) / 1 서(-X) / 2 북(-Z) / 3 동(+X)
static func _door_dir(rot: int) -> Vector3:
	match posmod(rot, 4):
		0: return Vector3(0, 0, 1)
		1: return Vector3(-1, 0, 0)
		2: return Vector3(0, 0, -1)
	return Vector3(1, 0, 0)

## 건물 시각 노드. b: {def_id,x,y,rot,state,progress,fed} (미리보기도 같은 형식). water: compute_water 결과.
## alpha < 1 이면 반투명 재질로 만든다(미리보기·공사 중).
func build_building_visual(def: BuildingDef, b: Dictionary, water: Dictionary, alpha: float = 1.0, tint: Color = Color.WHITE) -> Node3D:
	var n := Node3D.new()
	var rot := int(b.get("rot", 0))
	var fp := def.footprint(rot)
	var w := fp.x * CELL_W
	var d := fp.y * CELL_D
	var origin := cell_to_world(Vector2(float(b.x), float(b.y)))
	n.position = origin + Vector3(w / 2.0, 0.0, d / 2.0)
	var under: bool = String(b.get("state", "complete")) == "construction"
	var col := func(c: Color) -> Color:
		var cc := Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a * alpha)
		return cc
	var art_alpha := alpha * (0.48 if under else 1.0)
	match String(def.kind):
		"farm":
			var growth := 0 if under else VillageSim.growth_stage(b, def)
			var planted := not under and float(b.get("progress", 0.0)) > 0.0
			var art_stage := growth + 1 if planted else 0
			_fit_art(n, "farm_%d" % art_stage, w, d, 0, art_alpha, tint)
			if not under:
				var watered := bool(water.get("farms", {}).get(int(b.get("id", 0)), {}).get("watered", false))
				# Existing water status marker stays legible above the detailed crop bed.
				sphere(n, 0.10, Vector3(-w / 2.0 + 0.28, 0.7, -d / 2.0 + 0.22), col.call(Color("85b9c2") if watered else Color("cb866d")))
				box(n, Vector3(0.035, 0.5, 0.035), Vector3(-w / 2.0 + 0.28, 0.25, -d / 2.0 + 0.22), col.call(GardenAssets.WOOD))
		"well":
			_fit_art(n, "well", w, d, rot, art_alpha, tint)
		"house":
			_fit_art(n, "cottage", w, d, rot, art_alpha, tint)
		"lumber", "quarry":
			_fit_art(n, String(def.kind), w, d, rot, art_alpha, tint)
		"road", "repair":
			_fit_art(n, String(def.kind), w, d, rot, art_alpha, tint)
		"canal":
			var c := Vector2i(int(b.x), int(b.y))
			var cell_comp: Dictionary = water.get("cell_component", {})
			var comps: Array = water.get("components", [])
			var wet := not under and cell_comp.has(c) and int(comps[cell_comp[c]].capacity) > 0
			var wc := GardenAssets.WATER if wet else GardenAssets.SOIL
			box(n, Vector3(w - 0.2, 0.08, d - 0.1), Vector3(0, 0.04, 0), col.call(GardenAssets.STONE))
			box(n, Vector3(w - 0.4, 0.035, d - 0.24), Vector3(0, 0.095, 0), col.call(wc))
			for sz in [-1.0, 1.0]:
				box(n, Vector3(w - 0.25, 0.10, 0.08), Vector3(0, 0.08, sz * (d * 0.5 - 0.08)), col.call(GardenAssets.CREAM))
		"dam":
			_fit_art(n, "dam", w, d, 0, art_alpha, tint)
			var wheel := _art(n, "wheel", Vector3(w * 0.5 - 0.85, 0.86, 0.31), Vector3.ONE, 0, art_alpha, tint)
			if not under and alpha >= 0.999: dam_wheels.append(wheel)
		_:
			_fit_art(n, "training" if def.facility_id == &"training_ground" else "shed", w, d, rot, art_alpha, tint)
	if under and alpha >= 0.999:
		# 공사 중: 네 귀퉁이 기둥 + 자재 더미 + 진행 높이(바람으로 짓는 중)
		var frac := clampf(float(b.get("work_done", 0.0)) / maxf(def.work_required, 0.001), 0.0, 1.0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				box(n, Vector3(0.08, 0.9, 0.08), Vector3(sx * (w / 2.0 - 0.12), 0.45, sz * (d / 2.0 - 0.1)), Color(0.95, 0.85, 0.5))
		box(n, Vector3(0.6, 0.3, 0.35), Vector3(-w / 2.0 + 0.5, 0.15, d / 2.0 + 0.05), Color(0.55, 0.4, 0.22))
		box(n, Vector3(w - 0.4, 0.05, d - 0.3), Vector3(0.0, 0.05 + 0.85 * frac, 0.0), Color(0.6, 0.9, 1.0, 0.55))
	return n

func _building_sig(b: Dictionary, def: BuildingDef, water: Dictionary) -> String:
	var stage := VillageSim.growth_stage(b, def) if def.kind == &"farm" else 0
	var watered := bool(water.get("farms", {}).get(int(b.id), {}).get("watered", false))
	var wet := ""
	if def.kind == &"canal":
		var c := Vector2i(int(b.x), int(b.y))
		var cell_comp: Dictionary = water.get("cell_component", {})
		wet = str(cell_comp.get(c, -1))
		for dd in VillageSim.DIRS:
			wet += "," + str(cell_comp.has(c + dd))
		if cell_comp.has(c):
			wet += "|" + str(int(water.components[cell_comp[c]].capacity) > 0)
	var frac := int(clampf(float(b.work_done) / maxf(def.work_required, 0.001), 0.0, 1.0) * 20.0)
	var seeded := float(b.progress) > 0.0
	return "%s|%d|%d|%d|%s|%d|%s|%s|%d" % [b.def_id, int(b.x), int(b.y), int(b.rot), b.state, stage, str(watered), wet, frac] + ("s" if seeded else "")

## 건물 노드를 상태 서명으로 갱신(변한 것만 다시 만든다).
func sync_buildings(vs: VillageState, sim: VillageSim, water: Dictionary) -> void:
	var live := {}
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		var def := sim.def_of(b)
		if def == null:
			continue
		live[id] = true
		var sig := _building_sig(b, def, water)
		var entry: Dictionary = building_nodes.get(id, {})
		if entry.is_empty() or entry.sig != sig:
			if not entry.is_empty():
				_remove_dam_wheels(entry.node)
				entry.node.queue_free()
			var n := build_building_visual(def, b, water)
			building_root.add_child(n)
			building_nodes[id] = {"node": n, "sig": sig, "def": def}
			if faded_ids.has(id):
				_apply_fade(n, true)
	for id in building_nodes.keys():
		if not live.has(id):
			_remove_dam_wheels(building_nodes[id].node)
			building_nodes[id].node.queue_free()
			building_nodes.erase(id)

func _remove_dam_wheels(n: Node3D) -> void:
	for i in range(dam_wheels.size() - 1, -1, -1):
		var w: Node3D = dam_wheels[i]
		if not is_instance_valid(w) or w.is_ancestor_of(n) or n.is_ancestor_of(w):
			dam_wheels.remove_at(i)

## 건물의 화면 사각형(선택·가림 계산). SubViewport 픽셀.
func building_screen_rect(b: Dictionary, def: BuildingDef) -> Rect2:
	var fp := def.footprint(int(b.rot))
	var x0 := float(b.x) * CELL_W
	var z0 := float(b.y) * CELL_D
	var x1 := x0 + fp.x * CELL_W
	var z1 := z0 + fp.y * CELL_D
	var h := kind_height(def)
	var rect := Rect2()
	var first := true
	for px in [x0, x1]:
		for py in [0.0, h]:
			for pz in [z0, z1]:
				var s := camera.unproject_position(Vector3(px, py, pz))
				if first:
					rect = Rect2(s, Vector2.ZERO)
					first = false
				else:
					rect = rect.expand(s)
	return rect

## 화면 픽셀에 보이는 건물 ID 목록(앞쪽 건물 먼저, 같은 깊이면 작은 것 먼저).
func pick_buildings(px: Vector2, vs: VillageState, sim: VillageSim) -> Array:
	var hits := []
	for id in vs.sorted_building_ids():
		var b: Dictionary = vs.buildings[id]
		var def := sim.def_of(b)
		var r := building_screen_rect(b, def)
		if r.has_point(px):
			hits.append({"id": id, "front": int(b.y) + def.footprint(int(b.rot)).y, "area": r.get_area()})
	hits.sort_custom(func(a, b2): return a.front > b2.front if a.front != b2.front else a.area < b2.area)
	var out := []
	for h in hits:
		out.append(int(h.id))
	return out

## 가림 완화: 지정 건물만 옅게, 나머지는 원래대로
func set_faded(ids: Array) -> void:
	var want := {}
	for id in ids:
		want[id] = true
	for id in building_nodes.keys():
		var now: bool = want.has(id)
		var was: bool = faded_ids.has(id)
		if now != was:
			_apply_fade(building_nodes[id].node, now)
	faded_ids = want

func _apply_fade(n: Node, faded: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.has_meta("garden_asset"):
			var base: StandardMaterial3D = c.get_meta("base_material")
			c.material_override = GardenAssets.material(0.3, base.albedo_color, base.cull_mode == BaseMaterial3D.CULL_DISABLED) if faded else base
		elif c is MeshInstance3D and c.has_meta("color"):
			var color: Color = c.get_meta("color")
			c.material_override = mat(Color(color.r, color.g, color.b, 0.3 if faded else color.a))
		_apply_fade(c, faded)

# ------------------------------------------------------------------ 선택·미리보기·물

func _footprint_marker(parent: Node3D, cells: Array, c: Color, y: float = 0.035) -> void:
	for cc in cells:
		var cell: Vector2i = cc
		if not template.in_bounds(cell):
			continue
		box(parent, Vector3(CELL_W * 0.92, 0.02, CELL_D * 0.86), cell_center_world(cell) + Vector3(0.0, y, 0.0), c)

func _frame_marker(parent: Node3D, x: int, y: int, fp: Vector2i, c: Color, thick: float = 0.08) -> void:
	var w := fp.x * CELL_W
	var d := fp.y * CELL_D
	var o := cell_to_world(Vector2(float(x), float(y)))
	box(parent, Vector3(w, 0.03, thick), o + Vector3(w / 2.0, 0.04, 0.0), c)
	box(parent, Vector3(w, 0.03, thick), o + Vector3(w / 2.0, 0.04, d), c)
	box(parent, Vector3(thick, 0.03, d), o + Vector3(0.0, 0.04, d / 2.0), c)
	box(parent, Vector3(thick, 0.03, d), o + Vector3(w, 0.04, d / 2.0), c)

## 선택 표시: 건물 테두리 + 작업 위치(문). obstacle_cell 이 있으면 장애물 칸 표시.
func sync_selection(vs: VillageState, sim: VillageSim, selected_id: int, obstacle_cell: Vector2i, target: Dictionary) -> void:
	var sig := "%d|%s|%s" % [selected_id, str(obstacle_cell), str(target)]
	if sig == select_sig:
		return
	select_sig = sig
	_clear_children(select_root)
	if selected_id != 0 and vs.has_building(selected_id):
		var b: Dictionary = vs.buildings[selected_id]
		var def := sim.def_of(b)
		_frame_marker(select_root, int(b.x), int(b.y), def.footprint(int(b.rot)), Color(1.0, 0.95, 0.5))
		if def.needs_door:
			_footprint_marker(select_root, [sim.work_cell(b)], Color(1.0, 0.95, 0.5, 0.6), 0.045)
	if obstacle_cell.x >= 0:
		_footprint_marker(select_root, [obstacle_cell], Color(1.0, 0.95, 0.5, 0.55), 0.045)
	if not target.is_empty():
		if target.kind == "obstacle":
			_frame_marker(select_root, target.cell.x, target.cell.y, Vector2i(1, 1), Color(1.0, 0.95, 0.4), 0.06)
		elif vs.has_building(int(target.id)):
			var tb: Dictionary = vs.buildings[int(target.id)]
			_frame_marker(select_root, int(tb.x), int(tb.y), sim.def_of(tb).footprint(int(tb.rot)), Color(1.0, 0.95, 0.4), 0.06)

## 미리보기: 반투명 건물 + 점유 바닥 + 작업 위치. preview: can_place 결과(cells, door, ok). def null 이면 지운다.
func sync_preview(def: BuildingDef, x: int, y: int, rot: int, preview: Dictionary, water: Dictionary, mode: String, canal_cells: Array) -> void:
	var sig := "%s|%d|%d|%d|%s|%s|%s" % [def.id if def else "", x, y, rot, str(preview.get("ok", false)), mode, str(canal_cells)]
	if sig == preview_sig:
		return
	preview_sig = sig
	_clear_children(preview_root)
	if def == null or preview.is_empty():
		return
	var ok: bool = preview.get("ok", false)
	var tint := Color(0.55, 1.0, 0.6) if ok else Color(1.0, 0.5, 0.5)
	var ground := Color(0.3, 1.0, 0.4, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	var cells: Array = preview.get("cells", [])
	_footprint_marker(preview_root, cells, ground)
	if mode == "canal":
		for cc in cells:
			var cell: Vector2i = cc
			var pb := {"def_id": String(def.id), "x": cell.x, "y": cell.y, "rot": 0, "state": "complete", "progress": 0.0, "work_done": 0.0, "id": 0}
			preview_root.add_child(build_building_visual(def, pb, {}, 0.5, tint))
		return
	if x < 0 or y < 0:
		return
	var pb := {"def_id": String(def.id), "x": x, "y": y, "rot": posmod(rot, 4), "state": "complete", "progress": 0.0, "work_done": 0.0, "id": 0}
	preview_root.add_child(build_building_visual(def, pb, {}, 0.5, tint))
	var door: Vector2i = preview.get("door", Vector2i(-1, -1))
	if def.needs_door and door.x >= 0:
		_footprint_marker(preview_root, [door], Color(1.0, 0.95, 0.5, 0.7), 0.045)

## 관개 보기: 연결망 칸을 색으로, 수원→농장 선을 표시
func sync_water_overlay(show: bool, vs: VillageState, sim: VillageSim, water: Dictionary) -> void:
	var sig := ""
	if show:
		sig = str(water.get("cell_component", {}).size()) + "|" + str(water.get("farms", {})) + "|" + str(water.get("components", []).size())
	if sig == water_sig:
		return
	water_sig = sig
	_clear_children(water_root)
	if not show:
		return
	var comps: Array = water.get("components", [])
	var cell_comp: Dictionary = water.get("cell_component", {})
	var colors := [Color(0.3, 0.7, 1.0), Color(0.4, 1.0, 0.9), Color(0.7, 0.6, 1.0), Color(1.0, 0.8, 0.4)]
	for c in cell_comp.keys():
		var idx: int = cell_comp[c]
		var comp: Dictionary = comps[idx]
		var col: Color = colors[idx % colors.size()] if int(comp.capacity) > 0 else Color(0.6, 0.6, 0.6)
		_footprint_marker(water_root, [c], Color(col.r, col.g, col.b, 0.45), 0.4)
	var farms: Dictionary = water.get("farms", {})
	for fid in farms.keys():
		var info: Dictionary = farms[fid]
		if int(info.component) < 0 or not vs.has_building(fid):
			continue
		var b: Dictionary = vs.buildings[fid]
		var comp: Dictionary = comps[int(info.component)]
		var col: Color = colors[int(info.component) % colors.size()]
		var fc := cell_to_world(Vector2(float(b.x) + 1.5, float(b.y) + 1.5)) + Vector3(0.0, 0.6, 0.0)
		for sid in comp.sources:
			if not vs.has_building(sid):
				continue
			var sb: Dictionary = vs.buildings[sid]
			var sfp := sim.def_of(sb).footprint(int(sb.rot))
			var sc := cell_to_world(Vector2(float(sb.x) + sfp.x / 2.0, float(sb.y) + sfp.y / 2.0)) + Vector3(0.0, 0.6, 0.0)
			_line(water_root, sc, fc, col, 0.06)

func _line(parent: Node3D, a: Vector3, b: Vector3, c: Color, thick: float) -> void:
	var mid := (a + b) / 2.0
	var len := a.distance_to(b)
	if len < 1e-3:
		return
	var mi := box(parent, Vector3(len, thick, thick), mid, c)
	mi.look_at_from_position(mid, b, Vector3.UP)
	mi.rotate_object_local(Vector3.UP, PI / 2.0)

# ------------------------------------------------------------------ 배우

func _build_player() -> void:
	player_node = Node3D.new()
	player_node.name = "Player"
	actor_root.add_child(player_node)
	player_body = Node3D.new()
	player_node.add_child(player_body)
	# 기존 임시 외형(붉은 몸·살색 머리)을 단순 메시로 재사용. 새 디자인 없음.
	box(player_body, Vector3(0.5, 0.75, 0.32), Vector3(0.0, 0.62, 0.0), Color(0.75, 0.2, 0.2))
	sphere(player_body, 0.24, Vector3(0.0, 1.22, 0.0), Color(0.98, 0.88, 0.75))
	box(player_body, Vector3(0.12, 0.7, 0.12), Vector3(0.36, 0.7, 0.05), Color(0.6, 0.6, 0.65), Vector3(0.0, 0.0, -0.4))
	box(player_body, Vector3(0.16, 0.28, 0.16), Vector3(-0.14, 0.14, 0.0), Color(0.25, 0.2, 0.2))
	box(player_body, Vector3(0.16, 0.28, 0.16), Vector3(0.14, 0.14, 0.0), Color(0.25, 0.2, 0.2))
	var sh := MeshInstance3D.new()
	sh.mesh = _cyl_mesh(0.34, 0.34, 0.02)
	sh.material_override = mat(Color(0.1, 0.1, 0.12, 0.28), true)
	sh.position = Vector3(0, 0.011, 0)
	player_node.add_child(sh)

func set_player(q: Vector2, facing: int, moving: bool, delta: float) -> void:
	player_node.position = cell_to_world(q)
	player_body.scale.x = 1.0 if facing >= 0 else -1.0
	anim_t += delta
	player_body.position.y = absf(sin(anim_t * 10.0)) * 0.08 if moving else 0.0

## 정령: 주민마다 1개체. 상태는 VillageSim.work_status 로 판단하며 여기서는 표시만 한다.
func sync_actors(vs: VillageState, sim: VillageSim, delta: float) -> void:
	var live := {}
	var idx := 0
	for vid in vs.sorted_villager_ids():
		live[vid] = true
		if not sim.actors.has(vid):
			idx += 1
			continue
		var a: Dictionary = sim.actors[vid]
		var node: SpiritActor3D = actor_nodes.get(vid, null)
		if node == null:
			node = SpiritActor3D.new()
			node.name = "Spirit%d" % vid
			node.build(vid, idx)
			actor_root.add_child(node)
			actor_nodes[vid] = node
			node.position = cell_to_world(a.pos)
			node.last_pos = node.position
		var target := cell_to_world(a.pos)
		node.position = target
		var st := sim.work_status(vs, vid)
		var look: Variant = null
		if st.target.x >= 0:
			look = cell_center_world(st.target)
		node.update_anim(delta, String(st.state), look)
		node.set_icon("blocked" if st.state == "blocked" else ("water" if st.state == "rest" else ""))
		_sync_wind(vid, node, st, vs, sim, delta)
		idx += 1
	for vid in actor_nodes.keys():
		if not live.has(vid):
			actor_nodes[vid].queue_free()
			actor_nodes.erase(vid)
			_remove_wind(vid)

# ------------------------------------------------------------------ 바람·수확 효과

func _ribbon_material() -> StandardMaterial3D:
	return mat(Color(0.92, 1.0, 0.96, 0.42), true)

func _sync_wind(vid: int, node: SpiritActor3D, st: Dictionary, vs: VillageState, sim: VillageSim, delta: float) -> void:
	var working: bool = st.state == "work" and node.windup_t >= 0.2 and st.target.x >= 0
	if not working:
		_remove_wind(vid)
		return
	var from := node.global_position + Vector3(0.0, SpiritActor3D.HOVER_Y, 0.0)
	var to := cell_center_world(st.target) + Vector3(0.0, 0.25, 0.0)
	var kind := String(vs.villagers[vid].job_kind)
	var particle_col := Color(0.95, 0.85, 0.45)   # 씨앗
	if kind == "farm" and sim.is_farm_watered(int(vs.villagers[vid].job_building)):
		particle_col = Color(0.45, 0.72, 1.0)       # 물방울
	elif kind == "clear":
		particle_col = Color(0.5, 0.8, 0.4)         # 잎
	elif kind == "build":
		particle_col = Color(0.85, 0.75, 0.55)
	var ribbon: MeshInstance3D = wind_ribbons.get(vid, null)
	if ribbon == null:
		ribbon = MeshInstance3D.new()
		ribbon.mesh = ImmediateMesh.new()
		ribbon.material_override = _ribbon_material()
		fx_root.add_child(ribbon)
		wind_ribbons[vid] = ribbon
		var parts: Array = []
		for k in 4:
			parts.append(sphere(fx_root, 0.06, from, particle_col))
		wind_particles[vid] = parts
	var im: ImmediateMesh = ribbon.mesh
	im.clear_surfaces()
	var dir := to - from
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * 0.18
	for line in 3:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var offset := float(line - 1) * 0.16
		for i in 13:
			var k := float(i) / 12.0
			var p := from.lerp(to, k)
			p.y += sin(k * PI) * 0.35 + sin(anim_t * 9.0 + k * 9.0 + line) * 0.07
			p += side * (offset + sin(anim_t * 6.0 + k * 7.0 + line * 2.0) * 0.35)
			var width := 0.05 * (1.0 - absf(k - 0.5) * 1.2)
			im.surface_add_vertex(p + Vector3(0.0, width, 0.0))
			im.surface_add_vertex(p - Vector3(0.0, width, 0.0))
		im.surface_end()
	var parts: Array = wind_particles[vid]
	for k in parts.size():
		var mi: MeshInstance3D = parts[k]
		var ph := fmod(anim_t * 0.9 + float(k) * 0.25 + float(vid) * 0.1, 1.0)
		var p := from.lerp(to, ph)
		p.y += sin(ph * PI) * 0.45
		p += side * sin(ph * 6.0 + k) * 0.4
		mi.position = p
		mi.material_override = mat(particle_col)

func _remove_wind(vid: int) -> void:
	if wind_ribbons.has(vid):
		wind_ribbons[vid].queue_free()
		wind_ribbons.erase(vid)
	if wind_particles.has(vid):
		for p in wind_particles[vid]:
			p.queue_free()
		wind_particles.erase(vid)

## 수확: 밭의 이삭이 낮게 떠서 바구니로 모이고 정령이 짧게 기뻐한다(보상은 이미 확정된 이벤트에만 반응).
func play_harvest(b: Dictionary, def: BuildingDef, villager_id: int) -> void:
	var fp := def.footprint(int(b.rot))
	var w := fp.x * CELL_W
	var d := fp.y * CELL_D
	var origin := cell_to_world(Vector2(float(b.x), float(b.y)))
	var basket := origin + Vector3(w - 0.35, 0.45, d - 0.28)
	var items: Array = []
	var froms: Array = []
	for k in 6:
		var p := origin + Vector3(0.5 + (w - 1.0) * float(k % 3 + 0.5) / 3.0, 0.7, d * float(k / 3 + 0.5) / 2.0)
		items.append(sphere(fx_root, 0.1, p, Color(0.92, 0.78, 0.3)))
		froms.append(p)
	harvest_fx.append({"items": items, "from": froms, "to": basket, "t": 0.0})
	if actor_nodes.has(villager_id):
		actor_nodes[villager_id].play_harvest()

func update_fx(delta: float) -> void:
	for w in dam_wheels:
		if is_instance_valid(w):
			w.rotate_object_local(Vector3.FORWARD, delta * 1.5)
	for i in range(harvest_fx.size() - 1, -1, -1):
		var fx: Dictionary = harvest_fx[i]
		fx.t += delta
		var k: float = clampf(fx.t / 1.2, 0.0, 1.0)
		for j in fx.items.size():
			var mi: MeshInstance3D = fx.items[j]
			var kk: float = clampf(k * 1.3 - float(j) * 0.05, 0.0, 1.0)
			var p: Vector3 = (fx.from[j] as Vector3).lerp(fx.to, kk)
			p.y += sin(kk * PI) * 0.5
			mi.position = p
		if k >= 1.0:
			for mi in fx.items:
				mi.queue_free()
			harvest_fx.remove_at(i)

## 마을 퇴장: 효과·배우·미리보기를 정리한다(부모가 노드를 지우기 전에 호출해도 안전).
func clear_all() -> void:
	for vid in wind_ribbons.keys():
		_remove_wind(vid)
	for fx in harvest_fx:
		for mi in fx.items:
			mi.queue_free()
	harvest_fx.clear()
	_clear_children(preview_root)
	_clear_children(select_root)
	_clear_children(water_root)
	preview_sig = ""
	select_sig = ""
	water_sig = ""

# ------------------------------------------------------------------ 정원 배경 (장식 전용, 논리 격자/입력/통행에 참여하지 않음)

func _build_backdrop() -> void:
	_clear_children(backdrop_root)
	box(backdrop_root, Vector3(180, 0.2, 150), Vector3(MAP_W_UNITS * 0.5, -0.24, -24), Color("94a576"))
	var distant := Node3D.new()
	distant.name = "DistantHills"
	backdrop_root.add_child(distant)
	for i in 7:
		sphere(distant, 1.0, Vector3(-42.0 + i * 18.0, -3.7, -10.0), Color("a8bbb1") if i % 2 == 0 else Color("b5c6bb"), Vector3(16, 4.6 + (i % 3) * 0.25, 4))
	for i in 6:
		sphere(distant, 1.0, Vector3(-30.0 + i * 17, -3.3, -5.8), Color("9cac81"), Vector3(12, 4.1, 3))
	var grove := Node3D.new()
	grove.name = "GardenGrove"
	backdrop_root.add_child(grove)
	var xs := [-12.0, -7.0, -2.4, 2.8, 7.7, 12.8, 17.0, 27.0, 32.8, 38.0, 43.0]
	for i in xs.size():
		var sc := 0.77 + (i % 3) * 0.07
		_art(grove, "flower_tree" if i % 3 == 0 else "tree", Vector3(xs[i], -0.13, -3.1 - (i % 2) * 0.65), Vector3(sc, sc, sc), i)
	# Landmark greenhouse and garden shed stay behind the buildable boundary.
	_art(grove, "greenhouse", Vector3(22.1, -0.06, -2.1), Vector3(1.0, 1.0, 0.88))
	_art(grove, "shed", Vector3(-4.5, -0.06, -2.0), Vector3(0.82, 0.82, 0.8))
	var fence := Node3D.new()
	fence.name = "GardenFence"
	backdrop_root.add_child(fence)
	for i in 17:
		_art(fence, "fence", Vector3(-1.0 + i * 2.0, -0.1, -0.38), Vector3(1, 0.84, 1))
	var flowers := Node3D.new()
	flowers.name = "BorderFlowers"
	backdrop_root.add_child(flowers)
	for i in 13:
		_art(flowers, "planter", Vector3(0.8 + i * 2.65, -0.1, -0.94), Vector3(0.85, 0.85, 0.78), i)
	for x in [3.2, 15.8, 28.8]:
		_art(flowers, "lantern", Vector3(x, 0, -0.7), Vector3(0.72, 0.72, 0.72))
	_art(flowers, "cloud_sign", Vector3(20.0, 0, -0.58), Vector3(0.7, 0.7, 0.7))
	# Small edge stones and flowers replace square cliff blocks; they never become clearing jobs.
	for side in [-1.0, 1.0]:
		var x := -1.25 if side < 0 else MAP_W_UNITS + 1.25
		for i in 4:
			_art(flowers, "rock", Vector3(x, -0.05, 1.0 + i * 2.4), Vector3(0.8, 0.8, 0.8), i)
			_art(flowers, "planter", Vector3(x, -0.06, 2.2 + i * 2.4), Vector3(0.75, 0.8, 0.75), i)
