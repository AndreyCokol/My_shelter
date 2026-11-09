extends SceneTree

# CORE-04 / NX-06: injected filesystem failures on disposable campaign fixtures.
# This suite does NOT power off hardware or touch real player save slots.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const VICTORY := "core04:first-victory"

class FaultStore extends "res://game/systems/core/checkpoint_store.gd":
	var fail_primary := false
	var fail_backup_promotion := false
	var fail_backup_copy := false
	var fail_staging := false

	func _stage_checkpoint(state: Dictionary) -> bool:
		if fail_staging:
			return false
		return super(state)

	func _stage_backup(source: String, temporary: String) -> bool:
		if not fail_backup_copy:
			return super(source, temporary)
		# Inject interrupted/partial .bak.tmp copy, without changing .bak.
		var partial := FileAccess.open(temporary, FileAccess.WRITE)
		if partial != null:
			partial.store_string("{")
			partial.close()
		return false

	func _replace_primary(temporary: String, target: String) -> int:
		if fail_primary:
			return ERR_CANT_CREATE
		return super(temporary, target)

	func _replace_backup(temporary: String, target: String) -> int:
		if fail_backup_promotion:
			return ERR_CANT_CREATE
		return super(temporary, target)

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func make_session():
	var rules := Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	return Campaign.new(rules).coordinator

func request(session, kind: String, action_id: String) -> Dictionary:
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": action_id, "command_type": kind, "payload": {},
		"context": {"actor_id": "player", "scene_id": state.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

func clean(path: String) -> void:
	for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected", ".ready"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func fixture(path: String) -> Dictionary:
	clean(path)
	var session = make_session()
	var store = FaultStore.new(path)
	var first: Dictionary = session.execute(request(session, "session.save", "core04:baseline-one"), store)
	var second: Dictionary = session.execute(request(session, "session.save", "core04:baseline-two"), store)
	var good: bool = first.ok and second.ok and FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak")
	check(good, "fixture has distinct durable primary and backup")
	if good:
		check(FileAccess.get_sha256(path) != FileAccess.get_sha256(path + ".bak"),
			"fixture backup holds the previous primary revision")
	return {"ok": good, "session": session, "store": store}

func check_one_reward(state: Dictionary, action_id: String, label: String) -> void:
	var tools: Array = state.inventory.items.filter(func(item): return item.type_id == "tool.basic")
	check(state.completed_actions.has(action_id) and state.claimed_reward_ids == ["system"]
		and state.player.xp == 10 and state.wallet.system_coins == 8
		and tools.size() == 1 and tools[0].quantity == 1, label)

func primary_rename_failure(path: String) -> void:
	var f := fixture(path)
	if not f.ok:
		return
	var session = f.session
	var store: FaultStore = f.store
	var durable_primary := FileAccess.get_file_as_bytes(path)
	var durable_backup := FileAccess.get_file_as_bytes(path + ".bak")
	var before: Dictionary = session.get_snapshot()
	var victory: Dictionary = request(session, "game.enemy_defeated", VICTORY)
	store.fail_primary = true
	var denied: Dictionary = session.execute(victory, store)
	check(not denied.ok and denied.code == "SAVE_FAILED",
		"injected primary rename rejection reports precommit failure")
	check(FileAccess.get_file_as_bytes(path) == durable_primary
		and FileAccess.get_file_as_bytes(path + ".bak") == durable_backup,
		"precommit primary rename failure preserves BOTH durable files byte-for-byte")
	check(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".bak.tmp"),
		"primary rename failure cleans temporary files")
	check(session.get_snapshot() == before,
		"primary rename failure does not mutate memory or create a victory receipt")
	var unchanged = make_session()
	check(unchanged.load_checkpoint(Store.new(path)).ok and unchanged.get_snapshot() == before,
		"fresh process can load the unchanged checkpoint after failed rename")
	store.fail_primary = false
	var success: Dictionary = session.execute(victory, store)
	check(success.ok and FileAccess.get_file_as_bytes(path + ".bak") == durable_primary,
		"same action can be retried once and publishes previous primary as backup")
	var after: Dictionary = session.get_snapshot()
	check_one_reward(after, VICTORY, "retry gives one first-victory reward only")
	var replay: Dictionary = session.execute(victory, store)
	check(replay.code == "ALREADY_APPLIED" and session.get_snapshot() == after,
		"replaying a committed receipt does not duplicate victory rewards")
	var reopened = make_session()
	check(reopened.load_checkpoint(Store.new(path)).ok and reopened.get_snapshot() == after
		and reopened.execute(victory, Store.new(path)).code == "ALREADY_APPLIED",
		"reopening still replays the exact same durable receipt")

