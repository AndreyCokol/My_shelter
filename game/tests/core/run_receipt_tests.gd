extends SceneTree

# Lossless persisted receipt packing: exact replays, legacy migration and
# failure barriers. No completed action is ever removed or forgotten.
const Session = preload("res://game/systems/core/core_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Receipts = preload("res://game/systems/core/action_receipt.gd")

var checks: int = 0
var failures: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1
		push_error(description)

func action(id: String, amount: int = 1) -> Dictionary:
	return {"action_id": id, "command_type": "core.increment",
		"context": {"actor_id": "test", "scene_id": "any"},
		"payload": {"amount": amount}}

func write_raw(path: String, state: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state, "", true, true))
	file.close()
	return true

func _initialize() -> void:
	var location := "user://receipt-packing/" + str(Time.get_ticks_usec()) + ".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(location).get_base_dir())
	var store = Store.new(location)
	var session = Session.new()
	var first: Dictionary = session.execute(action("first", 3), store)
	check(first.ok and first.data.counter == 3, "compact first transaction commits")
	var first_receipt = session.get_snapshot().completed_actions["first"]
	check(first_receipt is Array and first_receipt.size() == 5 and first_receipt[0] == Receipts.FORMAT, "one durable action occupies compact receipt v1")
	check(Receipts.data(first_receipt) == first.data, "compact linked receipt retains full domain payload")
	check(session.execute(action("first", 3), store).code == "ALREADY_APPLIED" and session.get_snapshot().counter == 3, "same ID replays without mutation")
	check(session.execute(action("first", 2), store).code == "ACTION_CONFLICT", "same ID with changed semantic payload rejected")
	var loaded = Session.new()
	check(loaded.load_checkpoint(store).ok and loaded.execute(action("first", 3), store).state_revision == first.state_revision, "compact receipt survives actual disk reload")
	check(loaded.execute(action("first", 3), store).data == first.data, "replay returns the original response body")

	# Simulate a real historical JSON checkpoint, without changing schema_version.
	var legacy_state: Dictionary = session.get_snapshot()
	legacy_state.completed_actions["first"] = {"fingerprint": Receipts.fingerprint(first_receipt),
		"result": {"ok": true, "code": "OK", "action_id": "first",
			"state_revision": first.state_revision,
			"data": first.data.duplicate(true), "message_key": "core.ok"}}
	var legacy_store = Store.new(location + ".legacy")
	check(Session.validate(legacy_state) and write_raw(legacy_store.path, legacy_state), "historical full receipt JSON validates")
	var legacy_session = Session.new()
	check(legacy_session.load_checkpoint(legacy_store).ok, "old JSON checkpoint loads without up-front migration")
	check(legacy_session.execute(action("first", 3), legacy_store).code == "ALREADY_APPLIED", "old receipt replay works before conversion")
	var historical_bytes := FileAccess.get_file_as_string(legacy_store.path)
	legacy_store.fault = "before_replace"
	check(legacy_session.execute(action("blocked"), legacy_store).code == "SAVE_FAILED" and FileAccess.get_file_as_string(legacy_store.path) == historical_bytes, "precommit write failure never changes a legacy receipt or primary save")
	check(legacy_session.get_snapshot().completed_actions["first"] is Dictionary, "failed save leaves old live record intact")
	legacy_store.fault = ""
	check(legacy_session.execute(action("second", 2), legacy_store).ok, "new transaction commits after legacy load")
	var migrated: Dictionary = legacy_session.get_snapshot()
	check(migrated.completed_actions["first"] is Array and migrated.completed_actions["second"] is Array, "one durable commit compacts canonical historical receipt")
	check(migrated.counter == 5 and migrated.completed_actions.size() == 2, "compaction neither loses actions nor replays side effects")
	var recovered = Session.new()
	check(recovered.load_checkpoint(legacy_store).ok and recovered.execute(action("first", 3), legacy_store).code == "ALREADY_APPLIED" and recovered.execute(action("second", 2), legacy_store).code == "ALREADY_APPLIED", "all old and new IDs replay after restart")
	check(recovered.execute(action("first", 1), legacy_store).code == "ACTION_CONFLICT", "legacy collision detection preserved after conversion")
	var backup = Session.new()
	check(backup.load_checkpoint(legacy_store, true).ok and backup.execute(action("first", 3), legacy_store).code == "ALREADY_APPLIED", "legacy-format backup remains readable during explicit recovery")

	# Tamper with a compact receipt: validation must reject before live state swap.
	var corrupted: Dictionary = recovered.get_snapshot()
	var broken: Array = corrupted.completed_actions["first"]
	broken[2] = int(corrupted.state_revision) + 10
	var corrupt_store = Store.new(location + ".corrupt")
	check(write_raw(corrupt_store.path, corrupted), "create damaged receipt fixture")
	var safe_before: Dictionary = recovered.get_snapshot()
	check(not recovered.load_checkpoint(corrupt_store).ok and recovered.get_snapshot() == safe_before, "invalid compact receipt rejected without touching live session")
	for target in [store.path, legacy_store.path, corrupt_store.path]:
		for suffix in ["", ".tmp", ".bak", ".rejected"]:
			if FileAccess.file_exists(target + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(target + suffix))
	print("RECEIPT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
