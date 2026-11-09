extends SceneTree

# PERF-03 / CT-94: accelerate 30 minutes of nominal 60-FPS game clock
# WITHOUT pretending it is a 30-minute native Windows GUI playtest.
# This runs 108,000 real Godot GameClock/CampaignSession ticks and samples
# static process memory, CPU wall-clock time and durable save/reload integrity.
# Synthetic action receipts are written to a private test fixture, never a
# player's save slot. All 64px visual/gameplay assets remain in the project.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")

const NOMINAL_REAL_SECONDS := 30 * 60
const TARGET_FPS := 60
const TARGET_TICKS := NOMINAL_REAL_SECONDS * TARGET_FPS
const SYNTHETIC_RECEIPTS := 100

var checks: int = 0
var failures: int = 0

func check(value: bool, description: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + description)
	if not value:
		failures += 1
		push_error(description)

func seed_receipts(state: Dictionary) -> bool:
	for number in range(SYNTHETIC_RECEIPTS):
		var action_id := "ct94:seed:%d" % number
		state.completed_actions[action_id] = {
			"fingerprint": "ct94:" + str(number),
			"result": {"ok": true, "code": "OK", "action_id": action_id,
				"state_revision": 0, "data": {}, "message_key": "core.ok"},
		}
	return true

func _initialize() -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	check(Campaign.valid_rules(rules), "CT-94 validated live world rules for accelerated soak")
	var campaign = Campaign.new(rules)
	check(campaign.coordinator != null and campaign.coordinator.apply_runtime(seed_receipts),
		"CT-94 seed 100 synthetic durable action IDs without touching real saves")
	var initial: Dictionary = campaign.coordinator.get_snapshot()
	var expected_inventory: Dictionary = initial.inventory.duplicate(true)
	var expected_player: Dictionary = initial.player.duplicate(true)
	var started: int = Time.get_ticks_usec()
	var start_memory: int = OS.get_static_memory_usage()
	var highest_memory: int = start_memory
	var slowest_tick: int = 0
	var last_minute: int = int(initial.game_time_minutes)
	var all_ticks: bool = true
	var monotonic: bool = true
	var end_frame: int = 0
	for frame in range(TARGET_TICKS):
		var sample_started: int = Time.get_ticks_usec()
		if not campaign.tick(1.0 / TARGET_FPS):
			all_ticks = false
			end_frame = frame
			break
		slowest_tick = maxi(slowest_tick, Time.get_ticks_usec() - sample_started)
		if frame % (TARGET_FPS * 30) == 0:
			var now_minute: int = int(campaign.coordinator._state.game_time_minutes)
			monotonic = monotonic and now_minute >= last_minute
			last_minute = now_minute
			highest_memory = maxi(highest_memory, OS.get_static_memory_usage())
		end_frame = frame + 1
	var elapsed_us: int = Time.get_ticks_usec() - started
	highest_memory = maxi(highest_memory, OS.get_static_memory_usage())
	check(all_ticks and end_frame == TARGET_TICKS,
		"CT-94 all 108000 accelerated 60-FPS campaign ticks complete without rejection")
	check(monotonic, "CT-94 calendar never runs backward across sampled runtime frames")
	var snapshot: Dictionary = campaign.coordinator.get_snapshot()
	check(Model.validate(snapshot, rules) and snapshot.game_time_minutes == initial.game_time_minutes + NOMINAL_REAL_SECONDS
		and snapshot.clock_remainder == 0.0,
		"CT-94 30-minute 60-FPS minute boundaries leave a canonical zero remainder")
	check(snapshot.inventory == expected_inventory and snapshot.player == expected_player
		and snapshot.completed_actions.size() == SYNTHETIC_RECEIPTS,
		"CT-94 no surprise inventory/HP mutation or loss of 100 durable receipts")
	var path := "user://ct94-soak/%d.json" % Time.get_ticks_usec()
	var store = Store.new(path)
	var saved: Dictionary = store.write_checkpoint(snapshot, Model.validate.bind(rules))
	check(saved.get("committed", false), "CT-94 30-minute-equivalent campaign commits a durable checkpoint")
	var disk_bytes: int = FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	var reopened = Campaign.new(rules).coordinator
	var loaded: Dictionary = reopened.load_checkpoint(store)
	var reloaded_state: Dictionary = reopened.get_snapshot()
	if not loaded.get("ok", false) or reloaded_state != snapshot:
		print("CT-94 LOAD DIAGNOSTIC result=", loaded, " equal=", reloaded_state == snapshot)
		for key in snapshot:
			if reloaded_state.get(key) != snapshot[key]:
				print("CT-94 DIFFERING KEY=", key,
					" source_type=", typeof(snapshot[key]), " restored_type=", typeof(reloaded_state.get(key)))
				if key in ["clock_remainder", "game_time_minutes", "state_revision"]:
					print("CT-94 DIFFERING VALUE=", snapshot[key], " restored=", reloaded_state.get(key))
	check(loaded.get("ok", false) and reloaded_state == snapshot,
		"CT-94 independent session restores 30-minute simulation and receipts exactly")
	print("CT-94 SOAK PROFILE nominal_seconds=%d frames=%d final_game_minutes=%d elapsed_wall_ms=%.3f max_tick_ms=%.3f memory_initial_bytes=%d memory_peak_bytes=%d memory_delta_bytes=%d checkpoint_bytes=%d" %
		[NOMINAL_REAL_SECONDS, end_frame, int(snapshot.game_time_minutes),
		float(elapsed_us) / 1000.0, float(slowest_tick) / 1000.0,
		start_memory, highest_memory, highest_memory - start_memory, disk_bytes])
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("SOAK TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
