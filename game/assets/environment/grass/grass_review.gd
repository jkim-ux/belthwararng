extends Node3D
## HWR-GRASS-001 review scene: baked grass tiles under the real village camera, light and renderer.
## Open scenes/grass_review.tscn and press F6, or: godot --path game assets/environment/grass/grass_review.tscn
## Keys: 1 single  2 2x2  3 4x4 (16)  4 village cells (150)  5 all cells (192)
##       V village camera  C close  T top  B overview     W wind on/off  - / = wind strength
##       O original 1.93M-tri source beside the tile (single layout, loads from source_assets/)
##       S shadows  F vsync  H help/stats overlay  R rebuild with a new seed
## Uses only GrassTile / GrassField; no game state, no saves.

const SOURCE_GLB := "../source_assets/environments/tiles/grass block 3d model.glb"
const TEMPLATE := "res://data/village/ch1_farm_template.tres"
const GRASS_TERRAIN := [".", "W", "e"]
const LAYOUTS := ["single", "grid2", "grid4", "village", "full"]
const FRAME_WINDOW := 120

var field: GrassField
var camera: Camera3D
var light: DirectionalLight3D
var original: Node3D
var label: Label
var layout := "grid4"
var camera_preset := "village"
var wind_on := true
var wind_strength := 1.0
var seed_value := 7
var _frame_times: PackedFloat64Array = PackedFloat64Array()
var _last_tick := 0
var _cells: Array = []
var _cell_w := 2.0
var _cell_d := 0.9
var _y0_source := 0.0559
var _source_scale := 2.1978


func _ready() -> void:
	_cell_w = VillageStage3D.CELL_W
	_cell_d = VillageStage3D.CELL_D
	_read_manifest()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	camera.current = true
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	light.light_color = Color(1.0, 0.97, 0.9)
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = VillageStage3D.BACKGROUND_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.93, 0.91, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	field = GrassField.new()
	field.name = "Field"
	add_child(field)
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12))
	label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	ui.add_child(label)
	set_layout(layout)
	set_wind(wind_on, wind_strength)
	_last_tick = Time.get_ticks_usec()


