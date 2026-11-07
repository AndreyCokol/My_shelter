extends SceneTree

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
	app.transition("shelter")
	check(app.command("inventory.claim_parcel", {"parcel_id": "starter"}).ok, "populate inventory with real gameplay items")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/shelter-visual/shelter.png")
	for panel in ["inventory", "farm", "rest", "residents", "quests", "shop", "save", "credits", "workshop", "jobs", "map", "journal", "new_confirm"]:
		app.ui.open_panel(panel)
		await process_frame
		await process_frame
		check(app.ui.modal.visible and app.ui.heading.get_global_rect().size.x > 100, "step13 layout " + panel)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/shelter-visual/" + panel + ".png")
		app.ui.close_panel()
	check(app.transition("outside").ok, "render the generated city")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/shelter-visual/city.png")
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
	print("VISUAL TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
