class_name SpiritActor3D
extends Node3D
## 승인된 Tripo 정령 모델을 사용한다. 마을 논리·작업 상태는 VillageSim에 남긴다.
## 모델은 공유하고, 개체별 Skeleton3D 포즈만 변경한다. 원본 앞면 +Z를 게임 +X로 맞춘다.

const MODEL: PackedScene = preload("res://assets/wind_spirit/spirit.glb")
const HOVER_Y := 0.29

var villager_id: int = 0
var state: String = "idle"       ## idle/move/windup/work/harvest/blocked/rest
var body: Node3D
var model: Node3D
var skeleton: Skeleton3D
var bone_head: int
var bone_wing_l: int
var bone_wing_r: int
var bone_tail: int
var shadow: MeshInstance3D
var icon: MeshInstance3D          ## 상태 아이콘(막힘 !, 물 부족 물방울)
var icon_kind: String = ""
var t: float = 0.0
var phase: float = 0.0            ## 개체마다 다른 위상
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

static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi

func build(p_villager_id: int, _accessory: int) -> void:
	villager_id = p_villager_id
	phase = float(p_villager_id) * 1.7
	body = Node3D.new()
	body.name = "AnimatedBody"
	body.position = Vector3(0, HOVER_Y, 0)
	add_child(body)
	model = MODEL.instantiate()
	model.name = "ApprovedSpirit"
	model.rotation.y = PI * 0.5
	model.position = Vector3(-0.15, 0.015 - HOVER_Y, -0.081)
	body.add_child(model)
	skeleton = _find_skeleton(model)
	assert(skeleton != null, "Approved spirit requires its imported rig")
	bone_head = skeleton.find_bone("Head")
	bone_wing_l = skeleton.find_bone("WingLeft")
	bone_wing_r = skeleton.find_bone("WingRight")
	bone_tail = skeleton.find_bone("Tail")
	assert(mini(mini(bone_head, bone_tail), mini(bone_wing_l, bone_wing_r)) >= 0)
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

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

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
	var tail_sway := sin(t * 2.2 + phase) * 0.08
	var y := HOVER_Y
	var squash := 1.0
	var wing_rot := 0.015 + sin(t * 4.0 + phase) * 0.015
	var wing_back := 0.0
	if harvest_t > 0.0:
		harvest_t -= delta
		var k := clampf(harvest_t / 1.2, 0.0, 1.0)
		y += absf(sin((1.0 - k) * PI * 2.0)) * 0.24 * k
		wing_rot = 0.28 + sin(t * 24.0) * 0.24
		body.rotation.z = 0.0
	else:
		match state:
			"move":
				# 통통 뛰기: 착지 때 5~8% 눌림, 꼬리는 늦게 따라온다
				move_bob += delta * 9.0
				var hop := absf(sin(move_bob))
				y += hop * 0.22
				squash = 1.0 - (1.0 - hop) * 0.07
				tail_sway = sin(move_bob - 0.8) * 0.13
				wing_rot = 0.04 + hop * 0.15
				body.rotation.z = -0.12
			"windup", "work":
				windup_t += delta
				if windup_t < 0.2:
					# 모으기: 몸을 웅크리고 날개를 뒤로
					squash = 0.92
					wing_back = -0.06
					wing_rot = 0.015
				else:
					# 날개 펴고 바람 보내기(0.6초 펴기 / 0.3초 풀기를 반복)
					var cyc := fmod(windup_t - 0.2, 0.9)
					var spread: float = clampf(cyc / 0.6, 0.0, 1.0) if cyc < 0.6 else 1.0 - (cyc - 0.6) / 0.3
					wing_rot = 0.04 + spread * 0.52
					wing_back = 0.06 * spread
					y += spread * 0.06
					squash = 1.0 + spread * 0.03
				body.rotation.z = 0.0
			"blocked":
				# 고개 갸웃
				body.rotation.z = sin(t * 2.0 + phase) * 0.25
				y -= 0.005
			"rest":
				# 앉아서 쉼
				y -= 0.03
				squash = 0.95
				body.rotation.z = 0.0
				wing_rot = 0.0
			_:
				body.rotation.z = lerpf(body.rotation.z, 0.0, delta * 5.0)
				if fmod(t + phase, 5.0) > 4.5:
					# 잠깐 주변 보기
					body.rotation.y = sin(t * 3.0) * 0.4
				else:
					body.rotation.y = lerpf(body.rotation.y, 0.0, delta * 4.0)
	body.position.y = y
	body.scale = Vector3(breath * (2.0 - squash), squash, breath * (2.0 - squash))
	# 날개를 분리하지 않고 부드러운 가중치로 움직여 어깨가 벌어지지 않게 한다.
	skeleton.set_bone_pose_rotation(bone_wing_l, Quaternion.from_euler(Vector3(0, wing_back, wing_rot)))
	skeleton.set_bone_pose_rotation(bone_wing_r, Quaternion.from_euler(Vector3(0, -wing_back, -wing_rot)))
	skeleton.set_bone_pose_rotation(bone_tail, Quaternion.from_euler(Vector3(sin(t * 1.3 + phase) * 0.045, tail_sway, 0)))
	var head_tilt := sin(t * 2.0 + phase) * 0.12 if state == "blocked" else sin(t * 1.4 + phase) * 0.025
	skeleton.set_bone_pose_rotation(bone_head, Quaternion.from_euler(Vector3(0, 0, head_tilt)))
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
