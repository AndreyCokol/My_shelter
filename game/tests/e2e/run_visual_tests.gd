extends SceneTree

const RadialMenu = preload("res://game/ui/radial_menu.gd")

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app = preload("res://game/scenes/main/playable.tscn").instantiate()
	app.save_location = "user://visual-tests/" + str(Time.get_ticks_usec()) + ".json"
	app.starting_seed = 54
	root.add_child(app)
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("/tmp/shelter-visual")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.get_width() >= 640, "step13 real renderer produces viewport pixels")
	image.save_png("/tmp/shelter-visual/welcome.png")
	app.ui.close_panel()
	app.command("game.enemy_defeated") # Public UI facade must reject trusted-only command.
	check(not app.snapshot().world_states.first_enemy_defeated, "step12 UI facade cannot issue trusted combat reward")
	# Exercise real combat via actor, not a direct reward command.
	app.enemy().take_damage(100)
	for i in range(4):
		await physics_frame
	await process_frame
	check(app.snapshot().world_states.first_enemy_defeated, "step13 render scene keeps gameplay alive")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/shelter-visual/hospital.png")
	await capture_reference_candidate(app, "R3_hospital")
	await measure_frames(app, "hospital", Vector2(120, 299))
	var hospital = app.scene_router.current_world()
	app.hero.position = hospital.layout.exits.hospital_0_2.position
	await capture("stairs")
	hospital.interact()
	check(app.snapshot().scene.current_scene_id == "hospital_0_2", "stairs are usable in the rendered interior")
	app.transition("shelter")
	check(app.command("inventory.claim_parcel", {"parcel_id": "starter"}).ok, "populate inventory with real gameplay items")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/shelter-visual/shelter.png")
	await capture_reference_candidate(app, "R1_shelter")
	var ctrl := InputEventKey.new()
	ctrl.physical_keycode = KEY_CTRL
	ctrl.keycode = KEY_CTRL
	ctrl.location = KEY_LOCATION_LEFT
	ctrl.pressed = true
	root.push_input(ctrl, true)
	check(app.ui.radial.visible and app.ui.radial.items.size() >= 2, "render the radial HUD with real backpack items")
	await capture("radial")
	app.ui.close_radial()
	await check_full_hd_interface(app)
	for panel in ["inventory", "farm", "rest", "residents", "quests", "shop", "save", "credits", "workshop", "jobs", "map", "journal", "new_confirm"]:
		app.ui.open_panel(panel)
		await process_frame
		await process_frame
		check(app.ui.modal.visible and app.ui.heading.get_global_rect().size.x > 100, "step13 layout " + panel)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/shelter-visual/" + panel + ".png")
		app.ui.close_panel()
	check(app.transition("outside").ok, "render the generated city")
	app.hero.position = Vector2(740, 272)
	await capture("city")
	await capture_reference_candidate(app, "R2_street")
	await measure_frames(app, "street", Vector2(780, 272))
	var street = app.scene_router.current_world()
	app.hero.position = street.layout.exits.hospital.position
	await capture("hospital_door")
	street.interact()
	check(app.snapshot().scene.current_scene_id == "hospital", "rendered hospital door leads indoors")
	var interior = app.scene_router.current_world()
	app.hero.position = interior.layout.exits.outside.position
	interior.interact()
	check(app.snapshot().scene.current_scene_id == "outside", "rendered indoor exit returns to the street facade")
	street = app.scene_router.current_world()
	app.hero.position = street.layout.exits.house_0.position
	await capture("house_door")
	street.interact()
	check(app.snapshot().scene.current_scene_id == "house_0", "rendered residential facade leads to its lobby")
	interior = app.scene_router.current_world()
	app.hero.position = interior.layout.exits.house_0_2.position
	interior.interact()
	check(app.snapshot().scene.current_scene_id == "house_0_2", "rendered residential stairs lead to an apartment floor")
	interior = app.scene_router.current_world()
	var plan: Dictionary = interior.layout.floor_plan
	var apartment: Dictionary = plan.units.apt_01
	app.hero.position = plan.rooms[apartment.rooms[1]].rect.get_center()
	await capture("apartment")
	await capture_reference_candidate(app, "R4_apartment")
	app.hero.position = interior.layout.exits.house_0.position
	interior.interact()
	interior = app.scene_router.current_world()
	app.hero.position = interior.layout.exits.outside.position
	interior.interact()
	check(app.snapshot().scene.current_scene_id == "outside" and app.hero.position == app.scene_router.current_world().layout.exits.house_0.arrival, "rendered house exit returns to the same facade")
	check(app.transition("louvre").ok, "render the camp board in its scene")
	app.ui.open_panel("camp")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/shelter-visual/camp.png")
	var path: String = app.save_location
	app.free()
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	await process_frame
	await capture_three_seed_locations()
	print("VISUAL TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)



# Issue #44: capture genuinely different generated world seeds, not
# screen mockups. No force-upgrade of v4 saves. These are 720p Linux
# software-OpenGL review screenshots, NOT native Windows GUI playtests.
func capture_three_seed_locations() -> void:
	var scenes = preload("res://game/scenes/main/playable.tscn")
	for seed_value in [0, 54, 2147483647]:
		var sample = scenes.instantiate()
		var location := "user://visual-seeds/%d-%d.json" % [seed_value, Time.get_ticks_usec()]
		sample.save_location = location
		sample.starting_seed = seed_value
		root.add_child(sample)
		await process_frame
		await process_frame
		sample.ui.close_panel()
		var manifest: Dictionary = sample.snapshot().world_states.layout
		check(manifest.seed == seed_value and manifest.generator_version == 5,
			"real rendered seed %d uses v5 procedural world" % seed_value)
		sample.hero.position = Vector2(610, 260)
		await capture("seed_%d_hospital" % seed_value)
		var enter: Dictionary = sample.toggle_shelter()
		check(enter.get("ok", false) and sample.snapshot().scene.current_scene_id == "shelter",
			"seed %d enters shelter from hospital without quest unlock" % seed_value)
		await capture("seed_%d_shelter" % seed_value)
		var back: Dictionary = sample.toggle_shelter()
		check(back.get("ok", false) and sample.snapshot().scene.current_scene_id == "hospital",
			"seed %d returns to its hospital position" % seed_value)
		if is_instance_valid(sample.enemy()):
			sample.enemy().take_damage(100)
			for index in range(4):
				await physics_frame
		var outside: Dictionary = sample.transition("outside")
		check(outside.get("ok", false) and sample.snapshot().scene.current_scene_id == "outside",
			"seed %d provides a playable street facade" % seed_value)
		sample.hero.position = Vector2(750, 270)
		await capture("seed_%d_street" % seed_value)
		sample.free()
		for suffix in ["", ".tmp", ".bak", ".rejected"]:
			if FileAccess.file_exists(location + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(location + suffix))
		await process_frame
		print("SEED VISUALS: seed=%d captured hospital, shelter and street" % seed_value)


# Automated software-rendered coverage of the second target desktop
# resolution. It is NOT a replacement for the human Windows GUI smoke.
# The viewport remains 640×360 while the rendered output scales 3×.
func check_full_hd_interface(app) -> void:
	var previous_window_size: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	# DisplayServer can resize only the native window under Xvfb; the root
	# Window viewport must also be resized for genuine 1920-pixel captures.
	root.size = Vector2i(1920, 1080)
	for index in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	print("FULL HD DEBUG window=%s viewport_size=%s viewport_rect=%s image=%s screen=%s" % [str(DisplayServer.window_get_size()), str(root.size), str(root.get_visible_rect().size), str(screenshot.get_size()), str(DisplayServer.screen_get_size())])
	check(screenshot.get_size() == Vector2i(1920, 1080),
		"Full HD software renderer produces actual 1920x1080 pixels")
	check(app.ui.get_viewport_rect().size == Vector2(640, 360),
		"Full HD retains the 640x360 logical pixel-art interface")
	var logical_rect: Rect2 = Rect2(Vector2.ZERO, app.ui.get_viewport_rect().size)
	for section in [app.ui.hud.map_node, app.ui.hud.hotbar, app.ui.hud.navigation]:
		check(logical_rect.encloses(section.get_global_rect()),
			"Full HD HUD remains in logical view: " + section.name)
	check(logical_rect.encloses(app.ui.shelter_nav_button.get_global_rect()),
		"Full HD G shelter button remains visible and usable")
	check(screenshot.save_png("/tmp/shelter-visual/shelter_1080p.png") == OK,
		"Full HD shelter PNG saved from real renderer")
	app.ui.toggle_radial()
	await process_frame
	check(app.ui.radial.visible and app.session.pauses.is_paused(),
		"Full HD left-Ctrl wheel preserves the radial pause contract")
	var center: Vector2 = app.ui.radial.wheel_center()
	var wheel := Rect2(center - Vector2.ONE * RadialMenu.RADIUS,
		Vector2.ONE * RadialMenu.RADIUS * 2.0)
	check(logical_rect.encloses(wheel)
		and not wheel.intersects(app.ui.hud.map_node.get_global_rect())
		and not wheel.intersects(app.ui.hud.navigation.get_global_rect()),
		"Full HD radial menu does not obscure minimap or navigation")
	await capture("radial_1080p")
	app.ui.close_radial()
	for panel_id in ["inventory", "farm", "rest", "residents", "quests", "shop", "save",
			"credits", "workshop", "jobs", "map", "journal", "new_confirm"]:
		app.ui.open_panel(panel_id)
		await process_frame
		await process_frame
		var modal_rect: Rect2 = app.ui.modal.get_child(0).get_global_rect()
		check(logical_rect.encloses(modal_rect)
			and app.ui.heading.text.length() > 0 and app.ui.modal.visible,
			"Full HD panel fully fits the viewport: " + panel_id)
		await capture(panel_id + "_1080p")
		app.ui.close_panel()
	DisplayServer.window_set_size(previous_window_size)
	root.size = previous_window_size
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_size() == previous_window_size
		and not app.session.pauses.is_paused(),
		"Returning to original PC resolution preserves pause and viewport")


