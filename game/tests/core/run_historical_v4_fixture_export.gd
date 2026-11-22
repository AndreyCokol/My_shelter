extends SceneTree

# A1 provenance experiment: historical *original generator VERSION=4* commit
# 59bb12517e21850386092bd1e0a5e3d79c23c98a; no modern source is
# allowed to construct this checkpoint. Emits disposable test bytes in CI.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Model = preload("res://game/state/campaign_model.gd")

var checks: int = 0
var fails: int = 0

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		fails += 1
		push_error("FAIL " + label)
	else:
		print("PASS " + label)

func request(session, action_id: String, kind: String, payload: Dictionary = {}) -> Dictionary:
	var s: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in s.resource_revisions:
		revisions.append({"key": key, "revision": s.resource_revisions[key]})
	return {"action_id": action_id, "command_type": kind, "payload": payload,
		"context": {"actor_id":"player", "scene_id":s.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

# Canonical, type-aware fingerprint of important authored geometry and links.
# Uses only explicit v4 scene records and stable id/key order; no UI textures.
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
		# StringName and String keys can sort in a different Variant order
		# on Windows vs Linux. Normalize to String FIRST, then sort rows
		# by textual key to avoid a false cross-OS geometry mismatch.
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

func emit(name: String, state: Dictionary, store: Object, config: Dictionary) -> void:
	expect(Model.validate(state, config), name + " is valid under REAL v4 model")
	var result: Dictionary = store.write_checkpoint(state, Model.validate.bind(config))
	expect(result.get("committed", false), name + " persisted by REAL v4 CheckpointStore")
	if not result.get("committed", false):
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(store.path)
	expect(not bytes.is_empty(), name + " nonempty authentic save bytes")
	print("A1_REAL_V4_FIXTURE_" + name + "_B64=" + Marshalls.raw_to_base64(bytes))
	print("A1_REAL_V4_FIXTURE_" + name + "_SHA256=" + FileAccess.get_sha256(store.path))

func run() -> void:
	expect(Layout.VERSION == 4, "artifact generator executes historical VERSION 4 code")
	var geo: Dictionary = geometry_digest(54, Layout.VERSION)
	expect(geo.nodes > 15 and geo.sha256.length() == 64, "historical native v4 geometry canonical digest generated")
	print("A1_REAL_V4_GEOMETRY_NODES=" + str(geo.nodes))
	print("A1_REAL_V4_GEOMETRY_SHA256=" + geo.sha256)
	# Reproduce more than one procedural world, including allowed boundaries.
	# These values must come from the *original* v4 runtime, never modern code.
	for legacy_seed in [0, 1, 54, 1234, Layout.MAX_SEED]:
		var probe: Dictionary = geometry_digest(legacy_seed, 4)
		expect(probe.nodes == 30 and probe.sha256.length() == 64,
			"original generator4 produces 30-node canonical layout seed " + str(legacy_seed))
		print("A1_REAL_V4_GEOMETRY_SEED_" + str(legacy_seed) + "_SHA256=" + probe.sha256)
	var nodes: Dictionary = Layout.build(54, 4)
	var ids: Array = nodes.keys()
	ids.sort()
	for id in ids:
		var selected: Dictionary = {}
		for key in GEOMETRY_KEYS:
			if nodes[id].has(key):
				selected[key] = nodes[id][key]
		var canonical: String = JSON.stringify([id, geometry_value(selected)], "", true, true)
		print("A1_REAL_V4_NODE_" + id + "_SHA256=" + canonical.sha256_text())
		if id in ["hospital", "hospital_1_1", "house_0"]:
			print("A1_REAL_V4_EXIT_JSON_" + id + "=" +
				JSON.stringify(geometry_value(selected.get("exits", {})), "", true, true))
		if id in ["hospital", "hospital_1_1", "house_0", "house_0_2"]:
			for key in GEOMETRY_KEYS:
				if selected.has(key):
					print("A1_REAL_V4_FIELD_" + id + "__" + key + "_SHA256=" +
						JSON.stringify(geometry_value(selected[key]), "", true, true).sha256_text())
	var config: Dictionary = Rules.build()
	config.world_seed = 54
	config.scenes = Layout.entries()
	expect(Campaign.valid_rules(config), "actual old GameRules validates generator 4")
	if not Campaign.valid_rules(config):
		print("HISTORICAL V4 FIXTURE TESTS: %d checks, %d failures" % [checks, fails])
		quit(1)
		return
	var session = Campaign.new(config).coordinator
	var original: Dictionary = session.get_snapshot()
	expect(original.schema_version == 4
		and original.world_states.layout.generator_version == 4,
		"actual old campaign makes native v4 manifest, not patched modern state")
	var path: String = "user://a1-authentic-v4-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store = Store.new(path)
	emit("FRESH", original, store, config)
	var victory: Dictionary = request(session, "a1-historical-v4:first-win", "game.enemy_defeated")
	var earned: Dictionary = session.execute(victory, store)
	expect(earned.ok, "real old game commits first enemy victory and receipt")
	if earned.ok:
		var progressed: Dictionary = session.get_snapshot()
		expect(progressed.completed_actions.has(victory.action_id)
			and progressed.world_states.first_enemy_defeated,
			"old v4 state includes actual historical action receipt and world flag")
		emit("REWARD", progressed, store, config)
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("HISTORICAL V4 FIXTURE TESTS: %d checks, %d failures" % [checks, fails])
	quit(0 if fails == 0 else 1)
