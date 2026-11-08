extends SceneTree

# A0-F09: all paid work shifts use configured edible food, never the
# potato constant, and NEVER spend a resident's persistent food reservation.
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Work = preload("res://game/systems/shelter/resident_work.gd")
const Receipts = preload("res://game/systems/core/action_receipt.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
var checks := 0
var failures := 0
var serial := 0

func check(ok: bool, title: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + title)
	if not ok:
		failures += 1
		push_error(title)

func request(session, type: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": "resident-work:%d" % serial, "command_type": type,
		"payload": payload, "context": {"actor_id": "player",
			"scene_id": state.scene.current_scene_id, "expected_resource_revisions": revisions}}

func config(mode: String, food_ids: Array = ["crop.potato"]) -> Dictionary:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	rules.food.reserve_mode = mode
	rules.food.accepted_food_type_ids = food_ids.duplicate()
	rules.items["food.test_ration"] = {"name": "Тестовый паёк", "edible": true}
	return rules

func make_session(rules: Dictionary, food_type: String, quantity: int) -> Dictionary:
	var state: Dictionary = Model.new_state(rules)
	# Trusted fixture: first victory already recorded and NPC contact is at
	# louvre. All subsequent actions use real transactional CoreSession.
	state.scene.current_scene_id = "louvre"
	state.scene.entry_point_id = "default"
	state.world_states.first_enemy_defeated = true
	state.story_flags.append("system_unlocked")
	state.claimed_reward_ids.append("system")
	check(Logic.give(state, rules, food_type, quantity, "work-food-start"), "fixture gives allowed food stock " + food_type)
	check(Model.validate(state, rules), "fixture is a valid procedural checkpoint " + food_type)
	var path := "user://work-food/%s-%d.json" % [food_type.replace(".", "-"), Time.get_ticks_usec()]
	var store = Store.new(path)
	check(store.write_checkpoint(state, Model.validate.bind(rules)).get("committed", false), "fixture checkpoint written")
	var campaign = Campaign.new(rules)
	check(campaign.coordinator.load_checkpoint(store).ok, "fixture loaded by real coordinator")
	return {"campaign": campaign, "session": campaign.coordinator, "store": store}

func join_and_go_home(session, store) -> void:
	var resident := {"resident_id": "resident_1"}
	check(session.execute(request(session, "game.contact", resident), store).ok, "resident contact from louvre")
	check(session.execute(request(session, "game.consent", {"resident_id": "resident_1", "accept": true}), store).ok, "resident consents voluntarily")
	check(session.execute(request(session, "game.recruit", resident), store).ok, "resident recruited with a durable food receipt")
	check(session.execute(request(session, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}), store).ok, "shelter available after recruiting")

