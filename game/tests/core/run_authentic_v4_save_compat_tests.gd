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
# Native original generator-v4 canonical fingerprints from source SHA
# 59bb12517e21850386092bd1e0a5e3d79c23c98a; confirmed on both
# Linux and Windows (old test PR #191, commit 3c08f163...).
const OLD_V4_GEOMETRY := {
	0: "f239bfde9c6b06bf66b8d2093e462e9ae72a1b873908e8ac1b2e8eb3fd868174",
	1: "47e5cc76e27dc9fa4c5a28f083f92f6cb75610d01e9069a250f8fff08b37378f",
	54: "66e12d5213a5f7e93e2cb2ef9ac9f25b855760d332b5d5f79c977087fc6e0826",
	1234: "f87dcf8d2caee31444031aca392fea1865ecfd9c7305df12e0d99031d406d554",
	2147483647: "def5a7a20a16d5888d816771f6d6ba3ab42b56c1032d9d75cb74f1faf2c2bf38"
}
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

const GEOMETRY_KEYS := ["kind", "segment", "label", "bounds", "spawn", "loot",
	"enemy", "patrol", "obstacles", "links", "aprons", "roadways",
	"facades", "rooms", "floor_plan", "exits", "salvage", "event",
	"building_id", "floor_number"]

static func geometry_value(value):
	if value is Vector2:
		return ["Vector2", value.x, value.y]
	if value is Rect2:
		return ["Rect2", value.position.x, value.position.y, value.size.x, value.size.y]
	if value is PackedVector2Array:
		var values: Array = []
		for v in value:
			values.append(geometry_value(v))
		return ["PackedVector2Array", values]
	if value is Dictionary:
		# Normalize StringName / String to textual keys BEFORE sorting;
		# otherwise two true v4 environments can hash equivalent exits in
		# different orders despite identical positions and connectors.
		var rows: Array = []
		for k in value.keys():
			rows.append([str(k), geometry_value(value[k])])
		rows.sort_custom(func(a, b): return a[0] < b[0])
		return rows
	if value is Array:
		var result: Array = []
		for v in value:
			result.append(geometry_value(v))
		return result
	return value

static func geometry_digest(world_seed: int, version: int) -> Dictionary:
	var nodes: Dictionary = Layout.build(world_seed, version)
	var ids: Array = nodes.keys()
	ids.sort()
	var projection: Array = []
	for id in ids:
		var selected: Dictionary = {}
		for key in GEOMETRY_KEYS:
			if nodes[id].has(key):
				selected[key] = nodes[id][key]
		projection.append([id, geometry_value(selected)])
	return {"nodes": ids.size(),
		"sha256": JSON.stringify(projection, "", true, true).sha256_text()}

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
	var geom: Dictionary = geometry_digest(54, 4)
	print("A1_CURRENT_V4_GEOMETRY_NODES=" + str(geom.nodes))
	print("A1_CURRENT_V4_GEOMETRY_SHA256=" + geom.sha256)
	var nodes: Dictionary = Layout.build(54, 4)
	var ids: Array = nodes.keys()
	ids.sort()
	for id in ids:
		var selected: Dictionary = {}
		for key in GEOMETRY_KEYS:
			if nodes[id].has(key):
				selected[key] = nodes[id][key]
		print("A1_CURRENT_V4_NODE_" + id + "_SHA256=" +
			JSON.stringify([id, geometry_value(selected)], "", true, true).sha256_text())
	check(geom.nodes == 30, "current v4 compatibility renderer preserves all 30 historical scene IDs")
	# Legacy ground-floor exit keys may be StringName or String; the
	# corrected canonicalizer hashes both by sorted TEXT key, not Variant.
	check(geom.sha256 == "66e12d5213a5f7e93e2cb2ef9ac9f25b855760d332b5d5f79c977087fc6e0826",
		"current v4 geometry equals genuine v4 geometry using OS-stable canonical key order")
	# Deliberately compare multiple worlds, not only seed 54; include both
	# boundaries and verify per-seed cross-OS legacy geometry contracts.
	for legacy_seed in [0, 1, 54, 1234, Layout.MAX_SEED]:
		var candidate: Dictionary = geometry_digest(legacy_seed, 4)
		check(candidate.nodes == 30 and candidate.sha256 == OLD_V4_GEOMETRY[legacy_seed],
			"current v4 legacy geometry matches original source for seed " + str(legacy_seed))
		print("A1_CURRENT_V4_GEOMETRY_SEED_" + str(legacy_seed) + "_SHA256=" + candidate.sha256)
	for fixture in SOURCES:
		verify_one(config, fixture.name, fixture.sha256)
	print("AUTHENTIC V4 COMPAT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
