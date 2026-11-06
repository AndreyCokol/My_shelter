extends CharacterBody2D

var app
var health: int = 100
var hit_cooldown: float = 0.0
var reported: bool = false

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
	velocity = global_position.direction_to(target.global_position) * 43 if distance > 23 else Vector2.ZERO
	move_and_slide()
	if distance < 28 and hit_cooldown <= 0:
		target.take_damage(15)
		hit_cooldown = 1.0
	queue_redraw()

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health = maxi(0, health - amount)
	queue_redraw()

func _draw() -> void:
	if health <= 0:
		draw_circle(Vector2.ZERO, 10, Color("505c56"))
		return
	draw_circle(Vector2.ZERO, 11, Color("bb796d"))
	draw_rect(Rect2(-13, -22, 26, 3), Color("362a30"))
	draw_rect(Rect2(-13, -22, 26.0 * health / 100, 3), Color("df8e78"))
	draw_circle(Vector2(-4, -2), 2, Color("242830"))
	draw_circle(Vector2(4, -2), 2, Color("242830"))