func cleanup(path: String) -> void:
	for suffix in ["", ".bak", ".tmp", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _initialize() -> void:
	check(Work.FOOD_UNITS_PER_SHIFT == 1, "one unit of free edible food per shift")
	for mode in ["reserve", "consume"]:
		var rules := config(mode, ["food.test_ration"])
		check(Rules.validate(rules), "custom ration catalog validates " + mode)
		var fixture := make_session(rules, "food.test_ration", 3)
		var session = fixture.session
		var store = fixture.store
		join_and_go_home(session, store)
		var base: Dictionary = session.get_snapshot()
		var reserved: int = base.inventory.reservations.size()
		check(Logic.quantity(base, "food.test_ration") == 1 and reserved == (1 if mode == "reserve" else 0), "recruiting keeps only one free ration " + mode)
		var cmd: Dictionary = request(session, "game.assign_shift", {"resident_id": "resident_1", "job": "seed"})
		var before_failed: Dictionary = session.get_snapshot()
		store.fault = "before_replace"
		check(session.execute(cmd, store).code == "SAVE_FAILED" and session.get_snapshot() == before_failed, "failed work ration commit rolls back inventory, shift and receipt " + mode)
		store.fault = ""
		var paid: Dictionary = session.execute(cmd, store)
		check(paid.ok and paid.data.get("work_ration", {}).get("type_id") == "food.test_ration" and paid.data.work_ration.quantity == 1, "worker spends configured non-potato food " + mode)
		var after: Dictionary = session.get_snapshot()
		check(Logic.quantity(after, "food.test_ration") == 0 and after.inventory.reservations.size() == reserved and Model.validate(after, rules), "worker never consumes a reserved ration " + mode)
		check(session.execute(cmd, store).code == "ALREADY_APPLIED" and session.get_snapshot() == after, "work payment replay is idempotent " + mode)
		var due: int = int(after.residents.records[0].shift.due)
		check(session.execute(request(session, "clock.rest", {"target_minute": due}), store).ok and session.get_snapshot().residents.records[0].shift.ready, "work reaches ready state through shared calendar " + mode)
		var recovered = Campaign.new(rules)
		check(recovered.coordinator.load_checkpoint(store).ok and recovered.coordinator.get_snapshot().residents.records[0].shift.ready, "ready shift persists after disk reload " + mode)
		check(recovered.coordinator.execute(request(recovered.coordinator, "game.collect_shift", {"resident_id": "resident_1"}), store).ok, "collected production from food-funded shift " + mode)
		var empty: Dictionary = recovered.coordinator.get_snapshot()
		check(recovered.coordinator.execute(request(recovered.coordinator, "game.assign_shift", {"resident_id": "resident_1", "job": "sort"}), store).code == "INSUFFICIENT_RESOURCES" and recovered.coordinator.get_snapshot() == empty, "reserved or depleted food cannot fund another shift " + mode)
		cleanup(store.path)

	# Multiple valid foods and stacks: catalog priority wins, then stable
	# instance_id ordering; inventory insertion/reordering cannot affect payment.
	var mixed_rules := config("consume", ["food.test_ration", "crop.potato"])
	var mixed := make_session(mixed_rules, "crop.potato", 2)
	join_and_go_home(mixed.session, mixed.store)
	var reorder: Dictionary = mixed.session.get_snapshot()
	check(Logic.give(reorder, mixed_rules, "food.test_ration", 1, "z-ration") and Logic.give(reorder, mixed_rules, "food.test_ration", 1, "a-ration") and Logic.give(reorder, mixed_rules, "crop.potato", 1, "potato-extra"), "multiple certified food stacks prepared")
	reorder.inventory.items.reverse()
	check(mixed.store.write_checkpoint(reorder, Model.validate.bind(mixed_rules)).get("committed", false) and mixed.session.load_checkpoint(mixed.store).ok, "reordered multi-food inventory survives save/load")
	for expected in ["game:a-ration", "game:z-ration", "game:potato-extra"]:
		var action: Dictionary = mixed.session.execute(request(mixed.session, "game.assign_shift", {"resident_id": "resident_1", "job": "sort"}), mixed.store)
		var expected_type := "crop.potato" if expected == "game:potato-extra" else "food.test_ration"
		check(action.ok and action.data.work_ration.instance_id == expected and action.data.work_ration.type_id == expected_type, "deterministic mixed food payment selects " + expected)
		var due: int = int(mixed.session.get_snapshot().residents.records[0].shift.due)
		check(mixed.session.execute(request(mixed.session, "clock.rest", {"target_minute": due}), mixed.store).ok and mixed.session.execute(request(mixed.session, "game.collect_shift", {"resident_id": "resident_1"}), mixed.store).ok, "consecutive mixed food shift finishes and collects " + expected)
	check(mixed.session.execute(request(mixed.session, "game.assign_shift", {"resident_id": "resident_1", "job": "sort"}), mixed.store).code == "INSUFFICIENT_RESOURCES", "mixed ration catalog refuses a shift after all available food is consumed")
	cleanup(mixed.store.path)

	# Actual historical potato-reserve save after a ruleset food rebalance:
	# old joined NPC uses historical ration while NEW work uses the new whitelist.
	var old_rules := config("reserve")
	var legacy := make_session(old_rules, "crop.potato", 2)
	join_and_go_home(legacy.session, legacy.store)
	var old_state: Dictionary = legacy.session.get_snapshot()
	check(old_state.inventory.reservations.size() == 1 and Logic.quantity(old_state, "crop.potato") == 0, "historical potato is fully reserved")
	var new_rules := config("reserve", ["food.test_ration"])
	var loaded = Campaign.new(new_rules)
	check(loaded.coordinator.load_checkpoint(legacy.store).ok, "old potato resident survives configured food change")
	var before_no_food: Dictionary = loaded.coordinator.get_snapshot()
	check(loaded.coordinator.execute(request(loaded.coordinator, "game.assign_shift", {"resident_id": "resident_1", "job": "seed"}), legacy.store).code == "INSUFFICIENT_RESOURCES" and loaded.coordinator.get_snapshot() == before_no_food, "old reserved potato cannot fund newly configured rations")
	var stocked: Dictionary = loaded.coordinator.get_snapshot()
	check(Logic.give(stocked, new_rules, "food.test_ration", 1, "new-work-ration") and legacy.store.write_checkpoint(stocked, Model.validate.bind(new_rules)).get("committed", false) and loaded.coordinator.load_checkpoint(legacy.store).ok, "new edible ration supplied without changing old food receipt")
	var job_result: Dictionary = loaded.coordinator.execute(request(loaded.coordinator, "game.assign_shift", {"resident_id": "resident_1", "job": "seed"}), legacy.store)
	check(job_result.ok and job_result.data.work_ration.type_id == "food.test_ration" and loaded.coordinator.get_snapshot().inventory.reservations.size() == 1, "rebalance worker consumes new food and keeps old reserve")
	check(Receipts.data(loaded.coordinator.get_snapshot().completed_actions[job_result.action_id]).work_ration.type_id == "food.test_ration", "actual ration encoded in durable action receipt")
	cleanup(legacy.store.path)
	print("RESIDENT WORK FOOD TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
