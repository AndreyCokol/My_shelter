extends CharacterBody2D

var app
const MAX_HEALTH := 100
var health: int = MAX_HEALTH
var hit_cooldown: float = 0.0
var reported: bool = false
var patrol := PackedVector2Array()
var patrol_index := 0
var alert_remaining := 0.0
var last_noise := Vector2.ZERO
const VIEW_RANGE := 88.0
const SEARCH_DURATION := 3.5

func _ready() -> void:
	z_index = 8
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10
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
		velocity = global_position.direction_to(target.global_position) * 43 if distance > 23 else Vector2.ZERO
	else:
		update_patrol(target, distance, delta)
	move_and_slide()
	if hit_cooldown <= 0 and global_position.distance_to(target.global_position) < 28 and has_clear_line_to(target):
		target.take_damage(15)
		hit_cooldown = 1.0
	queue_redraw()

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
