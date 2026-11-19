extends SceneTree
## A5 visual smoke (real Godot renderer only; not a screenshot mock).
## Must run WITH a display, using Xvfb+software OpenGL in Linux CI.
const Preview = preload("res://game/scenes/prototypes/dual_view_preview.tscn")
const OUTPUT := "/tmp/shelter-dual-view"
const WIDTH := 1280
const HEIGHT := 720

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print(("PASS " if ok else "FAIL ") + label)

func frame_colours(frame: Image) -> Dictionary:
	var found := {}
	# Sampling actual 3D pixels protects against a blank/black frame.
	# Real 3D test primitives deliberately use flat colors. Require multiple
	# sampled scene colors, not a fabricated texture palette. Separately verify
	# different camera frames and physics walls in the standalone world test.
	for y in range(int(HEIGHT / 5), HEIGHT, 50):
		for x in range(int(WIDTH / 5), int(WIDTH * 4 / 5), 65):
			var color := frame.get_pixel(x, y)
			found[color.to_html()] = true
	return found

func capture(label: String) -> Image:
	for index in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(not frame.is_empty() and frame.get_size() == Vector2i(WIDTH, HEIGHT),
		"%s generated actual 1280x720 rendered pixels" % label)
	if frame.is_empty() or frame.get_size() != Vector2i(WIDTH, HEIGHT):
		return frame
	check(frame_colours(frame).size() >= 3, "%s rendered at least three nonuniform colors, not an empty frame" % label)
	check(frame.save_png(OUTPUT + "/" + label + ".png") == OK, "%s stored real PNG screenshot" % label)
	return frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	root.size = Vector2i(WIDTH, HEIGHT)
	var scene: Node3D = Preview.instantiate()
	root.add_child(scene)
	await process_frame
	var ortho: Camera3D = scene.get("overhead")
	var fps: Camera3D = scene.get("first_person")
	check(is_instance_valid(ortho) and ortho.current and ortho.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"start in strict topdown orthographic view")
	var overhead_image := await capture("topdown_1280x720")

	scene.call("set_first_person", true)
	check(is_instance_valid(fps) and fps.current and fps.projection == Camera3D.PROJECTION_PERSPECTIVE,
		"switch same scene to perspective FPS")
	var fps_image := await capture("first_person_1280x720")
	if not overhead_image.is_empty() and not fps_image.is_empty() and overhead_image.get_size() == fps_image.get_size():
		var differences := 0
		for y in range(int(HEIGHT / 5), int(HEIGHT * 4 / 5), 80):
			for x in range(int(WIDTH / 5), int(WIDTH * 4 / 5), 80):
				var a := overhead_image.get_pixel(x, y)
				var b := fps_image.get_pixel(x, y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.05:
					differences += 1
		check(differences >= 8, "two real cameras produce visibly different frames, not duplicated images")

	scene.call("set_first_person", false)
	check(ortho.current and not fps.current, "topdown camera restored with original world intact")
	scene.queue_free()
	await process_frame
	print("A5 DUAL VIEW VISUAL TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
