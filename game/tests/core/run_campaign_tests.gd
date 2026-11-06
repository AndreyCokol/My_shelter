extends SceneTree

const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func fixture_rules() -> Dictionary:
	# Technical fixtures, not accepted product balance or literary content.
	return {"version": "test-v1", "minutes_per_real_second": 1.0, "discovery_xp": 5,
		"items": {"seed.basic": {}, "tool.basic": {}},
		"containers": [{"id": "player", "capacity_units": 20}, {"id": "storage", "capacity_units": 100}],
		"scenes": {"shelter": ["default"], "outside": ["default"]},
		"offers": {"seed": {"type_id": "seed.basic", "quantity": 2, "price": 3}},
		"parcels": {"starter": {"type_id": "seed.basic", "quantity": 3, "coins": 10, "eligible": true}},
		"rewards": {"first": {"type_id": "tool.basic", "quantity": 1, "hero_xp": 7, "eligible": true}, "locked": {"type_id": "tool.basic", "quantity": 1, "eligible": false}}}

func request(session, id: String, kind: String, payload: Dictionary) -> Dictionary:
	var state: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in state.resource_revisions:
		versions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": id, "command_type": kind, "context": {"actor_id": "player", "scene_id": state.scene.current_scene_id, "expected_resource_revisions": versions}, "payload": payload}

