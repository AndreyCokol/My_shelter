extends RefCounted
## A2 prototype: deterministic starting-hospital floor geometry.
##
## THIS IS NOT AUTOMATICALLY INSTALLED into WorldLayout or CoreSession.
## Its use requires a new generator contract from A1, explicit new-campaign
## start at floor 3, and old generator v4/v5 save compatibility.
const Plans = preload("res://game/systems/world/building_plan.gd")
const FLOOR_SCENE_IDS := ["hospital", "hospital_0_2", "hospital_0_3", "hospital_0_4"]
const FLOOR_PATTERNS := [0, 2, 4]
const ROOF_BOUNDS := Rect2(40, 105, 1160, 480)

static func start_scene_id() -> String:
	return FLOOR_SCENE_IDS[2]

static func scene_id(floor_number: int) -> String:
	if floor_number < 1 or floor_number > FLOOR_SCENE_IDS.size():
		return ""
	return FLOOR_SCENE_IDS[floor_number - 1]

static func plan_for_floor(floor_number: int) -> Dictionary:
	if floor_number < 1 or floor_number > 4:
		return {}
	if floor_number < 4:
		# Deep-copy the stable catalog entry, so later world decoration cannot
		# accidentally mutate a cached plan shared between scenes or saves.
		var plan: Dictionary = Plans.get_plan("hospital", floor_number, FLOOR_PATTERNS[floor_number - 1]).duplicate(true)
		plan["is_roof"] = false
		plan["fixed_start"] = true
		return plan

	# The fourth playable level is an OPEN ROOFTOP, not the generic fourth
	# hospital floor, which currently contains laboratories and offices.
	# Use the same stable plan fields/anchors as BuildingPlan, with one open
	# roof surface and a collision boundary. A5 owns roof artwork/visuals.
	var roof: Dictionary = Plans.structure("hospital", 4, 0)
	var corridor: Dictionary = roof.rooms["corridor"]
	corridor["rect"] = ROOF_BOUNDS
	roof.rooms["corridor"] = corridor
	roof["loot"] = Vector2(580, 340)
	roof["enemy"] = Vector2(850, 360)
	roof["spawn"] = Vector2(120, 260)
	roof["is_roof"] = true
	roof["fixed_start"] = true
	Plans.compile(roof)
	assert(Plans.valid(roof), "Starter rooftop must pass existing physics geometry validation")
	return roof
