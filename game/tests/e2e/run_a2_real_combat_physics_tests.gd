extends SceneTree
## A2-02 native Godot combat test: REAL Player and Enemy scripts, REAL walls.
## FakeApp isolates the transaction/Core boundary only: no save/quest grant.
const Player = preload("res://game/entities/player/player.gd")
const Enemy = preload("res://game/entities/enemies/enemy.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Combat = preload("res://game/systems/combat/combat_loadout.gd")

class FakeApp extends RefCounted:
	var hero
	var foe
	var game_rules: Dictionary
	var game_state: Dictionary
	var active := true
	var defeated_enemy_events := 0
	var defeated_player_events := 0
	var hud_updates := 0
	func running() -> bool:
		return active
	func snapshot(_include_receipts: bool = false) -> Dictionary:
		return game_state.duplicate(true)
	func rules() -> Dictionary:
		return game_rules.duplicate(true)
	func enemy():
		return foe
	func update_hud() -> void:
		hud_updates += 1
	func enemy_defeated() -> void:
		defeated_enemy_events += 1
	func player_defeated() -> void:
		defeated_player_events += 1

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + title)

func static_wall(parent: Node2D, rect: Rect2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = rect.get_center()
	wall.collision_layer = 1
	parent.add_child(wall)
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	return wall

func _run() -> void:
	var rules := Rules.build()
	var clean_state := {
		"player": {"xp": 0, "equipped_weapon_instance_id": ""},
		"inventory": {"items": []},
	}
	check(Combat.valid_catalog(rules), "real combat rules catalog validates")
	var profile: Dictionary = Combat.profile(clean_state, rules)
	check(profile.damage > 0 and profile.reach > 50 and profile.cooldown > 0,
		"real default unarmed damage/reach/cooldown are positive")

	var game := FakeApp.new()
	game.game_rules = rules
	game.game_state = clean_state
	var arena := Node2D.new()
	arena.name = "A2_RealCombat_PhysicsArena"
	root.add_child(arena)
	var player = Player.new()
	var enemy = Enemy.new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	player.position = Vector2(100, 160)
	enemy.position = Vector2(150, 160)
	arena.add_child(player)
	arena.add_child(enemy)
	game.hero = player
	game.foe = enemy
	player.app = game
	enemy.app = game
	await physics_frame

	check(enemy.has_clear_line_to(player), "real zombie physics LOS is clear without any wall")
	check(player.try_attack(enemy.global_position) and enemy.health == enemy.MAX_HEALTH - int(profile.damage),
		"real Player attack causes exactly one valid melee damage")
	var after_first: int = enemy.health
	check(not player.try_attack(enemy.global_position) and enemy.health == after_first,
		"real attack cooldown rejects immediate duplicate attack")
	player.attack_cooldown = 0.0
	check(player.try_attack(Vector2(0, 160)) and enemy.health == after_first,
		"real facing cone forbids back-facing strike despite nearby enemy")

	var wall := static_wall(arena, Rect2(123, 138, 14, 44))
	await physics_frame
	check(not enemy.has_clear_line_to(player),
		"real Godot StaticBody2D completely occludes zombie-to-hero line")
	enemy.health = enemy.MAX_HEALTH
	player.attack_cooldown = 0.0
	check(player.try_attack(enemy.global_position) and enemy.health == enemy.MAX_HEALTH,
		"real Player cannot strike zombie through blocking wall")

	wall.queue_free()
	await physics_frame
	check(enemy.has_clear_line_to(player), "removing physical wall restores direct LOS")
	player.attack_cooldown = 0.0
	check(player.try_attack(enemy.global_position) and enemy.health == enemy.MAX_HEALTH - int(profile.damage),
		"attack can hit again only after wall removal")

	enemy.health = enemy.MAX_HEALTH
	enemy.position = Vector2(201, 160)
	await physics_frame
	check(enemy.has_clear_line_to(player), "distance-only test has clear LOS")
	player.attack_cooldown = 0.0
	check(player.try_attack(enemy.global_position) and enemy.health == enemy.MAX_HEALTH,
		"attack beyond actual unarmed reach cannot inflict any damage")
	enemy.position = Vector2(150, 160)
	await physics_frame

	player.health = 100
	player.defeated = false
	player.hurt_remaining = 0.0
	player.dodge_cooldown = 0.0
	player.dodge_remaining = 0.0
	check(player.try_dodge() and player.dodge_remaining > 0.0 and player.dodge_cooldown > 0.0,
		"real dodge activates temporary invulnerability and cooldown")
	check(not player.try_dodge(), "cannot dodge twice during cooldown")
	check(not player.take_damage(15) and player.health == 100,
		"real hero takes no damage while dodge is active")

	player.dodge_remaining = 0.0
	player.hurt_remaining = 0.0
	check(player.take_damage(15) and player.health == 85,
		"after dodge, a clear enemy hit reduces health once")
	check(not player.take_damage(15) and player.health == 85,
		"hurt invulnerability prevents stacked instantaneous duplicate damage")
	check(game.hud_updates == 1, "one confirmed damage triggers one HUD update")

	# Enemy death notification is delegated to A1 exactly once. Directly
	# invoke its production physics tick while its autonomous AI is frozen.
	enemy.health = 20
	enemy.reported = false
	enemy.take_damage(25)
	check(enemy.health == 0, "real zombie HP clamps at zero after lethal strike")
	enemy._physics_process(0.016)
	enemy._physics_process(0.016)
	await process_frame
	check(game.defeated_enemy_events == 1 and enemy.reported,
		"one lethal zombie gives exactly one deferred defeat event")
	enemy.take_damage(25)
	check(enemy.health == 0, "dead zombie cannot be killed repeatedly to generate new receipts")

	game.active = false
	player.attack_cooldown = 0.0
	player.dodge_cooldown = 0.0
	player.hurt_remaining = 0.0
	check(not player.try_attack(enemy.global_position),
		"paused or inactive session rejects direct actor attack")
	check(not player.try_dodge() and not player.take_damage(15),
		"inactive session rejects dodge and damage changes")

	arena.queue_free()
	await process_frame
	print("A2 REAL COMBAT PHYSICS TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
