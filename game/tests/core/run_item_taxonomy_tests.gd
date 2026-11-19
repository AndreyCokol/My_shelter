extends SceneTree
# A1-01: static prospective contract checks ONLY; no gameplay/save mutation.
const Taxonomy = preload("res://game/contracts/item_taxonomy_candidate.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	var categories: Array = Taxonomy.categories()
	check(categories == ["shelter_object", "material", "non_system", "system_equipment"],
		"four exactly approved classifications in fixed order")
	check(categories.size() == 4 and not categories.has("spatial_bag"),
		"bag ability does not become a fifth loot category")
	categories.append("illegal")
	check(Taxonomy.categories().size() == 4, "category list is returned as independent copy")
	for name in ["shelter_object", "material", "non_system", "system_equipment"]:
		check(Taxonomy.valid_category(name), "known category " + name)
	check(not Taxonomy.valid_category("currency") and not Taxonomy.valid_category(4),
		"unknown and non-string category rejected")
	check(Taxonomy.valid_metadata({"category": "shelter_object", "is_equipment": false}),
		"furniture/equipment for shelter remains ordinary shelter object")
	check(Taxonomy.valid_metadata({"category": "material", "is_equipment": false}),
		"fabric, steel and other materials remain materials")
	check(Taxonomy.valid_metadata({"category": "non_system", "is_equipment": false, "edible": true}),
		"consumables are ordinary non-system items")
	check(Taxonomy.valid_metadata({"category": "non_system", "is_equipment": true}),
		"ordinary worn equipment is non-system")
	check(Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "rare", "quality_percent": 0}),
		"zero quality valid within rarity for system gear")
	check(Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "legendary", "quality_percent": 100}),
		"hundred quality valid within rarity for system gear")
	check(Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "special", "quality_percent": 37.5}),
		"intermediate quality within an explicit rarity is valid")
	check(not Taxonomy.valid_metadata({"category": "material", "is_equipment": true}),
		"materials cannot masquerade as equipment")
	check(not Taxonomy.valid_metadata({"category": "shelter_object", "is_equipment": true}),
		"shelter equipment cannot masquerade as character gear")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": false,
		"rarity": "rare", "quality_percent": 30}),
		"system quality never applies to furniture or buildings")
	check(not Taxonomy.valid_metadata({"category": "non_system", "is_equipment": true,
		"rarity": "rare", "quality_percent": 20}),
		"ordinary equipment does not silently acquire system rarity")
	check(not Taxonomy.valid_metadata({"category": "material", "quality_percent": 20}),
		"material quality not confused with system equipment")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"quality_percent": 50}), "system quality requires rarity")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "rare"}), "system rarity requires quality within rarity")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "", "quality_percent": 50}), "empty rarity rejected")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "rare", "quality_percent": -1}), "negative system quality rejected")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "rare", "quality_percent": 101}), "over-100 system quality rejected")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "rare", "quality_percent": "high"}), "text quality rejected")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": "yes",
		"rarity": "rare", "quality_percent": 50}), "nonboolean equipment flag rejected")
	check(not Taxonomy.valid_metadata({"category": "system_equipment", "is_equipment": true,
		"rarity": "rare", "quality_percent": INF}), "infinite quality rejected")
	check(not Taxonomy.valid_metadata({"category": "spatial_bag", "is_equipment": true}),
		"spatial bag ability cannot be reclassified as a loot type")
	check(not Taxonomy.valid_metadata({}), "missing category rejected")
	print("ITEM TAXONOMY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
