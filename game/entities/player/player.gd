extends CharacterBody2D

var app
var health: int = 100
var facing := Vector2.RIGHT
var attack_cooldown: float = 0.0
var dodge_cooldown: float = 0.0
var dodge_remaining: float = 0.0
var hurt_remaining: float = 0.0
var swing_remaining: float = 0.0
var defeated: bool = false

func _ready() -> void:
	z_index = 10
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 9
	collider.shape = shape
	add_child(collider)

func _physics_process(delta: float) -> void:
	if app == null or not app.running() or defeated:
		velocity = Vector2.ZERO
		return
	attack_cooldown = maxf(0, attack_cooldown - delta)
	dodge_cooldown = maxf(0, dodge_cooldown - delta)
	dodge_remaining = maxf(0, dodge_remaining - delta)
	hurt_remaining = maxf(0, hurt_remaining - delta)
	swing_remaining = maxf(0, swing_remaining - delta)
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length() > 0.1 and dodge_remaining == 0:
		facing = direction.normalized()
	if Input.is_action_just_pressed("dodge"):
		try_dodge()
	if Input.is_action_just_pressed("attack") and get_viewport().gui_get_hovered_control() == null:
		try_attack(get_global_mouse_position())
	velocity = facing * 320 if dodge_remaining > 0 else direction * 115
	move_and_slide()
	position = position.clamp(Vector2(35, 100), Vector2(605, 330))
	queue_redraw()

func try_dodge() -> bool:
	if defeated or dodge_cooldown > 0 or app == null or not app.running():
		return false
	dodge_remaining = 0.22
	dodge_cooldown = 0.85
	return true

func try_attack(target: Vector2) -> bool:
	if defeated or attack_cooldown > 0 or app == null or not app.running():
		return false
	if target.distance_to(global_position) > 1:
		facing = global_position.direction_to(target)
	attack_cooldown = 0.45
	swing_remaining = 0.15
	var enemy = app.enemy()
	if is_instance_valid(enemy) and enemy.health > 0 and global_position.distance_to(enemy.global_position) < 64:
		var toward: Vector2 = global_position.direction_to(enemy.global_position)
		if facing.dot(toward) > 0.2:
			enemy.take_damage(25)
	return true

func take_damage(amount: int) -> bool:
	if amount <= 0 or defeated or dodge_remaining > 0 or hurt_remaining > 0 or app == null or not app.running():
		return false
	health = maxi(0, health - amount)
	hurt_remaining = 0.45
	queue_redraw()
	app.update_hud()
	if health == 0:
		defeated = true
		app.call_deferred("player_defeated")
	return true

func restore(hp: int) -> void:
	health = hp
	defeated = false
	dodge_remaining = 0
	attack_cooldown = 0
	hurt_remaining = 0
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2(1, 5), 12, Color(0, 0, 0, 0.3))
	draw_circle(Vector2.ZERO, 9, Color("f4c788") if hurt_remaining == 0 else Color("f07878"))
	draw_rect(Rect2(-7, 1, 14, 11), Color("61bdb1"))
	draw_line(facing * 8, facing * 17, Color("e8e7d5"), 3)
	if dodge_remaining > 0:
		draw_arc(Vector2.ZERO, 15, 0, TAU, 20, Color("96e6db"), 2)
	if swing_remaining > 0:
		var angle := facing.angle()
		draw_arc(Vector2.ZERO, 38, angle - 0.8, angle + 0.8, 12, Color("f6db91"), 3)
