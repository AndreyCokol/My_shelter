extends SceneTree

var checks: int = 0
var failures: int = 0
var app

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	app = preload("res://game/scenes/main/playable.tscn").instantiate()
	app.save_location = "user://runtime-tests/" + str(Time.get_ticks_usec()) + ".json"
	root.add_child(app)
	await process_frame
	check(app.ui.panel_id == "welcome" and app.session.pauses.is_paused(), "step12 welcome pauses world and combat")
	check(app.scene_router.current_world().scene_id == "hospital" and is_instance_valid(app.enemy()), "step5 real hospital and enemy mounted")
	app.ui.close_panel()
	var before: Vector2 = app.hero.position
	Input.action_press("move_right")
	for i in range(12):
		await physics_frame
	Input.action_release("move_right")
	check(app.hero.position.x > before.x, "step5 actual controller moves on physics frames")
	app.hero.position = Vector2(605, 300)
	Input.action_press("move_right")
	for i in range(8):
		await physics_frame
	Input.action_release("move_right")
	check(app.hero.position.x <= 605, "step5 walls and world bounds constrain movement")
	check(app.hero.try_dodge() and not app.hero.try_dodge(), "step5 dodge cooldown prevents spam")
	var hp: int = app.hero.health
	check(not app.hero.take_damage(20) and app.hero.health == hp, "step5 dodge grants invulnerability")
	app.hero.dodge_remaining = 0
	app.hero.position = app.enemy().position + Vector2(-38, 0)
	check(app.hero.try_attack(app.enemy().global_position) and not app.hero.try_attack(app.enemy().global_position), "step5 attack cooldown prevents repeated frame hit")
	for i in range(3):
		await create_timer(0.5).timeout
		if is_instance_valid(app.enemy()):
			app.hero.position = app.enemy().position + Vector2(-38, 0)
			app.hero.try_attack(app.enemy().global_position)
	await create_timer(0.1).timeout
	check(app.snapshot().world_states.first_enemy_defeated and app.snapshot().player.xp == 10, "E2E01 actual real time attacks unlock one reward")
	check(app.transition("shelter").ok and app.scene_router.current_world().scene_id == "shelter", "step6 actual scene transition keeps supplied hero")
	app.ui.open_panel("inventory")
	check(app.session.pauses.is_paused(), "step12 inventory modal pauses clock")
	app.ui.run_command("inventory.claim_parcel", {"parcel_id": "starter"})
	check(app.last_result.ok and app.session.pauses.is_paused(), "step12 panel command releases only own token and restores pause")
	var external: int = app.session.pauses.acquire_pause("test-other-window")
	app.ui.run_command("inventory.purchase", {"offer_id": "seed"})
	check(app.last_result.code == "PAUSED", "step12 panel cannot bypass another pause owner")
	app.session.pauses.release_pause(external)
	app.ui.close_panel()
	for id in ["plot_1", "plot_2"]:
		check(app.command("game.plant", {"plot_id": id}).ok and app.command("game.water", {"plot_id": id}).ok, "E2E02 plant and water " + id)
	var snapshot_before: Dictionary = app.snapshot()
	var preview: Dictionary = app.preview_rest(app.next_harvest_minute())
	check(preview.ok and preview.data.spoiled_plots == 0 and app.snapshot() == snapshot_before, "step9 preview is pure and exposes spoilage risk")
	check(app.command("clock.rest", {"target_minute": app.next_harvest_minute()}).ok, "E2E02 real calendar rest reaches crop maturity")
	for id in ["plot_1", "plot_2"]:
		check(app.command("game.harvest", {"plot_id": id}).ok, "E2E02 durable harvest " + id)
	check(app.snapshot().quests.records[2].status == "inactive", "E2E07 untracked story never blocks farming")
	check(app.transition("louvre").ok, "step11 actual NPC world mounted")
	for id in ["resident_1", "resident_2"]:
		check(app.command("game.contact", {"resident_id": id}).ok and app.command("game.consent", {"resident_id": id, "accept": true}).ok and app.command("game.recruit", {"resident_id": id}).ok, "E2E04 consent food and resident " + id)
	app.hero.position = Vector2(200, 270)
	app.hero.health = 73
	check(app.save_game().ok, "E2E05 save captures actor position and runtime health")
	var saved: Dictionary = app.snapshot()
	app.hero.position = Vector2(500, 130)
	app.hero.health = 11
	var loaded_result: Dictionary = app.load_game()
	if not (loaded_result.ok and app.snapshot() == saved and app.hero.health == 73 and app.hero.position == Vector2(200, 270)):
		print("LOAD DETAIL ", loaded_result, " hp ", app.hero.health, " position ", app.hero.position)
		for key in saved:
			if saved[key] != app.snapshot()[key]:
				print("DIFFERENT ", key, " before=", saved[key], " after=", app.snapshot()[key])
	check(loaded_result.ok and app.snapshot() == saved and app.hero.health == 73 and app.hero.position == Vector2(200, 270), "E2E05 load installs all domains position and health")
	app.ui.open_panel("inventory")
	var focused_button: Button = app.ui.body.find_children("*", "Button", true, false)[0]
	focused_button.grab_focus()
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	escape.pressed = false
	Input.parse_input_event(escape)
	await process_frame
	check(app.ui.panel_id.is_empty() and not app.session.pauses.is_paused(), "E2E08 Escape closes focused modal and releases its pause")
	check(root.gui_get_focus_owner() == null, "E2E08 closed modal leaves no focused action that Space can trigger")
	var subscriptions: int = app.session.events.subscription_count()
	for i in range(10):
		app.ui.open_panel("inventory")
		app.ui.close_panel()
	check(app.session.events.subscription_count() == subscriptions and not app.session.pauses.is_paused(), "E2E08 ten reopens do not leak subscriptions or pause tokens")
	for name in ["farm", "rest", "residents", "quests", "shop", "save", "menu"]:
		app.ui.open_panel(name)
		await process_frame
		check(app.ui.body.get_child_count() > 0, "step12 panel renders " + name)
		app.ui.close_panel()
	var path: String = app.save_location
	app.free()
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	await process_frame
	print("RUNTIME TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
