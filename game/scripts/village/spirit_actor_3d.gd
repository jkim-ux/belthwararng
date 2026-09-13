class_name SpiritActor3D
extends Node3D
## 흰 오목눈이 바람 정령 1개체의 외형과 동작(HWR-006 A 잎사귀 텃밭 기본). 논리 상태는 VillageSim 이 갖고,
## 이 노드는 부모(VillageStage3D)가 매 프레임 넘겨주는 상태·위치로 몸·날개·꼬리 피벗을 회전/스케일한다.
## 스켈레톤 없이 구/상자 메시로 만든 재사용 장면이며 나중에 .glb 로 바꿀 수 있도록 논리 ID(villager_id)와 분리한다.
## 떠오름/점프는 표시 애니메이션이며 실제 위치(바닥 X/Z)는 부모가 정한다. 접지 그림자는 바닥에 따로 둔다.

const BODY_R := 0.32
const HOVER_Y := 0.34            ## 몸 중심의 기본 높이(바닥 위)
const ACCESSORIES := ["leaf", "knot", "straw"]

var villager_id: int = 0
var state: String = "idle"       ## idle/move/windup/work/harvest/blocked/rest
var body: Node3D
var body_mesh: MeshInstance3D
var wing_l: Node3D
var wing_r: Node3D
var tail: Node3D
var eye_l: MeshInstance3D
var eye_r: MeshInstance3D
var shadow: MeshInstance3D
var icon: MeshInstance3D          ## 상태 아이콘(막힘 !, 물 부족 물방울)
var icon_kind: String = ""
var t: float = 0.0
var phase: float = 0.0            ## 개체마다 다른 위상
var blink_t: float = 0.0
var harvest_t: float = -1.0       ## 수확 기쁨 동작 남은 시간
var windup_t: float = 0.0         ## 작업 시작 후 경과(0.2초 모으기)
var move_bob: float = 0.0
var facing: float = 0.0           ## 바라보는 방향(라디안, +X 기준)
var last_pos: Vector3 = Vector3.ZERO

