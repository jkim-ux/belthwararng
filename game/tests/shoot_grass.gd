extends SceneTree
## HWR-GRASS-001 captures + performance table from the real review scene (needs a window / GPU).
##   godot --path game -s tests/shoot_grass.gd                       -> reports/HWR-GRASS-001_*.png + _perf.json
##   godot --path game --fixed-fps 24 -s tests/shoot_grass.gd -- --movie=/tmp/grass_frames   -> JPEG frames (wind)
##   ffmpeg -framerate 24 -i /tmp/grass_frames/f_%04d.jpg -pix_fmt yuv420p reports/HWR-GRASS-001_wind.mp4
## Writes only under reports/ (and the movie dir). Never touches user saves.

const WARMUP := 30
const SAMPLE := 240
const MOVIE_FRAMES := 168

var out_dir := ProjectSettings.globalize_path("res://").path_join("../reports")
var review: Node3D
var movie_dir := ""
var results: Array = []
var quick := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--movie="):
			movie_dir = a.trim_prefix("--movie=")
		if a == "--quick":
			quick = true
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("HWR-GRASS-001_%s.png" % name)
	var err := img.save_png(path)
	print("screenshot ", path, " err=", err)


func measure(name: String) -> Dictionary:
	await frames(WARMUP)
	review.reset_frame_stats()
	await frames(SAMPLE)
	var s: Dictionary = review.stats()
	s["name"] = name
	results.append(s)
	print("perf %-28s tiles %4d  %6.2f ms avg  %6.2f ms p95  %4d fps  draw %4d  prims %9d  vram %.1f MB" % [name, s.tiles, s.frame_ms_avg, s.frame_ms_p95, s.fps, s.draw_calls, s.primitives, s.video_mem_mb])
	return s


func run() -> void:
	var packed: PackedScene = load("res://assets/environment/grass/grass_review.tscn")
	review = packed.instantiate()
	root.add_child(review)
	await frames(5)
	print("renderer ", RenderingServer.get_current_rendering_method(), " gpu ", RenderingServer.get_video_adapter_name(), " window ", DisplayServer.window_get_size())
	if movie_dir != "":
		await movie()
		quit()
		return
	review.label.visible = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if quick:
		review.set_layout("grid4")
		review.set_camera_preset("village")
		review.set_wind(false, 1.0)
		await shot("quick_16_village_cam")
		review.set_camera_preset("close")
		review.set_wind(true, 1.0)
		await frames(40)
		await shot("quick_wind_on_close")
		quit()
		return

	# --- original vs result under the village camera (single tile, no wind)
	review.set_wind(false, 1.0)
	review.set_layout("single")
	var has_orig: bool = review.show_original(true)
	review.set_camera_preset("village")
	await frames(10)
	if has_orig:
		await shot("compare_single_village_cam")
		review.set_camera_preset("close")
		await shot("compare_single_close")
		review.set_camera_preset("top")
		await shot("compare_single_top")
		review.set_camera_preset("village")
		# original alone: hide the field by giving it an empty layout while keeping the camera framing
		review.field.set_hidden_cells([Vector2i(0, 0)])
		await measure("original_1_tile")
		review.field.set_hidden_cells([])
		review.show_original(false)
	review.set_camera_preset("village")
	await measure("tile_1")

	# --- seams and repetition
	review.set_layout("grid2")
	review.set_camera_preset("close")
	await shot("seam_2x2_close")
	review.set_camera_preset("top")
	await shot("seam_2x2_top")
	review.set_layout("grid4")
	review.set_camera_preset("village")
	await shot("tiles_16_village_cam")
	review.set_camera_preset("top")
	await shot("tiles_16_top")
	review.set_camera_preset("village")
	await measure("tiles_16_wind_off")
	review.set_wind(true, 1.0)
	await measure("tiles_16_wind_on")
	review.set_wind(false, 1.0)

	# --- village cell set (150) and the 192 upper bound
	review.set_layout("village")
	review.set_camera_preset("village")
	await shot("tiles_150_village_cam")
	await measure("tiles_150_wind_off")
	review.set_wind(true, 1.0)
	await measure("tiles_150_wind_on")
	review.set_camera_preset("overview")
	await shot("tiles_150_overview")
	review.set_wind(false, 1.0)
	review.set_layout("full")
	review.set_camera_preset("village")
	await shot("tiles_192_village_cam")
	await measure("tiles_192_wind_off")
	review.set_wind(true, 1.0)
	await measure("tiles_192_wind_on")
	review.set_shadows(false)
	await measure("tiles_192_wind_on_no_shadow")
	review.set_shadows(true)
	review.set_camera_preset("overview")
	await shot("tiles_192_overview")

	# --- wind stills (close camera on 4x4)
	review.set_layout("grid4")
	review.set_camera_preset("close")
	review.set_wind(false, 1.0)
	await shot("wind_off_close")
	review.set_wind(true, 1.0)
	await frames(40)
	await shot("wind_on_close")
	review.set_wind(true, 2.5)
	await frames(20)
	await shot("wind_strong_close")

	var f := FileAccess.open(out_dir.path_join("HWR-GRASS-001_perf.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"godot": Engine.get_version_info().string, "os": OS.get_name(), "results": results}, "  "))
	f.close()
	print("perf json written")
	quit()


func movie() -> void:
	DirAccess.make_dir_recursive_absolute(movie_dir)
	review.label.visible = false
	review.set_layout("grid4")
	review.set_camera_preset("close")
	review.set_wind(true, 1.2)
	await frames(10)
	for i in MOVIE_FRAMES:
		if i == MOVIE_FRAMES / 2:
			review.set_wind(true, 2.5)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		img.save_jpg(movie_dir.path_join("f_%04d.jpg" % i), 0.9)
	print("movie frames written to ", movie_dir)
