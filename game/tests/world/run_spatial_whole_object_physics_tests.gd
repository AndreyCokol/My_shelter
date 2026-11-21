extends SceneTree
## A2-05: native PhysicsServer2D oracle for the whole-object spatial LOS.
## Colliders are inflated with the exact same actor radius (9px) and EPS
## as the A2 geometry. This is a physics parity test, NOT campaign pickup.
const Guard = preload("res://game/systems/world/spatial_whole_object_intent.gd")
const ACTOR := Vector2(80, 160)
const OBJECT := Vector2(155, 160)
const RADIUS := 9.0
const EPSILON := 0.5
const FLOOR := Rect2(0, 0, 480, 360)
const ACTION := "a2:phys:001"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + title)

func physical_object() -> Dictionary:
	return {
		"scene_id": "hospital_0_3",
		"object_id": "loot:stretcher-01",
		"type_id": "material.salvage",
		"kind": "loot", "state": "loose",
		"position": OBJECT, "quantity": 1,
	}

func _build_wall(parent: Node2D, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = rect.get_center()
	parent.add_child(body)
	var shape := RectangleShape2D.new()
	shape.size = rect.size + Vector2.ONE * (RADIUS + EPSILON) * 2.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)

func _oracle(arena: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(ACTOR, OBJECT)
	query.collision_mask = 1
	query.hit_from_inside = true
	return arena.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _run() -> void:
	var cases: Array = [
		[], # Empty LOS.
		[Rect2(110, 150, 12, 20)], # Mid-path obstacle.
		[Rect2(112, 165, 10, 10)], # Near/within 9.5px actor margin.
		[Rect2(112, 215, 10, 10)], # Far from the ray.
		[Rect2(151, 150, 15, 20)], # Target inside obstacle.
		[Rect2(78, 150, 15, 20)], # Source inside obstacle.
		[Rect2(112, 130, 15, 9)], # Far above.
		[Rect2(95, 135, 8, 16), Rect2(125, 165, 16, 16)], # Multiple walls.
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	for i in range(140):
		var obstacles: Array = []
		for j in range(rng.randi_range(1, 5)):
			obstacles.append(Rect2(
				rng.randf_range(92.0, 145.0),
				rng.randf_range(128.0, 190.0),
				rng.randf_range(3.0, 15.0),
				rng.randf_range(3.0, 20.0)))
		cases.append(obstacles)

	for case_index in range(cases.size()):
		var walls: Array = cases[case_index]
		var arena := Node2D.new()
		root.add_child(arena)
		for wall in walls:
			_build_wall(arena, wall)
		# A physics sync is necessary: querying immediately after creating
		# static bodies can yield false "clear" if the shape is not installed.
		await physics_frame
		var physics_clear: bool = _oracle(arena)
		var result: Dictionary = Guard.prepare_intent(
			"hospital_0_3", ACTOR, physical_object(), FLOOR, walls, ACTION, 90.0, RADIUS)
		check(result.ok == physics_clear,
			"case %d A2 LOS matches native PhysicsServer2D for %d inflated walls" % [case_index, walls.size()])
		if result.ok:
			check(result.quantity == 1 and result.needs_core_commit and not result.hide_before_commit,
				"case %d even physical free path cannot remove uncommitted object" % case_index)
		else:
			check(result.code == "BLOCKED_LINE_OF_INTERACTION",
				"case %d physics-blocked ray produces explicit spatial failure" % case_index)
		arena.queue_free()
		await physics_frame

	print("A2 WHOLE OBJECT PHYSICS TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
