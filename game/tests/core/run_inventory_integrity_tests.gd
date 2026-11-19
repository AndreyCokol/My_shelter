extends SceneTree
# A1 disposable QA fixture: inventory conservation, rollback, durable receipt replay.
# Current capacity_units are counted units, NOT accepted physical weights.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Fixtures = preload("res://game/tests/core/campaign_fixtures.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS " + description)
	else:
		failures += 1
		push_error("FAIL " + description)

func request(session, id: String, kind: String, payload: Dictionary) -> Dictionary:
	var snap: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in snap.resource_revisions:
		versions.append({"key": key, "revision": snap.resource_revisions[key]})
	return {"action_id": id, "command_type": kind,
		"context": {"actor_id": "player", "scene_id": snap.scene.current_scene_id,
			"expected_resource_revisions": versions}, "payload": payload}

func totals(state: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for item in state.inventory.items:
		counts[item.type_id] = int(counts.get(item.type_id, 0)) + int(item.quantity)
	return counts

func first_in(state: Dictionary, container: String) -> Dictionary:
	for item in state.inventory.items:
		if item.type_id == "seed.basic" and item.container_id == container:
			return item
	return {}

func valid(session, config: Dictionary, expected: Dictionary) -> bool:
	var state: Dictionary = session.get_snapshot()
	return Model.validate(state, config) and totals(state) == expected

func cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func run() -> void:
	var config: Dictionary = Fixtures.rules()
	check(Campaign.valid_rules(config), "technical campaign fixture")
	var session = Campaign.new(config).coordinator
	if session == null:
		check(false, "campaign coordinator")
		quit(1)
		return
	var path: String = "user://a1-inventory-integrity-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store = Store.new(path)
	var parcel: Dictionary = session.execute(request(session, "a1-parcel", "inventory.claim_parcel", {"parcel_id": "starter"}), store)
	var reward: Dictionary = session.execute(request(session, "a1-reward", "progression.claim_reward", {"reward_id": "first"}), store)
	var expected := {"seed.basic": 3, "tool.basic": 1}
	check(parcel.ok and reward.ok and valid(session, config, expected), "two grants conserve four item units")
	var source: Dictionary = first_in(session.get_snapshot(), "player")
	if source.is_empty():
		check(false, "starter seed stack exists")
		cleanup(path)
		quit(1)
		return
	var full: Dictionary = request(session, "a1-full-out", "inventory.transfer",
		{"instance_id": source.instance_id, "from_id": "player", "to_id": "storage", "quantity": 3})
	check(session.execute(full, store).ok and valid(session, config, expected), "full stack transfer")
	var back: Dictionary = request(session, "a1-full-back", "inventory.transfer",
		{"instance_id": source.instance_id, "from_id": "storage", "to_id": "player", "quantity": 3})
	check(session.execute(back, store).ok and valid(session, config, expected), "full stack return")
	var frozen: Dictionary = session.get_snapshot()
	check(session.execute(back, store).code == "ALREADY_APPLIED" and session.get_snapshot() == frozen,
		"full transfer action cannot be applied twice")
	var stable: bool = true
	for i in range(32):
		var from_id: String = "player" if i % 2 == 0 else "storage"
		var to_id: String = "storage" if from_id == "player" else "player"
		var item: Dictionary = first_in(session.get_snapshot(), from_id)
		if item.is_empty():
			stable = false
			break
		var move: Dictionary = request(session, "a1-move-%02d" % i, "inventory.transfer",
			{"instance_id": item.instance_id, "from_id": from_id, "to_id": to_id, "quantity": 1})
		var outcome: Dictionary = session.execute(move, store)
		if not outcome.ok or not valid(session, config, expected):
			stable = false
			break
		var after: Dictionary = session.get_snapshot()
		if session.execute(move, store).code != "ALREADY_APPLIED" or session.get_snapshot() != after:
			stable = false
			break
		if i % 8 == 7:
			var loaded = Campaign.new(config).coordinator
			if not loaded.load_checkpoint(store).ok or loaded.get_snapshot() != after:
				stable = false
				break
			session = loaded
	check(stable and valid(session, config, expected),
		"32 transfer/replay pairs and 4 actual disk reloads conserve items")
	var chosen: Dictionary = first_in(session.get_snapshot(), "player")
	if chosen.is_empty():
		check(false, "seed remains after stress")
		cleanup(path)
		quit(1)
		return
	var cases: Array = [
		{"id": "zero", "n": 0, "from": "player", "to": "storage", "error": "INVALID_ARGUMENT"},
		{"id": "overdraw", "n": int(chosen.quantity) + 1, "from": "player", "to": "storage", "error": "INSUFFICIENT_RESOURCES"},
		{"id": "self", "n": 1, "from": "player", "to": "player", "error": "INVALID_ARGUMENT"},
		{"id": "wrong-source", "n": 1, "from": "storage", "to": "player", "error": "INVALID_STATE"}
	]
	for case in cases:
		var before: Dictionary = session.get_snapshot()
		var bad: Dictionary = request(session, "a1-reject-" + case.id, "inventory.transfer",
			{"instance_id": chosen.instance_id, "from_id": case["from"], "to_id": case["to"], "quantity": case.n})
		var answer: Dictionary = session.execute(bad, store)
		check(answer.code == case.error and session.get_snapshot() == before, "reject " + case.id + " without state change")
	var before_failure: Dictionary = session.get_snapshot()
	var io_request: Dictionary = request(session, "a1-retry", "inventory.transfer",
		{"instance_id": chosen.instance_id, "from_id": "player", "to_id": "storage", "quantity": 1})
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	store.fault = "before_replace"
	var failed: Dictionary = session.execute(io_request, store)
	store.fault = ""
	check(failed.code == "SAVE_FAILED" and session.get_snapshot() == before_failure
		and FileAccess.get_file_as_bytes(path) == bytes_before, "failed disk commit cannot mutate state or file")
	var retry: Dictionary = session.execute(io_request, store)
	var committed: Dictionary = session.get_snapshot()
	check(retry.ok and valid(session, config, expected), "retry after disk failure commits once")
	check(session.execute(io_request, store).code == "ALREADY_APPLIED" and session.get_snapshot() == committed,
		"retry receipt cannot duplicate movement")
	var restarted = Campaign.new(config).coordinator
	check(restarted.load_checkpoint(store).ok and restarted.get_snapshot() == committed
		and valid(restarted, config, expected), "final durable restart reproduces full inventory and receipts")
	cleanup(path)
	print("INVENTORY INTEGRITY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
