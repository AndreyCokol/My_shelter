extends SceneTree

const Space = preload("res://game/systems/world/dual_view_space.gd")
const Preview = preload("res://game/scenes/prototypes/dual_view_preview.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + name)

func _run() -> void:
	var points: Array[Vector2] = [
		Vector2.ZERO, Vector2(120, 260), Vector2(2400, 780),
		Vector2(-9999.25, 640.5), Vector2(1.0 / 3.0, 30.125),
	]
	for point in points:
		var world: Vector3 = Space.legacy_to_3d(point, 2.25)
		var restored: Vector2 = Space.world_to_legacy(world)
		check(world.is_finite() and restored.distance_to(point) < 0.005, "legacy 2D/3D coordinate roundtrip %s" % point)
		check(is_equal_approx(world.y, 2.25), "world elevation is independent from legacy second coordinate %s" % point)
	check(not Space.legacy_to_3d(Vector2(INF, 0)).is_finite(), "reject nonfinite legacy position")
	check(not Space.world_to_legacy(Vector3(NAN, 1, 2)).is_finite(), "reject nonfinite 3D position")
	var actor_raised := Vector3(3.25, 7.5, -2.0)
	check(is_equal_approx(Space.topdown_origin(actor_raised, 10.0).y, 17.5), "overhead camera follows elevated floors")
	check(is_equal_approx(Space.fps_origin(actor_raised).y, actor_raised.y + Space.EYE_OFFSET_FROM_BODY_CENTER_METRES), "FPS eye follows actor elevation, not static world altitude")

	var rectangle := Rect2(64, 32, 128, 48)
	var wall: Dictionary = Space.box_from_legacy_rect(rectangle, 3.0)
	check(wall.ok and wall.position.is_equal_approx(Vector3(4, 1.5, 1.75)), "2D rect center maps to 3D box center")
	check(wall.ok and wall.size.is_equal_approx(Vector3(4, 3, 1.5)), "wall width depth height preserve axis and world scale")
	check(not Space.box_from_legacy_rect(Rect2(0, 0, 0, 50)).ok, "reject degenerate wall rectangle")
	check(not Space.box_from_legacy_rect(rectangle, -2.0).ok, "reject negative wall height")

	var top_rotation := Space.topdown_rotation()
	check(is_equal_approx(top_rotation.x, -PI * 0.5) and is_zero_approx(top_rotation.y) and is_zero_approx(top_rotation.z), "strict topdown is exactly -90 degrees X, no yaw or tilt")
	var top_basis := Basis.from_euler(top_rotation)
	check((-top_basis.z).distance_to(Vector3(0, -1, 0)) < 0.0001, "topdown camera optical axis points exactly down -Y")

	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var yaw := Space.yaw_for_legacy_facing(direction)
		check(Space.facing_for_yaw(yaw).distance_to(direction) < 0.00001, "FPS heading roundtrip %s" % direction)
	check(Space.world_motion(Vector2(0, -1), 0.0, true).is_equal_approx(Vector3(0, 0, -1)), "FPS W points toward camera forward")
	check(Space.world_motion(Vector2(1, 0), 0.0, true).is_equal_approx(Vector3(1, 0, 0)), "FPS D strafes right")
	check(Space.world_motion(Vector2(0, -1), -PI * 0.5, true).distance_to(Vector3(1, 0, 0)) < 0.00001, "yaw rotates FPS movement without moving the world")
	check(Space.world_motion(Vector2(1, 1), -PI * 0.5, false).length() <= 1.001, "topdown diagonal speed bounded")

	# Real Godot scene: a single CharacterBody3D survives the view switch.
	var scene: Node3D = Preview.instantiate()
	get_root().add_child(scene)
	await process_frame
	var hero: CharacterBody3D = scene.get("hero")
	var overhead: Camera3D = scene.get("overhead")
	var fps: Camera3D = scene.get("first_person")
	check(is_instance_valid(hero) and is_instance_valid(overhead) and is_instance_valid(fps), "preview allocates one shared actor and two Camera3D instances")
	if is_instance_valid(hero) and is_instance_valid(overhead) and is_instance_valid(fps):
		var before := hero.position
		var current_hero_nodes := scene.find_children("*", "CharacterBody3D", true, false)
		check(current_hero_nodes.size() == 1 and overhead.current and not fps.current, "topdown default uses one actor and orthogonal camera")
		check(overhead.projection == Camera3D.PROJECTION_ORTHOGONAL and fps.projection == Camera3D.PROJECTION_PERSPECTIVE, "each camera has correct projection")
		scene.call("set_first_person", true)
		check(fps.current and not overhead.current and hero.position == before, "switch FPS without teleporting or duplicating hero")
		scene.call("set_first_person", false)
		check(overhead.current and not fps.current and scene.find_children("*", "CharacterBody3D", true, false).size() == 1, "switch back to strictly overhead view without duplication")

		# Real 3D collision query: one existing preview wall must block LOS.
		await physics_frame
		var origin := Space.legacy_to_3d(Vector2(105, 115), 1.1)
		var endpoint := Space.legacy_to_3d(Vector2(250, 115), 1.1)
		var query := PhysicsRayQueryParameters3D.create(origin, endpoint)
		query.exclude = [hero.get_rid()]
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider is StaticBody3D, "actual 3D physics wall blocks raycast in shared world")
		# Identical 3D collision object must be reported in both camera modes.
		hero.position = Space.legacy_to_3d(Vector2(105, 115), 0.9)
		scene.set("look_yaw", -PI * 0.5)
		await physics_frame
		var top_hit: Dictionary = scene.call("probe_forward", 8.0)
		check(top_hit.ok and top_hit.get("hit", false) and top_hit.collider is StaticBody3D, "overhead mode probes a real wall")
		scene.call("set_first_person", true)
		var fps_hit: Dictionary = scene.call("probe_forward", 8.0)
		check(fps_hit.ok and fps_hit.get("hit", false) and fps_hit.collider == top_hit.get("collider"), "FPS mode uses same world object, not a copied collision map")
		check(not scene.call("probe_forward", 0.0).ok, "invalid LOS reach is rejected without mutating actor")
		scene.call("set_first_person", false)

	scene.queue_free()
	await process_frame
	print("A2 DUAL VIEW TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