# VIS-01: capture real playable Godot at exactly the owner's 1672x941
# original pixel dimensions. Comparing to originals remains REPORT_ONLY
# until a reviewed pixel-overlay and asset pass; this is NOT a 1:1 claim.
func capture_reference_candidate(app, reference_id: String) -> void:
	var old_window: Vector2i = DisplayServer.window_get_size()
	var old_viewport: Vector2i = root.size
	var benchmark := Vector2i(1672, 941)
	DisplayServer.window_set_size(benchmark)
	root.size = benchmark
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	check(screenshot.get_size() == benchmark,
		"VIS-01 %s actual Godot screenshot uses original 1672x941 pixels" % reference_id)
	check(app.ui.get_viewport_rect().size == Vector2(640, 360),
		"VIS-01 %s keeps the logical interactive PC viewport" % reference_id)
	check(app.ui.hud.current_scene_id == app.snapshot().scene.current_scene_id,
		"VIS-02 %s displays live correct-world HUD palette state" % reference_id)
	var filename := "/tmp/shelter-visual/reference_%s_1672x941.png" % reference_id
	check(screenshot.save_png(filename) == OK,
		"VIS-01 %s actual GPU/CPU screenshot saved for owner pixel audit" % reference_id)
	DisplayServer.window_set_size(old_window)
	root.size = old_viewport
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().get_size() == old_viewport,
		"VIS-01 %s returns to playable PC resolution" % reference_id)


func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/shelter-visual/" + name + ".png")

func measure_frames(app, name: String, start: Vector2) -> void:
	app.hero.position = start
	await process_frame
	var started := Time.get_ticks_usec()
	Input.action_press("move_right")
	for frame in range(45):
		await RenderingServer.frame_post_draw
	Input.action_release("move_right")
	var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	print("LARGE MAP FRAME %s %s fps=%.1f sample_frames=45" % [OS.get_name(), name, 45.0 / seconds])
	check(app.hero.position.x > start.x, "measured live movement on " + name)
