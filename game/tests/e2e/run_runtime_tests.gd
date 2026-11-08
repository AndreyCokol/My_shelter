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
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	check(not app.ui.radial.visible and app.ui.panel_id == "welcome", "left Ctrl leaves the welcome panel active")
	check(app.scene_router.current_world().scene_id == "hospital" and is_instance_valid(app.enemy()), "step5 real hospital and enemy mounted")
	app.ui.close_panel()
	await check_hud_input()
	await check_integrated_shelter_input()
	var before: Vector2 = app.hero.position
	Input.action_press("move_right")
	for i in range(12):
		await physics_frame
	Input.action_release("move_right")
	check(app.hero.position.x > before.x, "step5 actual controller moves on physics frames")
	app.hero.position = Vector2(600, 226)
	Input.action_press("move_right")
	for i in range(10):
		await physics_frame
	Input.action_release("move_right")
	check(app.hero.position.x > 610 and app.camera.position.x > 600, "hero and camera cross the first interior sector")
	var right_edge: float = app.scene_router.current_world().floor_rect().end.x - 15
	app.hero.position = Vector2(right_edge, 300)
	Input.action_press("move_right")
	for i in range(8):
		await physics_frame
	Input.action_release("move_right")
	check(app.hero.position.x <= right_edge, "step5 walls and world bounds constrain movement")
	check(app.hero.try_dodge() and not app.hero.try_dodge(), "step5 dodge cooldown prevents spam")
	var hp: int = app.hero.health
	check(not app.hero.take_damage(20) and app.hero.health == hp, "step5 dodge grants invulnerability")
	app.hero.dodge_remaining = 0
	app.hero.position = app.enemy().position + Vector2(-38, 0)
	# A0-F02: create a real physics wall between two nearby actors.
	var blocked_enemy = app.enemy()
	var blocking_rect := Rect2(blocked_enemy.position + Vector2(-24, -19), Vector2(10, 38))
	var blocking_wall = app.scene_router.current_world().add_wall(blocking_rect)
	await physics_frame
	app.hero.position = blocked_enemy.position + Vector2(-38, 0)
	var blocked_hp: int = blocked_enemy.health
	check(app.hero.try_attack(blocked_enemy.global_position) and blocked_enemy.health == blocked_hp, "A0-F02 melee cannot damage an enemy through a real collision wall")
	blocking_wall.queue_free()
	await physics_frame
	app.hero.attack_cooldown = 0.0
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
	await process_frame
	var item: Dictionary = app.snapshot().inventory.items.filter(func(stack): return stack.type_id == "seed.basic")[0]
	for slot in app.ui.body.find_children("*", "Button", true, false):
		if slot.tooltip_text == "Семена":
			slot.pressed.emit()
			break
	var move_to_storage: Array = app.ui.body.find_children("*", "Button", true, false).filter(func(control): return control.text == "В хранилище")
	check(app.ui.inventory_selection == item.instance_id and move_to_storage.size() == 1, "inventory grid selection opens the actual item action")
	if not move_to_storage.is_empty():
		move_to_storage[0].pressed.emit()
	await process_frame
	var storage_tab: Array = app.ui.body.find_children("*", "Button", true, false).filter(func(control): return control.text == "Хранилище")
	if not storage_tab.is_empty():
		storage_tab[0].pressed.emit()
	var move_to_bag: Array = app.ui.body.find_children("*", "Button", true, false).filter(func(control): return control.text == "В рюкзак")
	check(app.last_result.ok and app.ui.inventory_container == "storage" and move_to_bag.size() == 1, "storage tab shows the transferred item")
	if not move_to_bag.is_empty():
		move_to_bag[0].pressed.emit()
	await process_frame
	check(app.last_result.ok and app.snapshot().inventory.items.any(func(stack): return stack.type_id == "seed.basic" and stack.container_id == "player" and stack.quantity == 4), "inventory UI moves the complete available stack back")
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
	check(app.transition("outside").ok and app.transition("louvre").ok, "step11 actual NPC world mounted")
	for id in ["resident_1", "resident_2"]:
		check(app.command("game.contact", {"resident_id": id}).ok and app.command("game.consent", {"resident_id": id, "accept": true}).ok and app.command("game.recruit", {"resident_id": id}).ok, "E2E04 consent food and resident " + id)
	app.hero.position = Vector2(200, 270)
	app.hero.health = 73
	check(app.save_game().ok, "E2E05 save captures actor position and runtime health")
	var saved: Dictionary = app.snapshot()
	app.hero.position = Vector2(500, 130)
	app.hero.health = 11
	var loaded_result: Dictionary = app.load_game()
	var loaded: Dictionary = app.snapshot()
	var positions_match: bool = loaded.scene.positions.keys().size() == saved.scene.positions.keys().size()
	for id in saved.scene.positions:
		var before_position: Dictionary = saved.scene.positions[id]
		var after_position: Dictionary = loaded.scene.positions.get(id, {"x": INF, "y": INF})
		positions_match = positions_match and Vector2(before_position.x, before_position.y) == Vector2(after_position.x, after_position.y)
	loaded.scene.positions = saved.scene.positions
	check(loaded_result.ok and positions_match and loaded == saved and app.hero.health == 73 and app.hero.position == Vector2(200, 270), "E2E05 load installs all domains position and health")
	app.ui.open_panel("inventory")
	var reserved_id: String = saved.inventory.reservations[0].instance_id
	var reserved_stack: Dictionary = saved.inventory.items.filter(func(stack): return stack.instance_id == reserved_id)[0]
	app.ui.select_inventory(reserved_stack.container_id, reserved_id)
	var reserved_quantity := 0
	for reservation in saved.inventory.reservations:
		if reservation.instance_id == reserved_id:
			reserved_quantity += int(reservation.quantity)
	var matching_labels: Array = app.ui.body.find_children("*", "Label", true, false).filter(func(control): return ("В резерве: %d" % reserved_quantity) in control.text)
	check(matching_labels.size() == 1, "inventory details show the real reservation on the selected stack")
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
	var first: String = app.ui.hud.items[0].instance_id
	send_key(KEY_1)
	check(app.ui.panel_id == "inventory" and app.ui.inventory_selection == first, "quick slot selects the real backpack stack")
	app.ui.close_panel()
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	await process_frame
	click_at(app.ui.radial.wheel_center() + Vector2(0, -40))
	check(app.ui.panel_id == "inventory" and app.ui.inventory_selection == first and not app.ui.radial.visible, "wheel sector selects the same backpack stack")
	app.ui.close_panel()
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


