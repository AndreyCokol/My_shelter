extends CharacterBody2D

var app
const MAX_HEALTH := 100
const BODY_RADIUS := 10.0
const CHASE_SPEED := 43.0
const CHASE_STOP_DISTANCE := 23.0
const WalkGrid = preload("res://game/systems/world/walk_grid.gd")
const PixelActors = preload("res://game/entities/characters/pixel_actor_frames.gd")
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
var pixel_sprite: AnimatedSprite2D
var attack_pose_remaining: float = 0.0
var visual_facing := Vector2.DOWN

func _ready() -> void:
	z_index = 8
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	collider.shape = shape
	add_child(collider)
	pixel_sprite = AnimatedSprite2D.new()
	pixel_sprite.name = "PixelActor64"
	pixel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_sprite.sprite_frames = PixelActors.frames(true)
	pixel_sprite.scale = Vector2(0.75, 0.75)
	add_child(pixel_sprite)
	pixel_sprite.play("idle_down")

func _update_pixel_animation(moving: bool) -> void:
	if not is_instance_valid(pixel_sprite):
		return
	if moving and velocity.length() > 0.1:
		visual_facing = velocity.normalized()
	var direction: String = PixelActors.direction_name(visual_facing)
	var pose := "attack" if attack_pose_remaining > 0.0 else ("walk" if moving else "idle")
	var animation: String = pose + "_" + direction
	if pixel_sprite.animation != animation:
		pixel_sprite.play(animation)
	elif not pixel_sprite.is_playing() and pose != "attack":
		pixel_sprite.play(animation)
	pixel_sprite.modulate = Color("606b68") if health == 0 else Color.WHITE
	if health == 0:
		pixel_sprite.pause()

func _physics_process(delta: float) -> void:
	if app == null or not app.running():
		return
	if health <= 0:
		_update_pixel_animation(false)
		if not reported:
			reported = true
			app.call_deferred("enemy_defeated")
		return
	hit_cooldown = maxf(0, hit_cooldown - delta)
	attack_pose_remaining = maxf(0.0, attack_pose_remaining - delta)
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
		attack_pose_remaining = 0.16
	_update_pixel_animation(velocity.length_squared() > 1.0)
	queue_redraw()

func update_chase(target: CharacterBody2D, distance: float, delta: float) -> void:
	if distance <= CHASE_STOP_DISTANCE and has_clear_line_to(target):
		_chase_path.clear()
		velocity = Vector2.ZERO
		return
	_steer_toward(target.global_position, CHASE_SPEED, CHASE_STOP_DISTANCE, delta)

# One collision-aware steering contract for ordinary zombies AND the hospital
# patrol/noise mode. Both share the current wall revision and safe AStar route;
# direct movement is used when there is no actual physics obstruction.
func _steer_toward(goal: Vector2, speed: float, stopping_distance: float, delta: float) -> void:
	var distance: float = global_position.distance_to(goal)
	if distance <= stopping_distance:
		_chase_path.clear()
		velocity = Vector2.ZERO
		return
	_chase_retry = maxf(0.0, _chase_retry - delta)
	var world = get_parent()
	if not world.has_method("collision_rects"):
		velocity = global_position.direction_to(goal) * speed
		return
	if _chase_grid != null and _grid_revision != world.collision_revision:
		_chase_grid = null
		_chase_path.clear()
		_chase_retry = 0.0
	if goal.distance_squared_to(_chase_goal) > 24.0 * 24.0:
		_chase_path.clear()
	if _chase_index >= _chase_path.size():
		var direction := global_position.direction_to(goal)
		var probe := minf(18.0, maxf(1.0, distance - stopping_distance))
		if not test_move(global_transform, direction * probe):
			velocity = direction * speed
			return
		if _chase_retry > 0.0:
			velocity = Vector2.ZERO
			return
		_plan_chase(world, goal)
	while _chase_index < _chase_path.size() and position.distance_squared_to(_chase_path[_chase_index]) <= 2.0:
		_chase_index += 1
	velocity = Vector2.ZERO
	if _chase_index < _chase_path.size():
		velocity = global_position.direction_to(world.to_global(_chase_path[_chase_index])) * speed

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
		# Noise positions are global. Direct steering previously got stuck at
		# hospital partition walls and could not reach the noise source.
		_steer_toward(last_noise, 55.0, 22.0, delta)
		return
	# Patrol waypoints are local to the World node; convert before steering.
	# This also fixes patrol direction when a scene is offset from the origin.
	var world = get_parent()
	var waypoint: Vector2 = world.to_global(patrol[patrol_index])
	if global_position.distance_to(waypoint) < 8.0:
		patrol_index = (patrol_index + 1) % patrol.size()
		waypoint = world.to_global(patrol[patrol_index])
	_steer_toward(waypoint, 32.0, 8.0, delta)

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
	# Render only gameplay indicators. The visual body is a real animated
	# 64x64 original PNG; death makes the surviving atlas muted, not a circle.
	if health <= 0:
		return
	if alert_remaining > 0:
		draw_rect(Rect2(-1, -34, 3, 5), Color("f4c56f"))
		draw_rect(Rect2(-1, -28, 3, 2), Color("f4c56f"))
	draw_rect(Rect2(-13, -27, 26, 3), Color("362a30"))
	draw_rect(Rect2(-13, -27, 26.0 * health / MAX_HEALTH, 3), Color("df8e78"))


# Persistent encounter state is optional in schema v4: old checkpoints still
# reconstruct the deterministic initial patrol/position when no record exists.
# Timers are frozen off-scene, just as the rest of the unmounted AI is.
func runtime_snapshot() -> Dictionary:
	return {
		"position": {"x": float(position.x), "y": float(position.y)},
		"last_noise": {"x": float(last_noise.x), "y": float(last_noise.y)},
		"patrol_index": patrol_index,
		"alert_remaining": alert_remaining,
		"hit_cooldown": hit_cooldown,
	}

static func valid_runtime(data) -> bool:
	if not data is Dictionary or data.size() != 5:
		return false
	for field in ["position", "last_noise"]:
		var point = data.get(field)
		if not point is Dictionary or point.size() != 2:
			return false
		for axis in ["x", "y"]:
			var number = point.get(axis)
			if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 1000000.0:
				return false
	var index = data.get("patrol_index")
	if not index is int or index < 0 or index >= 100:
		return false
	for field in ["alert_remaining", "hit_cooldown"]:
		var remaining = data.get(field)
		if not (remaining is int or remaining is float) or not is_finite(float(remaining)) or remaining < 0:
			return false
	if data.alert_remaining > SEARCH_DURATION or data.hit_cooldown > 1.0:
		return false
	return true

func restore_runtime(data: Dictionary) -> void:
	if not valid_runtime(data):
		return
	position = Vector2(data.position.x, data.position.y)
	last_noise = Vector2(data.last_noise.x, data.last_noise.y)
	patrol_index = int(data.patrol_index) % maxi(patrol.size(), 1)
	alert_remaining = float(data.alert_remaining)
	hit_cooldown = float(data.hit_cooldown)
