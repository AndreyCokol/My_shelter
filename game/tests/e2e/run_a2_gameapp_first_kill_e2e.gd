extends SceneTree
## A2-02 runtime integration: instantiate actual playable.tscn, GameApp, UI,
## SceneRouter, actual Enemy, CampaignSession and durable CheckpointStore.
## The first kill happens through real Enemy._physics_process deferred dispatch.
## No mocks: this is closer to production than isolated Player/Enemy QA.
const PLAYABLE := preload("res://game/scenes/main/playable.tscn")
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

func _run() -> void:
	var save_path := "user://a2-combat-live-qa/%d-%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	set_meta(GAME_META, {"seed": 42, "save_location": save_path})
	var app = PLAYABLE.instantiate()
	root.add_child(app)
	await process_frame
	await physics_frame
	check(app.campaign != null and app.scene_router != null and app.session != null,
		"actual playable.tscn constructed GameApp with Campaign/SceneRouter/Core")
	check(is_instance_valid(app.hero) and is_instance_valid(app.ui) and is_instance_valid(app.camera),
		"actual Player/UI/Camera mounted in product scene")
	var initial: Dictionary = app.snapshot()
	check(initial.schema_version == 4 and initial.world_states.layout.generator_version == Layout.VERSION,
		"live campaign uses schema4 and supported generator v5")
	check(initial.world_states.layout.seed == 42 and initial.scene.current_scene_id == "hospital",
		"live deterministic seed42 new-game starts in current legacy hospital")
	check(initial.claimed_reward_ids.is_empty() and not initial.world_states.first_enemy_defeated,
		"initial actual campaign has no first-kill receipt or unlock")
	check(is_instance_valid(app.enemy()) and app.enemy().health > 0,
		"real first zombie exists in actual hospital WorldHost")

	var retreat: Dictionary = app.toggle_shelter()
	var inside: Dictionary = app.snapshot()
	check(retreat.ok and inside.scene.current_scene_id == "shelter",
		"actual G transition to shelter accepted before the first kill")
	check(inside.claimed_reward_ids.is_empty() and not inside.world_states.first_enemy_defeated,
		"early G transition does not forge first System reward")
	var returned: Dictionary = app.toggle_shelter()
	var before: Dictionary = app.snapshot()
	check(returned.ok and before.scene.current_scene_id == "hospital",
		"actual shelter G return restores first-zombie hospital scene")
	check(is_instance_valid(app.enemy()) and app.enemy().health > 0,
		"first zombie still present after early escape and return")

	var enemy = app.enemy()
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.take_damage(enemy.MAX_HEALTH + 100)
	check(enemy.health == 0, "actual production Enemy clamps lethal hit to zero")
	enemy._physics_process(0.016)
	enemy._physics_process(0.016)
	await process_frame
	await process_frame
	var killed: Dictionary = app.snapshot()
	var earned: int = 0
	for item in killed.inventory.items:
		if item.type_id == "tool.basic" and item.container_id == "player":
			earned += int(item.quantity)
	check(killed.world_states.first_enemy_defeated and "system" in killed.claimed_reward_ids,
		"real Enemy death dispatch committed first System unlock and claim receipt")
	check(killed.player.xp == app.rules().rewards.system.hero_xp
		and killed.wallet.system_coins == app.rules().rewards.system.coins and earned == 1,
		"real first kill credits exactly one XP/coin reward and one owned weapon")
	check(not is_instance_valid(app.enemy()),
		"real GameApp hides/deletes zombie only after the accepted Core transaction")
	var committed_actions: int = killed.completed_actions.size()
	app.enemy_defeated()
	var duplicate: Dictionary = app.snapshot()
	check(duplicate.claimed_reward_ids == killed.claimed_reward_ids
		and duplicate.wallet.system_coins == killed.wallet.system_coins
		and duplicate.completed_actions.size() == committed_actions,
		"repeating death callback cannot duplicate reward or append receipt")

	var again: Dictionary = app.toggle_shelter()
	var shelter_state: Dictionary = app.snapshot()
	check(again.ok and shelter_state.scene.current_scene_id == "shelter",
		"actual G return remains available after System first kill")
	var go_back: Dictionary = app.toggle_shelter()
	var back_state: Dictionary = app.snapshot()
	check(go_back.ok and back_state.scene.current_scene_id == "hospital",
		"actual post-kill shelter return restores hospital and scene")
	check(not is_instance_valid(app.enemy()) and back_state.claimed_reward_ids.count("system") == 1,
		"world reload after G cannot resurrect the first zombie or grant reward twice")

	var saved: Dictionary = app.save_game()
	var saved_snapshot: Dictionary = app.snapshot()
	check(saved.ok, "actual GameApp saved campaign to CheckpointStore")
	var loaded: Dictionary = app.load_game()
	var loaded_snapshot: Dictionary = app.snapshot()
	check(loaded.ok and loaded_snapshot.scene.current_scene_id == saved_snapshot.scene.current_scene_id,
		"actual A1 load_checkpoint restored saved GameApp scene and position state")
	check(loaded_snapshot.claimed_reward_ids == saved_snapshot.claimed_reward_ids
		and loaded_snapshot.player.xp == saved_snapshot.player.xp
		and loaded_snapshot.wallet.system_coins == saved_snapshot.wallet.system_coins
		and loaded_snapshot.world_states.first_enemy_defeated,
		"actual loaded save preserves one claimed System reward, XP and coin ledger")
	check(not is_instance_valid(app.enemy()),
		"actual load checkpoint still does not respawn the defeated first zombie")

	app.queue_free()
	await process_frame
	for suffix in ["", ".bak"]:
		var target := ProjectSettings.globalize_path(save_path + suffix)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
	print("A2 GAMEAPP FIRST KILL E2E TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
