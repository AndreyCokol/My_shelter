extends SceneTree

# WORLD-01 / CT-84: building footprints cannot turn the shelter into a softlock.
# Enumerate ALL 2^10 placement patterns on the current procedural shelter,
# with a 10px inflated collision radius approximating the real player collider.
# No player item balances or existing save slots are touched by this test.
const Layout = preload("res://game/systems/world/world_layout.gd")
const Construction = preload("res://game/systems/shelter/construction.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func reachable_anchors(record: Dictionary, buildings: Dictionary) -> bool:
	var walkable: Rect2 = record.bounds.grow(-15)
	var step := 16
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(walkable.size / step) + Vector2i.ONE)
	grid.cell_size = Vector2(step, step)
	grid.offset = walkable.position
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	var obstacles: Array = record.obstacles.duplicate()
	for cell in buildings:
		obstacles.append(Construction.cell_rect(cell))
	for rect in obstacles:
		var blocked: Rect2 = rect.grow(10)
		var first := Vector2i(((blocked.position - walkable.position) / step).ceil())
		var last := Vector2i(((blocked.end - walkable.position) / step).floor())
		var region := Rect2i(first, (last - first + Vector2i.ONE).max(Vector2i.ZERO)).intersection(grid.region)
		if region.size.x > 0 and region.size.y > 0:
			grid.fill_solid_region(region)
	var start := Vector2i(((record.spawn - walkable.position) / step).round())
	if not grid.region.has_point(start) or grid.is_point_solid(start):
		return false
	# Physical objectives from World.interact: farm, rest and a reachable edge
	# of the workshop zone, plus every real door to the exterior world.
	var anchors: Array[Vector2] = [record.spawn, Vector2(220, 195),
		Vector2(400, 180), Vector2(170, 240)]
	for exit in record.exits.values():
		anchors.append(exit.arrival)
	for point in anchors:
		var cell := Vector2i(((point - walkable.position) / step).round())
		if not walkable.has_point(point) or not grid.region.has_point(cell) or grid.is_point_solid(cell):
			return false
		if grid.get_id_path(start, cell).is_empty():
			return false
	return true

func buildings_for_mask(mask: int) -> Dictionary:
	var result: Dictionary = {}
	for cell in range(Construction.COLUMNS * Construction.ROWS):
		if mask & (1 << cell):
			result[str(cell)] = "bench"
	return result

func _initialize() -> void:
	var checked_masks := 0
	var layouts: Dictionary = Layout.build(54)
	var shelter: Dictionary = layouts.shelter
	var all_reachable := true
	var all_legal := true
	var first_failure := -1
	var total: int = 1 << (Construction.COLUMNS * Construction.ROWS)
	for mask in range(total):
		var built: Dictionary = buildings_for_mask(mask)
		all_legal = all_legal and Construction.validate(built, {}, Layout.entries())
		if not reachable_anchors(shelter, built):
			all_reachable = false
			if first_failure == -1:
				first_failure = mask
		checked_masks += 1
	check(all_legal and checked_masks == 1024, "CT-84 all 1024 possible 10-cell shelter construction patterns are structurally legal")
	check(all_reachable, "CT-84 all 1024 construction patterns retain spawn-to-farm/rest/workshop/exit paths, first failure=%d" % first_failure)
	# Service geometry is intended to be seed-independent, but still verify
	# the worst-case fully occupied grid on different seed boundaries.
	for seed_value in [0, 1, 127, Layout.MAX_SEED]:
		var other: Dictionary = Layout.build(seed_value).shelter
		check(reachable_anchors(other, buildings_for_mask(total - 1)),
			"CT-84 fully occupied shelter preserves objectives on seed %d" % seed_value)
	print("SHELTER ACCESS TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
