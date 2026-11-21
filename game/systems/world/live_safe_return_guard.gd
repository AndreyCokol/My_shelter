extends RefCounted
## A2-07 live physics veto on top of the already-tested static reachable plan.
##
## Uses *actual Godot PhysicsServer2D* shape queries. The caller must create
## and sync the target scene's colliders before calling, and should re-check
## immediately before A1's atomic transition. No teleport/save/WorldHost edits.
##
## LIMITS: current physics snapshot only, bodies on collision_mask only.
## Explicit hazard/water areas must be included as Rect2 hazards; this does
## not authorize a durable scene change, nor predict enemy movement.
const Reachable = preload("res://game/systems/world/safe_reachable_position.gd")
const EDGE_EPSILON := 0.5
const MAX_ROUTE_VERTICES := Reachable.MAX_NODES + 4

static func plan_and_verify(
		space: PhysicsDirectSpaceState2D, bounds: Rect2,
		static_rectangles: Array, dynamic_rectangles: Array,
		hazard_rectangles: Array, desired: Vector2, safe_anchor: Vector2,
		actor_radius: float = 9.0, collision_mask: int = 1,
		excluded_rids: Array[RID] = []) -> Dictionary:
	if space == null or not _valid_query_args(actor_radius, collision_mask, excluded_rids):
		return _fail("INVALID_ARGUMENT")
	var all_blockers: Array = static_rectangles + dynamic_rectangles
	var plan: Dictionary = Reachable.nearest_reachable(
		bounds, all_blockers, desired, safe_anchor, actor_radius, hazard_rectangles)
	if not plan.get("ok", false):
		return plan
	return verify_live(space, plan, actor_radius, collision_mask, excluded_rids)

static func verify_live(
		space: PhysicsDirectSpaceState2D, planned: Dictionary,
		actor_radius: float = 9.0, collision_mask: int = 1,
		excluded_rids: Array[RID] = []) -> Dictionary:
	if space == null or not _valid_query_args(actor_radius, collision_mask, excluded_rids):
		return _fail("INVALID_ARGUMENT")
	if not planned.get("ok", false) or not planned.get("path") is Array:
		return _fail("INVALID_PLAN")
	var path: Array = planned["path"]
	if path.is_empty() or path.size() > MAX_ROUTE_VERTICES:
		return _fail("INVALID_PLAN")
	if not planned.get("anchor") is Vector2 or not planned.get("position") is Vector2:
		return _fail("INVALID_PLAN")
	if not path.front() is Vector2 or not path.back() is Vector2:
		return _fail("INVALID_PLAN")
	if not path.front().is_equal_approx(planned["anchor"]) or not path.back().is_equal_approx(planned["position"]):
		return _fail("INVALID_PLAN")

	var shape := CircleShape2D.new()
	shape.radius = maxf(actor_radius + EDGE_EPSILON, EDGE_EPSILON)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.margin = 0.001
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = excluded_rids

	for index in range(path.size()):
		var position: Vector2 = path[index]
		if not position.is_finite():
			return _fail("INVALID_PLAN")
		# Even if cast_motion fails to report a shape starting inside another
		# collider, explicit point overlap must veto the proposed spawn.
		query.transform = Transform2D(0.0, position)
		query.motion = Vector2.ZERO
		if not space.intersect_shape(query, 1).is_empty():
			return _fail("PHYSICS_BLOCKED")
		if index == 0:
			continue
		var previous: Vector2 = path[index - 1]
		if not is_equal_approx(previous.x, position.x) and not is_equal_approx(previous.y, position.y):
			return _fail("INVALID_PLAN")
		if previous.is_equal_approx(position):
			continue
		query.transform = Transform2D(0.0, previous)
		query.motion = position - previous
		var fractions: PackedFloat32Array = space.cast_motion(query)
		# Fail closed on ANY fractional sweep contact, even very near the end.
		# A 99.9% path is NOT a safe path for a solid player collider.
		if fractions.size() != 2 or not is_finite(fractions[0]) or not is_finite(fractions[1]) or fractions[0] < 1.0 or fractions[1] < 1.0:
			return _fail("PHYSICS_BLOCKED")
	var verified: Dictionary = planned.duplicate(true)
	verified["live_physics_verified"] = true
	verified["live_collision_scope"] = "physics_bodies_on_mask_at_query_time"
	verified["needs_a1_atomic_commit"] = true
	return verified

static func _valid_query_args(actor_radius: float, mask: int, excluded: Array[RID]) -> bool:
	if not is_finite(actor_radius) or actor_radius < 0.0 or actor_radius > 24.0 or mask <= 0:
		return false
	for item in excluded:
		if not item.is_valid():
			return false
	return true

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}
