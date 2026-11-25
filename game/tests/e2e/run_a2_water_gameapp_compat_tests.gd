extends SceneTree
## A2-01 native compatibility check on actual A1 GameApp/WorldHost/Save.
## Optional water metadata is absent in existing generator v5. This test
## prevents a future water change from making old G / first kill / save wet
## or breaking schema4 campaign state.
const PLAYABLE = preload("res://game/scenes/main/playable.tscn")
const Layout = preload("res://game/systems/world/world_layout.gd")
const GAME_META := &"shelter_next_campaign"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func water_dry(world) -> bool:
	if not is_instance_valid(world):
		return false
	var snapshot: Dictionary = world.water_hazard_snapshot()
	return snapshot.ok and snapshot.code == "OK" and snapshot.rectangles.is_empty() \
			and not is_instance_valid(world.water_zone_layer)

func _run() -> void:
	var save_path := "user://a2-water-gameapp-qa/%d-%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	set_meta(GAME_META, {"seed": 42, "save_location": save_path})
	var app = PLAYABLE.instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	check(app.campaign != null and app.scene_router != null and app.session != null,
		"real playable GameApp started A1 campaign with SceneRouter/Core")
	var initial: Dictionary = app.snapshot()
	check(initial.schema_version == 4 and initial.world_states.layout.generator_version == Layout.VERSION,
		"actual v5 generated campaign still has schema4, no save migration")
	check(initial.scene.current_scene_id == "hospital" and app.hero != null,
		"historical new-game start and persistent Player still work")
	check(water_dry(app.scene_router.current_world()) and not app.hero.water_contact,
		"old generated hospital does not acquire new flooded zones")
	check(is_instance_valid(app.enemy()) and app.enemy().health > 0,
		"actual first enemy remains in baseline hospital")

	var escape: Dictionary = app.toggle_shelter()
	check(escape.ok and app.snapshot().scene.current_scene_id == "shelter",
		"real G retreat to shelter works before first kill")
	check(water_dry(app.scene_router.current_world()) and not app.hero.water_contact,
		"real shelter is dry and WaterZones teardown did not contaminate persistent hero")
	var return_result: Dictionary = app.toggle_shelter()
	check(return_result.ok and app.snapshot().scene.current_scene_id == "hospital",
		"real G exit returns to hospital with WaterZones modification present")
	check(water_dry(app.scene_router.current_world()) and not app.hero.water_contact,
		"re-mounted old hospital remains dry after first G return")

	# Controlled death callback isolates A1's authoritative first reward,
	# rather than re-testing weapon hit cones already covered in PR #182.
	var enemy = app.enemy()
	check(is_instance_valid(enemy), "actual first zombie survives early G")
	if is_instance_valid(enemy):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.take_damage(enemy.MAX_HEALTH + 10)
		enemy._physics_process(0.016)
		await process_frame
		await process_frame
	var killed: Dictionary = app.snapshot()
	check(killed.world_states.first_enemy_defeated and "system" in killed.claimed_reward_ids,
		"one real Enemy->GameApp callback still commits initial System reward")
	check(not is_instance_valid(app.enemy()),
		"defeated first Enemy remains absent after authoritative A1 commit")

	var saved: Dictionary = app.save_game()
	check(saved.ok, "real water-aware WorldHost still permits durable A1 checkpoint")
	var loaded: Dictionary = app.load_game()
	check(loaded.ok and app.snapshot().claimed_reward_ids.count("system") == 1,
		"loading unchanged historical campaign does not duplicate first System reward")
	check(water_dry(app.scene_router.current_world()) and not app.hero.water_contact,
		"actual A1 load restores dry hero, no ghost water from previous scene")

	var retreat_again: Dictionary = app.toggle_shelter()
	var return_again: Dictionary = app.toggle_shelter()
	check(retreat_again.ok and return_again.ok
		and app.snapshot().scene.current_scene_id == "hospital",
		"post-reload G and return are unaffected by optional water support")
	check(app.snapshot().claimed_reward_ids.count("system") == 1
		and not is_instance_valid(app.enemy()),
		"real scene transitions after load neither duplicate reward nor respawn zombie")

	app.queue_free()
	await process_frame
	for suffix in ["", ".bak"]:
		var target := ProjectSettings.globalize_path(save_path + suffix)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
	print("A2 WATER GAMEAPP COMPAT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
