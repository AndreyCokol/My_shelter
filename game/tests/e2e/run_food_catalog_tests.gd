extends SceneTree

# A0-F25: food acceptance must be based on an explicit edible catalog tag,
# never solely on a player-configurable accepted_food_type_ids whitelist.
const Rules = preload("res://game/data/game_rules.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var original: Dictionary = Rules.build()
	check(Rules.validate(original) and Campaign.valid_rules(original), "CT-72 normal potato ration is a supported edible item")
	check(original.items["crop.potato"].edible == true and original.items["tool.basic"].edible == false, "CT-72 food tags are explicit and not inferred from item names")

	for nonfood in ["seed.basic", "tool.basic", "material.salvage", "material.lamp_kit"]:
		var bad := original.duplicate(true)
		bad.food.accepted_food_type_ids = [nonfood]
		check(not Rules.validate(bad) and not Campaign.valid_rules(bad), "CT-72 reject nonfood as sole resident ration " + nonfood)

	var mixed := original.duplicate(true)
	mixed.food.accepted_food_type_ids = ["crop.potato", "tool.basic"]
	check(not Rules.validate(mixed) and not Campaign.valid_rules(mixed), "CT-72 mixed potatoes and knife must not enable invalid recruitment")

	for invalid in ["", "food.unknown", "crop.potato"]:
		var malformed := original.duplicate(true)
		malformed.food.accepted_food_type_ids = ["crop.potato", invalid]
		check(not Rules.validate(malformed), "CT-72 unknown, empty or duplicate accepted ID refused " + invalid)

	var lacking := original.duplicate(true)
	lacking.items["crop.potato"].erase("edible")
	check(not Rules.validate(lacking), "CT-72 missing certification cannot be silently accepted")
	lacking = original.duplicate(true)
	lacking.items["crop.potato"].edible = "yes"
	check(not Rules.validate(lacking), "CT-72 truthy text cannot certify food")
	lacking = original.duplicate(true)
	lacking.items["crop.potato"].edible = false
	check(not Rules.validate(lacking), "CT-72 nonedible potato in active whitelist rejected")

	var future := original.duplicate(true)
	future.items["food.test_ration"] = {"name": "Полевой паёк", "edible": true}
	future.food.accepted_food_type_ids = ["food.test_ration"]
	check(Rules.validate(future) and Campaign.valid_rules(future), "CT-72 a separately certified edible ration is valid")
	future.food.accepted_food_type_ids = ["crop.potato", "food.test_ration"]
	check(Rules.validate(future), "CT-72 multiple certified edible types are valid")

	for mode in ["consume", "reserve"]:
		var valid := future.duplicate(true)
		valid.food.reserve_mode = mode
		check(Campaign.valid_rules(valid), "CT-72 food certification independent of legal reservation mode " + mode)

	var zero := original.duplicate(true)
	zero.food.units_per_resident = 0
	check(not Campaign.valid_rules(zero), "CT-72 zero units cannot make food free")
	zero.food.units_per_resident = -1
	check(not Campaign.valid_rules(zero), "CT-72 negative units cannot make food free")

	check(original.food.accepted_food_type_ids == ["crop.potato"], "CT-72 no rule object was mutated by validation")
	print("FOOD CATALOG TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