func _initialize() -> void:
	var config := fixture_rules()
	check(Campaign.valid_rules(config), "valid technical rules")
	var bad := config.duplicate(true)
	bad.offers.seed.price = -1
	check(not Campaign.valid_rules(bad), "negative rule price rejected")
	var campaign = Campaign.new(config)
	var session = campaign.coordinator
	var store = Store.new("user://campaign-tests/" + str(Time.get_ticks_usec()) + ".json")
	var purchase := request(session, "buy-empty", "inventory.purchase", {"offer_id": "seed"})
	check(session.execute(purchase, store).code == "INSUFFICIENT_RESOURCES" and session.get_snapshot().completed_actions.is_empty(), "CT-03 insufficient coins, no receipt")
	var parcel := request(session, "parcel", "inventory.claim_parcel", {"parcel_id": "starter"})
	check(session.execute(parcel, store).ok, "parcel grants items and coins together")
	check(session.get_snapshot().wallet.system_coins == 10 and session.get_snapshot().shelter.xp == 5, "discovery XP on first type")
	check(session.execute(request(session, "parcel-other-id", "inventory.claim_parcel", {"parcel_id": "starter"}), store).code == "INVALID_STATE", "parcel semantic ID prevents second claim")
	purchase = request(session, "buy", "inventory.purchase", {"offer_id": "seed"})
	campaign.tick(1.5)
	check(session.execute(purchase, store).ok, "CT-19 clock tick does not stale inventory purchase")
	check(session.get_snapshot().wallet.system_coins == 7 and session.get_snapshot().shelter.xp == 5, "CT-04 repeated type grants no discovery XP")
	check(session.execute(request(session, "reward", "progression.claim_reward", {"reward_id": "first"}), store).ok, "once-only reward")
	check(session.get_snapshot().player.xp == 7 and session.get_snapshot().shelter.xp == 10, "independent XP counters")
	check(session.execute(request(session, "locked", "progression.claim_reward", {"reward_id": "locked"}), store).code == "UNAVAILABLE", "ineligible reward rejected")
	var stale := request(session, "stale", "inventory.purchase", {"offer_id": "seed"})
	var transfer := request(session, "split", "inventory.transfer", {"instance_id": "grant:parcel", "from_id": "player", "to_id": "storage", "quantity": 2})
	check(session.execute(transfer, store).ok, "split stack transfer")
	var stale_result: Dictionary = session.execute(stale, store)
	check(stale_result.code == "STALE_REVISION" and "inventory:player" in stale_result.data.conflict_keys, "CT-19 genuine resource conflict")
	var before: Dictionary = session.get_snapshot()
	check(session.execute(request(session, "overdraw", "inventory.transfer", {"instance_id": "grant:parcel", "from_id": "player", "to_id": "storage", "quantity": 99}), store).code == "INSUFFICIENT_RESOURCES" and session.get_snapshot() == before, "transfer overdraw atomic")
	var full_rules := fixture_rules()
	full_rules.offers.seed.quantity = 1000
	var full = Campaign.new(full_rules).coordinator
	var full_store = Store.new(store.path + ".full")
	full.execute(request(full, "starter", "inventory.claim_parcel", {"parcel_id": "starter"}), full_store)
	var full_before: Dictionary = full.get_snapshot()
	check(full.execute(request(full, "full-buy", "inventory.purchase", {"offer_id": "seed"}), full_store).code == "CAPACITY_EXCEEDED" and full.get_snapshot() == full_before, "CT-03 full inventory preserves coins/items")
	var outside := request(session, "outside", "scene.transition", {"destination_scene_id": "outside", "entry_point_id": "default"})
	check(session.execute(outside, store).ok, "scene DTO transition")
	check(session.execute(request(session, "unsafe-rest", "clock.rest", {"target_minute": 100}), store).code == "NOT_IN_SAFE_AREA", "rest outside safe scene rejected")
	check(session.execute(request(session, "home", "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}), store).ok, "scene DTO round trip")
	check(session.execute(request(session, "rest", "clock.rest", {"target_minute": 100}), store).ok, "rest uses persistent calendar")
	var loaded = Campaign.new(config).coordinator
	var load_result: Dictionary = loaded.load_checkpoint(store)
	check(load_result.ok and loaded.get_snapshot() == session.get_snapshot(), "CT-10 full supported campaign state reload")
	check(loaded.execute(parcel, store).code == "ALREADY_APPLIED" and loaded.get_snapshot().wallet.system_coins == 7, "CT-22 replay across state/scene revisions")
	store.fault = "before_replace"
	before = session.get_snapshot()
	check(session.execute(request(session, "save-fail", "inventory.purchase", {"offer_id": "seed"}), store).code == "SAVE_FAILED" and session.get_snapshot() == before, "CT-20 purchase I/O failure rolls back all domains")
	store.fault = "after_replace"
	check(session.execute(request(session, "commit-recover", "inventory.purchase", {"offer_id": "seed"}), store).code == "UNAVAILABLE", "campaign commit enters recovery")
	store.fault = ""
	check(session.load_checkpoint(store).ok and session.get_snapshot().wallet.system_coins == 4, "campaign recovery restores exactly one purchase")
	var pause_token: int = session.pauses.acquire_pause("menu")
	var paused_before: Dictionary = session.get_snapshot()
	check(not campaign.tick(10.0) and session.get_snapshot() == paused_before, "paused campaign tick has no mutation")
	check(session.execute(request(session, "paused-buy", "inventory.purchase", {"offer_id": "seed"}), store).code == "PAUSED", "paused purchase rejected")
	check(session.execute(request(session, "menu-save", "session.save", {}), store).ok, "explicit save permitted from pause menu")
	session.pauses.release_pause(pause_token)
	var unknown := request(session, "unknown-field", "inventory.purchase", {"offer_id": "seed", "price": 0})
	check(session.execute(unknown, store).code == "INVALID_ARGUMENT", "client cannot override catalog price")
	var missing := request(session, "missing-revision", "inventory.purchase", {"offer_id": "seed"})
	missing.context.erase("expected_resource_revisions")
	check(session.execute(missing, store).code == "INVALID_ARGUMENT", "required optimistic revisions cannot be omitted")
	var corrupt: Dictionary = session.get_snapshot()
	corrupt.inventory.items[0].container_id = "missing"
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	before = session.get_snapshot()
	check(not session.load_checkpoint(store).ok and session.get_snapshot() == before, "CT-29 cross-domain invalid item prevents entire import")
	var mismatch := fixture_rules()
	mismatch.version = "test-v2"
	var wrong = Campaign.new(mismatch).coordinator
	check(not wrong.load_checkpoint(full_store).ok, "ruleset mismatch refused without migration")
	for path in [store.path, full_store.path]:
		for suffix in ["", ".tmp", ".bak", ".rejected"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("CAMPAIGN TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
