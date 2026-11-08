extends SceneTree

const DistrictEvents = preload("res://game/systems/world/district_events.gd")
const Expedition = preload("res://game/systems/world/expedition_order.gd")
const Camp = preload("res://game/systems/world/camp_network.gd")
const Work = preload("res://game/systems/shelter/resident_work.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Workshop = preload("res://game/systems/shelter/construction.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Plans = preload("res://game/systems/world/building_plan.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func reachable_floor(record: Dictionary) -> bool:
	var step := 5
	var start := Vector2i(120, 260)
	var pending: Array[Vector2i] = [start]
	var seen := {start: true}
	var index := 0
	while index < pending.size():
		var point := pending[index]
		index += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = point + direction * step
			if seen.has(next) or not Rect2i(40, 105, 561, 221).has_point(next):
				continue
			var blocked := false
			for obstacle in record.obstacles:
				if obstacle.grow(10).has_point(Vector2(next)):
					blocked = true
					break
			if not blocked:
				seen[next] = true
				pending.append(next)
	for slot in range(record.links.size()):
		var door: Vector2 = Layout.DOORS[slot]
		var approach := Vector2i(door + Vector2(20 if door.x < 320 else -20, 0))
		if not seen.has(approach):
			return false
	return seen.has(Vector2i(300, 265))

func expanded_geometry(record: Dictionary) -> bool:
	var bounds: Rect2 = record.bounds
	var expected: Vector2 = Layout.STREET_SIZE if record.kind == "outside" else Layout.INTERIOR_SIZE
	if bounds.size != expected or record.exits.size() != record.links.size():
		return false
	var walkable := bounds.grow(-15)
	var points := [record.spawn]
	if record.kind in ["outside", "house", "hospital"]:
		points.append(record.loot)
	if record.kind == "hospital":
		points.append(record.enemy)
	if record.kind == "outside":
		points.append_array([record.salvage, record.event])
		points.append_array(Array(record.patrol))
	for exit in record.exits.values():
		points.append_array([exit.position, exit.arrival])
	for obstacle in record.obstacles:
		if not bounds.encloses(obstacle):
			return false
		for point in points:
			if obstacle.grow(9).has_point(point):
				print("Blocked anchor ", record.segment, " at ", point, " by ", obstacle)
				return false
	return points.all(func(point): return walkable.has_point(point))

func expanded_routes(record: Dictionary) -> bool:
	var walkable: Rect2 = record.bounds.grow(-15)
	var grid := AStarGrid2D.new()
	var step := 16
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(walkable.size / step) + Vector2i.ONE)
	grid.cell_size = Vector2(step, step)
	grid.offset = walkable.position
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for rect in record.obstacles:
		var blocked: Rect2 = rect.grow(10)
		var first := Vector2i(((blocked.position - walkable.position) / step).ceil())
		var last := Vector2i(((blocked.end - walkable.position) / step).floor())
		var cells := Rect2i(first, (last - first + Vector2i.ONE).max(Vector2i.ZERO)).intersection(grid.region)
		grid.fill_solid_region(cells)
	var start := Vector2i(((record.spawn - walkable.position) / step).round())
	var targets := []
	if record.kind in ["outside", "house", "hospital"]:
		targets.append(record.loot)
	if record.kind == "hospital":
		targets.append(record.enemy)
	if record.kind == "outside":
		targets.append_array([record.salvage, record.event])
	for exit in record.exits.values():
		targets.append(exit.arrival)
	if record.has("floor_plan"):
		for room in record.floor_plan.rooms.values():
			targets.append(room.rect.get_center())
	for point in targets:
		var cell := Vector2i(((point - walkable.position) / step).round()).clamp(Vector2i.ZERO, grid.region.end - Vector2i.ONE)
		if grid.get_id_path(start, cell).is_empty():
			print("Unreachable ", record.segment, " at ", point)
			return false
	return true

func follow(app, target: String) -> bool:
	var world = app.scene_router.current_world()
	for portal in world.portals:
		if portal.to == target:
			app.hero.position = portal.position
			world.interact()
			return app.snapshot().scene.current_scene_id == target
	return false

func move_for(action: String, frames: int) -> void:
	Input.action_press(action)
	for frame in range(frames + 1):
		await physics_frame
	Input.action_release(action)