func send_key(code: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED, echo := false) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.keycode = code
	key.location = location
	key.pressed = true
	key.echo = echo
	root.push_input(key, true)
	var released := key.duplicate() as InputEventKey
	released.pressed = false
	released.echo = false
	root.push_input(released, true)


func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		root.push_input(click, true)


func check_hud_input() -> void:
	var radial = app.ui.radial
	check(app.ui.hud.visible and not radial.visible, "HUD starts with the item wheel hidden")
	send_key(KEY_CTRL, KEY_LOCATION_RIGHT)
	check(not radial.visible, "right Ctrl does not toggle the wheel")
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	check(radial.visible and not app.running(), "left Ctrl opens the wheel and pauses gameplay")
	send_key(KEY_CTRL, KEY_LOCATION_LEFT, true)
	check(radial.visible, "Ctrl echo cannot close the wheel")
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	check(not radial.visible and app.running(), "a second left Ctrl closes the wheel and resumes gameplay")
	var external: int = app.session.pauses.acquire_pause("test:recovery")
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	check(not radial.visible and not app.running(), "the wheel respects another pause owner")
	app.session.pauses.release_pause(external)
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	send_key(KEY_ESCAPE)
	check(not radial.visible and app.ui.panel_id.is_empty() and app.running(), "Escape dismisses the wheel without opening pause")
	for shortcut in [[KEY_M, "map"], [KEY_J, "journal"], [KEY_K, "workshop"], [KEY_I, "inventory"]]:
		send_key(shortcut[0])
		check(app.ui.panel_id == shortcut[1] and app.session.pauses.is_paused(), "HUD shortcut opens " + shortcut[1])
		app.ui.close_panel()
	send_key(KEY_1)
	check(app.ui.panel_id.is_empty(), "an empty quick slot opens no panel")
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	await process_frame
	var center: Vector2 = radial.wheel_center()
	click_at(center)
	check(not radial.visible and app.ui.panel_id == "inventory" and app.session.pauses.is_paused(), "wheel hub opens the backpack")
	app.ui.close_panel()
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	await process_frame
	click_at(Vector2(300, 120))
	check(not radial.visible and app.running() and app.hero.attack_cooldown == 0.0, "a click outside the wheel dismisses it without attacking")
	click_at(Vector2(300, 120))
	check(app.hero.attack_cooldown > 0.0, "an unhandled world click still attacks")
	app.hero.attack_cooldown = 0.0

# End-to-end regression for both PR #38 and PR #39 on a single SceneTree.
func check_integrated_shelter_input() -> void:
	var before: Dictionary = app.snapshot()
	var pos: Vector2 = app.hero.position
	check(not before.world_states.first_enemy_defeated, "integrated G test before first victory")
	send_key(KEY_CTRL, KEY_LOCATION_LEFT)
	check(app.ui.radial.visible and app.session.pauses.is_paused(), "integrated radial opens before first fight")
	send_key(KEY_G)
	check(app.snapshot().scene.current_scene_id == "shelter" and not app.ui.radial.visible and not app.session.pauses.is_paused(), "G closes radial and moves to shelter before Q01")
	check(not app.snapshot().world_states.first_enemy_defeated and not "system_unlocked" in app.snapshot().story_flags and app.snapshot().player.xp == before.player.xp, "retreat grants neither System nor XP")
	send_key(KEY_G)
	check(app.snapshot().scene.current_scene_id == before.scene.current_scene_id and app.hero.position == pos, "G returns to saved scene and exact position")
	app.ui.open_panel("inventory")
	app.ui.shelter_modal_button.pressed.emit()
	check(app.snapshot().scene.current_scene_id == "shelter" and app.ui.panel_id.is_empty() and not app.session.pauses.is_paused(), "modal shelter button releases only its own pause")
	send_key(KEY_G)
	check(app.snapshot().scene.current_scene_id == before.scene.current_scene_id, "G returns after modal warp")
	var external: int = app.session.pauses.acquire_pause("integration:external")
	var scene_before: String = app.snapshot().scene.current_scene_id
	send_key(KEY_G)
	check(app.snapshot().scene.current_scene_id == scene_before and app.session.pauses.is_paused(), "G cannot bypass external pause")
	app.session.pauses.release_pause(external)
	check(app.ui.shelter_nav_button.visible, "Shelter HUD action remains visible on world")
