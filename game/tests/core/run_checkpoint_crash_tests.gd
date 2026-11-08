extends SceneTree

const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const VICTORY := "crash:first-victory"
const PHASES := ["staged", "backup_copy", "replaced", "restored"]

class CrashStore extends "res://game/systems/core/checkpoint_store.gd":
	var stop_at: String

	func _init(save_path: String, phase: String) -> void:
		super(save_path)
		stop_at = phase

	func _stage_checkpoint(state: Dictionary) -> bool:
		var staged := super(state)
		if staged:
			hold_at("staged")
		return staged

	func _stage_backup(source: String, temporary: String) -> bool:
		if stop_at != "backup_copy":
			return super(source, temporary)
		var partial := FileAccess.open(temporary, FileAccess.WRITE)
		if partial == null:
			return false
		partial.store_string("{")
		partial.close()
		hold_at("backup_copy")
		return false

	func write_checkpoint(state: Dictionary, validator: Callable) -> Dictionary:
		var result := super(state, validator)
		if result.get("committed", false):
			hold_at("replaced")
		return result

	func restore_checkpoint(state: Dictionary) -> bool:
		var restored := super(state)
		if restored:
			hold_at("restored")
		return restored

	func hold_at(phase: String) -> void:
		if phase != stop_at:
			return
		var marker := FileAccess.open(path + ".ready", FileAccess.WRITE)
		if marker == null:
			return
		marker.store_string(phase)
		marker.close()
		# Keep the transaction in progress until the parent kills this process.
		OS.delay_msec(12000)

var checks := 0
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		run.call_deferred()
	elif args.size() == 3 and args[0] == "worker" and args[1] in PHASES:
		run_worker(args[1], args[2])
	else:
		push_error("Invalid checkpoint crash worker arguments")
		quit(1)

func make_session():
	var rules := Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	return Campaign.new(rules).coordinator

func request(session, kind: String, id: String) -> Dictionary:
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": id, "command_type": kind, "payload": {},
		"context": {"actor_id": "player", "scene_id": state.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

func run_worker(phase: String, path: String) -> void:
	var session = make_session()
	var store := CrashStore.new(path, phase)
	if phase == "restored":
		session.load_checkpoint(store, true)
	elif session.load_checkpoint(store).ok:
		session.execute(request(session, "game.enemy_defeated", VICTORY), store)
	push_error("Crash worker exited before it was killed at " + phase)
	quit(1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func interrupt(phase: String, path: String) -> bool:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", get_script().resource_path, "--", "worker", phase, path])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		return false
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		if FileAccess.get_file_as_string(path + ".ready") == phase:
			break
		await create_timer(0.02).timeout
	var reached := FileAccess.get_file_as_string(path + ".ready") == phase
	var killed := OS.is_process_running(pid) and OS.kill(pid) == OK
	return reached and killed

func run() -> void:
	var directory := ProjectSettings.globalize_path("user://checkpoint-crash-%d-%d" %
		[OS.get_process_id(), Time.get_ticks_usec()])
	for phase in PHASES:
		var path := directory.path_join(phase + ".json")
		await check_phase(phase, path)
		for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected", ".ready"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(directory)
	print("CHECKPOINT CRASH TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_phase(phase: String, path: String) -> void:
	var session = make_session()
	var store := Store.new(path)
	var first := request(session, "session.save", "crash:baseline-one")
	first.context.merge({"health": 73, "departure_position": {"x": 120, "y": 260}})
	var ready: bool = session.execute(first, store).ok
	var second := request(session, "session.save", "crash:baseline-two")
	second.context.merge({"health": 61, "departure_position": {"x": 150, "y": 260}})
	ready = ready and session.execute(second, store).ok
	check(ready, phase + " fixture has primary and backup")
	if not ready:
		return
	var primary := FileAccess.get_file_as_bytes(path)
	var backup := FileAccess.get_file_as_bytes(path + ".bak")
	var expected_state: Dictionary = session.get_snapshot()
	if phase == "restored":
		expected_state = store.read_checkpoint(path + ".bak").state
		var corrupt := FileAccess.open(path, FileAccess.WRITE)
		check(corrupt != null, "fixture can inject a damaged primary")
		if corrupt == null:
			return
		primary = "invalid primary fixture".to_utf8_buffer()
		corrupt.store_buffer(primary)
		corrupt.close()
	var stopped := await interrupt(phase, path)
	check(stopped, phase + " child reached the boundary and was killed")
	if not stopped:
		return
	match phase:
		"staged":
			check(FileAccess.get_file_as_bytes(path) == primary and FileAccess.get_file_as_bytes(path + ".bak") == backup
				and FileAccess.file_exists(path + ".tmp"), "staging interruption preserves both durable files")
		"backup_copy":
			check(FileAccess.get_file_as_bytes(path) == primary and FileAccess.get_file_as_bytes(path + ".bak") == backup
				and FileAccess.get_file_as_string(path + ".bak.tmp") == "{", "incomplete backup copy leaves both durable files byte-for-byte intact")
		"replaced":
			check(FileAccess.get_file_as_bytes(path + ".bak") == primary and not FileAccess.file_exists(path + ".tmp"),
				"primary replacement keeps the previous valid primary as backup")
		"restored":
			check(FileAccess.get_file_as_bytes(path + ".bak") == backup and FileAccess.get_file_as_bytes(path + ".rejected") == primary,
				"recovery interruption preserves the backup and the displaced primary")
	var reopened = make_session()
	var loaded: bool = reopened.load_checkpoint(store).ok
	check(loaded, phase + " opens a valid primary in a fresh session")
	if not loaded:
		return
	var recovered: Dictionary = reopened.get_snapshot()
	var expected_revision := 1 if phase == "restored" else (3 if phase == "replaced" else 2)
	check(recovered.state_revision == expected_revision and recovered.world_states.first_enemy_defeated == (phase == "replaced"),
		phase + " restores only durable effects")
	check(recovered.player.position == expected_state.player.position and recovered.player.hp == expected_state.player.hp
		and (phase == "replaced" or recovered == expected_state), phase + " preserves the expected saved game and hero data")
	var victory := request(reopened, "game.enemy_defeated", VICTORY)
	var result: Dictionary = reopened.execute(victory, store)
	check(result.code == ("ALREADY_APPLIED" if phase == "replaced" else "OK"), phase + " resolves a retried victory correctly")
	if phase == "backup_copy":
		check(FileAccess.get_file_as_bytes(path + ".bak") == primary and not FileAccess.file_exists(path + ".bak.tmp"),
			"retry replaces incomplete staging with a verified backup")
	var rewarded: Dictionary = reopened.get_snapshot()
	var gear: Array = rewarded.inventory.items.filter(func(item): return item.type_id == "tool.basic")
	check(rewarded.claimed_reward_ids == ["system"] and rewarded.player.xp == 10 and rewarded.wallet.system_coins == 8
		and gear.size() == 1 and gear[0].quantity == 1, phase + " restores one complete first-victory reward")
	check(reopened.execute(victory, store).code == "ALREADY_APPLIED" and reopened.get_snapshot() == rewarded,
		phase + " repeat command cannot duplicate the reward")
