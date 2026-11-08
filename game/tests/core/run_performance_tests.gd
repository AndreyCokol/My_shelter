extends SceneTree

# Compare lossless compact receipts against the historical full-response format.
# No action IDs or permanent rewards are dropped; replay remains exact.
const Model = preload("res://game/state/campaign_model.gd")
const Receipts = preload("res://game/systems/core/action_receipt.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Fixtures = preload("res://game/tests/core/campaign_fixtures.gd")

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var rules: Dictionary = Fixtures.rules()
	var state: Dictionary = Campaign.new(rules).coordinator.get_snapshot()
	var last_size: int = 0
	var last_bytes: int = 0
	for count in [100, 1000, 10000]:
		for index in range(last_size, count):
			var id := "perf:action:%d" % index
			var result := {"ok": true, "code": "OK", "action_id": id, "state_revision": index + 1, "data": {}, "message_key": "core.ok"}
			state.completed_actions[id] = Receipts.pack("f".repeat(64), result)
		state.state_revision = count
		var serialize_started: int = Time.get_ticks_usec()
		var size_bytes: int = JSON.stringify(state, "", true, true).to_utf8_buffer().size()
		var serialize_ms: float = (Time.get_ticks_usec() - serialize_started) / 1000.0
		var clone_started: int = Time.get_ticks_usec()
		var snapshot: Dictionary = state.duplicate(true)
		var clone_ms: float = (Time.get_ticks_usec() - clone_started) / 1000.0
		var validation_started: int = Time.get_ticks_usec()
		var valid: bool = Model.validate(snapshot, rules)
		var validate_ms: float = (Time.get_ticks_usec() - validation_started) / 1000.0
		print("RECEIPT PROFILE: actions=%d json_bytes=%d json_ms=%.3f duplicate_ms=%.3f validate_ms=%.3f" % [count, size_bytes, serialize_ms, clone_ms, validate_ms])
		check(valid and snapshot.completed_actions.size() == count and size_bytes > last_bytes, "A0-F05 snapshot remains valid at %d receipts and size growth is measurable" % count)
		last_bytes = size_bytes
		last_size = count
	# Same logical actions in the former wire format: measure real disk savings,
	# not a size comparison against a different number of operations.
	var legacy_state: Dictionary = state.duplicate(true)
	for id in legacy_state.completed_actions:
		var receipt: Array = legacy_state.completed_actions[id]
		legacy_state.completed_actions[id] = {"fingerprint": receipt[1],
			"result": {"ok": true, "code": "OK", "action_id": id,
				"state_revision": receipt[2], "data": receipt[3], "message_key": receipt[4]}}
	var historical_bytes: int = JSON.stringify(legacy_state, "", true, true).to_utf8_buffer().size()
	print("RECEIPT PACKING: actions=%d legacy_bytes=%d compact_bytes=%d saved_pct=%.2f" % [last_size, historical_bytes, last_bytes, 100.0 * (1.0 - float(last_bytes) / float(historical_bytes))])
	check(Model.validate(legacy_state, rules) and last_bytes * 10 < historical_bytes * 8, "lossless compact format reduces 10000 receipt save bytes by at least 20 percent")
	print("PERFORMANCE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
