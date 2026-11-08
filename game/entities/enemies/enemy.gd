extends CharacterBody2D

var app
const MAX_HEALTH := 100
const BODY_RADIUS := 10.0
const CHASE_SPEED := 43.0
const CHASE_STOP_DISTANCE := 23.0
const WalkGrid = preload("res://game/systems/world/walk_grid.gd")
var health: int = MAX_HEALTH
var hit_cooldown: float = 0.0
var reported: bool = false
var patrol := PackedVector2Array()
var patrol_index := 0
var alert_remaining := 0.0
var last_noise := Vector2.ZERO
const VIEW_RANGE := 88.0
const SEARCH_DURATION := 3.5
var _chase_grid: AStarGrid2D
var _grid_revision := -1
var _chase_path := PackedVector2Array()
var _chase_index := 0
var _chase_goal := Vector2.ZERO
var _chase_retry := 0.0

func _ready() -> void:
	z_index = 8
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	collider.shape = shape
	add_child(collider)

func _physics_process(delta: float) -> void:
	if app == null or not app.running():
		return
	if health <= 0:
		if not reported:
			reported = true
			app.call_deferred("enemy_defeated")
		return
	hit_cooldown = maxf(0, hit_cooldown - delta)
	var target = app.hero
	var distance: float = global_position.distance_to(target.global_position)
	if patrol.is_empty():
		update_chase(target, distance, delta)
	else:
		update_patrol(target, distance, delta)
	move_and_slide()
	if hit_cooldown <= 0 and global_position.distance_to(target.global_position) < 28 and has_clear_line_to(target):
		target.take_damage(15)
		hit_cooldown = 1.0
	queue_redraw()

func update_chase(target: CharacterBody2D, distance: float, delta: float) -> void:
	var goal := target.global_position
	if distance <= CHASE_STOP_DISTANCE and has_clear_line_to(target):
		_chase_path.clear()
		velocity = Vector2.ZERO
		return
	_chase_retry = maxf(0.0, _chase_retry - delta)
	var world = get_parent()
	if _chase_grid != null and _grid_revision != world.collision_revision:
		_chase_grid = null
		_chase_path.clear()
		_chase_retry = 0.0
	if goal.distance_squared_to(_chase_goal) > 24.0 * 24.0:
		_chase_path.clear()
	if _chase_index >= _chase_path.size():
		var direction := global_position.direction_to(goal)
		var probe := minf(18.0, maxf(1.0, distance - CHASE_STOP_DISTANCE))
		if not test_move(global_transform, direction * probe):
			velocity = direction * CHASE_SPEED
			return
		if _chase_retry > 0.0 or not world.has_method("collision_rects"):
			velocity = Vector2.ZERO
			return
		_plan_chase(world, goal)
	while _chase_index < _chase_path.size() and position.distance_squared_to(_chase_path[_chase_index]) <= 2.0:
		_chase_index += 1
	velocity = Vector2.ZERO
	if _chase_index < _chase_path.size():
		velocity = global_position.direction_to(world.to_global(_chase_path[_chase_index])) * CHASE_SPEED

func _plan_chase(world, goal: Vector2) -> void:
	_chase_retry = 0.25
	_chase_goal = goal
	_chase_index = 0
	if _chase_grid == null:
		_grid_revision = world.collision_revision
		_chase_grid = WalkGrid.build(world.floor_rect().grow(-15), world.collision_rects(), 12.0, BODY_RADIUS + 2.0)
	var from := WalkGrid.nearest_open(_chase_grid, position, func(point: Vector2):
		return not test_move(global_transform, world.to_global(point) - global_position))
	var to := WalkGrid.nearest_open(_chase_grid, world.to_local(goal))
	if _chase_grid.is_in_boundsv(from) and _chase_grid.is_in_boundsv(to):
		_chase_path = _chase_grid.get_point_path(from, to)

func hear_noise(origin: Vector2, radius: float) -> void:
	if not patrol.is_empty() and health > 0 and global_position.distance_to(origin) <= radius:
		last_noise = origin
		alert_remaining = SEARCH_DURATION

func update_patrol(target: CharacterBody2D, distance: float, delta: float) -> void:
	if distance <= VIEW_RANGE and has_clear_line_to(target):
		hear_noise(target.global_position, VIEW_RANGE)
	alert_remaining = maxf(0.0, alert_remaining - delta)
	if alert_remaining > 0:
		velocity = global_position.direction_to(last_noise) * 55 if global_position.distance_to(last_noise) > 22 else Vector2.ZERO
		return
	if global_position.distance_to(patrol[patrol_index]) < 8:
		patrol_index = (patrol_index + 1) % patrol.size()
	velocity = global_position.direction_to(patrol[patrol_index]) * 32

func has_clear_line_to(target: CharacterBody2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.exclude = [get_rid(), target.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health = maxi(0, health - amount)
	queue_redraw()

func _draw() -> void:
	if health <= 0:
		draw_circle(Vector2.ZERO, 10, Color("505c56"))
		return
	draw_circle(Vector2.ZERO, 11, Color("c98b67") if alert_remaining > 0 else Color("bb796d"))
	if alert_remaining > 0:
		draw_rect(Rect2(-1, -32, 3, 5), Color("f4c56f"))
		draw_rect(Rect2(-1, -26, 3, 2), Color("f4c56f"))
	draw_rect(Rect2(-13, -22, 26, 3), Color("362a30"))
	draw_rect(Rect2(-13, -22, 26.0 * health / MAX_HEALTH, 3), Color("df8e78"))
	draw_circle(Vector2(-4, -2), 2, Color("242830"))
	draw_circle(Vector2(4, -2), 2, Color("242830"))
