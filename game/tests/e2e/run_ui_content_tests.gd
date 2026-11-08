extends SceneTree

# P0 A5/A4: Q02 describes a post-victory return, never an unlock gate.
# Shop amounts/prices/time must come from the exact rules catalog.
const UI = preload("res://game/ui/game_ui.gd")
const Rules = preload("res://game/data/game_rules.gd")
var checks: int = 0
var failures: int = 0

func check(valid: bool, title: String) -> void:
	checks += 1
	print(("PASS " if valid else "FAIL ") + title)
	if not valid:
		failures += 1
		push_error(title)

func label_found(parent: Node, expected: String) -> bool:
	for label in parent.find_children("*", "Label", true, false):
		if expected in label.text:
			return true
	return false

func button_found(parent: Node, expected: String) -> bool:
	for control in parent.find_children("*", "Button", true, false):
		if control.text == expected:
			return true
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canonical: Dictionary = Rules.build()
	var changed: Dictionary = canonical.duplicate(true)
	changed.offers.seed.price = 17
	changed.offers.seed.quantity = 7
	changed.resource_respawn_minutes = 95
	check(Rules.validate(changed), "alternate offer price/quantity/respawn catalog valid")
	var nonpotato: Dictionary = canonical.duplicate(true)
	nonpotato.items["food.test_ration"] = {"name": "Полевой паёк", "edible": true}
	nonpotato.food.accepted_food_type_ids = ["food.test_ration"]
	check(Rules.validate(nonpotato) and "Полевой паёк" in UI.work_ration_hint(nonpotato) and not "Картофель" in UI.work_ration_hint(nonpotato), "A0-F09 work panel text follows the non-potato edible catalog")
	nonpotato.food.accepted_food_type_ids = ["crop.potato", "food.test_ration"]
	check("Картофель, Полевой паёк" in UI.work_ration_hint(nonpotato) and "1 ед. свободной еды" in UI.work_ration_hint(nonpotato), "A0-F09 multiple work foods are listed in the configured priority order")
	check(UI.offer_description(canonical, "seed") != UI.offer_description(changed, "seed"), "pricing UI is derived from current rules")
	check("7 ед." in UI.offer_description(changed, "seed") and "17 мон." in UI.offer_description(changed, "seed"), "shop adapts to alternative quantity and price")
	check("95 игровых минут" in UI.shop_hint(changed, "seed"), "resource refresh hint respects configured duration")
	check(UI.shop_hint({"offers": {}, "items": {}}, "seed") == "Сейчас нет предложений.", "missing catalog offer cannot claim purchasable resources")
	check("Вернуться" in UI.QUEST_TITLES[1] and "после первого боя" in UI.QUEST_TITLES[1] and not "Открыть убежище" in UI.QUEST_TITLES[1], "Q02 describes post-combat return, not locked shelter")

	var app = preload("res://game/scenes/main/playable.tscn").instantiate()
	var save_path := "user://ui-content-tests/" + str(Time.get_ticks_usec()) + ".json"
	app.save_location = save_path
	root.add_child(app)
	await process_frame
	app.ui.close_panel()
	check(not app.snapshot().world_states.first_enemy_defeated, "new game starts without System unlock")
	app.ui.open_panel("quests")
	await process_frame
	check(label_found(app.ui.body, "Q02 · Вернуться в убежище после первого боя — в работе"), "real quest panel displays truthful Q02 instruction")
	app.ui.close_panel()
	check(app.toggle_shelter().ok and app.snapshot().scene.current_scene_id == "shelter", "G escape works before first victory")
	check(app.snapshot().quests.records[1].status == "active", "early shelter escape does not prematurely complete Q02")
	app.ui.open_panel("shop")
	await process_frame
	check(label_found(app.ui.body, UI.shop_hint(app.rules(), "seed")), "real rendered shop text comes from live rules")
	check(button_found(app.ui.body, "Купить: " + UI.offer_description(app.rules(), "seed")), "real purchase button agrees with offer transaction")
	app.ui.close_panel()
	check(app.toggle_shelter().ok and app.snapshot().scene.current_scene_id == "hospital", "G returns to the original hospital after early escape")

	# Four legitimate real-time unarmed attacks unlock System. Q02 finishes
	# only after the next visit to shelter, not before or by purchasing seeds.
	var foe = app.enemy()
	app.hero.position = foe.position + Vector2(-38, 0)
	for i in range(4):
		app.hero.attack_cooldown = 0
		app.hero.try_attack(foe.global_position)
	await create_timer(0.15).timeout
	check(app.snapshot().world_states.first_enemy_defeated and app.snapshot().quests.records[0].status == "completed", "real first combat completes Q01")
	check(app.snapshot().quests.records[1].status == "active", "System unlock alone does not complete return-home Q02")
	check(app.toggle_shelter().ok and app.snapshot().quests.records[1].status == "completed", "post-combat return to shelter completes Q02 without changing early-G behavior")
	app.ui.open_panel("quests")
	await process_frame
	check(label_found(app.ui.body, "Q02 · Вернуться в убежище после первого боя — выполнено"), "completed Q02 is visibly clear in real UI")
	app.ui.close_panel()
	var weapon_stacks: Array = app.snapshot().inventory.items.filter(func(item): return item.type_id == "tool.basic" and item.container_id == "player")
	check(weapon_stacks.size() == 1, "victory puts one usable knife into the real inventory")
	if not weapon_stacks.is_empty():
		var knife_id: String = weapon_stacks[0].instance_id
		app.ui.open_panel("inventory")
		app.ui.select_inventory("player", knife_id)
		await process_frame
		var equip_buttons: Array = app.ui.body.find_children("*", "Button", true, false).filter(func(button): return button.text == "Взять в руки")
		check(equip_buttons.size() == 1, "actual inventory UI offers an equip action on the knife")
		if not equip_buttons.is_empty():
			equip_buttons[0].pressed.emit()
		await process_frame
		check(app.last_result.ok and app.snapshot().player.equipped_weapon_instance_id == knife_id and button_found(app.ui.body, "Снять оружие"), "inventory equip button commits weapon and changes the UI")
		check(app.ui.hud.items.any(func(item): return item.instance_id == knife_id and "[в руках]" in item.label), "HUD marks the equipped bagged knife")
		var remove_buttons: Array = app.ui.body.find_children("*", "Button", true, false).filter(func(button): return button.text == "Снять оружие")
		if not remove_buttons.is_empty():
			remove_buttons[0].pressed.emit()
		await process_frame
		check(app.last_result.ok and app.snapshot().player.equipped_weapon_instance_id.is_empty(), "inventory can unequip without altering first-victory reward")
		app.ui.close_panel()
	app.free()
	await process_frame
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("UI CONTENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
