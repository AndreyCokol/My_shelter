extends SceneTree
## A2-07 real PhysicsServer2D acceptance for static/dynamic shelter-return.
## This test uses real Godot colliders, not just manual Rect2 intersections.
const Guard = preload("res://game/systems/world/live_safe_return_guard.gd")
const Reachable = preload("res://game/systems/world/safe_reachable_position.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const BOUNDS := Rect2(0, 0, 320, 200)
const ANCHOR := Vector2(40, 100)
const GOAL := Vector2(240, 100)
const RADIUS := 9.0

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func wall(arena: Node2D, rectangle: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = rectangle.get_center()
	body.collision_layer = 1
	body.collision_mask = 1
	arena.add_child(body)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rectangle.size
	collision.shape = shape
	body.add_child(collision)
	return body

func actor(arena: Node2D, center: Vector2, radius: float) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 1
	arena.add_child(body)
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	collider.shape = circle
	body.add_child(collider)
	return body

func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	await physics_frame
	var space: PhysicsDirectSpaceState2D = arena.get_world_2d().direct_space_state

	var open: Dictionary = Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR)
	check(open.ok and open.position == GOAL and open.live_physics_verified,
		"open real physics world reaches exact original return position")
	check(open.needs_a1_atomic_commit and open.live_collision_scope == "physics_bodies_on_mask_at_query_time",
		"real collision proof never pretends it already committed SceneRouter/save")
	check(Guard.verify_live(space, open).ok,
		"unchanged live physics accepts exact route revalidation")
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR) == open,
		"repeated live physical planning is deterministic when scene does not change")

	# A real StaticBody2D wall separates the map, forcing fallback on
	# the reachable side, even though target position itself is empty.
	var barrier_rect := Rect2(154, -10, 12, 220)
	var separator := wall(arena, barrier_rect)
	await physics_frame
	var guard: Dictionary = Guard.plan_and_verify(
		space, BOUNDS, [barrier_rect], [], [], GOAL, ANCHOR)
	check(guard.ok and guard.relocated and guard.position.x < barrier_rect.position.x,
		"real full-height physical wall forces reachable-side fallback")
	check(guard.ok and guard.live_physics_verified and guard.path.size() >= 1,
		"fallback route has real PhysicsServer2D certified points/segments")
	var missed: Dictionary = Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR)
	check(not missed.ok and missed.code == "PHYSICS_BLOCKED",
		"missing stale Rect2 wall snapshot is vetoed by actual physics sweep")
	check(Guard.verify_live(space, open).code == "PHYSICS_BLOCKED",
		"previously safe route is vetoed after a new wall appears")
	separator.queue_free()
	await physics_frame
	check(Guard.verify_live(space, open).ok,
		"removal of the physical wall restores the previously open route")

	# A moving enemy can block only the MIDDLE of an otherwise clear
	# return path. Both endpoint tests remain empty; only a real
	# PhysicsServer2D swept-circle query can veto this trajectory.
	var roaming_enemy := actor(arena, Vector2(140, 100), 12.0)
	await physics_frame
	check(Guard.verify_live(space, open).code == "PHYSICS_BLOCKED",
		"live enemy across middle of route vetoes circle sweep despite free endpoints")
	roaming_enemy.queue_free()
	await physics_frame
	check(Guard.verify_live(space, open).ok,
		"after moving enemy away, middle segment can be retraversed")

	# Native dynamic CharacterBody2D at destination, missing from Rect2
	# snapshot: the old static planner would erroneously approve the spawn.
	var enemy := actor(arena, GOAL, 13.0)
	await physics_frame
	var occupied: Dictionary = Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR)
	check(not occupied.ok and occupied.code == "PHYSICS_BLOCKED",
		"live enemy in requested return position cannot be ignored")
	var enemy_rect := Rect2(enemy.position - Vector2(13, 13), Vector2(26, 26))
	var fallback: Dictionary = Guard.plan_and_verify(
		space, BOUNDS, [], [enemy_rect], [], GOAL, ANCHOR)
	check(fallback.ok and fallback.relocated and fallback.position.distance_to(GOAL) > 22,
		"snapshot of actual dynamic enemy allows reachable non-overlapping fallback")
	check(fallback.ok and fallback.path.front() == ANCHOR and fallback.path.back() == fallback.position,
		"enemy-aware fallback has a complete physical route from known anchor")
	var old_fallback: Dictionary = fallback.duplicate(true)
	enemy.position = fallback.position
	await physics_frame
	check(Guard.verify_live(space, old_fallback).code == "PHYSICS_BLOCKED",
		"enemy movement AFTER path planning invalidates arrival on live recheck")
	var updated_rect := Rect2(enemy.position - Vector2(13, 13), Vector2(26, 26))
	var updated := Guard.plan_and_verify(space, BOUNDS, [], [updated_rect], [], GOAL, ANCHOR)
	check(updated.ok and not updated.position.is_equal_approx(enemy.position),
		"updated actor snapshot re-plans safely after NPC moved")
	enemy.queue_free()
	await physics_frame
	check(Guard.verify_live(space, open).ok,
		"old desired return is restored after live enemy exits the scene")

	# A live actor at the anchor appears as a PhysicsServer collider. A1
	# must explicitly exclude its RID when checking its OWN walk path, or
	# stage a separate offscreen target scene with no actor collider.
	var hero := actor(arena, ANCHOR, RADIUS)
	await physics_frame
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR).code == "PHYSICS_BLOCKED",
		"self-collider blocks anchor unless excluded explicitly")
	var excluded: Array[RID] = [hero.get_rid()]
	var self_excluded := Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR, RADIUS, 1, excluded)
	check(self_excluded.ok and self_excluded.position == GOAL,
		"excluding ONLY own RID permits return while other bodies remain active")
	hero.queue_free()
	await physics_frame

	# Hazard geometry is an explicit non-solid forbidden region. This must
	# remain a strict caller responsibility, independent of PhysicsServer.
	var flooded := Rect2(151, -10, 30, 220)
	var safe_hazard := Guard.plan_and_verify(space, BOUNDS, [], [], [flooded], GOAL, ANCHOR)
	check(safe_hazard.ok and safe_hazard.position.x < flooded.position.x,
		"registered water/hazard rectangle prevents crossing flooded barrier")
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, Vector2(-4, 30)).code == "INVALID_ANCHOR",
		"invalid or unstaged anchor is rejected without moving the actor")
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR, -1.0).code == "INVALID_ARGUMENT",
		"negative actor radius refuses physics query")
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR, RADIUS, 0).code == "INVALID_ARGUMENT",
		"missing collision mask is rejected")
	check(Guard.verify_live(space, {"ok": true, "path": []}).code == "INVALID_PLAN",
		"forged empty plan is rejected without a physics authorization")
	check(Guard.verify_live(space, {
		"ok": true, "anchor": ANCHOR, "position": GOAL,
		"path": [ANCHOR, GOAL + Vector2(0, 10)]
	}).code == "INVALID_PLAN", "mismatched end point cannot get physics authorization")
	check(Guard.verify_live(space, {
		"ok": true, "anchor": ANCHOR, "position": GOAL + Vector2(0, 10),
		"path": [ANCHOR, GOAL + Vector2(0, 10)]
	}).code == "INVALID_PLAN", "diagonal unswept path segment cannot be declared safe")

	# Important A1/WorldHost integration case: the plan is in generator
	# LOCAL coordinates while PhysicsServer2D uses the world-space transform.
	# A scene may be mounted with translation and 90 degree rotation.
	var moved_scene := Node2D.new()
	moved_scene.position = Vector2(650, 270)
	moved_scene.rotation = PI / 2.0
	arena.add_child(moved_scene)
	wall(moved_scene, barrier_rect)
	await physics_frame
	var transform: Transform2D = moved_scene.global_transform
	var moved_fallback := Guard.plan_and_verify(space, BOUNDS, [barrier_rect], [], [], GOAL, ANCHOR,
		RADIUS, 1, [], transform)
	check(moved_fallback.ok and moved_fallback.relocated and moved_fallback.live_physics_verified,
		"translated+rotated WorldHost gives collision-safe reachable-side fallback")
	check(moved_fallback.ok and moved_fallback.position.x < barrier_rect.position.x,
		"world-space rigid transform preserves correct LOCAL fallback point")
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR,
		RADIUS, 1, [], transform).code == "PHYSICS_BLOCKED",
		"stale rectangle snapshot cannot miss a real rotated PhysicsServer2D wall")
	check(Guard.verify_live(space, open, RADIUS, 1, [], transform).code == "PHYSICS_BLOCKED",
		"re-check of original route is correctly rotated into target world")
	check(Guard.verify_live(space, moved_fallback, RADIUS, 1, [], transform).ok,
		"saved local fallback can be physically revalidated in moved/rotated scene")
	var scaling := Transform2D(Vector2(2.0, 0.0), Vector2(0.0, 2.0), Vector2.ZERO)
	var shear := Transform2D(Vector2(1.0, 0.0), Vector2(0.5, 1.0), Vector2.ZERO)
	var invalid_origin := Transform2D(Vector2.RIGHT, Vector2.DOWN, Vector2(INF, 0.0))
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR,
		RADIUS, 1, [], scaling).code == "INVALID_TRANSFORM",
		"scaled world cannot silently reuse unscaled player collider radius")
	check(Guard.plan_and_verify(space, BOUNDS, [], [], [], GOAL, ANCHOR,
		RADIUS, 1, [], shear).code == "INVALID_TRANSFORM",
		"sheared world fails closed, requiring explicit physics modeling")
	check(Guard.verify_live(space, open, RADIUS, 1, [], invalid_origin).code == "INVALID_TRANSFORM",
		"nonfinite world coordinate transform cannot certify any route")
	moved_scene.queue_free()
	await physics_frame
	check(Guard.verify_live(space, open).ok,
		"real world-space rotated blocker removal restores default coordinates")

	# Real production generator walls. No modification of historical v4/v5
	# game saves or the generator itself: physical shapes are created here.
	for version in [4, 5]:
		for seed_value in [0, 42]:
			var world: Dictionary = Layout.build(seed_value, version)
			for scene_id in ["hospital", "hospital_0_3", "outside"]:
				var node: Dictionary = world[scene_id]
				var area := Node2D.new()
				arena.add_child(area)
				for rect in node.obstacles:
					wall(area, rect)
				await physics_frame
				var result: Dictionary = Guard.plan_and_verify(
					space, node.bounds, node.obstacles, [], [], node.spawn, node.spawn)
				check(result.ok and not result.relocated and result.position == node.spawn,
					"generator v%d seed %d real %s collider verifies physical spawn" % [version, seed_value, scene_id])
				area.queue_free()
				await physics_frame

	print("A2 LIVE SAFE RETURN PHYSICS TESTS: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
