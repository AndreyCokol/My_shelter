extends SceneTree

# F03: proof that common sub-minute frames avoid a full campaign copy while
# preserving the clock, pause, save/load and custom calendar gate contracts.
const Rules = preload("res://game/data/game_rules.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
var checks: int = 0
var failures: int = 0
var time_events: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func receive_time(event: Dictionary) -> void:
	if event.event_type == "time_advanced":
		time_events += 1

func save_request(session, action_id: String) -> Dictionary:
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": action_id, "command_type": "session.save", "payload": {},
		"context": {"actor_id": "player", "scene_id": state.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

func _initialize() -> void:
	var rules := Rules.build()
	var fast = Campaign.new(rules)
	var slow = Campaign.new(rules)
	fast.coordinator.events.subscribe(self, receive_time)
	var successful := true
	for i in range(59):
		successful = fast.tick(1.0 / 60.0) and successful
	var state: Dictionary = fast.coordinator.get_snapshot()
	check(successful and state.game_time_minutes == 0 and fast._fractional_fast_ticks == 59,
		"F03: 59 fractional frames use scalar-only path")
	check(state.state_revision == 59 and is_equal_approx(state.clock_remainder, 59.0 / 60.0) and time_events == 0,
		"F03: fractional ticks retain old revision semantics without time event")
	check(fast.tick(1.0 / 60.0) and fast._fractional_fast_ticks == 59,
		"F03: minute boundary uses full validated calendar path")
	state = fast.coordinator.get_snapshot()
	check(state.game_time_minutes == 1 and is_zero_approx(state.clock_remainder) and time_events == 1 and state.state_revision == 60,
		"F03: exactly one minute and one notification at boundary")
	check(slow.tick(1.0) and slow.coordinator.get_snapshot().game_time_minutes == state.game_time_minutes
		and is_equal_approx(slow.coordinator.get_snapshot().clock_remainder, state.clock_remainder),
		"F03: 60 fractional frames and one one-minute tick agree on time")

	var paused = fast.coordinator.pauses.acquire_pause("modal")
	var before: Dictionary = fast.coordinator.get_snapshot()
	check(not fast.tick(0.25) and fast.coordinator.get_snapshot() == before,
		"F03: pause prevents scalar updates and revisions")
	fast.coordinator.pauses.release_pause(paused)
	check(fast.tick(0.25) and fast._fractional_fast_ticks == 60,
		"F03: resumed sub-minute tick uses fast path")

	var path := "user://tick-fastpath-tests/" + str(Time.get_ticks_usec()) + ".json"
	var store = Store.new(path)
	var saved: Dictionary = fast.coordinator.execute(save_request(fast.coordinator, "clock-save"), store)
	check(saved.get("ok", false), "F03: explicit checkpoint saves fractional remainder")
	var persisted: Dictionary = fast.coordinator.get_snapshot()
	var reloaded = Campaign.new(rules)
	check(reloaded.coordinator.load_checkpoint(store).get("ok", false)
		and reloaded.coordinator.get_snapshot() == persisted,
		"F03: restart restores fractional remainder, revision and receipts exactly")
	check(reloaded.tick(0.75) and reloaded.coordinator.get_snapshot().game_time_minutes == 2
		and is_zero_approx(reloaded.coordinator.get_snapshot().clock_remainder),
		"F03: restored fraction crosses next whole-minute boundary once")

	var custom = Campaign.new(rules)
	var rejecting_provider = func(_state: Dictionary, _from: int, _to: int): return {"ok": false}
	var handler = func(_state: Dictionary, _entry: Dictionary): return {"ok": true, "events": []}
	check(custom.configure_calendar(rejecting_provider, handler), "F03: custom gate installs successfully")
	before = custom.coordinator.get_snapshot()
	check(not custom.tick(0.1) and custom._fractional_fast_ticks == 0
		and custom.coordinator.get_snapshot() == before,
		"F03: a custom provider can still refuse a zero-minute tick")
	check(not fast.tick(INF) and not fast.tick(NAN) and not fast.tick(-1.0),
		"F03: nonfinite and negative time still rejected")

	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("TICK FASTPATH TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
