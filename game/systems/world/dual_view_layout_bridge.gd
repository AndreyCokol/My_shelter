extends RefCounted
## A2/A5 spatial adapter for *existing* versioned WorldLayout geometry.
##
## This is a read-only bridge for the dual-camera experiment: it does not
## install a campaign scene, alter a save manifest or instantiate game rewards.
## A1's SceneRouter and the legacy 2D WorldLayout remain authoritative.
const Layout = preload("res://game/systems/world/world_layout.gd")
const Space = preload("res://game/systems/world/dual_view_space.gd")
const ACTOR_CENTER_METRES := 0.9
const MAX_COLLIDERS := 2048

static func snapshot(seed_value: int, scene_id: String, version: int = Layout.VERSION) -> Dictionary:
	if seed_value < 0 or seed_value > Layout.MAX_SEED or version not in [4, 5]:
		return _error("INVALID_MANIFEST")
	if scene_id.is_empty():
		return _error("INVALID_SCENE_ID")
	# The production generator returns every scene deterministically for this
	# manifest. Do not mutate its returned nodes or cached BuildingPlans.
	var nodes: Dictionary = Layout.build(seed_value, version)
	if not nodes.has(scene_id):
		return _error("SCENE_NOT_FOUND")
	var source: Dictionary = nodes[scene_id]
	if not Layout.kind(scene_id) in ["hospital", "house", "outside"]:
		return _error("UNSUPPORTED_SCENE")
	return from_record(seed_value, scene_id, version, source)

static func from_record(seed_value: int, scene_id: String, version: int, source: Dictionary) -> Dictionary:
	var bounds = source.get("bounds")
	var spawn = source.get("spawn")
	var obstacles = source.get("obstacles")
	if not bounds is Rect2 or not bounds.is_finite() or not bounds.has_area():
		return _error("INVALID_BOUNDS")
	if not spawn is Vector2 or not spawn.is_finite() or not bounds.has_point(spawn):
		return _error("INVALID_SPAWN")
	if not obstacles is Array or obstacles.size() > MAX_COLLIDERS:
		return _error("INVALID_OBSTACLES")
	var boxes: Array[Dictionary] = []
	for rectangle in obstacles:
		if not rectangle is Rect2 or not rectangle.is_finite() or not rectangle.has_area():
			return _error("INVALID_OBSTACLES")
		# Source walls are already the actual physics wall & furniture
		# rectangles used by the current 2D campaign.
		var box: Dictionary = Space.box_from_legacy_rect(rectangle)
		if not box.get("ok", false):
			return _error("INVALID_OBSTACLES")
		if rectangle.grow(9.0).has_point(spawn):
			return _error("BLOCKED_SPAWN")
		boxes.append(box)
	var floor_box := Space.box_from_legacy_rect(bounds, 0.2)
	if not floor_box.get("ok", false):
		return _error("INVALID_BOUNDS")
	return {
		"ok": true,
		"code": "OK",
		"seed": seed_value,
		"generator_version": version,
		"scene_id": scene_id,
		"kind": Layout.kind(scene_id),
		"legacy_bounds": bounds,
		"legacy_spawn": spawn,
		"hero_position": Space.legacy_to_3d(spawn, ACTOR_CENTER_METRES),
		"floor": {
			"position": Vector3(floor_box.position.x, -0.1, floor_box.position.z),
			"size": floor_box.size,
		},
		"wall_boxes": boxes,
		"wall_count": boxes.size(),
		# This is metadata for QA, NOT a staged transition or persisted save.
		"exit_count": source.get("exits", {}).size(),
	}

static func _error(code: String) -> Dictionary:
	return {"ok": false, "code": code}
