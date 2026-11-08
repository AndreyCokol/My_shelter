extends CharacterBody2D

var app
var health: int = 100
var hit_cooldown: float = 0.0
var reported: bool = false
var patrol := PackedVector2Array()
var patrol_index := 0
var alert_remaining := 0.0
var last_noise := Vector2.ZERO
const VIEW_RANGE := 88.0
const SEARCH_DURATION := 3.5
const ActorPainter = preload("res://game/entities/visual/pixel_actor.gd")
var visual_stride := 0.0
var visual_facing := Vector2.DOWN
var damage_flash := 0.0

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
	damage_flash = maxf(0, damage_flash - delta)
	var target = app.hero
	var distance: float = global_position.distance_to(target.global_position)
	if patrol.is_empty():
		velocity = global_position.direction_to(target.global_position) * 43 if distance > 23 else Vector2.ZERO
	else:
		update_patrol(target, distance, delta)
	if velocity.length_squared() > 0.01:
		visual_facing = velocity.normalized()
		visual_stride += delta * 8.0
	move_and_slide()
	if distance < 28 and hit_cooldown <= 0:
		target.take_damage(15)
		hit_cooldown = 1.0
	queue_redraw()

func hear_noise(origin: Vector2, radius: float) -> void:
	if not patrol.is_empty() and health > 0 and global_position.distance_to(origin) <= radius:
		last_noise = origin
		alert_remaining = SEARCH_DURATION

func update_patrol(target: CharacterBody2D, distance: float, delta: float) -> void:
	if distance <= VIEW_RANGE:
		var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
		query.exclude = [get_rid(), target.get_rid()]
		if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			hear_noise(target.global_position, VIEW_RANGE)
	alert_remaining = maxf(0.0, alert_remaining - delta)
	if alert_remaining > 0:
		velocity = global_position.direction_to(last_noise) * 55 if global_position.distance_to(last_noise) > 22 else Vector2.ZERO
		return
	if global_position.distance_to(patrol[patrol_index]) < 8:
		patrol_index = (patrol_index + 1) % patrol.size()
	velocity = global_position.direction_to(patrol[patrol_index]) * 32

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health = maxi(0, health - amount)
	damage_flash = 0.19
	queue_redraw()

func _draw() -> void:
	ActorPainter.zombie(self, visual_facing, visual_stride,
		damage_flash > 0, alert_remaining > 0, health <= 0)
	if health <= 0:
		return
	# Health is attached to the enemy, not to world decor.
	draw_rect(Rect2(-14, -30, 28, 4), Color("211b1b"))
	draw_rect(Rect2(-13, -29, 26.0 * health / 100.0, 2),
		Color("d76855") if damage_flash > 0 else Color("bd4841"))