func test_apartment(app):
	var reached := follow(app, "outside") and follow(app, "house_0") and follow(app, "house_0_2")
	check(reached, "player enters a house from its facade and climbs to the second floor")
	if not reached:
		return app
	var world = app.scene_router.current_world()
	var plan: Dictionary = world.layout.floor_plan
	var unit: Dictionary = plan.units.apt_01
	var foyer: Dictionary = plan.rooms[unit.entry]
	var living: Dictionary = plan.rooms[unit.rooms[1]]
	var entry: Dictionary = plan.doors.filter(func(door): return door.to == foyer.id)[0]
	var internal: Dictionary = plan.doors.filter(func(door): return door.to == living.id)[0]
	app.hero.position = entry.position + Vector2(0, 20)
	await move_for("move_up", 24)
	check(foyer.rect.has_point(app.hero.position), "movement crosses the real opening into the apartment foyer")
	var shift: float = internal.position.x - app.hero.position.x
	await move_for("move_left" if shift < 0 else "move_right", roundi(absf(shift) * 60 / 115))
	await move_for("move_up", 34)
	check(living.rect.has_point(app.hero.position), "movement through the foyer reaches the apartment living area")
	var saved_position: Vector2 = app.hero.position
	var path: String = app.save_location
	check(app.save_game().ok, "player can save inside an apartment")
	app.free()
	await process_frame
	app = preload("res://game/scenes/main/playable.tscn").instantiate()
	app.save_location = path
	app.starting_seed = 777
	root.add_child(app)
	check(app.load_game().ok and app.snapshot().scene.current_scene_id == "house_0_2" and app.hero.position == saved_position and app.scene_router.current_world().layout.floor_plan == plan, "restarting restores the same apartment and position upstairs")
	var upstairs_hp: int = app.hero.health
	check(app.toggle_shelter().ok and app.snapshot().scene.return_scene_id == "house_0_2", "G retreat from upper apartment retains its exact procedural floor")
	check(app.save_game().ok and app.load_game().ok and app.snapshot().scene.current_scene_id == "shelter", "shelter entered from the apartment survives full save/load")
	check(app.toggle_shelter().ok and app.snapshot().scene.current_scene_id == "house_0_2" and app.hero.position == saved_position and app.hero.health == upstairs_hp, "G returns to apartment floor, exact position and original HP after reload")
	check(follow(app, "house_0") and follow(app, "outside") and app.hero.position == app.scene_router.current_world().layout.exits.house_0.arrival, "going downstairs returns to the original street facade")
	var street_position: Vector2 = app.hero.position
	var street_hp: int = app.hero.health
	check(app.toggle_shelter().ok and app.snapshot().scene.return_scene_id == "outside", "G from outside always enters shelter, remembering street origin")
	check(app.toggle_shelter().ok and app.snapshot().scene.current_scene_id == "outside" and app.hero.position == street_position and app.hero.health == street_hp, "G returns to exact street entry point and HP")
	check(app.toggle_shelter().ok, "G has no cooldown when re-entering shelter immediately after return")
	return app

func test_unconditional_shelter(app) -> void:
	# The player may retreat before the first kill, even with a living enemy.
	var original: Vector2 = app.hero.position
	app.hero.health = 73 # A retreat from combat must also checkpoint current HP.
	check(not app.snapshot().world_states.first_enemy_defeated and is_instance_valid(app.enemy()), "shelter shortcut scenario starts before System unlock with a living enemy")
	app.enemy().take_damage(33)
	check(app.transition("outside").code == "UNAVAILABLE" and app.command("inventory.claim_parcel", {"parcel_id": "starter"}).code == "UNAVAILABLE", "ordinary travel and System parcel remain locked before first victory")
	check(app.ui.shelter_nav_button != null and app.ui.shelter_modal_button != null, "shelter shortcut is present in HUD and modal UI")
	app.ui.open_panel("inventory")
	app.ui.shelter_modal_button.pressed.emit()
	var entered: Dictionary = app.snapshot()
	check(entered.scene.current_scene_id == "shelter" and entered.scene.return_scene_id == "hospital" and app.ui.panel_id.is_empty() and not app.session.pauses.is_paused(), "modal shelter action escapes before first kill without leaking pause")
	check(not entered.world_states.first_enemy_defeated and entered.claimed_reward_ids.is_empty() and entered.wallet.system_coins == 0 and entered.player.hp == 73, "early shelter escape preserves damaged health without granting System or XP/coins")
	check(app.save_game().ok and app.load_game().ok and app.snapshot().scene.return_scene_id == "hospital" and app.hero.health == 73, "pre-unlock shelter, combat HP and return scene persist across save and load")
	app.ui.open_panel("menu")
	var shortcut := InputEventKey.new()
	shortcut.physical_keycode = KEY_G
	shortcut.keycode = KEY_G
	shortcut.pressed = true
	app._unhandled_input(shortcut)
	check(app.snapshot().scene.current_scene_id == "hospital" and app.hero.position == original and app.ui.panel_id.is_empty() and not app.session.pauses.is_paused(), "G shortcut from paused menu returns to exact hospital exit position")
	check(is_instance_valid(app.enemy()) and app.enemy().health == 67 and not app.snapshot().world_states.first_enemy_defeated, "retreat, save and reload preserve the opening enemy's damage and keep System locked")
	var external: int = app.session.pauses.acquire_pause("test-external-pause")
	app.ui.open_panel("menu")
	var paused_scene: String = app.snapshot().scene.current_scene_id
	app.ui.shelter_modal_button.pressed.emit()
	check(app.snapshot().scene.current_scene_id == paused_scene and app.last_result.code == "PAUSED" and app.ui.panel_id == "menu" and app.session.pauses.is_paused(), "shelter button cannot bypass unrelated pause or silently close its menu")
	app.ui.close_panel()
	app.session.pauses.release_pause(external)
	var before_failure: Dictionary = app.snapshot()
	app.enemy().take_damage(17)
	# SceneRouter holds a separate checkpoint store from GameApp's UI command store.
	# Fault the store used by the *transition*, not the UI command fixture.
	app.scene_router._store.fault = "before_replace"
	check(app.toggle_shelter().code == "SAVE_FAILED" and app.snapshot() == before_failure and app.hero.position == original and app.enemy().health == 50, "failed shelter commit keeps the live enemy damaged without changing the checkpoint")
	app.scene_router._store.fault = ""
	check(app.toggle_shelter().ok and app.toggle_shelter().ok and app.hero.position == original and is_instance_valid(app.enemy()) and app.enemy().health == 50, "retry checkpoints the latest damage and keeps the shelter shortcut available")