static func _mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func _sphere(parent: Node3D, r: float, pos: Vector3, c: Color, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = _mat(c)
	mi.position = pos
	mi.scale = sc
	parent.add_child(mi)
	return mi

static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi

func build(p_villager_id: int, accessory: int) -> void:
	villager_id = p_villager_id
	phase = float(p_villager_id) * 1.7
	body = Node3D.new()
	body.position = Vector3(0, HOVER_Y, 0)
	add_child(body)
	var white := Color(0.97, 0.96, 0.93)
	var grey := Color(0.62, 0.6, 0.58)
	body_mesh = _sphere(body, BODY_R, Vector3.ZERO, white, Vector3(1.0, 0.92, 0.95))
	# 눈·부리(정면 +X 방향을 앞으로 본다)
	eye_l = _sphere(body, 0.035, Vector3(0.24, 0.08, 0.12), Color(0.08, 0.08, 0.1))
	eye_r = _sphere(body, 0.035, Vector3(0.24, 0.08, -0.12), Color(0.08, 0.08, 0.1))
	_box(body, Vector3(0.09, 0.05, 0.06), Vector3(0.32, 0.0, 0.0), Color(0.25, 0.22, 0.2))
	# 날개(어깨 피벗)
	wing_l = Node3D.new()
	wing_l.position = Vector3(0.0, 0.02, 0.24)
	body.add_child(wing_l)
	_box(wing_l, Vector3(0.28, 0.05, 0.2), Vector3(-0.04, 0.0, 0.1), grey)
	wing_r = Node3D.new()
	wing_r.position = Vector3(0.0, 0.02, -0.24)
	body.add_child(wing_r)
	_box(wing_r, Vector3(0.28, 0.05, 0.2), Vector3(-0.04, 0.0, -0.1), grey)
	# 긴 꼬리(뒤쪽 피벗, 몸통 길이 정도)
	tail = Node3D.new()
	tail.position = Vector3(-0.26, -0.02, 0.0)
	body.add_child(tail)
	_box(tail, Vector3(0.36, 0.045, 0.07), Vector3(-0.18, 0.0, 0.03), grey)
	_box(tail, Vector3(0.36, 0.045, 0.07), Vector3(-0.18, 0.0, -0.03), Color(0.7, 0.68, 0.66))
	# 작은 발
	_box(body, Vector3(0.08, 0.04, 0.05), Vector3(0.05, -0.31, 0.08), Color(0.55, 0.42, 0.3))
	_box(body, Vector3(0.08, 0.04, 0.05), Vector3(0.05, -0.31, -0.08), Color(0.55, 0.42, 0.3))
	# 액세서리(잎/물 매듭/짚 매듭) — 역할 제한이 아니라 외형 변주
	match ACCESSORIES[posmod(accessory, ACCESSORIES.size())]:
		"leaf":
			var leaf := _box(body, Vector3(0.16, 0.02, 0.09), Vector3(-0.02, 0.32, 0.04), Color(0.4, 0.72, 0.36))
			leaf.rotation = Vector3(0.0, 0.5, 0.35)
		"knot":
			_sphere(body, 0.06, Vector3(0.18, -0.16, 0.0), Color(0.42, 0.68, 0.92))
		"straw":
			_box(body, Vector3(0.05, 0.05, 0.22), Vector3(0.0, 0.3, 0.0), Color(0.88, 0.76, 0.42))
	# 접지 그림자(바닥에 고정, 떠오름과 분리)
	shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.02
	cm.radial_segments = 16
	shadow.mesh = cm
	shadow.material_override = _mat(Color(0.1, 0.1, 0.12, 0.28), true)
	shadow.position = Vector3(0, 0.011, 0)
	add_child(shadow)
	# 상태 아이콘(머리 위, 필요할 때만)
	icon = _box(self, Vector3(0.08, 0.26, 0.08), Vector3(0.0, 1.05, 0.0), Color(1.0, 0.85, 0.3))
	icon.material_override = _mat(Color(1.0, 0.85, 0.3), true)
	icon.visible = false

func play_harvest() -> void:
	harvest_t = 1.2

## 매 프레임 갱신. p_state: VillageSim.work_status 의 state, look_at_pos: 작업/이동 대상(월드, 없으면 null)
func update_anim(delta: float, p_state: String, look_at_pos: Variant) -> void:
	t += delta
	if p_state != state:
		if p_state == "work":
			windup_t = 0.0
		state = p_state
	# 바라보는 방향: 이동 벡터 또는 대상 방향
	var moved := global_position - last_pos
	if moved.length() > 0.001:
		facing = atan2(-moved.z, moved.x)
	elif look_at_pos != null:
		var d: Vector3 = (look_at_pos as Vector3) - global_position
		if d.length() > 0.05:
			facing = atan2(-d.z, d.x)
	last_pos = global_position
	rotation.y = lerp_angle(rotation.y, facing, minf(1.0, delta * 10.0))
	# 기본 호흡·꼬리
	var breath := 1.0 + sin(t * 3.0 + phase) * 0.02
	var tail_sway := sin(t * 2.2 + phase) * 0.18
	var y := HOVER_Y
	var squash := 1.0
	var wing_rot := 0.15 + sin(t * 4.0 + phase) * 0.08
	var wing_back := 0.0
	if harvest_t > 0.0:
		harvest_t -= delta
		var k := clampf(harvest_t / 1.2, 0.0, 1.0)
		y += sin((1.0 - k) * PI * 2.0) * 0.28 * k + 0.05
		wing_rot = 0.9 + sin(t * 30.0) * 0.4
		rotation.y += (1.0 - k) * 0.0   # 회전 대신 짧은 점프·날갯짓
	else:
		match state:
			"move":
				# 통통 뛰기: 착지 때 5~8% 눌림, 꼬리는 늦게 따라온다
				move_bob += delta * 9.0
				var hop := absf(sin(move_bob))
				y += hop * 0.22
				squash = 1.0 - (1.0 - hop) * 0.07
				tail_sway = sin(move_bob - 0.8) * 0.25
				wing_rot = 0.35 + hop * 0.3
				body.rotation.z = -0.12
			"windup", "work":
				windup_t += delta
				if windup_t < 0.2:
					# 모으기: 몸을 웅크리고 날개를 뒤로
					squash = 0.92
					wing_back = -0.6
					wing_rot = 0.1
				else:
					# 날개 펴고 바람 보내기(0.6초 펴기 / 0.3초 풀기를 반복)
					var cyc := fmod(windup_t - 0.2, 0.9)
					var spread: float = clampf(cyc / 0.6, 0.0, 1.0) if cyc < 0.6 else 1.0 - (cyc - 0.6) / 0.3
					wing_rot = 0.2 + spread * 1.1
					wing_back = 0.2 * spread
					y += spread * 0.06
					squash = 1.0 + spread * 0.03
				body.rotation.z = 0.0
			"blocked":
				# 고개 갸웃
				body.rotation.z = sin(t * 2.0 + phase) * 0.25
				y -= 0.04
			"rest":
				# 앉아서 쉼
				y -= 0.12
				squash = 0.95
				body.rotation.z = 0.0
				wing_rot = 0.05
			_:
				body.rotation.z = lerpf(body.rotation.z, 0.0, delta * 5.0)
				if fmod(t + phase, 5.0) > 4.5:
					# 잠깐 주변 보기
					body.rotation.y = sin(t * 3.0) * 0.4
				else:
					body.rotation.y = lerpf(body.rotation.y, 0.0, delta * 4.0)
	body.position.y = y
	body.scale = Vector3(breath * (2.0 - squash), squash, breath * (2.0 - squash))
	wing_l.rotation = Vector3(wing_rot, wing_back, 0.0)
	wing_r.rotation = Vector3(-wing_rot, -wing_back, 0.0)
	tail.rotation = Vector3(0.0, tail_sway, 0.08 + sin(t * 1.3 + phase) * 0.06)
	# 눈 깜박임(무작위 순간)
	blink_t -= delta
	if blink_t <= 0.0:
		blink_t = 2.5 + fmod(absf(sin(t * 7.0 + phase)) * 3.0, 3.0)
	var blink: float = 0.15 if blink_t < 0.12 else 1.0
	eye_l.scale = Vector3(1.0, blink, 1.0)
	eye_r.scale = Vector3(1.0, blink, 1.0)
	# 그림자: 떠오를수록 작고 옅게
	var lift: float = clampf((y - HOVER_Y) / 0.4, 0.0, 1.0)
	shadow.scale = Vector3(1.0 - lift * 0.35, 1.0, 1.0 - lift * 0.35)

func set_icon(kind: String) -> void:
	if kind == icon_kind:
		return
	icon_kind = kind
	icon.visible = kind != ""
	match kind:
		"blocked":
			icon.material_override = _mat(Color(1.0, 0.75, 0.25), true)
			icon.scale = Vector3(1.0, 1.0, 1.0)
		"water":
			icon.material_override = _mat(Color(0.35, 0.65, 1.0), true)
			icon.scale = Vector3(1.6, 0.6, 1.6)
