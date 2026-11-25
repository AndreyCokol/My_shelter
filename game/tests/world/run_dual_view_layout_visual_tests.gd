extends SceneTree
## A5: true Godot software-rendered screenshots of existing v5 hospital/city.
## This test is separate from a real Windows GUI playthrough.
const Preview = preload("res://game/scenes/prototypes/dual_view_layout_preview.tscn")
const OUT := "/tmp/shelter-a5-real-layout"
const SIZE := Vector2i(1280, 720)
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(name)
	print(("PASS " if ok else "FAIL ") + name)

func _different(a: Image, b: Image) -> bool:
	var changed := 0
	for y in range(150, 620, 60):
		for x in range(150, 1130, 60):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) > 0.10:
				changed += 1
	return changed >= 5

func _capture(name: String) -> Image:
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	check(not screenshot.is_empty() and screenshot.get_size() == SIZE, name + " actual renderer produced 1280x720")
	if screenshot.is_empty() or screenshot.get_size() != SIZE:
		return screenshot
	check(screenshot.save_png(OUT + "/" + name + ".png") == OK, name + " true PNG saved")
	return screenshot

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	DisplayServer.window_set_size(SIZE)
	root.size = SIZE
	var preview: Node3D = Preview.instantiate()
	root.add_child(preview)
	await process_frame
	var model: Dictionary = preview.get("layout_snapshot")
	var camera_top: Camera3D = preview.get("overhead")
	var camera_fps: Camera3D = preview.get("first_person")
	var hero: CharacterBody3D = preview.get("hero")
	check(model.scene_id == "hospital_0_3" and model.wall_count > 10, "actual third-floor walls loaded")
	var demo_hud: CanvasLayer = preview.get("hud")
	var demo_panel: PanelContainer = demo_hud.get_node_or_null("ModeHelpPanel")
	check(is_instance_valid(demo_panel) and demo_panel.custom_minimum_size.x <= 200.0, "A5 preview panel stays under 200 logical pixels wide")
	check(camera_top.current and camera_top.projection == Camera3D.PROJECTION_ORTHOGONAL, "topdown projection on real hospital")
	var player_id := hero.get_instance_id()
	var floor_3: Image = await _capture("hospital_floor3_topdown_1280x720")

	preview.call("set_first_person", true)
	check(camera_fps.current and player_id == hero.get_instance_id(), "first person same actual hospital actor")
	var fps: Image = await _capture("hospital_floor3_fps_1280x720")
	if floor_3.get_size() == SIZE and fps.get_size() == SIZE:
		check(_different(floor_3, fps), "real hospital topdown and FPS frames are visibly distinct")

	preview.call("cycle_layout")
	model = preview.get("layout_snapshot")
	check(model.scene_id == "hospital" and model.wall_count > 10, "actual hospital ground-floor generated")
	var ground: Image = await _capture("hospital_floor1_topdown_1280x720")
	preview.call("cycle_layout")
	model = preview.get("layout_snapshot")
	check(model.scene_id == "outside" and model.wall_count > 0, "actual city street generated")
	var city: Image = await _capture("outside_topdown_1280x720")
	check(hero.get_instance_id() == player_id and camera_top.current, "camera and actor remain stable across test layouts")
	check(not ground.is_empty() and not city.is_empty(), "real floor-one and city frames exist")

	preview.queue_free()
	await process_frame
	print("A5 REAL LAYOUT VISUAL TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