func run() -> void:
	var geometry := {}
	var signatures := {}
	var road_signatures := {}
	var expanded_samples := {}
	var clearance := true
	var valid_graphs := true
	var valid_plans := true
	var distinct_plans := true
	for seed_value in range(128):
		var nodes := Layout.build(seed_value)
		var old_nodes := Layout.build(seed_value, 2)
		road_signatures[JSON.stringify(nodes.outside.links)] = true
		var reachable := {"shelter": true}
		var frontier := ["shelter"]
		var used := {}
		var plans := {}
		for id in nodes:
			var entry: Dictionary = nodes[id]
			clearance = expanded_geometry(entry) and clearance
			var shape := "%s:%s" % [entry.segment, JSON.stringify(entry.exits.values().map(func(exit): return exit.position))]
			if entry.has("floor_plan"):
				var plan: Dictionary = entry.floor_plan
				shape = "%s:%d:%d" % [entry.kind, entry.floor_number, plan.pattern]
				if plans.has(shape):
					distinct_plans = false
				plans[shape] = true
				var expected_pattern: int = int(entry.segment.get_slice(":", 1 if entry.kind == "house" else 2)) * 2
				valid_plans = valid_plans and plan.pattern in [expected_pattern, expected_pattern + 1]
			expanded_samples[shape] = entry
			valid_graphs = valid_graphs and entry.links.size() <= Layout.DOORS.size() and not used.has(entry.segment)
			used[entry.segment] = true
			for target in entry.links:
				var exit: Dictionary = entry.exits[target]
				var paired: Dictionary = nodes[target].exits[id]
				valid_graphs = valid_graphs and id in nodes[target].links and exit.connector_id == paired.connector_id
				if exit.form.begins_with("stairs"):
					valid_graphs = valid_graphs and exit.position == paired.position and exit.form != paired.form
			if old_nodes.has(id) and not geometry.has(entry.segment):
				geometry[entry.segment] = old_nodes[id]
		while not frontier.is_empty():
			var id = frontier.pop_back()
			for target in nodes[id].links:
				if not reachable.has(target):
					reachable[target] = true
					frontier.append(target)
		valid_graphs = valid_graphs and reachable.size() == 30 and used.size() == 30
		signatures[JSON.stringify(used.keys())] = true
	check(valid_graphs and signatures.size() > 1, "128 seeds produce connected graphs and distinct assignments")
	check(clearance, "128 seeds use exact map areas with clear arrival, exit and objective anchors")
	check(valid_plans and distinct_plans, "128 seeds generate distinct checked plans for all four hospitals and houses")
	check(expanded_samples.values().all(expanded_routes), "every expanded room and street profile connects its exits and objectives")
	check(road_signatures.size() > 3, "new seeds vary the actual roads and keep every district reachable")
	check(Layout.build(54) == Layout.build(54), "same seed reconstructs exact layout")
	var broken: Dictionary = Plans.get_plan("house", 2, 5).duplicate(true)
	broken.walls.append(Rect2(broken.doors[0].position - Vector2(10, 10), Vector2(20, 20)))
	check(not Plans.valid(broken) and Plans.checked(broken, "house", 2, 5) == Plans.get_plan("house", 2, 2), "blocked doorway activates an aligned, checked fallback floor")
	var passable := true
	for record in geometry.values():
		passable = passable and reachable_floor(record)
	check(passable, "all catalog geometries provide collision clearance to doors and resource point")
	check(geometry.values().all(func(record): return record.obstacles != Layout.FALLBACK_BLOCKS), "every authored segment passes the runtime geometry guard")
	var fallback := Layout.checked_obstacles([Rect2(61, 116, 20, 50)])
	check(fallback == Layout.FALLBACK_BLOCKS and reachable_floor({"obstacles": fallback, "links": ["a", "b", "c", "d", "e", "f"]}), "invalid geometry falls back to a passable module with the same door slots")
	var app = preload("res://game/scenes/main/playable.tscn").instantiate()
	var path := "user://world-tests/" + str(Time.get_ticks_usec()) + ".json"
	app.save_location = path
	app.starting_seed = 54
	root.add_child(app)
	app.ui.close_panel()
	var initial: Dictionary = app.snapshot()
	check(initial.schema_version == 4 and initial.world_states.layout.seed == 54, "normal game scene starts a versioned seeded world")
	test_unconditional_shelter(app)
	var enemy = app.enemy()
	enemy.health = 0
	app.enemy_defeated()
	check(follow(app, "outside") and follow(app, "house_0"), "actual interaction follows paired city and house doors")
	var house_world = app.scene_router.current_world()
	app.hero.position = house_world.resource_point
	house_world.interact()
	check(app.last_result.ok and app.snapshot().world_states.locations.house_0.looted, "house loot commits to its own location")
	house_world.interact()
	check(app.last_result.code == "UNAVAILABLE", "cleared house cannot duplicate its loot")
	var first_house_position: Vector2 = app.hero.position
	check(app.toggle_shelter().ok and app.snapshot().scene.return_scene_id == "house_0" and app.toggle_shelter().ok and app.hero.position == first_house_position, "G returns to exact ground-floor house position without duplicating house loot")
	check(follow(app, "outside") and follow(app, "hospital") and follow(app, "hospital_0_2"), "hospital entry and stairs reach the selected floor")
	var stairs = app.scene_router.current_world()
	check(app.hero.position == stairs.layout.exits.hospital.arrival and stairs.layout.exits.hospital.form == "stairs_down", "upper floor arrives at the paired staircase landing")
	app.enemy().take_damage(29)
	check(follow(app, "hospital") and app.hero.position == app.scene_router.current_world().layout.exits.hospital_0_2.arrival and follow(app, "hospital_0_2") and app.enemy().health == 71, "paired staircase preserves the enemy damage on its own floor")
	check(app.save_game().ok and app.load_game().ok and app.enemy().health == 71, "save and load on a hospital floor restore enemy HP")
	var invalid_hp: Dictionary = app.snapshot()
	invalid_hp.world_states.enemy_health = {"hospital_0_2": 101}
	check(not Model.validate(invalid_hp, app.rules()), "invalid persisted enemy HP is rejected")
	var floor_enemy = app.enemy()
	floor_enemy.health = 0
	check(app.save_game().ok and app.load_game().ok and app.enemy().health == 0 and not app.snapshot().world_states.locations.get("hospital_0_2", {}).get("defeated", false), "a lethal hit pending the reward transaction survives a checkpoint")
	app.enemy_defeated()
	check(app.snapshot().world_states.locations.hospital_0_2.defeated and app.snapshot().claimed_reward_ids == ["system"], "floor enemy persists without duplicating onboarding reward")
	check(not app.snapshot().world_states.has("enemy_health"), "committed enemy defeats remove the stored injury")
	app.hero.position = Vector2(310, 270)
	var hospital_floor_hp: int = app.hero.health
	check(app.toggle_shelter().ok and app.snapshot().scene.return_scene_id == "hospital_0_2" and app.toggle_shelter().ok and app.hero.position == Vector2(310, 270) and app.hero.health == hospital_floor_hp, "G returns to exact hospital upper-floor coordinates and HP")
	check(app.save_game().ok, "procedural state saves")
	var saved: Dictionary = app.snapshot()
	app.free()
	await process_frame
	app = preload("res://game/scenes/main/playable.tscn").instantiate()
	app.save_location = path
	app.starting_seed = 777
	root.add_child(app)
	check(app.load_game().ok and app.snapshot() == saved and app.enemy() == null and app.scene_router.current_world().layout == Layout.build(54).hospital_0_2, "fresh game instance restores saved seed, loot, floor and defeated enemy")
	check(app.command("game.expand_farm").code == "NOT_IN_SAFE_AREA", "farm can only be expanded in the shelter")
	check(app.transition("shelter").ok and app.command("game.expand_farm").code == "INSUFFICIENT_RESOURCES", "expansion requires the full cost")
	check(app.command("inventory.claim_parcel", {"parcel_id": "starter"}).ok, "starter coins can contribute to building")
	var before_expansion: Dictionary = app.snapshot()
	app.save_store.fault = "before_replace"
	check(app.command("game.expand_farm").code == "SAVE_FAILED" and app.snapshot() == before_expansion, "failed save leaves both wallet and farm unchanged")
	app.save_store.fault = ""
	app.ui.open_panel("farm")
	var upgrade_buttons: Array = app.ui.body.get_children().filter(func(node): return node is Button and node.text.begins_with("Построить третью грядку"))
	if not upgrade_buttons.is_empty():
		upgrade_buttons[0].pressed.emit()
	app.ui.close_panel()
	var expanded: Dictionary = app.snapshot()
	check(expanded.crops.plots.size() == 3 and expanded.wallet.system_coins == before_expansion.wallet.system_coins - app.rules().farm_expansion_cost, "farm button builds a third plot and charges once")
	check(app.command("game.expand_farm").code == "INVALID_STATE" and app.snapshot() == expanded, "already built plot cannot be purchased again")
	check(app.command("game.plant", {"plot_id": "plot_3"}).ok and app.command("game.water", {"plot_id": "plot_3"}).ok, "third plot uses the existing planting and watering flow")
	check(app.command("clock.rest", {"target_minute": app.next_harvest_minute()}).ok and app.snapshot().crops.plots[2].status == "ripe", "new plot matures on the shared calendar")
	check(app.load_game().ok and app.snapshot().crops.plots[2].status == "ripe" and app.command("game.harvest", {"plot_id": "plot_3"}).ok, "expanded farm reloads and yields crops")
	var current_layout: Dictionary = app.snapshot().world_states.layout
	var original: Dictionary = app.snapshot()
	original.world_states.layout.generator_version = 1
	check(app.save_store.write_checkpoint(original, Model.validate.bind(app.rules())).get("committed", false) and app.load_game().ok, "version-one procedural checkpoint still loads")
	check(app.scene_router.current_world().layout == Layout.build(54, 1).shelter, "older layout version is selected from the checkpoint")
	var original_city := Layout.from_manifest(original.world_states.layout)
	check(original_city.outside.links == ["house_0", "hospital", "street_1", "street_2", "louvre", "shelter"], "original seed retains its road markers and order")
	original.world_states.layout.generator_version = 3
	var version_three := Layout.from_manifest(original.world_states.layout)
	check(app.save_store.write_checkpoint(original, Model.validate.bind(app.rules())).get("committed", false) and app.load_game().ok and app.scene_router.current_world().layout == version_three.shelter, "version-three procedural saves retain their map")
	check(not version_three.has("house_0_2") and follow(app, "outside") and follow(app, "house_0") and not app.scene_router.current_world().layout.has("floor_plan"), "version-three house retains its original ground floor")
	original.world_states.layout = current_layout
	check(app.save_store.write_checkpoint(original, Model.validate.bind(app.rules())).get("committed", false) and app.load_game().ok, "restore current layout for remaining gameplay checks")
	original.world_states.layout.generator_version = 2
	original.scene.current_scene_id = "outside"
	original.scene.entry_point_id = "default"
	original.player.position = {"x": 544, "y": 140}
	check(app.save_store.write_checkpoint(original, Model.validate.bind(app.rules())).get("committed", false) and app.load_game().ok and app.scene_router.current_world().floor_rect() == Layout.LEGACY_FLOOR, "prior generator opens its original map safely")
	var before_upgrade: Dictionary = app.snapshot()
	check(app.command("session.upgrade_world").ok and app.snapshot().world_states.layout.seed == 54 and app.scene_router.current_world().floor_rect().size == Layout.STREET_SIZE and app.hero.position == Layout.DEFAULT_SPAWN, "upgrade remounts the same street and moves a blocked position to the safe spawn")
	check(app.snapshot().inventory == before_upgrade.inventory and app.snapshot().world_states.locations == before_upgrade.world_states.locations and app.transition("shelter").ok, "map upgrade keeps inventory and location progress")
	app = await test_apartment(app)
	test_workshop(app)
	test_resident_work(app)
	test_camp_network(app)
	test_expedition(app)
	await test_patrol(app)
	await measure_world_switches(app)
	test_furniture(app)
	var legacy = Campaign.new(Rules.build())
	check(app.save_store.write_checkpoint(legacy.coordinator.get_snapshot(), Model.validate.bind(app.rules())).get("committed", false), "legacy fixture writes version 3 checkpoint")
	check(app.load_game().ok and app.snapshot().schema_version == 3 and app.scene_router.current_world().layout.is_empty(), "old version 3 saves load with original geometry")
	var legacy_state: Dictionary = app.snapshot()
	app.save_store.fault = "before_replace"
	check(app.command("session.upgrade_world").code == "SAVE_FAILED" and app.snapshot() == legacy_state and app.scene_router.current_world().layout.is_empty(), "failed upgrade leaves the previous world and save intact")
	app.save_store.fault = ""
	check(app.command("session.upgrade_world").ok and app.snapshot().schema_version == 4 and not app.scene_router.current_world().layout.is_empty(), "explicit migration mounts procedural geometry in the same scene slot")
	check(app.snapshot().inventory == legacy_state.inventory and app.save_store.read_checkpoint(path + ".bak").state.schema_version == 3, "migration keeps player inventory and backs up the previous schema")
	current_scene = app
	app.ui.open_panel("new_confirm")
	var seed_fields: Array = app.ui.body.get_children().filter(func(node): return node is LineEdit)
	check(seed_fields.size() == 1, "new game confirmation provides a seed input")
	app.new_game("2147483648")
	check(FileAccess.file_exists(path) and current_scene == app, "invalid seed leaves the existing campaign and checkpoint in place")
	if not seed_fields.is_empty():
		seed_fields[0].text_submitted.emit("12345")
	await process_frame
	await process_frame
	var next = current_scene
	check(is_instance_valid(next) and next != app and next.snapshot().world_states.layout.seed == 12345 and next.ui.panel_id.is_empty(), "seed input starts the specified world through the normal scene reload")
	if is_instance_valid(next):
		next.free()
	await process_frame
	var directory := path.get_base_dir()
	var prefix := path.get_file()
	var archives := 0
	for name in DirAccess.get_files_at(directory):
		if name.begins_with(prefix):
			if ".archive-" in name:
				archives += 1
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name)))
	check(archives == 2, "new campaign preserves both previous save files as archives")
	await test_survival(91)
	await test_survival(263)
	print("WORLD TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_workshop(app) -> void:
	var recipe := {"recipe": "lamp_kit"}
	var bench := {"cell": "0", "structure": "bench"}
	check(app.command("game.craft", recipe).code == "UNAVAILABLE", "crafting requires a workshop")
	check(follow(app, "outside"), "leave shelter to collect construction supplies")
	var street = app.scene_router.current_world()
	app.hero.position = app.scene_router.current_world().salvage_point()
	street.interact()
	check(app.last_result.ok and app.snapshot().world_states.salvage_ready_at.has("outside"), "street interaction collects salvage")
	street.interact()
	check(app.last_result.code == "UNAVAILABLE", "same pile cannot be looted again immediately")
	check(app.command("game.build", bench).code == "NOT_IN_SAFE_AREA", "construction is restricted to the shelter")
	check(app.transition("shelter").ok, "return to shelter with construction supplies")
	app.hero.position = Workshop.cell_rect("0").get_center()
	check(app.command("game.build", bench).code == "INVALID_STATE", "cannot build over the hero")
	app.hero.position = Vector2(174, 263)
	var shelter = app.scene_router.current_world()
	shelter.interact()
	var build_buttons: Array = app.ui.body.get_children().filter(func(node): return node is Button and node.text.begins_with("Построить верстак"))
	if app.ui.panel_id == "workshop" and not build_buttons.is_empty():
		build_buttons[0].pressed.emit()
	app.ui.close_panel()
	check(app.snapshot().shelter.get("buildings", {}) == {"0": "bench"} and shelter.building_bodies.has("0"), "workshop button builds a collidable bench")
	check(app.command("game.craft", recipe).code == "INSUFFICIENT_RESOURCES", "crafting rejects missing ingredients")
	check(app.command("clock.rest", {"target_minute": int(app.snapshot().game_time_minutes) + Workshop.SALVAGE_INTERVAL}).ok, "advance time until supplies renew")
	check(follow(app, "outside"), "return to the same salvage pile")
	app.hero.position = app.scene_router.current_world().salvage_point()
	app.scene_router.current_world().interact()
	check(app.last_result.ok and app.transition("shelter").ok, "salvage renews independently of the seed supply")
	var before_craft: Dictionary = app.snapshot()
	app.save_store.fault = "before_replace"
	check(app.command("game.craft", recipe).code == "SAVE_FAILED" and app.snapshot() == before_craft, "crafting rolls back both inputs and output on save failure")
	app.save_store.fault = ""
	var lamp := {"cell": "6", "structure": "lamp"}
	check(app.command("game.craft", recipe).ok and app.command("game.build", lamp).ok, "crafted kit can be built into a lamp")
	check(app.load_game().ok and app.scene_router.current_world().building_bodies.size() == 2, "load reconstructs both buildings and collision bodies")
	check(app.command("game.dismantle", {"cell": "6"}).ok and not app.scene_router.current_world().building_bodies.has("6"), "dismantling removes the building and collider")

func test_resident_work(app) -> void:
	var resident := {"resident_id": "resident_1"}
	var shift := {"resident_id": "resident_1", "job": "seed"}
	check(app.command("game.assign_shift", shift).code == "UNAVAILABLE", "only settled residents can work")
	check(follow(app, "outside") and follow(app, "louvre"), "reach the camp to recruit a resident")
	check(app.command("game.contact", resident).ok and app.command("game.consent", {"resident_id": "resident_1", "accept": true}).ok and app.command("game.recruit", resident).ok, "resident joins voluntarily with a food reserve")
	check(app.transition("shelter").ok and app.command("game.assign_shift", shift).ok, "assign a shift with unreserved food")
	check(app.command("game.collect_shift", resident).code == "UNAVAILABLE" and app.command("game.assign_shift", shift).code == "INVALID_STATE", "cannot collect early or replace an active shift")
	var due: int = int(app.snapshot().residents.records[0].shift.due)
	check(app.command("clock.rest", {"target_minute": due}).ok and app.snapshot().residents.records[0].shift.ready, "resident shift finishes on the shared calendar")
	check(app.load_game().ok and app.snapshot().residents.records[0].shift.ready, "completed work persists through reload")
	check(app.command("game.collect_shift", resident).ok and app.command("game.collect_shift", resident).code == "UNAVAILABLE", "resident production can only be collected once")
	check(app.command("game.assign_shift", shift).code == "INSUFFICIENT_RESOURCES", "reserved food cannot be spent on resident work")

func test_camp_network(app) -> void:
	var day := 2
	var minute := day * Camp.DAY + Camp.OPEN
	check(app.command("clock.rest", {"target_minute": minute}).ok, "rest reaches the next scouts' request window")
	check(follow(app, "outside"), "city access remains open after long rest")
	var street = app.scene_router.current_world()
	var neighbor: String = ""
	var missing: String = ""
	for district in range(1, Layout.DISTRICTS):
		var id := Layout.street(district)
		if id in street.layout.links:
			neighbor = id
		else:
			missing = id
	check(not missing.is_empty() and not app.transition(missing).ok, "cannot bypass an absent road with a default entry")
	check(not neighbor.is_empty() and follow(app, neighbor) and follow(app, "outside"), "generated road works in both directions")
	app.hero.position = app.scene_router.current_world().salvage_point()
	app.scene_router.current_world().interact()
	check(app.last_result.ok and follow(app, "louvre"), "bring supplies to the camp")
	var payload := {"day": day, "faction": "scouts"}
	check(app.command("game.trade_camp", {"faction": "scouts"}).code == "UNAVAILABLE", "trade requires faction trust")
	check(app.command("game.fulfill_contract", {"day": day - 1, "faction": "scouts"}).code == "UNAVAILABLE", "expired contract cannot charge the player")
	app.hero.position = Vector2(250, 190)
	app.scene_router.current_world().interact()
	var board: Array = app.ui.body.get_children().filter(func(node): return node is Button and node.text == "Объявления и торговля")
	if not board.is_empty():
		board[0].pressed.emit()
	var contract: Array = app.ui.body.get_children().filter(func(node): return node is Button and node.text == "Передать припасы")
	if not contract.is_empty():
		contract[0].pressed.emit()
	app.ui.close_panel()
	var network: Dictionary = app.snapshot().world_states.get("camp_network", {})
	check(network.get("reputation", {}).get("scouts") == 1 and app.command("game.fulfill_contract", payload).code == "UNAVAILABLE", "board grants trust and pays the request only once")
	check(app.command("game.trade_camp", {"faction": "scouts"}).ok and app.command("game.trade_camp", {"faction": "scouts"}).code == "UNAVAILABLE", "trusted trade has daily stock")
	check(app.load_game().ok and app.snapshot().world_states.camp_network.last_trade.scouts == day, "camp trust and stock survive reload")
	check(app.transition("shelter").ok and app.command("clock.rest", {"target_minute": (day + 1) * Camp.DAY + Camp.OPEN}).ok, "advance to the next request")
	check(Camp.schedule(int(app.snapshot().game_time_minutes), 54).faction == "settlers", "requests alternate factions on the shared calendar")
	check(follow(app, "outside") and follow(app, "louvre") and app.command("game.trade_camp", {"faction": "scouts"}).ok, "daily stock replenishes while the faction retains trust")

func test_patrol(app) -> void:
	check(follow(app, "outside") and app.enemy() == null, "starting district leaves the critical supply route open")
	var road: String = ""
	for id in app.scene_router.current_world().layout.links:
		if id.begins_with("street_"):
			road = id
			break
	check(not road.is_empty() and follow(app, road) and is_instance_valid(app.enemy()), "outer district mounts an independent patrol")
	var foe = app.enemy()
	if not is_instance_valid(foe):
		return
	var start: Vector2 = foe.position
	for frame in range(5):
		await physics_frame
	check(foe.position.distance_to(start) > 0.5 and foe.alert_remaining == 0, "unalerted enemy follows its patrol")
	app.hero.position = foe.position - Vector2(105, 0)
	app.hero.attack_cooldown = 0
	check(app.hero.try_attack(foe.position) and foe.alert_remaining > 0 and foe.last_noise == app.hero.position, "attack noise attracts the enemy outside sight range")
	foe.take_damage(23)
	check(follow(app, "outside") and follow(app, road) and app.enemy().health == 77, "street patrol retains damage across ordinary road transitions")
	foe = app.enemy()
	foe.health = 0
	app.enemy_defeated()
	check(road in app.snapshot().world_states.get("cleared_patrols", []), "patrol defeat is tracked per district")
	check(app.load_game().ok and app.enemy() == null, "cleared patrol stays gone after reloading")
	app.hero.position = app.scene_router.current_world().event_point()
	app.scene_router.current_world().interact()
	check(app.ui.panel_id == "district_event", "cleared district exposes its encounter through an in-world interaction")
	var event := DistrictEvents.event_for(app.snapshot(), road)
	var before: Dictionary = app.snapshot()
	if Logic.quantity(before, event.item) >= event.cost:
		app.ui.run_command("game.resolve_district", {"choice": "helped"})
		check(app.last_result.ok and app.snapshot().wallet.system_coins == before.wallet.system_coins + event.reward, "helping consumes the required supplies and pays the stated reward")
	else:
		app.ui.run_command("game.resolve_district", {"choice": "helped"})
		check(app.last_result.code == "INSUFFICIENT_RESOURCES" and app.snapshot() == before, "encounter refuses to spend unavailable supplies")
		app.ui.run_command("game.resolve_district", {"choice": "declined"})
	app.ui.close_panel()
	check(app.load_game().ok and app.snapshot().world_states.district_events.has(road) and app.command("game.resolve_district", {"choice": "helped"}).code == "UNAVAILABLE", "encounter outcome persists and cannot pay twice")

func measure_world_switches(app) -> void:
	if not follow(app, "outside"):
		check(false, "reach the switch measurement route")
		return
	await process_frame
	var before := OS.get_static_memory_usage()
	var timings := PackedFloat64Array()
	var streets := PackedFloat64Array()
	var interiors := PackedFloat64Array()
	var correct := true
	var hero = app.hero
	for index in range(24):
		var destination := "house_0" if index % 2 == 0 else "outside"
		var started := Time.get_ticks_usec()
		correct = follow(app, destination) and correct
		var milliseconds := (Time.get_ticks_usec() - started) / 1000.0
		timings.append(milliseconds)
		if destination == "outside":
			streets.append(milliseconds)
		else:
			interiors.append(milliseconds)
		correct = correct and app.get_node("WorldHost").get_child_count() == 3 and app.hero == hero
		await process_frame
	timings.sort()
	streets.sort()
	interiors.sort()
	print("LARGE MAP LOAD %s street_median_ms=%.3f interior_median_ms=%.3f" % [OS.get_name(), streets[6], interiors[6]])
	print("WORLD SWITCH METRICS %s n=%d median_ms=%.3f peak_ms=%.3f retained_engine_bytes=%d" % [OS.get_name(), timings.size(), timings[12], timings[23], OS.get_static_memory_usage() - before])
	check(correct, "24 consecutive transitions keep one mounted world, one camera and the same hero")

func test_expedition(app) -> void:
	var state: Dictionary = app.snapshot()
	var expected := Expedition.choose_target(state)
	check(not expected.is_empty() and app.command("game.accept_expedition").ok and app.snapshot().quests.expedition.target == expected, "camp assigns a hospital objective from the actual world")
	check(app.command("game.claim_expedition").code == "UNAVAILABLE", "expedition reward requires completing the objective")
	var nodes := Layout.from_manifest(state.world_states.layout)
	state.world_states.locations[expected] = {"defeated": true}
	check(Expedition.choose_target(state) != expected, "objective selector skips exhausted hospitals")
	for id in nodes:
		if id != "hospital" and nodes[id].kind == "hospital":
			state.world_states.locations[id] = {"defeated": true}
	check(Expedition.choose_target(state).is_empty(), "fully cleared world receives a supply objective")
	var path := Layout.route(nodes, "louvre", expected)
	var traversed: bool = path.size() > 1
	for id in path.slice(1):
		traversed = traversed and follow(app, id)
	check(traversed and is_instance_valid(app.enemy()), "generated route reaches the assigned enemy")
	var foe = app.enemy()
	if not is_instance_valid(foe):
		return
	var hospital = app.scene_router.current_world()
	var cache := Layout.hospital_cache(expected, app.snapshot().world_states.layout)
	app.hero.position = hospital.resource_point
	var cache_position: Vector2 = app.hero.position
	app.hero.health = 57
	foe.take_damage(31)
	var before_cache: Dictionary = app.snapshot()
	app.save_store.fault = "before_replace"
	hospital.interact()
	check(app.last_result.code == "SAVE_FAILED" and app.snapshot() == before_cache and app.hero.health == 57 and app.hero.position == cache_position, "failed loot autosave preserves committed state and live hero status")
	app.save_store.fault = ""
	hospital.interact()
	check(app.last_result.ok and app.last_result.data.type_id == cache.item, "hospital floor grants its configured supply")
	check(app.load_game().ok and app.hero.health == 57 and app.hero.position == cache_position and app.enemy().health == 69, "loot autosave restores hero position and HP together with enemy HP")
	hospital = app.scene_router.current_world()
	foe = app.enemy()
	hospital.interact()
	check(app.last_result.code == "UNAVAILABLE", "hospital supplies are finite")
	foe.health = 0
	app.enemy_defeated()
	check(app.snapshot().world_states.locations[expected] == {"cache_looted": true, "defeated": true}, "looting and defeat persist independently on one floor")
	path.reverse()
	for id in path.slice(1):
		traversed = traversed and follow(app, id)
	check(traversed and app.command("game.claim_expedition").ok, "completed expedition pays on returning to camp")
	check(app.load_game().ok and app.command("game.claim_expedition").code == "UNAVAILABLE", "expedition payout remains unique after reload")

func test_furniture(app) -> void:
	var cabinet := {"cell": "1", "structure": "cabinet"}
	var bed := {"cell": "2", "structure": "bed"}
	var materials := int(Workshop.STRUCTURES.cabinet.cost) + int(Workshop.STRUCTURES.bed.cost)
	for trip in range(3):
		if Logic.quantity(app.snapshot(), "material.salvage") >= materials:
			break
		app.transition("shelter")
		app.command("clock.rest", {"target_minute": int(app.snapshot().game_time_minutes) + Workshop.SALVAGE_INTERVAL})
		follow(app, "outside")
		app.hero.position = app.scene_router.current_world().salvage_point()
		app.scene_router.current_world().interact()
	check(app.transition("shelter").ok and app.command("game.build", cabinet).ok and app.command("game.build", bed).ok, "salvage supports separate storage and housing upgrades")
	var state: Dictionary = app.snapshot()
	var base: int = int(app.rules().containers[1].capacity_units)
	check(state.inventory.containers[1].capacity_units == base + Workshop.CABINET_CAPACITY and Work.duration(state, "resident_1") == Work.RESTED_DURATION, "cabinet adds storage and a bed shortens a resident shift")
	state.inventory.items.append({"instance_id": "fixture:full-cabinet", "type_id": "material.salvage", "container_id": "storage", "quantity": base + 1})
	check(app.save_store.write_checkpoint(state, Model.validate.bind(app.rules())).get("committed", false) and app.load_game().ok and app.scene_router.current_world().building_bodies.has("1"), "expanded storage and cabinet restore together")
	check(app.command("game.dismantle", {"cell": "1"}).code == "CAPACITY_EXCEEDED", "occupied capacity prevents cabinet demolition")
	var moved: Dictionary = app.command("inventory.transfer", {"instance_id": "fixture:full-cabinet", "from_id": "storage", "to_id": "player", "quantity": 1})
	check(moved.ok and app.command("game.dismantle", {"cell": "1"}).ok and app.snapshot().inventory.containers[1].capacity_units == base, "clearing excess stock allows demolition without item loss")

func test_survival(seed_value: int) -> void:
	var app = preload("res://game/scenes/main/playable.tscn").instantiate()
	var path := "user://world-tests/survival-%d-%s.json" % [seed_value, Time.get_ticks_usec()]
	app.save_location = path
	app.starting_seed = seed_value
	root.add_child(app)
	app.ui.close_panel()
	app.enemy().health = 0
	app.enemy_defeated()
	var exhausted: Dictionary = app.snapshot()
	exhausted.wallet.system_coins = 0
	var saved: bool = app.save_store.write_checkpoint(exhausted, Model.validate.bind(app.rules())).get("committed", false)
	check(saved and app.load_game().ok and Logic.quantity(app.snapshot(), "seed.basic") == 0, "seed %d starts the recovery route without seed or money" % seed_value)
	var viable := true
	for day in range(3):
		viable = follow(app, "outside") and viable
		app.hero.position = app.scene_router.current_world().resource_point
		app.scene_router.current_world().interact()
		viable = app.last_result.ok and app.transition("shelter").ok and viable
		viable = app.command("game.plant", {"plot_id": "plot_1"}).ok and app.command("game.water", {"plot_id": "plot_1"}).ok and viable
		viable = app.command("clock.rest", {"target_minute": app.next_harvest_minute()}).ok and app.command("game.harvest", {"plot_id": "plot_1"}).ok and viable
		viable = app.command("clock.rest", {"target_minute": (day + 1) * Camp.DAY}).ok and app.load_game().ok and viable
	check(viable and Logic.quantity(app.snapshot(), "crop.potato") == 9 and app.snapshot().wallet.system_coins == 0, "seed %d sustains three days of harvests with no purchases or optional orders" % seed_value)
	app.free()
	await process_frame
	for suffix in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
