extends SceneTree
## A2-01 native Area2D -> real Player swimming acceptance.
## Attaches optional water metadata to an ACTUAL WorldLayout v5 "outside"
## scene without modifying the historical generator, manifest or checkpoints.
const WorldScene = preload("res://game/scenes/worlds/outside.tscn")
const WaterZones = preload("res://game/systems/world/world_water_zones.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Player = preload("res://game/entities/player/player.gd")
const Mobility = preload("res://game/systems/world/topdown_mobility.gd")

const WATER_ONE := Rect2(350, 630, 130, 65)
const WATER_TWO := Rect2(440, 630, 130, 65)
var checks := 0
var failures := 0

class FakeRouter extends RefCounted:
	var active_world
	func current_world():
		return active_world

class FakeApp extends RefCounted:
	var scene_router = FakeRouter.new()
	func running() -> bool:
		return true

func _initialize() -> void:
	call_deferred("_run")

func check(good: bool, title: String) -> void:
	checks += 1
	if not good:
		failures += 1
	print(("PASS " if good else "FAIL ") + title)

func at_next_physics() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	var floor := Rect2(0, 0, 2400, 800)
	var invalid = WaterZones.new()
	check(not invalid.configure([Rect2(2400, 400, 10, 10)], floor)
		and invalid.active_water_zone_count() == 0,
		"water metadata outside scene bounds rejected atomically")
	check(not invalid.configure([Rect2(10, 20, 0, 90)], floor)
		and invalid.active_water_zone_count() == 0,
		"zero-area water cannot create an invisible contact volume")
	check(not invalid.configure(["unsafe"], floor)
		and invalid.active_water_zone_count() == 0,
		"non-Rect2 metadata cannot create unsafe water")
	var too_many := []
	for index in range(WaterZones.MAX_ZONES + 1):
		too_many.append(Rect2(20, 20, 10, 10))
	check(not invalid.configure(too_many, floor),
		"unbounded number of water Area2D volumes rejected")
	invalid.free()

	var app = FakeApp.new()
	var nodes: Dictionary = Layout.build(42, 5)
	var original_world: Dictionary = nodes["outside"]
	check(not original_world.has("water_zones"),
		"existing v5 generator has no implicitly flooded maps")
	var water_map: Dictionary = original_world.duplicate(true)
	water_map["water_zones"] = [WATER_ONE, WATER_TWO]
	nodes["outside"] = water_map
	var world = WorldScene.instantiate()
	world.configure_layout(nodes, "outside")
	root.add_child(world)
	app.scene_router.active_world = world
	await at_next_physics()
	check(world.water_zones_valid and is_instance_valid(world.water_zone_layer),
		"actual outside WorldHost created native Area2D water layer from optional metadata")
	var hazards: Array[Rect2] = world.water_hazard_rects()
	check(hazards == [WATER_ONE, WATER_TWO],
		"authoritative water rectangles exposed as non-solid safe-return hazards")
	check(world.water_zone_layer.active_water_zone_count() == 2,
		"both separately authored water bodies have real independent contact colliders")
	var solid_collision: Array[Rect2] = world.collision_rects()
	check(solid_collision.size() > 0 and not solid_collision.has(WATER_ONE)
		and not solid_collision.has(WATER_TWO),
		"water is not a static wall and does not corrupt old navigation collision catalog")
	var deep_copy: Array[Rect2] = world.water_hazard_rects()
	deep_copy.clear()
	check(world.water_hazard_rects().size() == 2,
		"caller cannot mutate the persistent water hazard list by clearing a return array")

	var water_is_clear := true
	for obstacle in solid_collision:
		if obstacle.grow(9).intersects(WATER_ONE) or obstacle.grow(9).intersects(WATER_TWO):
			water_is_clear = false
	check(water_is_clear,
		"test water pools do not overlap actual physical v5 street walls")

	for action in ["move_left", "move_right", "move_up", "move_down", "run", "jump", "dodge"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var hero = Player.new()
	hero.app = app
	hero.position = Vector2(300, 645)
	root.add_child(hero)
	# Keep hero fully registered in PhysicsServer2D; only turn off the
	# automatic callback because the test drives exactly one movement tick.
	hero.set_physics_process(false)
	await at_next_physics()
	check(not hero.water_contact and hero.movement_state == "idle",
		"real Player starts dry, away from flooded street geometry")
	Input.action_press("move_right")
	Input.action_press("run")
	hero._physics_process(0.016)
	check(hero.movement_state == "run" and absf(hero.velocity.x - Mobility.RUN_SPEED) < 0.01,
		"existing optional run speed works on dry v5 street")

	# Enter first pool while a land dodge and VFX jump are already active.
	hero.dodge_remaining = 0.14
	hero.jump_remaining = 0.22
	hero.pixel_sprite.position.y = -11.0
	hero.position = Vector2(370, 645)
	await at_next_physics()
	check(hero.water_contact and hero.dodge_remaining == 0.0
		and hero.jump_remaining == 0.0 and hero.pixel_sprite.position.y == 0.0,
		"real Area2D contact cancels active land dodge and visual-only jump")
	check(not hero.try_dodge(), "Space dodge is refused during water contact")
	hero._physics_process(0.016)
	check(hero.movement_state == "swim"
		and absf(hero.velocity.x - Mobility.SWIM_SPEED) < 0.01,
		"Player moves at real swimming speed even while run modifier is held")
	var pure_water := Mobility.step(Vector2.RIGHT, Vector2.RIGHT, true, true, true, 0.20, 0.30, 0.016)
	check(pure_water.ok and pure_water.mode == "swim"
		and pure_water.velocity.x == Mobility.SWIM_SPEED
		and pure_water.jump_remaining == 0.0,
		"water dominates stale land-dodge/visual-jump state in pure movement controller")

	# Two overlapping Area2D layers: leaving the first while remaining in
	# the second must NOT clear the actor's wet flag.
	hero.position = Vector2(460, 645)
	await at_next_physics()
	check(hero.water_contact,
		"real Player remains wet while standing in overlapping water patches")
	hero.position = Vector2(540, 645)
	await at_next_physics()
	check(hero.water_contact,
		"leaving first zone while still inside second cannot falsely end swimming")
	hero.position = Vector2(600, 645)
	await at_next_physics()
	check(not hero.water_contact,
		"leaving last water Area2D restores dry Player state")
	hero._physics_process(0.016)
	check(hero.movement_state == "run" and absf(hero.velocity.x - Mobility.RUN_SPEED) < 0.01,
		"dry land running speed returns after actual water exit")

	# Core reload / Player.restore() can reset the boolean while the body
	# remains inside water; active overlap should correct state immediately.
	hero.position = Vector2(460, 645)
	await at_next_physics()
	check(hero.water_contact, "Player reenters Area2D after exiting both zones")
	hero.restore(100)
	check(not hero.water_contact, "Player.restore resets old world contact")
	await at_next_physics()
	check(hero.water_contact,
		"active water monitor restores contact after a same-scene Player restore")

	# A1 SceneRouter destroys one WorldHost on scene transitions. Its active
	# water volumes must release state on persistent hero before the next map.
	world.queue_free()
	await process_frame
	await physics_frame
	check(not hero.water_contact,
		"unloading flooded WorldHost clears water from persistent Player")

	var dry_nodes: Dictionary = Layout.build(42, 5)
	var dry_world = WorldScene.instantiate()
	dry_world.configure_layout(dry_nodes, "outside")
	root.add_child(dry_world)
	app.scene_router.active_world = dry_world
	await at_next_physics()
	check(not is_instance_valid(dry_world.water_zone_layer)
		and dry_world.water_hazard_rects().is_empty(),
		"legacy v5 same-scene map remains dry when no new water metadata was provided")
	check(not hero.water_contact,
		"loading an unmodified historical scene does not inherit prior flood state")

	Input.action_release("move_right")
	Input.action_release("run")
	Input.action_release("dodge")
	Input.action_release("jump")
	dry_world.queue_free()
	hero.queue_free()
	await process_frame
	print("A2 REAL WATER CONTACT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
