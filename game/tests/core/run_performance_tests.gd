extends SceneTree

# Read-only synthetic benchmark of the existing durable receipt format.
# No production receipt deletion: replay of arbitrary action_id stays exact.
const Model = preload("res://game/state/campaign_model.gd")
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
			state.completed_actions[id] = {"fingerprint": "f".repeat(64), "result": result}
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
	print("PERFORMANCE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
