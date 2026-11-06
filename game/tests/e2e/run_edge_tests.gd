extends SceneTree

const Rules = preload("res://game/data/game_rules.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
var checks: int = 0
var failures: int = 0
var serial: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func req(session, kind: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	var state: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in state.resource_revisions:
		versions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": "edge-" + str(serial), "command_type": kind, "payload": payload, "context": {"actor_id": "player", "scene_id": state.scene.current_scene_id, "expected_resource_revisions": versions}}

func home(session, store) -> void:
	session.execute(req(session, "game.enemy_defeated"), store)
	session.execute(req(session, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}), store)
	session.execute(req(session, "inventory.claim_parcel", {"parcel_id": "starter"}), store)

func _initialize() -> void:
	var rules := Rules.build()
	var campaign = Campaign.new(rules)
	var session = campaign.coordinator
	var path := "user://edges/" + str(Time.get_ticks_usec()) + ".json"
	var store = Store.new(path)
	home(session, store)
	for id in ["plot_1", "plot_2"]:
		session.execute(req(session, "game.plant", {"plot_id": id}), store)
		session.execute(req(session, "game.water", {"plot_id": id}), store)
	var before: Dictionary = session.get_snapshot()
	store.fault = "before_replace"
	check(session.execute(req(session, "clock.rest", {"target_minute": 180}), store).code == "SAVE_FAILED" and session.get_snapshot() == before, "real crop rest write failure leaves both plots and clock unchanged")
	store.fault = ""
	check(session.execute(req(session, "clock.rest", {"target_minute": 300}), store).ok and session.get_snapshot().crops.plots.all(func(p): return p.status == "spoiled"), "long rest crosses maturity and exact spoil boundary for both plots")
	check(session.execute(req(session, "game.harvest", {"plot_id": "plot_1"}), store).code == "INVALID_STATE", "cannot harvest at spoil_at")
	check(session.execute(req(session, "game.clear", {"plot_id": "plot_1"}), store).ok and session.execute(req(session, "game.plant", {"plot_id": "plot_1"}), store).ok, "spoiled plot can be cleared and replanted")
	var bad: Dictionary = session.get_snapshot()
	bad.crops.plots[0].ripe_at = -1
	check(not Model.validate(bad, rules), "negative crop deadline rejected")
	bad = session.get_snapshot()
	bad.inventory.items.append(null)
	check(not Model.validate(bad, rules), "malformed inventory rejected before reservation cross validation")
	bad = session.get_snapshot()
	bad.inventory.containers[0].capacity_units = 999
	check(not Model.validate(bad, rules), "save cannot inflate catalog container capacity")
	var stale := req(session, "game.water", {"plot_id": "plot_1"})
	campaign.tick(1.0)
	check(session.execute(stale, store).ok, "clock-only tick does not stale farm resource revision")
	check(session.execute(stale, store).code == "ALREADY_APPLIED", "water receipt replays after state changes")
	check(session.execute(req(session, "scene.transition", {"destination_scene_id": "outside", "entry_point_id": "default"}), store).ok, "leave shelter after crop operations")
	check(session.execute(req(session, "game.resource_collect"), store).ok, "renewable source first collection")
	campaign.tick(float(rules.resource_respawn_minutes))
	check(session.execute(req(session, "game.resource_collect"), store).ok, "renewable source available at exact cooldown boundary")
	check(session.execute(req(session, "clock.rest", {"target_minute": 1000}), store).code == "NOT_IN_SAFE_AREA", "real gameplay refuses unsafe rest")
	# Full-inventory harvest must leave the plot ripe and food ungranted.
	var small_rules := Rules.build()
	small_rules.containers[0].capacity_units = 5
	var full = Campaign.new(small_rules)
	var fullstore = Store.new(path + ".full")
	home(full.coordinator, fullstore)
	full.coordinator.execute(req(full.coordinator, "game.plant", {"plot_id": "plot_1"}), fullstore)
	full.coordinator.execute(req(full.coordinator, "game.water", {"plot_id": "plot_1"}), fullstore)
	full.tick(180.0)
	before = full.coordinator.get_snapshot()
	check(full.coordinator.execute(req(full.coordinator, "game.harvest", {"plot_id": "plot_1"}), fullstore).code == "CAPACITY_EXCEEDED" and full.coordinator.get_snapshot() == before, "full inventory harvest preserves ripe crop and all resources")
	# Food modes and alternate balance values, including insufficient supply.
	for mode in ["reserve", "consume"]:
		for units in [1, 3]:
			var config := Rules.build()
			config.food.reserve_mode = mode
			config.food.units_per_resident = units
			var run = Campaign.new(config)
			var target = run.coordinator
			var targetstore = Store.new(path + "." + mode + str(units))
			home(target, targetstore)
			target.execute(req(target, "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}), targetstore)
			target.execute(req(target, "game.contact", {"resident_id": "resident_1"}), targetstore)
			target.execute(req(target, "game.consent", {"resident_id": "resident_1", "accept": false}), targetstore)
			check(target.execute(req(target, "game.recruit", {"resident_id": "resident_1"}), targetstore).code == "REQUIRES_CONSENT", "explicit decline respected " + mode + str(units))
			target.execute(req(target, "game.consent", {"resident_id": "resident_1", "accept": true}), targetstore)
			before = target.get_snapshot()
			check(target.execute(req(target, "game.recruit", {"resident_id": "resident_1"}), targetstore).code == "INSUFFICIENT_RESOURCES" and target.get_snapshot() == before and before.residents.records[0].status == "AWAITING_SUPPLIES", "insufficient food preserves consent without partial reserve " + mode + str(units))
			target.execute(req(target, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}), targetstore)
			target.execute(req(target, "game.plant", {"plot_id": "plot_1"}), targetstore)
			target.execute(req(target, "game.water", {"plot_id": "plot_1"}), targetstore)
			run.tick(180.0)
			target.execute(req(target, "game.harvest", {"plot_id": "plot_1"}), targetstore)
			target.execute(req(target, "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}), targetstore)
			var food_before := Logic.quantity(target.get_snapshot(), "crop.potato")
			check(target.execute(req(target, "game.recruit", {"resident_id": "resident_1"}), targetstore).ok and Logic.quantity(target.get_snapshot(), "crop.potato") == food_before - units, "configured food rule applied " + mode + str(units))
			check(Model.validate(target.get_snapshot(), config), "food accounting remains valid " + mode + str(units))
			cleanup(targetstore.path)
	# Corruption cannot partially replace any live domain.
	before = session.get_snapshot()
	var corrupt := before.duplicate(true)
	corrupt.quests.records[0].status = "bad"
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	check(not session.load_checkpoint(store).ok and session.get_snapshot() == before, "corrupt quest rejects entire live campaign import")
	check(session.load_checkpoint(store, true).ok, "explicit backup recovery works with real domain schema")
	cleanup(store.path)
	cleanup(fullstore.path)
	print("EDGE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
