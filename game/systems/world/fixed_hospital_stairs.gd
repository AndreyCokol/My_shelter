extends RefCounted
## A2-03: pure fixed-hospital stair transition contract.
##
## This file does NOT call SceneRouter, mutate GameState, teleport the actor
## or persist a checkpoint. A1 must stage/commit the transition atomically.
## Historical generator v4/v5 scene IDs remain untouched.
const Fixed = preload("res://game/systems/world/fixed_start_hospital.gd")
const Plans = preload("res://game/systems/world/building_plan.gd")
const MIN_FLOOR := 1
const MAX_FLOOR := 4

static func floor_number(scene_id: String) -> int:
	for floor in range(MIN_FLOOR, MAX_FLOOR + 1):
		if Fixed.scene_id(floor) == scene_id:
			return floor
	return 0

static func stairs_transition(scene_id: String, direction: String) -> Dictionary:
	var floor := floor_number(scene_id)
	if floor == 0:
		return _error("UNKNOWN_SCENE")
	if direction != "up" and direction != "down":
		return _error("INVALID_DIRECTION")

	var delta := 1 if direction == "up" else -1
	var destination_floor: int = floor + delta
	if destination_floor < MIN_FLOOR or destination_floor > MAX_FLOOR:
		return _error("NO_STAIR_CONNECTION")

	var source_plan: Dictionary = Fixed.plan_for_floor(floor)
	var target_plan: Dictionary = Fixed.plan_for_floor(destination_floor)
	if source_plan.is_empty() or target_plan.is_empty() or not Plans.valid(source_plan) or not Plans.valid(target_plan):
		return _error("INVALID_FLOOR_PLAN")

	var source_stair: Vector2 = source_plan.stairs_up if delta > 0 else source_plan.stairs_down
	var target_stair: Vector2 = target_plan.stairs_down if delta > 0 else target_plan.stairs_up
	if not source_stair.is_finite() or not target_stair.is_finite():
		return _error("INVALID_STAIR_COORDINATE")
	if not source_stair.is_equal_approx(target_stair):
		# The initial starter hospital was designed with consecutive floors
		# using identical X/Y stair anchors. A1 must NEVER silently teleport
		# between mismatched plans; version migration is a separate contract.
		return _error("STAIRS_NOT_ALIGNED")
	return {
		"ok": true,
		"code": "OK",
		"source_scene": scene_id,
		"target_scene": Fixed.scene_id(destination_floor),
		"source_floor": floor,
		"target_floor": destination_floor,
		"direction": direction,
		"source_position": source_stair,
		"target_position": target_stair,
		"target_is_roof": bool(target_plan.get("is_roof", false)),
		"spatial_contract": "same_local_xy_anchor",
	}

static func _error(code: String) -> Dictionary:
	return {"ok": false, "code": code}
