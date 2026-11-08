extends SceneTree

# AUD2-07: collision-aware egress for the 5x2 shelter construction grid.
# Tests real collision rectangles grown by 10 px for the player's radius 9.
# Does not replace native Windows physics/movement tests or prove every live
# build sequence, but catches configurations that cut off vital access points.
const Layout = preload("res://game/systems/world/world_layout.gd")
const Construction = preload("res://game/systems/shelter/construction.gd")
const STEP := 10.0
const CLEARANCE := 10.0

var checks := 0
var failures := 0
var checked_masks := 0
var checked_paths := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)
	else:
		print("PASS " + label)

func clear(point: Vector2, walkable: Rect2, obstacles: Array) -> bool:
	if not walkable.has_point(point):
		return false
	for rect in obstacles:
		if rect.grow(CLEARANCE).has_point(point):
			return false
	return true

func mask_ok(node: Dictionary, mask: int) -> bool:
	var obstacles: Array = node.obstacles.duplicate()
	var selected := {}
	for index in range(Construction.COLUMNS * Construction.ROWS):
		if mask & (1 << index):
			var cell := str(index)
			selected[cell] = "bench"
			obstacles.append(Construction.cell_rect(cell))
	if not Construction.validate(selected, {}, Layout.entries()):
		return false
	var walkable: Rect2 = node.bounds.grow(-15)
	var objectives: Array[Vector2] = [
		node.spawn, Vector2(220, 195), Vector2(400, 180),
		Vector2(165, 236),
	]
	for portal in node.exits.values():
		objectives.append(portal.position)
		objectives.append(portal.arrival)
	for point in objectives:
		if not clear(point, walkable, obstacles):
			print("CONSTRUCTION BLOCKED mask=%d at=%s" % [mask, str(point)])
			return false
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO,
		Vector2i((walkable.size / STEP).floor()) + Vector2i.ONE)
	grid.cell_size = Vector2(STEP, STEP)
	grid.offset = walkable.position
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for obstacle in obstacles:
		var inflated: Rect2 = obstacle.grow(CLEARANCE)
		var first: Vector2i = Vector2i(((inflated.position - walkable.position) / STEP).ceil())
		var last: Vector2i = Vector2i(((inflated.end - walkable.position) / STEP).floor())
		var affected: Rect2i = Rect2i(first, (last - first + Vector2i.ONE).max(Vector2i.ZERO)).intersection(grid.region)
		if affected.has_area():
			grid.fill_solid_region(affected, true)
	var start := Vector2i(((node.spawn - walkable.position) / STEP).round())
	if not grid.region.has_point(start) or grid.is_point_solid(start):
		return false
	for point in objectives:
		var target := Vector2i(((point - walkable.position) / STEP).round())
		if not grid.region.has_point(target) or grid.is_point_solid(target) or grid.get_id_path(start, target).is_empty():
			print("CONSTRUCTION UNREACHABLE mask=%d target=%s" % [mask, str(point)])
			return false
		checked_paths += 1
	return true

func _initialize() -> void:
	var baseline: Dictionary = Layout.build(54).shelter
	check(baseline.kind == "shelter" and baseline.exits.has("outside"),
		"current generator shelter has expected safe exit and buildable area")
	check(Construction.COLUMNS * Construction.ROWS == 10,
		"construction acceptance covers all ten saved cell slots")
	# Empty, full, single-cell, all-but-one and densely varied masks.
	# Saving only structure types does not change physical collision footprints.
	var masks := {0: true, (1 << 10) - 1: true}
	for index in range(10):
		masks[1 << index] = true
		masks[((1 << 10) - 1) ^ (1 << index)] = true
		masks[(1 << (index + 1)) - 1] = true
	for value in range(128):
		masks[posmod(value * 139 + (value / 3) * 71, 1 << 10)] = true
	for mask in masks:
		checked_masks += 1
		check(mask_ok(baseline, int(mask)),
			"shelter with occupied construction mask %d retains spawn, farm, rest, workshop and exit routes" % int(mask))
	check(checked_masks >= 100 and checked_paths >= 500,
		"egress regression covers at least 100 distinct build layouts and 500 real collision paths")
	print("CONSTRUCTION ROUTES PROFILE masks=%d paths=%d step=%.1f player_clearance=%.1f" %
		[checked_masks, checked_paths, STEP, CLEARANCE])
	print("CONSTRUCTION ROUTES TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
