extends SceneTree
## A2-03 direct Godot PhysicsServer2D route smoke:
## fixed hospital spawn -> both stairs on all 4 levels; ground floor
## two-leg corridor/lobby -> external entrance; obstructed corridor must fail.
## Isolated spatial test, DOES NOT move the live Campaign actor or save.
const Fixed = preload("res://game/systems/world/fixed_start_hospital.gd")
const Plans = preload("res://game/systems/world/building_plan.gd")
const ACTOR_RADIUS := 9.0
const EPS := 0.5
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func add_collider(parent: Node2D, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	# Minkowski inflate the 2D wall to model character center clearance.
	shape.size = rect.size + Vector2.ONE * 2.0 * (ACTOR_RADIUS + EPS)
	collider.shape = shape
	body.add_child(collider)

func physics_clear(arena: Node2D, start: Vector2, finish: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(start, finish)
	query.collision_mask = 1
	return arena.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _run() -> void:
	for floor_number in range(1, 5):
		var plan: Dictionary = Fixed.plan_for_floor(floor_number)
		check(Plans.valid(plan), "floor %d fixed plan accepted before PhysicsServer2D build" % floor_number)
		var arena := Node2D.new()
		arena.name = "FixedFloor%dPhysics" % floor_number
		root.add_child(arena)
		for wall in plan.walls:
			add_collider(arena, wall)
		for fixture in plan.furniture:
			add_collider(arena, fixture.rect)
		await physics_frame
		check(physics_clear(arena, plan.spawn, plan.stairs_up), "floor %d actual Godot physics spawn to up-stairs LOS walk corridor clear" % floor_number)
		check(physics_clear(arena, plan.spawn, plan.stairs_down), "floor %d actual Godot physics spawn to down-stairs LOS walk corridor clear" % floor_number)
		if floor_number == 1:
			var lobby_point := Vector2(plan.entrance.x, plan.spawn.y)
			check(physics_clear(arena, plan.spawn, lobby_point), "first-floor start reaches lobby alignment in corridor")
			check(physics_clear(arena, lobby_point, plan.entrance), "first-floor corridor/lobby route reaches the outside entrance")

		if floor_number == 3:
			# Mutation test: closing the shared corridor must be detected
			# by the exact same engine ray, not silently passed as 'safe'.
			add_collider(arena, Rect2(480, 201, 20, 100))
			await physics_frame
			check(not physics_clear(arena, plan.spawn, plan.stairs_up), "physical wall closure prevents third-floor exit via corridor")

		arena.queue_free()
		await physics_frame
	print("A2 FIXED HOSPITAL PHYSICS TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
