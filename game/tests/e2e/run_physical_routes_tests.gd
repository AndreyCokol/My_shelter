extends SceneTree

# Issue #44: static collision-grid route acceptance on EVERY node in 132 seeds.
# Uses actual WorldLayout.obstacles (walls plus furniture), exit locations, and
# a 10px inflated obstacle radius for the player's 9px collision circle.
# This checks 2D path reachability; it does not simulate GUI keyboard movement.
const Layout = preload("res://game/systems/world/world_layout.gd")
const WalkGrid = preload("res://game/systems/world/walk_grid.gd")
const STEP := 12.0
const CLEARANCE := 10.0
var checks: int = 0
var failures: int = 0
var scenes_seen: int = 0
var physical_profiles_checked: int = 0
var paths_checked: int = 0
var _cache := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error(label)

func target(name: String, point: Vector2) -> Dictionary:
	return {"name": name, "point": point}

func objectives(record: Dictionary) -> Array:
	var result: Array = []
	if record.kind in ["outside", "house", "hospital"]:
		result.append(target("loot", record.loot))
	if record.kind == "hospital":
		result.append(target("enemy", record.enemy))
	if record.kind == "outside":
		result.append(target("salvage", record.salvage))
		result.append(target("event", record.event))
		for index in range(record.patrol.size()):
			result.append(target("patrol:%d" % index, record.patrol[index]))
	for destination in record.exits:
		var exit: Dictionary = record.exits[destination]
		result.append(target("portal:%s" % destination, exit.position))
		result.append(target("arrival:%s" % destination, exit.arrival))
	if record.has("floor_plan"):
		var plan: Dictionary = record.floor_plan
		result.append(target("stairs_up", plan.stairs_up))
		result.append(target("stairs_down", plan.stairs_down))
		for room in plan.rooms.values():
			result.append(target("room:%s" % room.id, room.rect.get_center()))
		for door in plan.doors:
			var normal := Vector2.DOWN if door.horizontal else Vector2.RIGHT
			result.append(target("door:%s:left" % door.id, door.position - normal * 13.0))
			# The street-side sample is outside the building's floor plan and
			# is not a requirement for traversability of indoor rooms.
			if door.to != "street":
				result.append(target("door:%s:right" % door.id, door.position + normal * 13.0))
	return result

func profile_key(record: Dictionary, points: Array) -> String:
	# Cache only when source collider geometry AND ALL target coordinates match.
	# Labels/scene IDs alone are never treated as physical evidence.
	var positions: Array = points.map(func(entry): return str(entry.point))
	return str([record.bounds, record.spawn, record.obstacles, positions])

func clear_point(point: Vector2, floor: Rect2, obstacles: Array) -> bool:
	if not floor.has_point(point):
		return false
	for blocked in obstacles:
		if blocked.grow(CLEARANCE).has_point(point):
			return false
	return true

func walkable_profile(record: Dictionary, seed_value: int, scene_id: String) -> bool:
	var points: Array = objectives(record)
	var signature := profile_key(record, points)
	if _cache.has(signature):
		return _cache[signature]
	physical_profiles_checked += 1
	var floor: Rect2 = record.bounds.grow(-15)
	var obstacles: Array = record.obstacles
	if not clear_point(record.spawn, floor, obstacles):
		print("ROUTE BLOCKED spawn seed=%d scene=%s" % [seed_value, scene_id])
		_cache[signature] = false
		return false
	var grid := WalkGrid.build(floor, obstacles, STEP, CLEARANCE)
	var start := Vector2i(((record.spawn - floor.position) / STEP).round())
	if not grid.region.has_point(start) or grid.is_point_solid(start):
		print("ROUTE GRID BLOCKED spawn seed=%d scene=%s" % [seed_value, scene_id])
		_cache[signature] = false
		return false
	for entry in points:
		var point: Vector2 = entry.point
		if not clear_point(point, floor, obstacles):
			print("ROUTE BLOCKED target seed=%d scene=%s target=%s at %s" %
				[seed_value, scene_id, entry.name, str(point)])
			_cache[signature] = false
			return false
		var goal: Vector2i = Vector2i(((point - floor.position) / STEP).round())
		if not grid.region.has_point(goal) or grid.is_point_solid(goal) or grid.get_id_path(start, goal).is_empty():
			print("ROUTE UNREACHABLE seed=%d scene=%s target=%s at %s" %
				[seed_value, scene_id, entry.name, str(point)])
			_cache[signature] = false
			return false
		paths_checked += 1
	_cache[signature] = true
	return true

func _initialize() -> void:
	var passed := true
	var seeds: Array = range(128) + [128, 1023, 65535, Layout.MAX_SEED]
	for seed_value in seeds:
		var world: Dictionary = Layout.build(seed_value)
		var good_seed: bool = world.size() == 30
		for scene_id in world:
			scenes_seen += 1
			good_seed = walkable_profile(world[scene_id], seed_value, scene_id) and good_seed
		if not good_seed:
			check(false, "physical paths and objectives in all 30 scenes for seed %d" % seed_value)
		else:
			check(true, "physical paths and objectives in all 30 scenes for seed %d" % seed_value)
		passed = passed and good_seed
	check(scenes_seen == 132 * 30, "132 complete worlds / 3960 physically enumerated scenes")
	check(physical_profiles_checked > 30 and paths_checked > 100,
		"routes cover more than 30 different collider profiles and 100 targets")
	print("ROUTES PROFILE worlds=132 scenes=%d unique_colliders=%d checked_paths=%d step=%.1f clearance=%.1f" %
		[scenes_seen, physical_profiles_checked, paths_checked, STEP, CLEARANCE])
	print("ROUTES TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
