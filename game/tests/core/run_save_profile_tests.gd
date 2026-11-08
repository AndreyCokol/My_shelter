extends SceneTree

# Issue #35/F05: isolated disk benchmark and safety check for durable receipts.
# Synthetic accepted receipts measure storage and load costs; they do NOT model
# a real 30-minute GUI session. Never touches the user's save slots.
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func with_receipts(original: Dictionary, count: int) -> Dictionary:
	var state: Dictionary = original.duplicate(true)
	for index in range(count):
		var id := "f05:profile:%d" % index
		state.completed_actions[id] = {
			"fingerprint": "f05:" + str(index),
			"result": {"ok": true, "code": "OK", "action_id": id,
				"state_revision": 0, "data": {}, "message_key": "core.ok"}
		}
	return state

func clean(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _initialize() -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	check(Campaign.valid_rules(rules), "F05 profiling rules and world are valid")
	var base: Dictionary = Campaign.new(rules).coordinator.get_snapshot()
	var previous_bytes := 0
	var previous_count := 0
	for count in [100, 1000, 10000]:
		var source: Dictionary = with_receipts(base, count)
		check(Model.validate(source, rules), "F05 state with %d synthetic receipts validates" % count)
		var path := "user://f05-save-profile/%d-%d.json" % [Time.get_ticks_usec(), count]
		var store = Store.new(path)
		clean(path)
		var started := Time.get_ticks_usec()
		var result: Dictionary = store.write_checkpoint(source, Model.validate.bind(rules))
		var write_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		check(result.get("committed", false), "F05 checkpoint with %d receipts was committed" % count)
		var bytes: int = FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
		check(bytes > previous_bytes and count > previous_count,
			"F05 durable checkpoint grows monotonically with receipt count %d" % count)
		started = Time.get_ticks_usec()
		var restored = Campaign.new(rules).coordinator
		var loaded: Dictionary = restored.load_checkpoint(store)
		var load_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		check(loaded.get("ok", false), "F05 checkpoint with %d receipts can load from disk" % count)
		var equivalent: bool = loaded.get("ok", false) and restored.get_snapshot() == source
		check(equivalent, "F05 %d receipt IDs and data survive load without pruning" % count)
		print("F05 SAVE PROFILE receipts=%d bytes=%d write_ms=%.3f load_ms=%.3f" %
			[count, bytes, write_ms, load_ms])
		previous_bytes = bytes
		previous_count = count
		clean(path)
	print("SAVE PROFILE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
