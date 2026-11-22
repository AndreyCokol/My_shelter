extends SceneTree

# A1-04: exact historical generator v4 checkpoint bytes from real historical
# source SHA 59bb12517e21850386092bd1e0a5e3d79c23c98a, exported via
# PR #191 and verified with identical Linux/Windows SHA-256.
# No modern generator_version mutation is allowed for these fixtures.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Model = preload("res://game/state/campaign_model.gd")
const OLD_WIN_ID := "a1-historical-v4:first-win"
const SOURCES := [
	{"name":"fresh", "sha256":"b7aa2dad9fda7cc82e4d8b8792b87b660efea00e64eb29e890586a26c35221d8"},
	{"name":"reward", "sha256":"f1ca6539208d5b440fdb95e830925112162131934bb82d8d43329d14fd3d2514"}
]
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

func request(session, action_id: String, kind: String) -> Dictionary:
	var s: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in s.resource_revisions:
		revisions.append({"key": key, "revision": s.resource_revisions[key]})
	return {"action_id":action_id, "command_type":kind, "payload":{},
		"context":{"actor_id":"player", "scene_id":s.scene.current_scene_id,
			"expected_resource_revisions":revisions}}

func cleanup(path: String) -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp", ".rejected", ".rejected.1"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func historical_bytes(name: String) -> PackedByteArray:
	var fixture_file: String = "res://game/tests/fixtures/authentic_gen4_%s.b64" % name
	var base64: String = FileAccess.get_file_as_string(fixture_file).strip_edges()
	return Marshalls.base64_to_raw(base64)

func import_old(path: String, raw: PackedByteArray, sha: String) -> bool:
	cleanup(path)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(raw)
	file.flush()
	var good: bool = file.get_error() == OK
	file.close()
	return good and FileAccess.get_sha256(path) == sha

func verify_one(config: Dictionary, name: String, expected_sha: String) -> void:
	var original: PackedByteArray = historical_bytes(name)
	check(not original.is_empty(), "authentic v4 " + name + " bytes decoded")
	if original.is_empty():
		return
	var path: String = "user://a1-real-old-v4-%s-%d-%d.json" % [name, OS.get_process_id(), Time.get_ticks_usec()]
	check(import_old(path, original, expected_sha), "real old " + name + " bytes identical to historical CI SHA256")
	var store = Store.new(path)
	var read: Dictionary = store.read_checkpoint()
	check(read.ok, "modern JSON parser reads authentic old v4 checkpoint " + name)
	if not read.ok:
		cleanup(path)
		return
	var source: Dictionary = read.state
	check(source.schema_version == 4
		and source.world_states.layout.generator_version == 4
		and source.world_states.layout.seed == 54,
		"original historical native v4 manifest, not rewritten modern manifest")
	check(Model.validate(source, config),
		"modern domain validator accepts native historical v4 " + name)
	if not Model.validate(source, config):
		cleanup(path)
		return
	var session = Campaign.new(config).coordinator
	var loaded: Dictionary = session.load_checkpoint(store)
	check(loaded.ok and session.get_snapshot() == source,
		"real old v4 " + name + " loads unchanged into modern CampaignSession")
	if not loaded.ok:
		cleanup(path)
		return
	check(FileAccess.get_file_as_bytes(path) == original,
		"loading real old v4 checkpoint does not rewrite durable original bytes")
	var state: Dictionary = session.get_snapshot()
	if name == "reward":
		check(state.completed_actions.has(OLD_WIN_ID)
			and state.world_states.first_enemy_defeated,
			"historical native v4 reward and action receipt retained")
		var replay: Dictionary = request(session, OLD_WIN_ID, "game.enemy_defeated")
		check(session.execute(replay, store).code == "ALREADY_APPLIED",
			"authentic historical receipt replay cannot regrant weapon or XP")
		check(FileAccess.get_file_as_bytes(path) == original,
			"authentic historic receipt replay leaves original file intact")
	var upgrade: Dictionary = request(session, "a1-real-v4:%s:upgrade" % name, "session.upgrade_world")
	var migrated: Dictionary = session.execute(upgrade, store)
	check(migrated.ok, "explicit actual legacy v4 -> current world upgrade succeeds " + name)
	if not migrated.ok:
		cleanup(path)
		return
	var after: Dictionary = session.get_snapshot()
	check(after.world_states.layout.generator_version == Layout.VERSION
		and after.world_states.layout.seed == 54 and Model.validate(after, config),
		"upgraded real old v4 save preserves seed, valid schema4 and current generator")
	check(FileAccess.get_file_as_bytes(path + ".bak") == original,
		"backup contains EXACT original historical v4 bytes after upgrade")
	check(session.execute(upgrade, store).code == "ALREADY_APPLIED",
		"upgrade receipt replay cannot migrate again")
	var reboot = Campaign.new(config).coordinator
	check(reboot.load_checkpoint(store).ok and reboot.get_snapshot() == after,
		"modern upgraded state survives independent disk reload")
	if name == "reward":
		check(reboot.execute(request(reboot, OLD_WIN_ID, "game.enemy_defeated"), store).code ==
			"ALREADY_APPLIED", "old v4 victory receipt survives migration and reboot")
	var rollback: Dictionary = reboot.load_checkpoint(store, true)
	check(rollback.ok and reboot.get_snapshot() == source,
		"explicit backup rollback restores actual historic v4 domain state")
	check(FileAccess.get_file_as_bytes(path + ".bak") == original,
		"rollback preserves exact historical v4 backup bytes")
	cleanup(path)

func run() -> void:
	var config: Dictionary = Rules.build()
	config.world_seed = 54
	config.scenes = Layout.entries()
	check(Campaign.valid_rules(config), "current config validates before importing actual old saves")
	check(Layout.VERSION > 4, "test executes current generator, distinct from real v4 fixture generator")
	for fixture in SOURCES:
		verify_one(config, fixture.name, fixture.sha256)
	print("AUTHENTIC V4 COMPAT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
