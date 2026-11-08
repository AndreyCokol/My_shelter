extends SceneTree

const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Calendar = preload("res://game/systems/core/calendar_planner.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Fixtures = preload("res://game/tests/core/campaign_fixtures.gd")
const GameRules = preload("res://game/data/game_rules.gd")
var checks: int = 0
var failures: int = 0
var notifications: Array = []
var boundaries: Array = [
	{"minute": 8, "priority": 1, "entity_id": "b"},
	{"minute": 5, "priority": 2, "entity_id": "story"},
	{"minute": 5, "priority": 0, "entity_id": "b"},
	{"minute": 5, "priority": 1, "entity_id": "a"},
	{"minute": 5, "priority": 0, "entity_id": "a"}]
var fail_entity: String = ""
var deny: bool = false

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func receive(event: Dictionary) -> void:
	notifications.append(event)

func source(_state: Dictionary, from: int, target: int):
	if deny:
		return {"ok": false}
	return boundaries.filter(func(e): return e.minute > from and e.minute <= target)

func consume(state: Dictionary, entry: Dictionary) -> Dictionary:
	# Synthetic persisted effect; no Farm/Quest implementation is claimed.
	state.player.xp += 1
	if entry.entity_id == fail_entity:
		return {"ok": false}
	return {"ok": true, "events": [{"event_type": "fixture_boundary", "payload": entry.duplicate(true)}]}

func request(session, id: String, target: int) -> Dictionary:
	return {"action_id": id, "command_type": "clock.rest", "context": {"actor_id": "player", "scene_id": session.get_snapshot().scene.current_scene_id}, "payload": {"target_minute": target}}

func make_campaign():
	var campaign = Campaign.new(Fixtures.rules())
	campaign.configure_calendar(source, consume)
	return campaign

func check_gameplay_ticks(store) -> void:
	var campaign := Campaign.new(GameRules.build())
	var session = campaign.coordinator
	session.events.subscribe(self, receive)
	var planted: bool = session.apply_runtime(func(state):
		state.crops.plots[0].merge({"status": "growing", "ripe_at": 1, "spoil_at": 2}, true)
		return true)
	check(planted, "production clock fixture has one growing crop")
	notifications.clear()
	var start: Dictionary = session.get_snapshot()
	var all_ticks_ok := true
	for frame in range(59):
		all_ticks_ok = campaign.tick(1.0 / 60.0) and all_ticks_ok
	var partial: Dictionary = session.get_snapshot()
	check(all_ticks_ok and partial.game_time_minutes == 0 and is_equal_approx(partial.clock_remainder, 59.0 / 60.0) and partial.state_revision == start.state_revision + 59 and notifications.is_empty(), "production subminute ticks retain fractional time and revisions without events")
	var token: int = session.pauses.acquire_pause("test")
	check(not campaign.tick(1.0 / 60.0) and session.get_snapshot() == partial, "paused production tick preserves fractional time and revisions")
	session.pauses.release_pause(token)
	var save := {"action_id": "gameplay-clock-save", "command_type": "session.save", "payload": {}, "context": {"actor_id": "player", "scene_id": "hospital"}}
	check(session.execute(save, store).ok, "production checkpoint saves a fractional minute")
	var reloaded := Campaign.new(GameRules.build())
	var resumed = reloaded.coordinator
	check(resumed.load_checkpoint(store).ok and is_equal_approx(resumed.get_snapshot().clock_remainder, partial.clock_remainder), "production checkpoint restores fractional time")
	resumed.events.subscribe(self, receive)
	notifications.clear()
	var before_boundary: Dictionary = resumed.get_snapshot()
	check(reloaded.tick(1.0 / 60.0), "production tick reaches the crop boundary after reload")
	var after_boundary: Dictionary = resumed.get_snapshot()
	check(after_boundary.game_time_minutes == 1 and after_boundary.crops.plots[0].status == "ripe" and after_boundary.resource_revisions.farm == before_boundary.resource_revisions.farm + 1, "minute boundary commits farm state with the clock")
	check(notifications.map(func(e): return e.event_type) == ["time_advanced", "crop_changed"] and notifications.all(func(e): return e.game_minute == 1 and e.state_revision == after_boundary.state_revision), "production boundary publishes time and crop events at one revision")
	check(resumed.execute(save, store).code == "ALREADY_APPLIED" and resumed.get_snapshot() == after_boundary, "calendar tick retains saved command receipts for replay")
	var presentation: Dictionary = resumed.get_snapshot(false)
	presentation.crops.plots[0].status = "empty"
	check(not presentation.has("completed_actions") and resumed.get_snapshot() == after_boundary, "presentation snapshot omits receipts and isolates nested state")

	var revision_at_limit: bool = resumed.apply_runtime(func(state):
		state.resource_revisions.farm = Calendar.MAX_MINUTE
		return true)
	var before_failure: Dictionary = resumed.get_snapshot()
	notifications.clear()
	check(revision_at_limit and not reloaded.tick(1.0) and resumed.get_snapshot() == before_failure and notifications.is_empty(), "invalid deadline update rolls back clock, crop, revisions and events")
	check(reloaded.configure_calendar(source, consume), "production campaign accepts a replacement calendar adapter")
	deny = true
	check(not reloaded.tick(0.1) and resumed.get_snapshot() == before_failure, "replacement provider can veto even a fractional tick")
	deny = false

func _initialize() -> void:
	var campaign = make_campaign()
	var session = campaign.coordinator
	var store = Store.new("user://calendar-tests/" + str(Time.get_ticks_usec()) + ".json")
	session.events.subscribe(self, receive)
	var rest := request(session, "rest", 10)
	check(session.execute(rest, store).ok, "rest commits all calendar boundaries")
	var state: Dictionary = session.get_snapshot()
	check(state.game_time_minutes == 10 and state.player.xp == 5, "all fixture effects share authoritative calendar")
	var ordered: Array = []
	for event in notifications:
		if event.event_type == "fixture_boundary":
			ordered.append([event.payload.minute, event.payload.priority, event.payload.entity_id])
	check(ordered == [[5, 0, "a"], [5, 0, "b"], [5, 1, "a"], [5, 2, "story"], [8, 1, "b"]], "CT-44 time, phase and entity order")
	check(notifications.filter(func(e): return e.event_type == "fixture_boundary").all(func(e): return e.game_minute == e.payload.minute), "deadline envelope preserves boundary minute despite later commit")
	check(notifications.size() == 6 and notifications[0].event_type == "time_advanced", "time notification precedes ordered domain notifications")
	check(notifications.all(func(e): return e.state_revision == state.state_revision), "one revision for whole rest plan")
	notifications.clear()
	check(session.execute(rest, store).code == "ALREADY_APPLIED" and notifications.is_empty() and session.get_snapshot() == state, "calendar replay never reprocesses boundaries")
	var natural = make_campaign()
	check(natural.tick(10.0) and natural.coordinator.get_snapshot().player.xp == state.player.xp, "CT-44 tick uses same planner as rest")
	var small = make_campaign()
	for i in range(10):
		small.tick(1.0)
	check(small.coordinator.get_snapshot().player.xp == state.player.xp and small.coordinator.get_snapshot().game_time_minutes == 10, "CT-44 large and small advances equivalent")
	var fractional = make_campaign()
	check(fractional.tick(0.4) and fractional.coordinator.get_snapshot().player.xp == 0, "fractional tick does not cross boundary")
	var token: int = fractional.coordinator.pauses.acquire_pause("modal")
	var before: Dictionary = fractional.coordinator.get_snapshot()
	check(not fractional.tick(9.0) and fractional.coordinator.get_snapshot() == before, "modal pause preserves remainder and domains")
	fractional.coordinator.pauses.release_pause(token)
	check(fractional.coordinator.execute(request(fractional.coordinator, "fractional-rest", 5), store).ok and fractional.coordinator.get_snapshot().clock_remainder == 0, "explicit integer rest resets fractional remainder")
	check(fractional.tick(0.6) and fractional.coordinator.get_snapshot().game_time_minutes == 5, "old remainder cannot skip minute after rest")

	boundaries[1].interactive = true
	var stopped = make_campaign()
	var stopped_result: Dictionary = stopped.coordinator.execute(request(stopped.coordinator, "stop", 10), store)
	check(stopped_result.ok and stopped_result.data.actual_to_minute == 5 and stopped_result.data.interrupted, "CT-45 rest stops at interactive boundary")
	check(stopped.coordinator.get_snapshot().player.xp == 4, "stop completes all phases at same minute, excludes later ones")
	var tick_stop = make_campaign()
	check(tick_stop.tick(10.7) and tick_stop.coordinator.get_snapshot().game_time_minutes == 5 and tick_stop.coordinator.get_snapshot().clock_remainder == 0, "tick stop discards unconsumed frame time")
	# Domain adapter must expose persisted pending-choice state as a gate.
	deny = true
	before = stopped.coordinator.get_snapshot()
	check(not stopped.tick(10.0) and stopped.coordinator.get_snapshot() == before, "domain gate prevents next tick from skipping pending choice")
	check(stopped.coordinator.execute(request(stopped.coordinator, "denied", 9), store).code == "UNAVAILABLE" and stopped.coordinator.get_snapshot() == before, "domain gate refuses rest atomically")
	deny = false
	boundaries[1].erase("interactive")

	var failing = make_campaign()
	failing.coordinator.events.subscribe(self, receive)
	notifications.clear()
	before = failing.coordinator.get_snapshot()
	fail_entity = "story"
	check(not failing.tick(10.0) and failing.coordinator.get_snapshot() == before and notifications.is_empty(), "late handler failure rolls back tick and events")
	check(failing.coordinator.execute(request(failing.coordinator, "failed", 10), store).code == "INVALID_STATE" and failing.coordinator.get_snapshot() == before, "late handler failure rolls back rest and receipt")
	fail_entity = ""
	store.fault = "before_replace"
	check(failing.coordinator.execute(request(failing.coordinator, "write-fail", 10), store).code == "SAVE_FAILED" and failing.coordinator.get_snapshot() == before and notifications.is_empty(), "rest I/O failure discards all planned effects")
	store.fault = "after_replace"
	var recover := request(failing.coordinator, "recover", 10)
	check(failing.coordinator.execute(recover, store).code == "UNAVAILABLE" and failing.coordinator.get_snapshot() == before and notifications.is_empty(), "postcommit interruption publishes no partial calendar")
	store.fault = ""
	check(failing.coordinator.load_checkpoint(store).ok and failing.coordinator.get_snapshot().player.xp == 5, "recovery loads committed calendar effects exactly once")
	notifications.clear()
	check(failing.coordinator.execute(recover, store).code == "ALREADY_APPLIED" and notifications.is_empty(), "recovered rest receipt remains silent")

	var invalid = make_campaign()
	before = invalid.coordinator.get_snapshot()
	boundaries.append(boundaries[0].duplicate(true))
	check(not invalid.tick(10.0) and invalid.coordinator.get_snapshot() == before, "duplicate deadline identity rejected before effects")
	boundaries.pop_back()
	boundaries.append({"minute": 7, "priority": -1, "entity_id": "bad"})
	check(not invalid.tick(10.0) and invalid.coordinator.get_snapshot() == before, "malformed deadline rejects whole plan")
	boundaries.pop_back()
	check(not invalid.configure_calendar(source, Callable()), "partial adapter configuration refused")
	check(invalid.tick(10.0) and invalid.coordinator.get_snapshot().player.xp == 5, "failed configuration preserves working adapters")
	var expired = make_campaign()
	var owner = Node.new()
	check(expired.configure_calendar(owner.get_child_count, owner.get_child_count), "trusted callable pair can be installed")
	owner.free()
	check(not expired.tick(10.0) and expired.coordinator.get_snapshot().game_time_minutes == 0, "destroyed adapter fails closed instead of silently skipping deadlines")
	var overflow = make_campaign()
	before = overflow.coordinator.get_snapshot()
	check(not overflow.tick(INF) and not overflow.tick(NAN) and not overflow.tick(-1) and not overflow.tick(1.0e300) and overflow.coordinator.get_snapshot() == before, "nonfinite and out of range delta refused without conversion")
	var fast_rules := Fixtures.rules()
	fast_rules.minutes_per_real_second = 1.0e300
	var fast = Campaign.new(fast_rules)
	check(not fast.tick(1.0e300) and fast.coordinator.get_snapshot().game_time_minutes == 0, "finite rate times finite delta overflow rejected")
	var bootstrap = preload("res://game/systems/core/game_clock.gd").new()
	bootstrap.minutes_per_real_second = -1
	check(bootstrap.tick(1.0, false) == 0 and bootstrap.minute == 0, "bootstrap clock rejects invalid rate")
	bootstrap.minutes_per_real_second = 1.0e300
	check(bootstrap.tick(1.0e300, false) == 0 and bootstrap.minute == 0 and bootstrap.remainder == 0, "bootstrap clock also guards numeric overflow")
	var plain = Calendar.new()
	check(not plain.advance({"game_time_minutes": 4}, 3, "tick").ok, "calendar never moves backward")
	var gameplay_store = Store.new(store.path + ".gameplay")
	check_gameplay_ticks(gameplay_store)
	for path in [store.path, gameplay_store.path]:
		for suffix in ["", ".tmp", ".bak", ".rejected"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("CALENDAR TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