func backup_promotion_failure(path: String) -> void:
	var f := fixture(path)
	if not f.ok:
		return
	var session = f.session
	var store: FaultStore = f.store
	var old_primary := FileAccess.get_file_as_bytes(path)
	var old_backup := FileAccess.get_file_as_bytes(path + ".bak")
	var victory: Dictionary = request(session, "game.enemy_defeated", VICTORY)
	store.fail_backup_promotion = true
	var result: Dictionary = session.execute(victory, store)
	check(result.ok and result.code == "OK",
		"failure AFTER primary commit reports success, never a false uncommitted result")
	check(FileAccess.get_file_as_bytes(path + ".bak") == old_backup
		and FileAccess.get_file_as_bytes(path) != old_primary,
		"postcommit backup promotion failure retains older valid backup and committed primary")
	check(not FileAccess.file_exists(path + ".bak.tmp"),
		"failed postcommit backup promotion cleans staging file")
	var committed_primary := FileAccess.get_file_as_bytes(path)
	var committed_state: Dictionary = session.get_snapshot()
	check_one_reward(committed_state, VICTORY, "postcommit backup failure still gives exactly one reward")
	var reopened = make_session()
	var loaded: Dictionary = reopened.load_checkpoint(Store.new(path))
	check(loaded.ok and reopened.get_snapshot() == committed_state,
		"new process loads committed primary despite failed backup promotion")
	check(reopened.execute(victory, Store.new(path)).code == "ALREADY_APPLIED"
		and reopened.get_snapshot() == committed_state,
		"retry after backup promotion failure cannot double-reward")
	var repaired: Dictionary = reopened.execute(request(reopened, "session.save", "core04:next-save"), Store.new(path))
	check(repaired.ok and FileAccess.get_file_as_bytes(path + ".bak") == committed_primary,
		"next successful save repairs backup to the previous committed primary")

func copy_and_staging_failures(path: String) -> void:
	var f := fixture(path)
	if not f.ok:
		return
	var session = f.session
	var store: FaultStore = f.store
	var primary := FileAccess.get_file_as_bytes(path)
	var backup := FileAccess.get_file_as_bytes(path + ".bak")
	var before: Dictionary = session.get_snapshot()
	var victory: Dictionary = request(session, "game.enemy_defeated", VICTORY)
	store.fail_backup_copy = true
	var fail_copy: Dictionary = session.execute(victory, store)
	check(not fail_copy.ok and fail_copy.code == "SAVE_FAILED",
		"partial backup copy is rejected before primary commit")
	check(FileAccess.get_file_as_bytes(path) == primary and FileAccess.get_file_as_bytes(path + ".bak") == backup,
		"partial .bak.tmp copy never overwrites existing valid primary or backup")
	check(not FileAccess.file_exists(path + ".bak.tmp") and not FileAccess.file_exists(path + ".tmp"),
		"partial backup copy cleans only temporary files")
	store.fail_backup_copy = false
	store.fail_staging = true
	var fail_stage: Dictionary = session.execute(victory, store)
	check(not fail_stage.ok and fail_stage.code == "SAVE_FAILED"
		and FileAccess.get_file_as_bytes(path) == primary
		and FileAccess.get_file_as_bytes(path + ".bak") == backup,
		"injected staging write refusal keeps original durable files")
	check(session.get_snapshot() == before and not FileAccess.file_exists(path + ".tmp"),
		"staging failure leaves memory, receipts and primary untouched")

func run() -> void:
	var directory := "user://core-save-failure-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		check(false, "isolated save fixture directory could be created")
	else:
		primary_rename_failure(directory.path_join("primary-rename.json"))
		backup_promotion_failure(directory.path_join("backup-promotion.json"))
		copy_and_staging_failures(directory.path_join("copy-and-stage.json"))
		for filename in ["primary-rename.json", "backup-promotion.json", "copy-and-stage.json"]:
			clean(directory.path_join(filename))
		DirAccess.remove_absolute(absolute)
	print("SAVE FAILURE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
