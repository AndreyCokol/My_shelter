extends SceneTree

const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Router = preload("res://game/systems/scene_router/scene_router.gd")
const Fixtures = preload("res://game/tests/core/campaign_fixtures.gd")
var checks: int = 0
var failures: int = 0
var observed_router
var scene_fact_count: int = 0
var scene_fact_after_install: bool = false
var previous_observed_world_id: int = 0

func on_scene_fact(_event: Dictionary) -> void:
	scene_fact_count += 1
	scene_fact_after_install = observed_router.current_world().get_instance_id() != previous_observed_world_id

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func packed_world(spawn: Vector2, with_marker: bool = true) -> PackedScene:
	var world := Node2D.new()
	world.name = "TestWorld"
	var entries := Node2D.new()
	entries.name = "EntryPoints"
	world.add_child(entries)
	entries.owner = world
	if with_marker:
		var marker := Marker2D.new()
		marker.name = "default"
		marker.position = spawn
		entries.add_child(marker)
		marker.owner = world
	var packed := PackedScene.new()
	packed.pack(world)
	world.free()
	return packed

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var campaign = Campaign.new(Fixtures.rules())
	var session = campaign.coordinator
	var store = Store.new("user://router-tests/" + str(Time.get_ticks_usec()) + ".json")
	var host := Node2D.new()
	var actor := Node2D.new()
	root.add_child(host)
	host.add_child(actor)
	var registry := {"shelter": packed_world(Vector2(10, 20)), "outside": packed_world(Vector2(100, 200))}
	var router = Router.new(host, actor, session, store, registry)
	check(router.mount_current() and host.get_child_count() == 2, "mount actual world with one actor")
	actor.position = Vector2(32.25, 17.5)
	check(router.save("save-position").ok, "save captures actual actor position")
	var old := router.current_world()
	check(router.try_transition("go-out", "outside", "default").ok, "actual world transition commits")
	check(not is_instance_valid(old) and actor.position == Vector2(100, 200) and host.get_child_count() == 2, "old world disposed, actor reused, entry marker applied")
	actor.position = Vector2(250.5, 300.25)
	check(router.try_transition("go-home", "shelter", "default").ok and actor.position == Vector2(32.25, 17.5), "return to saved shelter position")
	check(session.get_snapshot().scene.last_outside_position == {"x": 250.5, "y": 300.25}, "outside return coordinate persisted")
	check(router.try_transition("out-again", "outside", "default").ok and actor.position == Vector2(250.5, 300.25), "outside round trip restores departure point")
	var mounted = router.current_world()
	actor.position = Vector2(260, 310)
	var replay: Dictionary = router.try_transition("go-home", "shelter", "default")
	check(replay.code == "ALREADY_APPLIED" and router.current_world() == mounted and actor.position == Vector2(260, 310), "old action replay does not remount or teleport")
	var before: Dictionary = session.get_snapshot()
	check(router.try_transition("missing-resource", "absent", "default").code == "UNAVAILABLE" and session.get_snapshot() == before and router.current_world() == mounted, "missing resource preserves state and active world")
	check(router.try_transition("missing-marker", "shelter", "bad").code == "UNAVAILABLE" and session.get_snapshot() == before, "missing entry rejected before commit")
	check(router.try_transition("path-entry", "shelter", "../default").code == "UNAVAILABLE", "entry cannot traverse node paths")
	store.fault = "before_replace"
	check(router.try_transition("failed-write", "shelter", "default").code == "SAVE_FAILED" and router.current_world() == mounted and session.get_snapshot() == before, "failed checkpoint keeps active world and campaign")
	store.fault = ""
	var token: int = session.pauses.acquire_pause("menu")
	check(router.try_transition("paused", "shelter", "default").code == "PAUSED" and router.current_world() == mounted, "paused transition has no world mutation")
	session.pauses.release_pause(token)
	check(router.save("save-outside").ok, "save updated outside position")
	actor.position = Vector2(999, 999)
	check(router.load_saved().ok and actor.position == Vector2(260, 310), "reload restores actual actor coordinate")
	# Broken resource during load must not publish candidate state or state_loaded.
	var bad_host := Node2D.new()
	var bad_actor := Node2D.new()
	root.add_child(bad_host)
	bad_host.add_child(bad_actor)
	var bad_campaign = Campaign.new(Fixtures.rules())
	var bad_session = bad_campaign.coordinator
	var bad_router = Router.new(bad_host, bad_actor, bad_session, store, {"shelter": registry.shelter, "outside": packed_world(Vector2.ZERO, false)})
	bad_router.mount_current()
	var old_bad_world = bad_router.current_world()
	var bad_before: Dictionary = bad_session.get_snapshot()
	check(not bad_router.load_saved().ok and bad_session.get_snapshot() == bad_before and bad_router.current_world() == old_bad_world, "load stages resource before replacing state/world")
	# Crash after durable checkpoint, before RAM/world swap.
	store.fault = "after_replace"
	mounted = router.current_world()
	check(router.try_transition("disk-crash", "shelter", "default").code == "UNAVAILABLE" and router.current_world() == mounted and session.pauses.is_paused(), "postcommit failure freezes old world for recovery")
	store.fault = ""
	check(router.load_saved().ok and session.get_snapshot().scene.current_scene_id == "shelter" and actor.position == Vector2(32.25, 17.5), "recovery restores committed target and position together")
	mounted = router.current_world()
	check(router.try_transition("disk-crash", "shelter", "default").code == "ALREADY_APPLIED" and router.current_world() == mounted, "recovered transition replay is effect-free")
	observed_router = router
	previous_observed_world_id = mounted.get_instance_id()
	session.events.subscribe(self, on_scene_fact, ["scene_changed"])
	var previous_world_id: int = mounted.get_instance_id()
	var observer: Array = [false]
	session.committed.connect(func(_result): observer[0] = router.current_world().get_instance_id() != previous_world_id and session.get_snapshot().scene.current_scene_id == "outside")
	check(router.try_transition("observed", "outside", "default").ok and observer[0], "notification observes installed runtime and committed state")
	check(scene_fact_count == 1 and scene_fact_after_install, "DomainEvent delivered after actual world installation")
	session.events.unsubscribe_owner(self)
	observed_router = null
	var reentrant: Array = [""]
	session.committed.connect(func(_result): reentrant[0] = router.try_transition("reentrant", "outside", "default").code)
	check(router.try_transition("back-for-reentrant", "shelter", "default").ok and reentrant[0] == "UNAVAILABLE", "reentrant transition cannot replace a committing world")
	var loaded_observer: Array = [false]
	session.state_loaded.connect(func(): loaded_observer[0] = actor.position == Vector2(32.25, 17.5))
	check(router.load_saved().ok and loaded_observer[0], "state_loaded observes restored runtime")
	for connection in session.state_loaded.get_connections():
		session.state_loaded.disconnect(connection.callable)
	# Release external signal closure before disposal; no retained router/session cycle.
	for connection in session.committed.get_connections():
		session.committed.disconnect(connection.callable)
	var old_schema: Dictionary = session.get_snapshot()
	old_schema.schema_version = 1
	var legacy_file := FileAccess.open(store.path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(old_schema))
	legacy_file.close()
	var preserved: Dictionary = session.get_snapshot()
	check(not router.load_saved().ok and session.get_snapshot() == preserved, "unsupported old schema refuses load without live mutation")
	var missing_result: Dictionary = router.try_transition("error-envelope", "absent", "default")
	check(missing_result.action_id == "error-envelope" and missing_result.has("state_revision") and missing_result.has("message_key"), "router errors preserve CommandResult envelope")
	for path in [store.path]:
		for suffix in ["", ".tmp", ".bak", ".rejected"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	host.free()
	bad_host.free()
	var main = preload("res://game/scenes/main/main.tscn").instantiate()
	root.add_child(main)
	var supplied_actor := Node2D.new()
	check(main.start_campaign(Fixtures.rules(), registry, supplied_actor, store.path + ".main").ok and main.scene_router.current_world().get_parent() == main.get_node("WorldHost"), "composition root accepts supplied campaign/world/actor")
	check(main.start_campaign(Fixtures.rules(), registry, supplied_actor).code == "INVALID_STATE", "composition root prevents duplicate campaign/actor")
	main.free()
	print("ROUTER TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
