extends SceneTree

const Bus = preload("res://game/systems/core/event_bus.gd")
const Core = preload("res://game/systems/core/core_session.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Fixtures = preload("res://game/tests/core/campaign_fixtures.gd")

class Probe extends Node:
	var received: Array = []
	var mutate: bool = false
	var session
	var store
	var observed_committed: bool = true
	var attempted_code: String = ""
	var bus
	var nested_result: bool = true
	var remove_token: int = 0
	var add_probe
	func on_event(event: Dictionary) -> void:
		received.append(event.duplicate(true))
		if session != null:
			observed_committed = observed_committed and session.get_snapshot().state_revision == event.state_revision
			attempted_code = session.execute({"action_id": "listener-mutation", "command_type": "session.save", "payload": {}, "context": {"actor_id": "player", "scene_id": "shelter"}}, store).code
		if bus != null:
			if remove_token != 0:
				bus.unsubscribe(remove_token)
			if add_probe != null:
				bus.subscribe(add_probe, add_probe.on_event)
			var nested := event.duplicate(true)
			nested.event_id += "-nested"
			nested_result = bus.publish_after_commit(nested)
		if mutate:
			event.payload.clear()
			event.event_type = "tampered"

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func fact(id: String, type: String = "unit") -> Dictionary:
	return {"event_id": id, "event_type": type, "action_id": "unit-action", "game_minute": 0, "state_revision": 0, "payload": {"value": 1}}

func request(session, id: String, kind: String, payload: Dictionary) -> Dictionary:
	var snapshot: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in snapshot.resource_revisions:
		versions.append({"key": key, "revision": snapshot.resource_revisions[key]})
	return {"action_id": id, "command_type": kind, "payload": payload, "context": {"actor_id": "player", "scene_id": snapshot.scene.current_scene_id, "expected_resource_revisions": versions}}

func types(probe: Probe) -> Array:
	var result: Array = []
	for event in probe.received:
		result.append(event.event_type)
	return result

func _initialize() -> void:
	var bus = Bus.new()
	var first := Probe.new()
	var second := Probe.new()
	first.mutate = true
	var token: int = bus.subscribe(first, first.on_event)
	for i in range(10):
		check(bus.subscribe(first, first.on_event) == token, "repeat subscription token %d" % i)
	check(bus.subscription_count() == 1, "CT-13 repeated registration does not accumulate subscriptions")
	bus.subscribe(second, second.on_event, ["unit"])
	var original := fact("one")
	check(bus.publish_after_commit(original), "valid fact delivered")
	check(second.received.size() == 1 and second.received[0].payload.value == 1 and original.payload.value == 1, "subscriber payload mutation cannot affect others/publisher")
	check(not bus.publish_after_commit(original) and first.received.size() == 1, "duplicate event ID not delivered twice")
	check(bus.publish_after_commit(fact("different-type", "other")) and second.received.size() == 1, "event type filter")
	var bad := fact("bad")
	bad.state_revision = -1
	check(not bus.publish_after_commit(bad), "malformed event rejected")
	var named := fact("string-name")
	named.event_type = StringName("unit")
	check(bus.publish_after_commit(named) and second.received.back().event_type == "unit", "StringName event types supported by contract")
	bus.unsubscribe(token)
	bus.unsubscribe(token)
	check(bus.subscription_count() == 1, "unsubscribe is idempotent")
	second.free()
	check(bus.subscription_count() == 0 and bus.publish_after_commit(fact("after-free")), "destroyed scene owner pruned")
	first.free()
	var during := Probe.new()
	var removed := Probe.new()
	var added := Probe.new()
	during.bus = bus
	during.add_probe = added
	bus.subscribe(during, during.on_event)
	during.remove_token = bus.subscribe(removed, removed.on_event)
	bus.publish_after_commit(fact("membership"))
	check(removed.received.is_empty() and added.received.is_empty(), "unsubscribe during dispatch effective, new listener waits")
	check(not during.nested_result, "reentrant fact publication rejected")
	bus.publish_after_commit(fact("membership-next"))
	check(added.received.size() == 1, "new subscription starts on next event")
	bus.unsubscribe_owner(during)
	during.free()
	removed.free()
	added.free()
	check(bus.subscription_count() == 0, "owner lifecycle leaves no live subscriptions")
	# A0-F04: bounded notification delivery history under long-lived sessions.
	# Durable action/reward receipts are deliberately not pruned by this ring.
	var stress = Bus.new()
	var stress_started: int = Time.get_ticks_usec()
	var stress_ok: bool = true
	for i in range(100000):
		if not stress.publish_after_commit(fact("stress:" + str(i))):
			stress_ok = false
			break
	var stress_ms: float = (Time.get_ticks_usec() - stress_started) / 1000.0
	print("EVENT DEDUP STRESS: 100000 facts in %.2f ms, retained=%d limit=%d" % [stress_ms, stress.history_size(), Bus.HISTORY_LIMIT])
	check(stress_ok and stress.history_size() == Bus.HISTORY_LIMIT, "A0-F04 100k unique facts retain only bounded recent IDs")
	check(not stress.publish_after_commit(fact("stress:99999")), "A0-F04 most recent duplicate suppressed")
	check(stress.publish_after_commit(fact("stress:0")), "A0-F04 expired notification may repeat without changing domain state")
	stress.reset_history()
	check(stress.history_size() == 0, "A0-F04 load clears temporary ring")
	var campaign = Campaign.new(Fixtures.rules())
	var session = campaign.coordinator
	var store = Store.new("user://event-tests/" + str(Time.get_ticks_usec()) + ".json")
	var observer := Probe.new()
	observer.session = session
	observer.store = store
	session.events.subscribe(observer, observer.on_event)
	var parcel := request(session, "parcel", "inventory.claim_parcel", {"parcel_id": "starter"})
	check(session.execute(parcel, store).ok, "campaign publishes after successful commit")
	check(types(observer) == ["item_granted", "first_item_type_discovered", "parcel_claimed", "progression_changed", "wallet_changed"], "domain event order follows atomic operation")
	check(observer.observed_committed and observer.attempted_code == "UNAVAILABLE", "listeners see committed snapshot and cannot mutate reentrantly")
	var ids: Dictionary = {}
	for event in observer.received:
		ids[event.event_id] = true
	check(ids.size() == observer.received.size(), "stable distinct event ordinal IDs")
	observer.received.clear()
	check(session.execute(parcel, store).code == "ALREADY_APPLIED" and observer.received.is_empty(), "replay emits no facts")
	store.fault = "before_replace"
	check(session.execute(request(session, "failed", "inventory.purchase", {"offer_id": "seed"}), store).code == "SAVE_FAILED" and observer.received.is_empty(), "failed commit emits no facts")
	store.fault = ""
	var remainder_before: Dictionary = store.read_checkpoint().state
	campaign.tick(0.25)
	check(observer.received.is_empty(), "fractional tick emits no calendar fact")
	campaign.tick(1.0)
	check(types(observer) == ["time_advanced"] and observer.received[0].payload.reason == "tick", "calendar boundary emits one time event")
	check(store.read_checkpoint().state == remainder_before, "runtime tick does not write checkpoint")
	observer.received.clear()
	store.fault = "after_replace"
	check(session.execute(request(session, "lost-response", "inventory.purchase", {"offer_id": "seed"}), store).code == "UNAVAILABLE" and observer.received.is_empty(), "postcommit interruption defers all notifications")
	store.fault = ""
	check(session.load_checkpoint(store).ok and types(observer) == ["state_loaded"], "recovery emits refresh, not repeated reward facts")
	check(session.events.subscription_count() == 1 and observer.observed_committed, "live subscription retained through load")
	observer.received.clear()
	check(session.execute(request(session, "lost-response", "inventory.purchase", {"offer_id": "seed"}), store).code == "ALREADY_APPLIED" and observer.received.is_empty(), "recovered purchase replay silent")
	check(session.execute(request(session, "rest", "clock.rest", {"target_minute": 100}), store).ok and types(observer) == ["time_advanced"] and observer.received[0].payload.reason == "rest", "rest uses same calendar event contract")
	var malformed = Core.new()
	malformed._planner = func(state, _request):
		state.counter += 1
		return {"ok": true, "events": [{"payload": {}}]}
	check(malformed.execute({"action_id": "invalid-draft", "command_type": "core.increment", "payload": {"amount": 1}, "context": {"actor_id": "test"}}, store).code == "INVALID_STATE" and malformed.get_snapshot().counter == 0, "invalid domain event plan rejects whole command before disk")
	observer.free()
	check(session.events.subscription_count() == 0, "campaign UI owner destruction cleans subscription")
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + suffix))
	print("EVENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
