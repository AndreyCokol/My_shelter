extends SceneTree

# P0 A2: persisted weapon selection, XP-derived damage, physics LOS and
# transfer/save/replay invariants. Only the trusted test directly records victory.
const Rules = preload("res://game/data/game_rules.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Combat = preload("res://game/systems/combat/combat_loadout.gd")
const Player = preload("res://game/entities/player/player.gd")
const Enemy = preload("res://game/entities/enemies/enemy.gd")

class ArenaApp extends RefCounted:
	var state: Dictionary
	var catalog: Dictionary
	var target
	var full_snapshot_requested := false
	func running() -> bool:
		return true
	func snapshot(include_receipts: bool = true) -> Dictionary:
		full_snapshot_requested = full_snapshot_requested or include_receipts
		return state.duplicate(true)
	func rules() -> Dictionary:
		return catalog.duplicate(true)
	func enemy():
		return target

var checks := 0
var failures := 0

func check(value: bool, detail: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + detail)
	if not value:
		failures += 1
		push_error(detail)

func request(session, id: String, kind: String, payload: Dictionary = {}) -> Dictionary:
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": id, "command_type": kind, "payload": payload,
		"context": {"actor_id": "player", "scene_id": state.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var rules: Dictionary = Rules.build()
	check(Rules.validate(rules), "combat catalog accepts the initial P0 punch/knife balance")
	var bad: Dictionary = rules.duplicate(true)
	bad.combat.weapons["tool.basic"].cooldown = 0.0
	check(not Rules.validate(bad), "zero weapon cooldown rejected by rules validation")
	var campaign = Campaign.new(rules)
	var session = campaign.coordinator
	var save_path := "user://combat-equipment/" + str(Time.get_ticks_usec()) + ".json"
	var store = Store.new(save_path)
	var starting: Dictionary = session.get_snapshot()
	var punch := Combat.profile(starting, rules)
	check(punch.weapon_type_id.is_empty() and punch.damage == 25 and punch.reach == 64.0, "new player is unarmed with base damage/range")
	check(session.execute(request(session, "equip-nothing", "game.equip_weapon", {"instance_id": "missing"}), store).code != "OK", "no phantom weapon can be equipped before first encounter")
	check(session.execute(request(session, "first-defeat", "game.enemy_defeated"), store).ok, "first trusted victory grants the knife only once")
	var unlocked: Dictionary = session.get_snapshot()
	var knife: Dictionary = unlocked.inventory.items.filter(func(item): return item.type_id == "tool.basic")[0]
	check(unlocked.player.xp == 10 and Combat.profile(unlocked, rules).weapon_type_id.is_empty(), "first victory grants XP and bagged knife without silently equipping")
	check(Combat.profile(unlocked, rules).damage == 26, "persisted hero experience contributes bounded +1 damage even unarmed")
	check(session.execute(request(session, "invalid-gear", "game.equip_weapon", {"instance_id": "invented"}), store).code == "NOT_FOUND", "arbitrary gear ID rejected")
	var equip_cmd := request(session, "equip-knife", "game.equip_weapon", {"instance_id": knife.instance_id})
	check(session.execute(equip_cmd, store).ok, "equip a specific owned bag weapon")
	var armed: Dictionary = session.get_snapshot()
	var knife_profile := Combat.profile(armed, rules)
	check(knife_profile.weapon_type_id == "tool.basic" and knife_profile.damage == 39 and knife_profile.reach == 76.0 and absf(knife_profile.cooldown - 0.55) < 0.001, "equipped knife provides configurable damage/reach/cooldown and XP bonus")
	check(session.execute(equip_cmd, store).code == "ALREADY_APPLIED" and session.get_snapshot() == armed, "replay equip is exactly once")
	check(session.execute(request(session, "equip-knife", "game.equip_weapon", {"instance_id": ""}), store).code == "ACTION_CONFLICT", "same action ID cannot be reused to unequip")

	# Real physics ray and runtime actor attack: unarmed at 70px misses; knife
	# at 70px hits; a solid collision wall still rejects knife melee.
	var arena := Node2D.new()
	root.add_child(arena)
	var hero = Player.new()
	var foe = Enemy.new()
	arena.add_child(hero)
	arena.add_child(foe)
	hero.set_physics_process(false)
	foe.set_physics_process(false)
	hero.position = Vector2(100, 100)
	foe.position = Vector2(170, 100)
	var facade := ArenaApp.new()
	facade.catalog = rules
	facade.target = foe
	hero.app = facade
	facade.state = unlocked
	await physics_frame
	var hp: int = foe.health
	check(hero.try_attack(foe.global_position) and foe.health == hp, "unarmed cannot reach opponent at 70 pixels")
	hero.attack_cooldown = 0.0
	facade.state = armed
	check(hero.try_attack(foe.global_position) and foe.health == hp - knife_profile.damage, "real actor melee uses equipped knife damage and reach")
	check(not facade.full_snapshot_requested, "real actor melee does not read the persisted action journal")
	foe.health = hp
	hero.attack_cooldown = 0.0
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 36)
	shape.shape = rect
	wall.add_child(shape)
	arena.add_child(wall)
	wall.position = Vector2(135, 100)
	await physics_frame
	check(hero.try_attack(foe.global_position) and foe.health == hp, "equipped knife cannot hit through a physics wall")
	wall.queue_free()
	await physics_frame

	var loaded = Campaign.new(rules).coordinator
	check(loaded.load_checkpoint(store).ok and loaded.get_snapshot().player.equipped_weapon_instance_id == knife.instance_id, "equipped weapon ID persists through save/load")
	var transfer := request(session, "store-knife", "inventory.transfer", {"instance_id": knife.instance_id, "from_id": "player", "to_id": "storage", "quantity": 1})
	check(session.execute(transfer, store).ok and session.get_snapshot().player.equipped_weapon_instance_id.is_empty(), "moving entire equipped stack to storage atomically unequips it")
	check(Combat.profile(session.get_snapshot(), rules).weapon_type_id.is_empty(), "stashed knife no longer grants combat stats")
	check(session.execute(request(session, "equip-stashed", "game.equip_weapon", {"instance_id": knife.instance_id}), store).code == "NOT_FOUND", "weapon in shelter storage cannot be equipped")
	var malformed: Dictionary = session.get_snapshot()
	malformed.player.equipped_weapon_instance_id = knife.instance_id
	check(not Model.validate(malformed, rules), "invalid equip reference into storage rejected on load")
	var restore := request(session, "restore-knife", "inventory.transfer", {"instance_id": knife.instance_id, "from_id": "storage", "to_id": "player", "quantity": 1})
	check(session.execute(restore, store).ok and session.execute(request(session, "equip-restored", "game.equip_weapon", {"instance_id": knife.instance_id}), store).ok, "weapon can be re-equipped after moving back to player bag")
	check(session.execute(request(session, "remove-gear", "game.equip_weapon", {"instance_id": ""}), store).ok, "explicit unarmed command remains available")
	var old_save: Dictionary = session.get_snapshot()
	old_save.player.erase("equipped_weapon_instance_id")
	check(Model.validate(old_save, rules) and Combat.profile(old_save, rules).weapon_type_id.is_empty(), "legacy schema-v4 player without gear field remains valid and safely unarmed")
	arena.queue_free()
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("COMBAT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
