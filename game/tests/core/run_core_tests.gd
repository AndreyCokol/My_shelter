extends SceneTree

const Session = preload("res://game/systems/core/core_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Clock = preload("res://game/systems/core/game_clock.gd")
const Pauses = preload("res://game/systems/core/pause_registry.gd")
var failures: int = 0
var checks: int = 0
var emitted: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + label)
	else:
		print("PASS " + label)

func command(id: String, amount: int = 1) -> Dictionary:
	return {"action_id": id, "command_type": "core.increment", "context": {"actor_id": "test", "scene_id": "a"}, "payload": {"amount": amount}}

func _initialize() -> void:
	var store = Store.new("user://core-tests/" + str(Time.get_ticks_usec()) + ".json")
	var session = Session.new()
	session.committed.connect(func(_r): emitted += 1)
	var first: Dictionary = session.execute(command("one"), store)
	check(first.ok and first.data.counter == 1, "CT-01 first commit")
	var replay: Dictionary = session.execute(command("one"), store)
	check(replay.ok and replay.code == "ALREADY_APPLIED" and emitted == 1, "CT-01 replay has no events")
	check(session.execute(command("one", 2), store).code == "ACTION_CONFLICT", "CT-02 changed payload")
	check(session.execute(command("negative", -1), store).code == "INVALID_ARGUMENT", "reject negative input")
	session.execute(command("two"), store)
	var retry := command("one")
	retry.context = {"actor_id": "test", "scene_id": "other", "expected_resource_revisions": [{"key": "anything", "revision": 99}]}
	replay = session.execute(retry, store)
	check(replay.state_revision == first.state_revision and session.get_snapshot().counter == 2, "CT-33 historical receipt, current snapshot")
	var restarted = Session.new()
	check(restarted.load_checkpoint(store).ok and restarted.execute(retry, store).code == "ALREADY_APPLIED", "CT-22 replay after actual disk reload")
	var copy: Dictionary = restarted.get_snapshot()
	copy.counter = 400
	check(restarted.get_snapshot().counter == 2, "snapshot isolation")
	store.fault = "before_replace"
	check(session.execute(command("before"), store).code == "SAVE_FAILED" and session.get_snapshot().counter == 2, "CT-30 failure before commit")
	store.fault = "after_replace"
	check(session.execute(command("after"), store).code == "UNAVAILABLE" and session.get_snapshot().counter == 2, "CT-30 failure after disk before RAM")
	check(session.pauses.is_paused() and session.execute(command("blocked"), store).code == "UNAVAILABLE", "CT-30 recovery blocks mutations")
	store.fault = ""
	check(session.load_checkpoint(store).ok and session.get_snapshot().counter == 3, "CT-30 recover committed checkpoint")
	check(session.execute(command("after"), store).code == "ALREADY_APPLIED" and emitted == 2, "CT-30 no duplicate recovery effect")
	var corrupt: Dictionary = session.get_snapshot()
	# Compact receipts link the original revision at index 2.
	var corrupted_receipt: Array = corrupt.completed_actions["one"]
	corrupted_receipt[2] = 9999
	var primary_before := FileAccess.get_file_as_string(store.path)
	var backup_before := FileAccess.get_file_as_string(store.path + ".bak")
	check(not store.write_checkpoint(corrupt, Session.validate).committed, "checkpoint store rejects a new state with an invalid receipt")
	check(FileAccess.get_file_as_string(store.path) == primary_before and FileAccess.get_file_as_string(store.path + ".bak") == backup_before, "rejected new checkpoint preserves primary and backup bytes")
	# Restore the fixture even when a regression overwrites either file.
	var fixture := FileAccess.open(store.path + ".bak", FileAccess.WRITE)
	fixture.store_string(backup_before)
	fixture.close()
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	var loaded_count: Array = [0]
	session.state_loaded.connect(func(): loaded_count[0] += 1)
	check(not session.load_checkpoint(store).ok and session.get_snapshot().counter == 3 and loaded_count[0] == 0, "CT-29 invalid linked receipt leaves live session intact")
	check(session.load_checkpoint(store, true).ok and session.get_snapshot().counter == 2, "CT-11 explicit backup load")
	var rejected := FileAccess.get_file_as_bytes(store.path + ".rejected")
	check(rejected == JSON.stringify(corrupt).to_utf8_buffer(), "first backup restore retains the corrupted primary byte for byte")
	check(session.execute(command("after-backup"), store).ok, "CT-11 restored backup accepts subsequent writes")
	var displaced := FileAccess.get_file_as_bytes(store.path)
	check(session.load_checkpoint(store, true).ok and session.get_snapshot().counter == 2, "repeating backup restore is supported")
	check(FileAccess.get_file_as_bytes(store.path + ".rejected") == rejected and FileAccess.get_file_as_bytes(store.path + ".rejected.1") == displaced, "repeating restore keeps each displaced primary in its own archive")
	var malformed := command("bad-context")
	malformed.context = []
	check(session.execute(malformed, store).code == "INVALID_ARGUMENT", "malformed context rejected")
	var pause = Pauses.new()
	var menu: int = pause.acquire_pause("menu")
	var inventory: int = pause.acquire_pause("inventory")
	pause.release_pause(inventory)
	pause.release_pause(inventory)
	check(pause.is_paused(), "CT-31 nested pause retained")
	pause.release_pause(menu)
	check(not pause.is_paused(), "CT-31 last reason released")
	var a = Clock.new()
	var b = Clock.new()
	for i in range(600):
		a.tick(1.0 / 60.0, false)
	for i in range(300):
		b.tick(1.0 / 30.0, false)
	check(a.minute == 10 and b.minute == 10, "CT-23 same calendar at 30 and 60 FPS")
	a.tick(10.0, true)
	check(a.minute == 10, "CT-05 paused clock")
	var deadlines: Array = [{"minute": 12, "priority": 1, "entity_id": "a"}, {"minute": 10, "priority": 0, "entity_id": "b"}, {"minute": 10, "priority": 0, "entity_id": "a"}]
	var whole: Array = Clock.ordered_deadlines(deadlines, 0, 12)
	var split: Array = Clock.ordered_deadlines(deadlines, 0, 10) + Clock.ordered_deadlines(deadlines, 10, 12)
	check(whole == split and whole[0].entity_id == "a" and whole[2].minute == 12, "CT-32 ordered scheduler, split interval equivalence")
	# A0-F05: the UI/combat read must not walk the unbounded durable
	# receipt ledger or leak a mutable reference to the authoritative state.
	var full_record: Dictionary = session.get_snapshot()
	var quick_view: Dictionary = session.get_snapshot(false)
	check(not quick_view.has("completed_actions") and full_record.has("completed_actions")
		and full_record.completed_actions.size() > 0,
		"CT-92 lightweight combat snapshot excludes durable receipts without altering full snapshot")
	var original_counter: int = int(session.get_snapshot().counter)
	quick_view.counter = 999999
	check(session.get_snapshot().counter == original_counter,
		"CT-92 editing a lightweight combat snapshot does not mutate the authoritative core")
	# Trusted runtime veto: a real checkpoint, not a mocked write.
	var guarded = Session.new()
	var guard_store = Store.new(store.path + ".guard.json")
	check(guarded.execute(command("baseline"), guard_store).ok, "runtime veto baseline")
	check(guarded.execute(command("baseline2"), guard_store).ok, "runtime veto backup baseline")
	var baseline: Dictionary = guarded.get_snapshot()
	var guard_primary := FileAccess.get_file_as_bytes(guard_store.path)
	var guard_backup := FileAccess.get_file_as_bytes(guard_store.path + ".bak")
	var counts: Array = [0, 0, 0, 0]
	var decision: Array = [false]
	guarded.committed.connect(func(_r): counts[3] += 1)
	guarded.runtime_required = true
	guarded.runtime_preparer = func(_candidate, _reason):
		return {"ok": true, "precommit_check": func():
			counts[0] += 1
			return decision[0],
			"discard": func(): counts[1] += 1,
			"install": func():
				counts[2] += 1
				return true}
	check(guarded.execute(command("veto"), guard_store).code == "UNAVAILABLE", "precommit runtime veto rejects command")
	check(guarded.get_snapshot() == baseline and counts == [1, 1, 0, 0], "veto preserves RAM receipts and discards exactly once")
	check(FileAccess.get_file_as_bytes(guard_store.path) == guard_primary and FileAccess.get_file_as_bytes(guard_store.path + ".bak") == guard_backup, "veto preserves both checkpoint byte sequences")
	check(not guarded.is_busy() and not guarded.requires_recovery(), "veto leaves session available without recovery")
	check(guarded.load_checkpoint(guard_store, true).code == "UNAVAILABLE", "veto rejects explicit backup restore")
	check(guarded.get_snapshot() == baseline and counts == [2, 2, 0, 0] and not guarded.pauses.is_paused(), "load veto preserves RAM and releases load pause")
	check(FileAccess.get_file_as_bytes(guard_store.path) == guard_primary and FileAccess.get_file_as_bytes(guard_store.path + ".bak") == guard_backup and not FileAccess.file_exists(guard_store.path + ".rejected"), "backup veto does not replace or archive primary")
	decision[0] = "true"
	check(guarded.execute(command("veto"), guard_store).code == "UNAVAILABLE" and counts == [3, 3, 0, 0], "non-bool guard answer fails closed")
	decision[0] = true
	check(guarded.execute(command("veto"), guard_store).ok and counts == [4, 3, 1, 1], "same rejected action can be retried once approved")
	check(guarded.execute(command("veto"), guard_store).code == "ALREADY_APPLIED" and counts == [4, 3, 1, 1], "receipt replay bypasses runtime guard and install")
	guarded.runtime_preparer = func(_candidate, _reason):
		return {"ok": true, "precommit_check": Callable(), "discard": func(): counts[1] += 1}
	var approved: Dictionary = guarded.get_snapshot()
	check(guarded.execute(command("malformed-guard"), guard_store).code == "UNAVAILABLE" and guarded.get_snapshot() == approved and counts[1] == 4, "invalid callable fails closed and cleans up")
	# Compose the new veto with the real store fault seams. Approval alone
	# is not a commit; recovery must not replay effects or lose its pause.
	counts.fill(0)
	decision[0] = true
	guarded.runtime_preparer = func(_candidate, _reason):
		return {"ok": true, "precommit_check": func():
			counts[0] += 1
			return decision[0],
			"discard": func(): counts[1] += 1,
			"install": func():
				counts[2] += 1
				return true}
	var fault_primary := FileAccess.get_file_as_bytes(guard_store.path)
	var fault_backup := FileAccess.get_file_as_bytes(guard_store.path + ".bak")
	guard_store.fault = "before_replace"
	check(guarded.execute(command("guard-fault"), guard_store).code == "SAVE_FAILED", "approved guard cannot bypass pre-replace write failure")
	check(guarded.get_snapshot() == approved and counts == [1, 1, 0, 0] and not guarded.is_busy() and not guarded.requires_recovery(), "pre-replace failure discards approved runtime without publishing")
	check(FileAccess.get_file_as_bytes(guard_store.path) == fault_primary and FileAccess.get_file_as_bytes(guard_store.path + ".bak") == fault_backup, "approved guard with failed write preserves checkpoint bytes")
	guard_store.fault = "after_replace"
	check(guarded.execute(command("guard-fault"), guard_store).code == "UNAVAILABLE", "approved guard enters recovery after durable replacement")
	check(guarded.get_snapshot() == approved and counts == [2, 2, 0, 0] and guarded.requires_recovery() and guarded.pauses.is_paused(), "post-replace failure does not install or emit and retains recovery pause")
	guard_store.fault = ""
	var durable_primary := FileAccess.get_file_as_bytes(guard_store.path)
	var durable_backup := FileAccess.get_file_as_bytes(guard_store.path + ".bak")
	check(durable_primary != fault_primary, "post-replace fault really changed durable primary")
	decision[0] = false
	check(guarded.load_checkpoint(guard_store).code == "UNAVAILABLE", "guard may reject primary reload during recovery")
	check(guarded.get_snapshot() == approved and counts == [3, 3, 0, 0] and guarded.requires_recovery() and guarded.pauses.is_paused() and not guarded.is_busy(), "veto releases load pause but preserves recovery barrier")
	check(FileAccess.get_file_as_bytes(guard_store.path) == durable_primary and FileAccess.get_file_as_bytes(guard_store.path + ".bak") == durable_backup, "recovery veto leaves durable files intact")
	check(guarded.execute(command("guard-fault"), guard_store).code == "UNAVAILABLE" and counts == [3, 3, 0, 0], "recovery barrier blocks retry before runtime preparation")
	decision[0] = true
	check(guarded.load_checkpoint(guard_store).ok and counts == [4, 3, 1, 0] and not guarded.requires_recovery() and not guarded.pauses.is_paused(), "approved reload installs durable state and clears recovery")
	check(guarded.get_snapshot().counter == approved.counter + 1 and guarded.execute(command("guard-fault"), guard_store).code == "ALREADY_APPLIED" and counts == [4, 3, 1, 0], "recovered receipt prevents duplicated command effect and runtime install")
	guarded.runtime_preparer = Callable()
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".rejected"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(guard_store.path + suffix))
	for suffix in ["", ".tmp", ".bak", ".rejected", ".rejected.1"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + suffix))
	print("CORE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
