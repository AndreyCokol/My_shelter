extends SceneTree

const DistrictEvents = preload("res://game/systems/world/district_events.gd")
const Expedition = preload("res://game/systems/world/expedition_order.gd")
const Camp = preload("res://game/systems/world/camp_network.gd")
const Work = preload("res://game/systems/shelter/resident_work.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Workshop = preload("res://game/systems/shelter/construction.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
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

func follow(app, target: String) -> bool:
	var world = app.scene_router.current_world()
	for portal in world.portals:
		if portal.to == target:
			app.hero.position = portal.position
			world.interact()
			return app.snapshot().scene.current_scene_id == target
	return false

func run() -> void:
	var geometry := {}
	var signatures := {}
	var road_signatures := {}
	var valid_graphs := true
	for seed_value in range(128):
		var nodes := Layout.build(seed_value)
		road_signatures[JSON.stringify(nodes.outside.links)] = true
		var reachable := {"shelter": true}
		var frontier := ["shelter"]
		var used := {}
		for id in nodes:
			var entry: Dictionary = nodes[id]
			valid_graphs = valid_graphs and entry.links.size() <= Layout.DOORS.size() and not used.has(entry.segment)
			used[entry.segment] = true
			for target in entry.links:
				valid_graphs = valid_graphs and id in nodes[target].links
			if not geometry.has(entry.segment):
				geometry[entry.segment] = entry
		while not frontier.is_empty():
			var id = frontier.pop_back()
			for target in nodes[id].links:
				if not reachable.has(target):
					reachable[target] = true
					frontier.append(target)
		valid_graphs = valid_graphs and reachable.size() == 26 and used.size() == 26
		signatures[JSON.stringify(used.keys())] = true
	check(valid_graphs and signatures.size() > 1, "128 seeds produce connected graphs and distinct assignments")
	check(road_signatures.size() > 3, "new seeds vary the actual roads and keep every district reachable")
	check(Layout.build(54) == Layout.build(54), "same seed reconstructs exact layout")
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
	check(follow(app, "outside") and follow(app, "hospital") and follow(app, "hospital_0_2"), "hospital entry and stairs reach the selected floor")
	var floor_enemy = app.enemy()
	floor_enemy.health = 0
	app.enemy_defeated()
	check(app.snapshot().world_states.locations.hospital_0_2.defeated and app.snapshot().claimed_reward_ids == ["system"], "floor enemy persists without duplicating onboarding reward")
	app.hero.position = Vector2(310, 270)
	check(app.transition("shelter").ok and app.transition("hospital_0_2").ok and app.hero.position == Vector2(310, 270), "shelter return restores exact floor and coordinates")
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
	original.world_states.layout = current_layout
	check(app.save_store.write_checkpoint(original, Model.validate.bind(app.rules())).get("committed", false) and app.load_game().ok, "restore current layout for remaining gameplay checks")
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
	app.hero.position = Workshop.SALVAGE_POINT
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
	app.hero.position = Workshop.SALVAGE_POINT
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
	app.hero.position = Workshop.SALVAGE_POINT
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
	check(follow(app, "outside") and follow(app, road), "player can abandon a fight and return by the same road")
	foe = app.enemy()
	foe.health = 0
	app.enemy_defeated()
	check(road in app.snapshot().world_states.get("cleared_patrols", []), "patrol defeat is tracked per district")
	check(app.load_game().ok and app.enemy() == null, "cleared patrol stays gone after reloading")
	app.hero.position = DistrictEvents.POINT
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
	var correct := true
	var hero = app.hero
	for index in range(24):
		var destination := "house_0" if index % 2 == 0 else "outside"
		var started := Time.get_ticks_usec()
		correct = follow(app, destination) and correct
		timings.append((Time.get_ticks_usec() - started) / 1000.0)
		correct = correct and app.get_node("WorldHost").get_child_count() == 3 and app.hero == hero
		await process_frame
	timings.sort()
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
	hospital.interact()
	check(app.last_result.ok and app.last_result.data.type_id == cache.item, "hospital floor grants its configured supply")
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
		app.hero.position = Workshop.SALVAGE_POINT
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