func _read_manifest() -> void:
	var f := FileAccess.open("res://assets/environment/grass/grass_manifest.json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_y0_source = float(d.get("source_y_reference", _y0_source))
		_source_scale = float(d.get("source_to_world_scale", _source_scale))


# ------------------------------------------------------------------ layouts / camera

func cells_for(name: String) -> Array:
	var out: Array = []
	match name:
		"single":
			out.append(Vector2i(0, 0))
		"grid2":
			for y in 2:
				for x in 2:
					out.append(Vector2i(x, y))
		"grid4":
			for y in 4:
				for x in 4:
					out.append(Vector2i(x, y))
		"village":
			var t: VillageTemplate = load(TEMPLATE)
			if t == null:
				return cells_for("full")
			for y in VillageTemplate.HEIGHT:
				for x in VillageTemplate.WIDTH:
					if GRASS_TERRAIN.has(t.terrain_at(Vector2i(x, y))):
						out.append(Vector2i(x, y))
		"full":
			for y in VillageTemplate.HEIGHT:
				for x in VillageTemplate.WIDTH:
					out.append(Vector2i(x, y))
	return out


func set_layout(name: String) -> void:
	layout = name
	_cells = cells_for(name)
	field.build(_cells, _cell_w, _cell_d, seed_value)
	set_camera_preset(camera_preset)


func layout_bounds() -> Rect2:
	var r := Rect2()
	for i in _cells.size():
		var c: Vector2i = _cells[i]
		var cr := Rect2(c.x * _cell_w, c.y * _cell_d, _cell_w, _cell_d)
		r = cr if i == 0 else r.merge(cr)
	return r


## Same contract as VillageStage3D.set_camera: orthographic, PITCH_DEG down, CAM_DIST back along +Z.
func set_camera_preset(name: String) -> void:
	camera_preset = name
	var b := layout_bounds()
	var center := Vector3(b.get_center().x, 0.0, b.get_center().y)
	var pitch := deg_to_rad(VillageStage3D.PITCH_DEG)
	var size := VillageStage3D.ORTHO_SIZE
	match name:
		"close":
			size = 2.6
		"top":
			pitch = deg_to_rad(89.0)
			size = maxf(b.size.y * 1.15, 2.0)
		"overview":
			size = maxf(b.size.x * 0.62, 6.0)
		_:
			size = VillageStage3D.ORTHO_SIZE
	if original != null and layout == "single":
		center.x -= 1.3
		size = minf(size, 3.2)
	camera.size = size
	camera.position = center + Vector3(0.0, VillageStage3D.CAM_DIST * sin(pitch), VillageStage3D.CAM_DIST * cos(pitch))
	camera.rotation = Vector3(-pitch, 0.0, 0.0)


# ------------------------------------------------------------------ wind / shadows / original

func set_wind(on: bool, strength: float) -> void:
	wind_on = on
	wind_strength = strength
	GrassTile.set_wind(strength if on else 0.0)


func set_shadows(on: bool) -> void:
	light.shadow_enabled = on
	field.set_cast_shadows(on)


## Loads the untouched Tripo source (1.93M triangles) next to the tile with the same scale/offset
## as the bake, so both are seen under one camera and light. Returns false if the file is absent.
func show_original(on: bool) -> bool:
	if original != null:
		original.queue_free()
		original = null
	if on:
		var path := ProjectSettings.globalize_path("res://").path_join(SOURCE_GLB)
		if not FileAccess.file_exists(path):
			push_warning("original not found: " + path)
			set_camera_preset(camera_preset)
			return false
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(path, state)
		if err != OK:
			push_warning("original load failed: %d" % err)
			return false
		original = doc.generate_scene(state)
		original.name = "Original"
		original.position = Vector3(_cell_w * 0.5 - 2.6, -_y0_source * _source_scale, _cell_d * 0.5)
		original.scale = Vector3.ONE * _source_scale
		add_child(original)
	set_camera_preset(camera_preset)
	return true


# ------------------------------------------------------------------ stats

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frame_times.append(float(now - _last_tick) / 1000.0)
	_last_tick = now
	if _frame_times.size() > FRAME_WINDOW:
		_frame_times = _frame_times.slice(_frame_times.size() - FRAME_WINDOW)
	if label.visible:
		label.text = describe()


func reset_frame_stats() -> void:
	_frame_times = PackedFloat64Array()
	_last_tick = Time.get_ticks_usec()


func stats() -> Dictionary:
	var times := _frame_times.duplicate()
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg = avg / maxf(times.size(), 1.0)
	var p95 := times[int(floor((times.size() - 1) * 0.95))] if times.size() > 0 else 0.0
	return {
		"layout": layout, "camera": camera_preset, "tiles": field.tile_count(), "multimeshes": field.multimesh_count(),
		"wind": wind_strength if wind_on else 0.0, "shadows": light.shadow_enabled, "original": original != null,
		"fps": Engine.get_frames_per_second(), "frame_ms_avg": snappedf(avg, 0.01), "frame_ms_p95": snappedf(p95, 0.01),
		"frame_samples": times.size(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"window": DisplayServer.window_get_size(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
	}


func describe() -> String:
	var s := stats()
	return ("HWR-GRASS-001 review  %s | %s  tiles %d  multimesh %d\n" % [s.layout, s.camera, s.tiles, s.multimeshes]
		+ "%d fps  %.2f ms avg  %.2f ms p95  draw %d  prims %d  vram %.1f MB (tex %.1f)\n" % [s.fps, s.frame_ms_avg, s.frame_ms_p95, s.draw_calls, s.primitives, s.video_mem_mb, s.texture_mem_mb]
		+ "wind %.2f  shadows %s  vsync %s  original %s  %s / %s\n" % [s.wind, s.shadows, s.vsync, s.original, s.renderer, s.gpu]
		+ "1-5 layout  V/C/T/B camera  W wind  -/= strength  O original  S shadows  F vsync  R reseed  H hide")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: set_layout("single")
		KEY_2: set_layout("grid2")
		KEY_3: set_layout("grid4")
		KEY_4: set_layout("village")
		KEY_5: set_layout("full")
		KEY_V: set_camera_preset("village")
		KEY_C: set_camera_preset("close")
		KEY_T: set_camera_preset("top")
		KEY_B: set_camera_preset("overview")
		KEY_W: set_wind(not wind_on, wind_strength)
		KEY_MINUS: set_wind(wind_on, maxf(0.0, wind_strength - 0.25))
		KEY_EQUAL: set_wind(wind_on, minf(3.0, wind_strength + 0.25))
		KEY_O: show_original(original == null)
		KEY_S: set_shadows(not light.shadow_enabled)
		KEY_F:
			var off := DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if off else DisplayServer.VSYNC_DISABLED)
			reset_frame_stats()
		KEY_H: label.visible = not label.visible
		KEY_R:
			seed_value += 1
			set_layout(layout)
