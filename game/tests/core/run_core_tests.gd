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
	corrupt.completed_actions.one.result.state_revision = 9999
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
	check(session.execute(command("after-backup"), store).ok, "CT-11 restored backup accepts subsequent writes")
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
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + suffix))
	print("CORE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
