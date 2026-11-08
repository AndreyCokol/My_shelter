extends SceneTree

# F03 reproducible synthetic stress benchmark. Never uses production save slots.
# Measures wall-clock tick cost of builtin fast path vs the previous validated
# runtime path with a 4-district procedural world and 100/1000/10000 receipts.
# The latter is purposefully selected ONLY in this isolated test fixture.
# This is not a graphical FPS or heap-allocation profiler.
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Model = preload("res://game/state/campaign_model.gd")
const FRAMES := 24
var checks: int = 0
var failures: int = 0

func check(ok: bool, name: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		failures += 1
		push_error(name)

func seeded_fixture(base: Dictionary, receipts: int) -> Dictionary:
	var state: Dictionary = base.duplicate(true)
	for i in range(receipts):
		var id := "perf:receipt:%d" % i
		state.completed_actions[id] = {"fingerprint": "perf:" + str(i),
			"result": {"ok": true, "code": "OK", "action_id": id,
				"state_revision": 0, "data": {}, "message_key": "core.ok"}}
	return state

func run_ticks(campaign) -> Dictionary:
	var started := Time.get_ticks_usec()
	var all_ok := true
	for frame in range(FRAMES):
		all_ok = campaign.tick(1.0 / 600.0) and all_ok
	return {"ok": all_ok, "millis": float(Time.get_ticks_usec() - started) / 1000.0}

func _initialize() -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	check(Campaign.valid_rules(rules), "profiling world and rules validate")
	print("F03 PROFILE scenes=%d frames=%d (not GUI/FPS measurement)" % [rules.scenes.size(), FRAMES])
	var sample = Campaign.new(rules)
	for count in [100, 1000, 10000]:
		var synthetic: Dictionary = seeded_fixture(sample.coordinator.get_snapshot(), count)
		check(Model.validate(synthetic, rules), "synthetic %d receipt fixture validates" % count)
		var fast = Campaign.new(rules)
		var baseline = Campaign.new(rules)
		# Test-only validated state injection, NEVER exposed to the player.
		fast.coordinator._state = synthetic.duplicate(true)
		baseline.coordinator._state = synthetic.duplicate(true)
		# Select previous full runtime path without modifying the production
		# calendar implementation or disabling deadline processing.
		baseline._builtin_calendar = false
		var measured_fast: Dictionary = run_ticks(fast)
		var measured_baseline: Dictionary = run_ticks(baseline)
		var same: bool = fast.coordinator.get_snapshot() == baseline.coordinator.get_snapshot()
		check(measured_fast.ok and measured_baseline.ok and same and fast._fractional_fast_ticks == FRAMES,
			"fast and fallback snapshots exactly match with %d receipts" % count)
		print("F03 PROFILE receipts=%d scene_count=%d fast_ms=%.3f full_ms=%.3f serialized_bytes=%d" %
			[count, rules.scenes.size(), measured_fast.millis, measured_baseline.millis,
				JSON.stringify(synthetic).to_utf8_buffer().size()])
	print("TICK PROFILE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
