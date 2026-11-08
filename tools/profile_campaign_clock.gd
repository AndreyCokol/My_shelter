extends SceneTree

const Campaign = preload("res://game/systems/core/campaign_session.gd")
const EventBus = preload("res://game/systems/core/event_bus.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const FRAMES_PER_MINUTE := 60
const SAMPLED_MINUTES := 3
const RECEIPT_COUNTS := [100, 1000, 10000]

func _initialize() -> void:
	if "--hud" in OS.get_cmdline_user_args():
		_profile_hud.call_deferred()
		return
	var rules := Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	var locations := Layout.build(rules.world_seed)
	print("world_locations,tracked_locations,receipts,subminute_p50_us,subminute_p95_us,minute_p50_us,minute_max_us,crop_deadline_us,sampled_memory_start_bytes,sampled_memory_high_bytes")
	for receipt_count in RECEIPT_COUNTS:
		var campaign := Campaign.new(rules)
		if not campaign.coordinator.apply_runtime(_populate.bind(locations, receipt_count)):
			push_error("Could not initialize a valid campaign profile fixture")
			quit(1)
			return
		for frame in range(FRAMES_PER_MINUTE):
			if not campaign.tick(1.0 / FRAMES_PER_MINUTE):
				push_error("Clock warmup failed at frame %d" % frame)
				quit(1)
				return
		var subminute: Array[int] = []
		var minute: Array[int] = []
		var crop_deadline_us := 0
		var start_memory := OS.get_static_memory_usage()
		var high_memory := start_memory
		for frame in range(SAMPLED_MINUTES * FRAMES_PER_MINUTE):
			var start := Time.get_ticks_usec()
			var ok := campaign.tick(1.0 / FRAMES_PER_MINUTE)
			var elapsed := Time.get_ticks_usec() - start
			if not ok:
				push_error("Clock tick failed at frame %d" % frame)
				quit(1)
				return
			high_memory = maxi(high_memory, OS.get_static_memory_usage())
			if frame + 1 == 2 * FRAMES_PER_MINUTE:
				crop_deadline_us = elapsed
			elif (frame + 1) % FRAMES_PER_MINUTE == 0:
				minute.append(elapsed)
			else:
				subminute.append(elapsed)
		var state: Dictionary = campaign.coordinator.get_snapshot()
		if state.game_time_minutes != 1 + SAMPLED_MINUTES or not is_zero_approx(state.clock_remainder) or state.crops.plots[0].status != "ripe":
			push_error("Unexpected elapsed campaign time")
			quit(1)
			return
		subminute.sort()
		minute.sort()
		print("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			locations.size(), state.world_states.locations.size(), receipt_count,
			subminute[floori(subminute.size() / 2.0)], subminute[ceili(subminute.size() * 0.95) - 1],
			int((minute.front() + minute.back()) / 2.0), minute.back(), crop_deadline_us, start_memory, high_memory])
	quit(0 if _profile_events() else 1)

func _profile_hud() -> void:
	var scene := load("res://game/scenes/main/playable.tscn") as PackedScene
	if scene == null:
		push_error("Import the game assets before profiling the HUD")
		quit(1)
		return
	var app = scene.instantiate()
	app.starting_seed = 54
	root.add_child(app)
	if app.ui == null:
		push_error("Playable scene could not initialize the HUD")
		app.free()
		quit(1)
		return
	app.ui.close_panel()
	var locations := Layout.build(54)
	print("receipts,hud_p50_us,hud_p95_us")
	for receipt_count in RECEIPT_COUNTS:
		if not app.session.apply_runtime(_populate.bind(locations, receipt_count)):
			push_error("Could not initialize a valid HUD profile fixture")
			app.free()
			quit(1)
			return
		var samples: Array[int] = []
		for sample in range(30):
			var start := Time.get_ticks_usec()
			app.update_hud()
			samples.append(Time.get_ticks_usec() - start)
		samples.sort()
		print("%d,%d,%d" % [receipt_count, int((samples[14] + samples[15]) / 2.0), samples[28]])
	app.free()
	quit()

func _populate(state: Dictionary, locations: Dictionary, receipt_count: int) -> bool:
	state.crops.plots[0].merge({"status": "growing", "ripe_at": 3, "spoil_at": 100}, true)
	for id in locations:
		match Layout.kind(id):
			"outside":
				if id != "outside":
					state.world_states.locations[id] = {"resource_ready_at": 60}
			"house":
				state.world_states.locations[id] = {"looted": true}
			"hospital":
				if id != "hospital":
					state.world_states.locations[id] = {"defeated": true}
	var fingerprint := "clock-profile".sha256_text()
	for index in range(receipt_count):
		var action_id := "profile:%d" % index
		state.completed_actions[action_id] = {"fingerprint": fingerprint, "result": {
			"action_id": action_id, "ok": true, "code": "OK",
			"state_revision": state.state_revision, "data": {}, "message_key": "core.ok",
		}}
	return true

func _profile_events() -> bool:
	var bus := EventBus.new()
	var event := {"event_type": "profile", "event_id": "", "action_id": "profile", "game_minute": 0, "state_revision": 0, "payload": {}}
	print("unique_events,retained_ids,order_slots,static_memory_bytes")
	for index in range(1, 100001):
		event.event_id = "profile:%d" % index
		if not bus.publish_after_commit(event):
			push_error("Unique event %d was rejected" % index)
			return false
		if index % 25000 == 0:
			print("%d,%d,%d,%d" % [index, bus._seen.size(), bus._seen_order.size(), OS.get_static_memory_usage()])
			if bus._seen.size() != EventBus.MAX_RECENT_EVENT_IDS or bus._seen_order.size() >= 2 * EventBus.MAX_RECENT_EVENT_IDS:
				push_error("Event history exceeded its configured window")
				return false
	if bus.publish_after_commit(event):
		push_error("Recent duplicate was delivered")
		return false
	bus.reset_history()
	return bus.publish_after_commit(event)
