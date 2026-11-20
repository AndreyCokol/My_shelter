extends SceneTree
## A2/A5: direct Godot verification of legacy v4/v5 geometry in 3D.
const Layout = preload("res://game/systems/world/world_layout.gd")
const Space = preload("res://game/systems/world/dual_view_space.gd")
const Bridge = preload("res://game/systems/world/dual_view_layout_bridge.gd")
const Preview = preload("res://game/scenes/prototypes/dual_view_layout_preview.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)
	else:
		print("PASS " + label)

func _run() -> void:
	check(Bridge.snapshot(-1, "hospital").code == "INVALID_MANIFEST", "negative seed refused")
	check(Bridge.snapshot(0, "hospital", 3).code == "INVALID_MANIFEST", "unreviewed historical version refused")
	check(Bridge.snapshot(0, "missing").code == "SCENE_NOT_FOUND", "unknown scene refused")
	check(Bridge.snapshot(0, "shelter").code == "UNSUPPORTED_SCENE", "A3 shelter content not claimed as A2 world geometry")
	var invalid_record := {"bounds": Rect2(0, 0, 100, 100), "spawn": Vector2(50, 50), "obstacles": [Rect2(40, 40, 30, 30)]}
	check(Bridge.from_record(0, "hospital", 5, invalid_record).code == "BLOCKED_SPAWN", "colliding legacy spawn refused")
	invalid_record.obstacles = [Rect2(20, 20, 0, 30)]
	check(Bridge.from_record(0, "hospital", 5, invalid_record).code == "INVALID_OBSTACLES", "degenerate old-world wall refused")
	invalid_record.obstacles = []
	invalid_record.spawn = Vector2(-100, 10)
	check(Bridge.from_record(0, "hospital", 5, invalid_record).code == "INVALID_SPAWN", "spawn outside world bounds refused")

	for seed_value in [0, 42, 127]:
		for version in [4, 5]:
			var nodes: Dictionary = Layout.build(seed_value, version)
			for scene_id in ["hospital_0_3", "hospital", "outside", "house_0"]:
				var snapshot: Dictionary = Bridge.snapshot(seed_value, scene_id, version)
				check(snapshot.ok, "seed %d v%d %s valid layout snapshot" % [seed_value, version, scene_id])
				if not snapshot.ok:
					continue
				var old: Dictionary = nodes[scene_id]
				check(snapshot.wall_count == old.obstacles.size() and snapshot.legacy_bounds == old.bounds and snapshot.legacy_spawn == old.spawn, "seed %d v%d %s exact existing collider/bounds provenance" % [seed_value, version, scene_id])
				check(Space.world_to_legacy(snapshot.hero_position).distance_to(old.spawn) < 0.01, "seed %d v%d %s spawn roundtrip" % [seed_value, version, scene_id])
				check(snapshot == Bridge.snapshot(seed_value, scene_id, version), "seed %d v%d %s repeat deterministic" % [seed_value, version, scene_id])
				for index in range(snapshot.wall_boxes.size()):
					var original: Rect2 = old.obstacles[index]
					var converted: Dictionary = snapshot.wall_boxes[index]
					if not converted.position.is_finite() or not converted.size.is_finite():
						check(false, "nonfinite wall geometry")
						break
					var return_rect := Rect2(
						Space.world_to_legacy(converted.position) - Vector2(converted.size.x, converted.size.z) * Space.PIXELS_PER_METRE * 0.5,
						Vector2(converted.size.x, converted.size.z) * Space.PIXELS_PER_METRE)
					if return_rect.position.distance_to(original.position) > 0.02 or return_rect.size.distance_to(original.size) > 0.02:
						check(false, "legacy wall changed during 3D extrusion")
						break
	check(Layout.manifest(42) == Layout.manifest(42), "legacy manifest still available without mutation")

	# Real scene graph, using current v5 floor 3, then floor 1 and street.
	var scene: Node3D = Preview.instantiate()
	root.add_child(scene)
	await process_frame
	var hero: CharacterBody3D = scene.get("hero")
	var topdown: Camera3D = scene.get("overhead")
	var fps: Camera3D = scene.get("first_person")
	var before_hero_id := hero.get_instance_id()
	check(scene.get("layout_snapshot").scene_id == "hospital_0_3", "real starter third-floor prototype staged")
	check(topdown.current and topdown.projection == Camera3D.PROJECTION_ORTHOGONAL, "3D layout retains strict orthographic topdown")
	var first_count := scene.get("layout_snapshot").wall_count
	var physical: Array = scene.get_children().filter(func(node): return node.is_in_group("a5_layout_preview_geometry"))
	check(physical.size() == first_count + 1, "actual 3D physics objects match v5 obstacle count plus floor")
	scene.call("set_first_person", true)
	check(fps.current and hero.get_instance_id() == before_hero_id, "same actor in first person at actual hospital")
	scene.call("cycle_layout")
	check(scene.get("layout_snapshot").scene_id == "hospital" and hero.get_instance_id() == before_hero_id, "switch floor 3 -> floor 1 without recreating hero")
	scene.call("cycle_layout")
	check(scene.get("layout_snapshot").scene_id == "outside" and topdown.current and hero.get_instance_id() == before_hero_id, "street scene preserves actor and topdown camera")
	scene.call("cycle_layout")
	check(scene.get("layout_snapshot").scene_id == "hospital_0_3" and fps.get_instance_id() != topdown.get_instance_id(), "cycle restores third floor with same two cameras")
	scene.queue_free()
	await process_frame
	print("A5 LAYOUT BRIDGE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
