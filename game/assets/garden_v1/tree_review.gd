extends Node3D
## F6 in scenes/tree_review.tscn. Drag to orbit; wheel to zoom.
## Uses the same mesh and material factory as the village, without writing saves.
var camera: Camera3D
var yaw := 0.0
var pitch := 0.16
var distance := 7.0

func _ready() -> void:
	add_child(GardenAssets.make("tree"))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position.y = -0.031
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c6b69f")
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-49, -32, 0)
	sun.light_color = Color("fff0d2")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 22.0
	sun.shadow_bias = 0.025
	sun.shadow_normal_bias = 0.30
	add_child(sun)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("c6b69f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d4d0")
	env.ambient_light_energy = 0.55
	world.environment = env
	add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	camera.current = true
	add_child(camera)
	_camera_pose()

func _camera_pose() -> void:
	var center := Vector3(0, 1.46, 0)
	camera.position = center + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(center)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.007
		pitch = clampf(pitch + event.relative.y * 0.005, -0.08, 1.1)
		_camera_pose()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(1.1, camera.size * 0.90)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(6.0, camera.size / 0.90)
