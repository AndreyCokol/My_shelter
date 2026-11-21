extends SceneTree
## A2-01 real Player movement plus pure mode state-machine acceptance.
## P0 scope: no new InputMap physical keys, no new water world, jump is VFX
## ONLY and must never let CharacterBody2D pass through actual walls.
const Mobility = preload("res://game/systems/world/topdown_mobility.gd")
const Player = preload("res://game/entities/player/player.gd")

class FakeRouter extends RefCounted:
	func current_world():
		return null

class FakeApp extends RefCounted:
	var scene_router = FakeRouter.new()
	func running() -> bool:
		return true

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(good: bool, description: String) -> void:
	checks += 1
	if not good:
		failures += 1
	print(("PASS " if good else "FAIL ") + description)

func fake_wall(parent: Node2D, rect: Rect2) -> void:
	var wall := StaticBody2D.new()
	parent.add_child(wall)
	wall.position = rect.get_center()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	wall.add_child(collider)

func _run() -> void:
	var idle: Dictionary = Mobility.step(Vector2.ZERO, Vector2.RIGHT, false, false, false, 0.0, 0.0, 0.016)
	check(idle.ok and idle.mode == "idle" and idle.velocity == Vector2.ZERO,
		"no input gives exactly zero movement")
	var walking: Dictionary = Mobility.step(Vector2.RIGHT, Vector2.RIGHT, false, false, false, 0.0, 0.0, 0.016)
	check(walking.ok and walking.mode == "walk" and walking.velocity == Vector2(115, 0),
		"old baseline walking speed remains exactly 115 px/s")
	var running: Dictionary = Mobility.step(Vector2.RIGHT, Vector2.RIGHT, true, false, false, 0.0, 0.0, 0.016)
	check(running.ok and running.mode == "run" and running.velocity == Vector2(165, 0),
		"optional running is faster than baseline walking")
	var swimming: Dictionary = Mobility.step(Vector2.RIGHT, Vector2.RIGHT, true, true, true, 0.0, 0.0, 0.016)
	check(swimming.ok and swimming.mode == "swim" and swimming.velocity.x == Mobility.SWIM_SPEED
		and swimming.jump_remaining == 0.0, "water prevents running/jumping and reduces movement speed")
	var floating: Dictionary = Mobility.step(Vector2.ZERO, Vector2.RIGHT, false, true, true, 0.0, 0.0, 0.016)
	check(floating.ok and floating.mode == "float" and floating.velocity == Vector2.ZERO,
		"stationary water mode is floating, not running or jumping")
	var dodge: Dictionary = Mobility.step(Vector2.ZERO, Vector2.RIGHT, false, false, false, 0.20, 0.0, 0.016)
	check(dodge.ok and dodge.mode == "dodge" and dodge.velocity == Vector2(320, 0),
		"real baseline dodge velocity stays exactly 320 px/s")
	check(dodge.jump_remaining == 0.0 and dodge.visual_height == 0.0,
		"dodge never stacks a virtual jump")

	var jump: Dictionary = Mobility.step(Vector2.RIGHT, Vector2.RIGHT, false, true, false, 0.0, 0.0, 0.016)
	check(jump.ok and jump.mode == "jump" and jump.jump_remaining > 0.0
		and jump.jump_remaining < Mobility.JUMP_DURATION and jump.visual_height > 0.0,
		"visual-only jump starts with bounded timer and sprite offset")
	var jump_follow: Dictionary = Mobility.step(Vector2.RIGHT, Vector2.RIGHT, false, true, false, 0.0, jump.jump_remaining, 0.016)
	check(jump_follow.jump_remaining < jump.jump_remaining,
		"repeat jump input while airborne never restarts an active jump")
	var grounded: Dictionary = Mobility.step(Vector2.RIGHT, Vector2.RIGHT, false, false, false, 0.0, 0.10, 0.2)
	check(grounded.ok and grounded.mode == "walk" and grounded.jump_remaining == 0.0
		and grounded.visual_height == 0.0, "visual jump lands with no leftover elevation")
	var water_landing: Dictionary = Mobility.step(Vector2.RIGHT, Vector2.RIGHT, false, false, true, 0.0, 0.40, 0.016)
	check(water_landing.mode == "swim" and water_landing.jump_remaining == 0.0
		and water_landing.visual_height == 0.0, "entering water cancels an existing visual jump")
	for sample in [
		[Vector2(INF, 0), Vector2.RIGHT, 0.016],
		[Vector2(2, 0), Vector2.RIGHT, 0.016],
		[Vector2.RIGHT, Vector2(2, 0), 0.016],
		[Vector2.RIGHT, Vector2.RIGHT, -0.01],
		[Vector2.RIGHT, Vector2.RIGHT, INF],
	]:
		var bad: Dictionary = Mobility.step(sample[0], sample[1], false, false, false, 0.0, 0.0, sample[2])
		check(not bad.ok and bad.code == "INVALID_MOVEMENT_INPUT",
			"invalid magnitude, infinite or negative time cannot create unsafe velocity")

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	for k in range(100):
		var angle := rng.randf_range(-PI, PI)
		var intensity := rng.randf()
		var direction := Vector2(cos(angle), sin(angle)) * intensity
		var run_requested := rng.randi_range(0, 1) == 1
		var water := rng.randi_range(0, 1) == 1
		var movement: Dictionary = Mobility.step(direction, Vector2.DOWN, run_requested, false, water, 0.0, 0.0, 0.016)
		var expected_speed: float = Mobility.SWIM_SPEED if water else (Mobility.RUN_SPEED if run_requested else Mobility.WALK_SPEED)
		check(movement.ok and movement.velocity.length() <= expected_speed + 0.00001
			and movement.velocity.is_finite() and movement.visual_height == 0.0,
			"seeded input %d speed cap and finite movement" % k)

	# The real CharacterBody2D uses the new mode contract without losing
	# the old InputMap actions, the existing 9px collider or wall physics.
	for action in ["move_left", "move_right", "move_up", "move_down", "dodge", "run", "jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var arena := Node2D.new()
	root.add_child(arena)
	var hero = Player.new()
	hero.app = FakeApp.new()
	hero.process_mode = Node.PROCESS_MODE_DISABLED
	hero.position = Vector2(80, 160)
	arena.add_child(hero)
	await physics_frame
	Input.action_press("move_right")
	hero._physics_process(0.016)
	check(hero.movement_state == "walk" and absf(hero.velocity.x - 115.0) < 0.01,
		"real Player walks at exact old speed without modifiers")
	Input.action_press("run")
	hero._physics_process(0.016)
	check(hero.movement_state == "run" and absf(hero.velocity.x - Mobility.RUN_SPEED) < 0.01,
		"real Player obeys optional run action when mapped by input owner")
	hero.set_water_contact(true)
	hero._physics_process(0.016)
	check(hero.movement_state == "swim" and absf(hero.velocity.x - Mobility.SWIM_SPEED) < 0.01,
		"real Player swims only when world reports water contact")
	check(hero.jump_remaining == 0.0 and hero.pixel_sprite.position.y == 0.0,
		"real Player entering water cannot retain artificial jump elevation")
	hero.set_water_contact(false)
	Input.action_release("run")
	hero._physics_process(0.016)
	check(hero.movement_state == "walk" and absf(hero.velocity.x - 115.0) < 0.01,
		"real Player leaves water and returns to old walk speed")
	check(hero.try_dodge(), "real Space dodge still accepted with walking inputs")
	hero._physics_process(0.016)
	check(hero.movement_state == "dodge" and absf(hero.velocity.length() - 320.0) < 0.01,
		"real Player dodge physics still uses original 320 px/s")
	hero.restore(100)
	Input.action_release("move_right")
	Input.action_press("move_left")
	hero.position = Vector2(90, 160)
	# Wall is to the left of the actor; move left for one second.
	fake_wall(arena, Rect2(56, 120, 10, 85))
	await physics_frame
	for step_number in range(40):
		hero._physics_process(1.0 / 60.0)
		await physics_frame
	check(hero.position.x >= 66.0 + 9.0 - 0.1,
		"actual CharacterBody2D cannot pass through a native wall while walking")
	Input.action_release("move_left")
	Input.action_release("dodge")
	Input.action_release("jump")
	Input.action_release("run")
	hero.restore(100)
	check(hero.movement_state == "idle" and hero.jump_remaining == 0.0 and not hero.water_contact,
		"real hero restore resets optional movement states safely")
	arena.queue_free()
	await process_frame

	print("A2 LOCOMOTION CONTRACT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
