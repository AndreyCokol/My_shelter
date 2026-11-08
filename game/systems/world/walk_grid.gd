extends RefCounted

static func build(floor: Rect2, obstacles: Array, step: float, clearance: float) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, Vector2i((floor.size / step).floor()) + Vector2i.ONE)
	grid.cell_size = Vector2(step, step)
	grid.offset = floor.position
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for obstacle in obstacles:
		var expanded: Rect2 = obstacle.grow(clearance)
		var first := Vector2i(((expanded.position - floor.position) / step).ceil())
		var last := Vector2i(((expanded.end - floor.position) / step).floor())
		var affected := Rect2i(first, (last - first + Vector2i.ONE).max(Vector2i.ZERO)).intersection(grid.region)
		if affected.has_area():
			grid.fill_solid_region(affected, true)
	return grid

static func nearest_open(grid: AStarGrid2D, point: Vector2, can_enter: Callable = Callable()) -> Vector2i:
	var id := Vector2i(((point - grid.offset) / grid.cell_size).round())
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(-1, 2):
		for x in range(-1, 2):
			var candidate := id + Vector2i(x, y)
			if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate):
				continue
			var position := grid.get_point_position(candidate)
			var distance := point.distance_squared_to(position)
			if distance < best_distance and (not can_enter.is_valid() or can_enter.call(position)):
				best = candidate
				best_distance = distance
	return best
