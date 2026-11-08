extends CharacterBody2D

const DODGE_COOLDOWN := 0.85
const Combat = preload("res://game/systems/combat/combat_loadout.gd")
const PixelActors = preload("res://game/entities/characters/pixel_actor_frames.gd")

var app
var health: int = 100
var facing := Vector2.RIGHT
var attack_cooldown: float = 0.0
var dodge_cooldown: float = 0.0
var dodge_remaining: float = 0.0
var hurt_remaining: float = 0.0
var swing_remaining: float = 0.0
var defeated: bool = false
var pixel_sprite: AnimatedSprite2D

func _ready() -> void:
	z_index = 10
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 9
	collider.shape = shape
	add_child(collider)
	pixel_sprite = AnimatedSprite2D.new()
	pixel_sprite.name = "PixelActor64"
	pixel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_sprite.sprite_frames = PixelActors.frames(false)
	pixel_sprite.scale = Vector2(0.75, 0.75)
	add_child(pixel_sprite)
	pixel_sprite.play("idle_right")

# An attack, dodge, damage flash and directional walk change animation without
# replacing any input/physics/hitbox logic. The 64x64 source pixels are real PNG
# assets; their world display size is deliberately smaller than the map doors.
func _update_pixel_animation(moving: bool) -> void:
	if not is_instance_valid(pixel_sprite):
		return
	var direction: String = PixelActors.direction_name(facing)
	var pose := "idle"
	if swing_remaining > 0.0:
		pose = "attack"
	elif moving or dodge_remaining > 0.0:
		pose = "walk"
	var target: String = pose + "_" + direction
	if pixel_sprite.animation != target:
		pixel_sprite.play(target)
	elif not pixel_sprite.is_playing() and pose != "attack":
		pixel_sprite.play(target)
	pixel_sprite.speed_scale = 1.5 if dodge_remaining > 0.0 else 1.0
	pixel_sprite.modulate = Color("ecb7ad") if hurt_remaining > 0.0 else Color.WHITE
	if defeated:
		pixel_sprite.pause()
		pixel_sprite.modulate = Color("656666")

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
	velocity = facing * 320 if dodge_remaining > 0 else direction * 115
	move_and_slide()
	var world = app.scene_router.current_world()
	if is_instance_valid(world):
		var walkable: Rect2 = world.floor_rect().grow(-15)
		position = position.clamp(walkable.position, walkable.end)
	_update_pixel_animation(direction.length() > 0.1)
	queue_redraw()

func dodge_readiness() -> float:
	return 1.0 - clampf(dodge_cooldown / DODGE_COOLDOWN, 0.0, 1.0)

func try_dodge() -> bool:
	if defeated or dodge_cooldown > 0 or app == null or not app.running():
		return false
	dodge_remaining = 0.22
	dodge_cooldown = DODGE_COOLDOWN
	return true

func try_attack(target: Vector2) -> bool:
	if defeated or attack_cooldown > 0 or app == null or not app.running():
		return false
	if target.distance_to(global_position) > 1:
		facing = global_position.direction_to(target)
	var attack_profile: Dictionary = Combat.profile(app.snapshot(false), app.rules())
	attack_cooldown = float(attack_profile.cooldown)
	swing_remaining = 0.15
	_update_pixel_animation(false)
	var enemy = app.enemy()
	if is_instance_valid(enemy):
		enemy.hear_noise(global_position, 132.0)
	if is_instance_valid(enemy) and enemy.health > 0 and global_position.distance_to(enemy.global_position) < float(attack_profile.reach):
		var toward: Vector2 = global_position.direction_to(enemy.global_position)
		if facing.dot(toward) > 0.2 and enemy.has_clear_line_to(self):
			enemy.take_damage(int(attack_profile.damage))
	return true

func take_damage(amount: int) -> bool:
	if amount <= 0 or defeated or dodge_remaining > 0 or hurt_remaining > 0 or app == null or not app.running():
		return false
	health = maxi(0, health - amount)
	# Switch to defeated before updating the sprite. Otherwise the last
	# lethal hit leaves a permanently red "hurt" frame while physics stops.
	if health == 0:
		defeated = true
	hurt_remaining = 0.45
	_update_pixel_animation(false)
	queue_redraw()
	app.update_hud()
	if health == 0:
		app.call_deferred("player_defeated")
	return true

func restore(hp: int) -> void:
	health = hp
	defeated = hp == 0
	velocity = Vector2.ZERO
	dodge_remaining = 0
	dodge_cooldown = 0
	attack_cooldown = 0
	hurt_remaining = 0
	swing_remaining = 0
	_update_pixel_animation(false)
	queue_redraw()

func _draw() -> void:
	# 64x64 animated sprite is the actor artwork; only combat indicators use
	# primitive overlays. No placeholder circle/body is drawn behind the sprite.
	if dodge_remaining > 0:
		draw_arc(Vector2.ZERO, 15, 0, TAU, 20, Color("96e6db"), 2)
	if swing_remaining > 0:
		var angle := facing.angle()
		draw_arc(Vector2.ZERO, 38, angle - 0.8, angle + 0.8, 12, Color("f6db91"), 3)
