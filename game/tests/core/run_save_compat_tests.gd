extends SceneTree

# CORE-04 / NX-06: archive-slot, damaged primary, backup recovery and
# generator v4 -> v5 compatibility. Disposable fixtures ONLY. No real
# Windows GUI, power loss, disk exhaustion or player profile is touched.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const FIRST_VICTORY := "core04:savecompat:enemy-first"

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func rules() -> Dictionary:
	var config: Dictionary = Rules.build()
	config.world_seed = 54
	config.scenes = Layout.entries()
	return config

func coordinator(config: Dictionary):
	return Campaign.new(config).coordinator

func command(session, action_id: String, kind: String, payload: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in snapshot.resource_revisions:
		versions.append({"key": key, "revision": snapshot.resource_revisions[key]})
	return {"action_id": action_id, "command_type": kind, "payload": payload,
		"context": {"actor_id": "player", "scene_id": snapshot.scene.current_scene_id,
			"expected_resource_revisions": versions}}

func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return false
	out.store_buffer(bytes)
	out.flush()
	var good := out.get_error() == OK
	out.close()
	return good

func clean_slot(path: String) -> void:
	for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected", ".rejected.1",
		".archive-a", ".bak.archive-a", ".ready"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func distinct_revision_fixture(config: Dictionary, path: String) -> Dictionary:
	clean_slot(path)
	var session = coordinator(config)
	var store = Store.new(path)
	var s1: Dictionary = session.execute(command(session, "core04:savecompat:s1", "session.save"), store)
	var s2: Dictionary = session.execute(command(session, "core04:savecompat:s2", "session.save"), store)
	var ok: bool = s1.ok and s2.ok and FileAccess.file_exists(path + ".bak")
	check(ok and FileAccess.get_sha256(path) != FileAccess.get_sha256(path + ".bak"),
		"fixture holds distinct validated primary and .bak save revisions")
	return {"ok": ok, "session": session, "store": store}

func check_one_reward(state: Dictionary, label: String) -> void:
	var gear: Array = state.inventory.items.filter(func(item): return item.type_id == "tool.basic")
	check(state.world_states.first_enemy_defeated and state.claimed_reward_ids == ["system"]
		and state.player.xp == 10 and state.wallet.system_coins == 8
		and gear.size() == 1 and gear[0].quantity == 1
		and state.completed_actions.has(FIRST_VICTORY), label)

func archived_slots(config: Dictionary, path: String) -> void:
	var fixture: Dictionary = distinct_revision_fixture(config, path)
	if not fixture.ok:
		return
	var original = fixture.session
	var store: Store = fixture.store
	var kill: Dictionary = command(original, FIRST_VICTORY, "game.enemy_defeated")
	check(original.execute(kill, store).ok, "archived profile earns genuine first-victory receipt")
	var original_snapshot: Dictionary = original.get_snapshot()
	var primary: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var backup: PackedByteArray = FileAccess.get_file_as_bytes(path + ".bak")
	var archived_primary := path + ".archive-a"
	var archived_backup := path + ".bak.archive-a"
	var p: String = ProjectSettings.globalize_path(path)
	check(DirAccess.rename_absolute(p, ProjectSettings.globalize_path(archived_primary)) == OK,
		"archive primary uses actual atomic rename and unique destination")
	check(DirAccess.rename_absolute(p + ".bak", ProjectSettings.globalize_path(archived_backup)) == OK,
		"archive backup is separate from the archived primary")
	check(FileAccess.get_file_as_bytes(archived_primary) == primary
		and FileAccess.get_file_as_bytes(archived_backup) == backup
		and not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"),
		"archive preserves both former durable files byte-for-byte")
	var historic = coordinator(config)
	var historic_result: Dictionary = historic.load_checkpoint(Store.new(archived_primary))
	check(historic_result.ok and historic.get_snapshot() == original_snapshot,
		"archived primary reopens with original schema, world and receipts")
	check(historic.execute(kill, Store.new(archived_primary)).code == "ALREADY_APPLIED",
		"archived action receipt cannot issue second first-victory reward")
	var replacement = coordinator(config)
	var new_save: Dictionary = replacement.execute(
		command(replacement, "core04:savecompat:new-game", "session.save"), Store.new(path))
	check(new_save.ok and not replacement.get_snapshot().world_states.first_enemy_defeated,
		"a new independent slot can be written without importing old rewards")
	check(FileAccess.get_file_as_bytes(archived_primary) == primary
		and FileAccess.get_file_as_bytes(archived_backup) == backup,
		"writing new current slot does not overwrite either archived save")
	check(coordinator(config).load_checkpoint(Store.new(path)).ok,
		"new active slot remains independently loadable")
	clean_slot(path)

func damaged_primary_recovery(config: Dictionary, path: String) -> void:
	var fixture: Dictionary = distinct_revision_fixture(config, path)
	if not fixture.ok:
		return
	var original = fixture.session
	var store: Store = fixture.store
	var backup: PackedByteArray = FileAccess.get_file_as_bytes(path + ".bak")
	var invalid := "{DAMAGED_PRIMARY".to_utf8_buffer()
	check(write_bytes(path, invalid), "isolated fixture replaces only primary with deliberately damaged bytes")
	check(write_bytes(path + ".bak.tmp", "{INTERRUPTED_STAGE".to_utf8_buffer()),
		"isolated .bak.tmp simulates an interrupted previous backup copy")
	var parse_result: Dictionary = store.read_checkpoint()
	check(not parse_result.ok and parse_result.code == "INVALID_STATE",
		"malformed primary returns a structured INVALID_STATE without engine error")
	var before = coordinator(config)
	var untouched: Dictionary = before.get_snapshot()
	var rejected: Dictionary = before.load_checkpoint(store)
	check(not rejected.ok and rejected.code == "INVALID_STATE"
		and before.get_snapshot() == untouched,
		"corrupt primary is rejected without importing partial state")
	check(FileAccess.get_file_as_bytes(path + ".bak") == backup,
		"failed primary load keeps validated .bak byte-identical")
	var restored: Dictionary = before.load_checkpoint(store, true)
	check(restored.ok and Model.validate(before.get_snapshot(), config),
		"explicit user-selected .bak restore validates and installs historic checkpoint")
	check(FileAccess.get_file_as_bytes(path + ".rejected") == invalid
		and FileAccess.get_file_as_bytes(path + ".bak") == backup
		and not FileAccess.file_exists(path + ".tmp"),
		"recovery archives damaged primary exactly and never modifies backup")
	var kill: Dictionary = command(before, FIRST_VICTORY, "game.enemy_defeated")
	check(before.execute(kill, store).ok,
		"recoverable campaign can commit first real victory despite stale .bak.tmp")
	check_one_reward(before.get_snapshot(), "recovered campaign produces one first-victory reward")
	check(before.execute(kill, store).code == "ALREADY_APPLIED",
		"retrying recovered victory does not duplicate items or experience")
	var rebooted = coordinator(config)
	check(rebooted.load_checkpoint(store).ok and rebooted.get_snapshot() == before.get_snapshot()
		and rebooted.execute(kill, store).code == "ALREADY_APPLIED",
		"post-recovery disk reload exactly preserves receipt and single reward")
	check(FileAccess.get_file_as_bytes(path + ".rejected") == invalid,
		"later successful checkpoint does not overwrite the archived damaged primary")
	clean_slot(path)

func generator_upgrade(config: Dictionary, path: String) -> void:
	clean_slot(path)
	var store = Store.new(path)
	var older: Dictionary = coordinator(config).get_snapshot()
	check(older.schema_version == 4 and older.world_states.layout.generator_version == Layout.VERSION,
		"compatibility fixture begins with supported schema4 and current generator")
	# Recreate a historical layout descriptor, keeping all other state valid.
	older.world_states.layout.generator_version = 4
	check(Model.validate(older, config), "historical schema4/generator v4 checkpoint validates without silent upgrade")
	check(store.write_checkpoint(older, Model.validate.bind(config)).committed,
		"generator v4 save persists with original geometry version")
	var primary_v4: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var old_runtime = coordinator(config)
	check(old_runtime.load_checkpoint(store).ok and old_runtime.get_snapshot() == older,
		"loading old save retains generator v4 unchanged until explicit consent")
	var upgrade: Dictionary = command(old_runtime, "core04:upgrade:v4-to-v5", "session.upgrade_world")
	var result: Dictionary = old_runtime.execute(upgrade, store)
	var migrated: Dictionary = old_runtime.get_snapshot()
	check(result.ok and migrated.schema_version == 4
		and migrated.world_states.layout.generator_version == Layout.VERSION
		and migrated.world_states.layout.seed == older.world_states.layout.seed
		and Model.validate(migrated, config),
		"explicit v4->v5 upgrade preserves schema4, seed and domain validation")
	check(FileAccess.get_file_as_bytes(path + ".bak") == primary_v4,
		"migration keeps byte-for-byte original v4 save in backup")
	check(old_runtime.execute(upgrade, store).code == "ALREADY_APPLIED"
		and old_runtime.get_snapshot() == migrated,
		"repeat migration action ID cannot apply upgrade twice")
	var reopened = coordinator(config)
	check(reopened.load_checkpoint(store).ok and reopened.get_snapshot() == migrated,
		"restart installs exactly the migrated schema4/v5 world")
	check(reopened.execute(command(reopened, "core04:upgrade:again", "session.upgrade_world"), store).code == "UNAVAILABLE",
		"a newly requested upgrade is refused once generator v5 is current")
	check(reopened.load_checkpoint(store, true).ok
		and reopened.get_snapshot() == older
		and FileAccess.get_file_as_bytes(path + ".bak") == primary_v4,
		"explicit rollback restores full historical generator v4 checkpoint from backup")
	check(FileAccess.file_exists(path + ".rejected")
		and FileAccess.get_file_as_bytes(path + ".rejected") != primary_v4,
		"rolling back migration retains displaced v5 save in rejected archive")
	var upgrade_again: Dictionary = command(reopened, "core04:upgrade:after-rollback", "session.upgrade_world")
	check(reopened.execute(upgrade_again, store).ok
		and reopened.get_snapshot().world_states.layout.generator_version == Layout.VERSION,
		"historical backup may be deliberately and safely upgraded after rollback")
	check(reopened.execute(upgrade_again, store).code == "ALREADY_APPLIED",
		"upgraded-after-rollback receipt is durable and idempotent")
	clean_slot(path)

func run() -> void:
	var config: Dictionary = rules()
	check(Campaign.valid_rules(config), "save compatibility suite uses actual validated campaign rules")
	var location: String = "user://core-save-compat-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var dir: String = ProjectSettings.globalize_path(location)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		check(false, "create disposable save compatibility directory")
	else:
		archived_slots(config, location.path_join("archive.json"))
		damaged_primary_recovery(config, location.path_join("recovery.json"))
		generator_upgrade(config, location.path_join("generator.json"))
		DirAccess.remove_absolute(dir)
	print("SAVE COMPAT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
