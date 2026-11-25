extends RefCounted
## A2-05: PURE spatial interaction intent and post-commit visibility guard.
##
## This file cannot grant items, remove world nodes, write saves or dispatch
## runtime commands. A1 must first implement a typed command with a durable
## object-specific receipt; existing "game.resource_collect" is NOT that API.
## The world object collider itself must be excluded from blockers; blockers
## must include the *current authoritative* wall/closed-door rectangles.
const Receipts = preload("res://game/systems/core/action_receipt.gd")
const DEFAULT_REACH := 55.0
const MAX_REACH := 128.0
const DEFAULT_ACTOR_RADIUS := 9.0
const MAX_GEOMETRY := 2048
const EPS := 0.5

static func prepare_intent(
		scene_id: String, actor_position: Vector2, object_data: Dictionary,
		world_bounds: Rect2, blockers: Array, action_id: String,
		reach: float = DEFAULT_REACH, actor_radius: float = DEFAULT_ACTOR_RADIUS
) -> Dictionary:
	if not _id(scene_id) or not _id(action_id) or not actor_position.is_finite():
		return _error("INVALID_ARGUMENT")
	if not is_finite(reach) or reach <= 0.0 or reach > MAX_REACH 			or not is_finite(actor_radius) or actor_radius < 0.0 or actor_radius > 24.0:
		return _error("INVALID_ARGUMENT")
	if not world_bounds.is_finite() or not world_bounds.has_area():
		return _error("INVALID_BOUNDS")
	if not object_data is Dictionary or object_data.size() != 7:
		return _error("INVALID_OBJECT")
	var world_id = object_data.get("scene_id")
	var object_id = object_data.get("object_id")
	var type_id = object_data.get("type_id")
	var kind = object_data.get("kind")
	var state = object_data.get("state")
	var position = object_data.get("position")
	var quantity = object_data.get("quantity")
	if not _id(world_id) or not _id(object_id) or not _id(type_id) 			or not kind is String or not state is String or not position is Vector2 			or not position.is_finite() or not quantity is int or quantity != 1:
		return _error("INVALID_OBJECT")
	if world_id != scene_id:
		return _error("WRONG_SCENE")
	if not world_bounds.has_point(actor_position) or not world_bounds.has_point(position):
		return _error("OUT_OF_BOUNDS")
	if actor_position.distance_to(position) > reach:
		return _error("OUT_OF_REACH")
	var operation := _operation(kind, state)
	if operation.is_empty():
		return _error("UNAVAILABLE")
	if operation == "PART_EXTRACTION_FORBIDDEN":
		return _error("PART_EXTRACTION_FORBIDDEN")
	if blockers.size() > MAX_GEOMETRY:
		return _error("INVALID_GEOMETRY")
	var forbidden: Array[Rect2] = []
	for obstacle in blockers:
		if not obstacle is Rect2 or not obstacle.is_finite() or not obstacle.has_area():
			return _error("INVALID_GEOMETRY")
		forbidden.append(obstacle.grow(actor_radius + EPS))
	if not _line_clear(actor_position, position, forbidden):
		return _error("BLOCKED_LINE_OF_INTERACTION")
	var identity := [scene_id, object_id, type_id, kind, state, operation, 1]
	var evidence := JSON.stringify(identity).sha256_text()
	return {
		"ok": true, "code": "OK", "action_id": action_id,
		"scene_id": scene_id, "object_id": object_id, "type_id": type_id,
		"object_kind": kind, "object_state": state, "operation": operation,
		"quantity": 1, "object_identity_sha256": evidence,
		"needs_core_commit": true, "hide_before_commit": false,
		"read_only_spatial_proof": "static_rectangles_current_scene",
	}

# Returns an advisory instruction to hide a world object ONLY after A1's
# *already committed* ledger is authoritative. NEVER trust a client response.
# Semantic fingerprint must be obtained from A1's canonical normalization, not
# invented by this A2 layer. The response has to match the persisted receipt.
static func after_durable_commit(
		intent: Dictionary, response: Dictionary, trusted_a1_snapshot: Dictionary,
		expected_fingerprint: String) -> Dictionary:
	if not _valid_intent(intent) or not _id(expected_fingerprint):
		return _error("INVALID_ARGUMENT")
	if not response.get("ok", false) or not response.get("code") in ["OK", "ALREADY_APPLIED"] 			or response.get("action_id") != intent.action_id:
		return _error("NOT_COMMITTED")
	if not trusted_a1_snapshot.get("completed_actions") is Dictionary 			or not trusted_a1_snapshot.get("state_revision") is int:
		return _error("UNVERIFIED_RECEIPT")
	var book: Dictionary = trusted_a1_snapshot.completed_actions
	if not book.has(intent.action_id):
		return _error("UNVERIFIED_RECEIPT")
	var entry = book[intent.action_id]
	if not Receipts.valid(intent.action_id, entry, int(trusted_a1_snapshot.state_revision)):
		return _error("UNVERIFIED_RECEIPT")
	if Receipts.fingerprint(entry) != expected_fingerprint:
		return _error("ACTION_CONFLICT")
	var record: Dictionary = Receipts.data(entry)
	if not _same_committed_object(record, intent):
		return _error("WRONG_OBJECT_RECEIPT")
	var response_data = response.get("data")
	if not response_data is Dictionary or response_data != record:
		return _error("UNVERIFIED_RECEIPT")
	if response.get("state_revision") != _receipt_revision(entry):
		return _error("UNVERIFIED_RECEIPT")
	return {
		"ok": true, "code": "OK",
		"can_hide_world_object": true,
		"scene_id": intent.scene_id, "object_id": intent.object_id,
		"action_id": intent.action_id, "reason": "verified_a1_durable_receipt",
	}

static func _same_committed_object(record: Dictionary, intent: Dictionary) -> bool:
	return record.size() == 6 and record.get("scene_id") == intent.scene_id 			and record.get("object_id") == intent.object_id 			and record.get("type_id") == intent.type_id 			and record.get("operation") == intent.operation 			and record.get("quantity") == 1 			and record.get("object_identity_sha256") == intent.object_identity_sha256

static func _receipt_revision(entry) -> int:
	if entry is Array:
		return int(entry[2]) if entry.size() == 5 else -1
	if entry is Dictionary and entry.get("result") is Dictionary:
		return int(entry.result.get("state_revision", -1))
	return -1

static func _valid_intent(intent: Dictionary) -> bool:
	if not intent.get("ok", false) or intent.get("needs_core_commit") != true 			or intent.get("hide_before_commit") != false or intent.get("quantity") != 1:
		return false
	for key in ["action_id", "scene_id", "object_id", "type_id", "object_identity_sha256"]:
		if not _id(intent.get(key)):
			return false
	return intent.get("operation") in [
		"collect_whole", "salvage_destroyed_structure",
		"break_structure", "transport_whole_to_processing",
	]

static func _operation(kind: String, state: String) -> String:
	match kind:
		"loot":
			return "collect_whole" if state == "loose" else ""
		"debris":
			return "collect_whole" if state == "destroyed" else ""
		"wall", "door":
			if state == "intact":
				return "break_structure"
			if state == "destroyed":
				return "salvage_destroyed_structure"
		"vehicle", "pole":
			return "transport_whole_to_processing" if state == "intact" else ""
		"vehicle_part":
			return "PART_EXTRACTION_FORBIDDEN"
	return ""

static func _id(value) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	# ASCII-only stable IDs: prevent embedded CR/LF, path separators and
	# escaped JSON identities that might diverge across the save ledger.
	for byte in value.to_utf8_buffer():
		if not ((byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) 				or (byte >= 48 and byte <= 57) or byte in [45, 46, 58, 95]):
			return false
	return true

static func _line_clear(start: Vector2, finish: Vector2, forbidden: Array[Rect2]) -> bool:
	for box in forbidden:
		if _closed_segment_intersects_rect(start, finish, box):
			return false
	return true

static func _closed_segment_intersects_rect(start: Vector2, finish: Vector2, rect: Rect2) -> bool:
	# Slab intersection including boundaries and an actor-radius buffer.
	var delta := finish - start
	var low := 0.0
	var high := 1.0
	for axis in [0, 1]:
		var a: float = start[axis]
		var direction: float = delta[axis]
		var minimum: float = rect.position[axis]
		var maximum: float = rect.end[axis]
		if absf(direction) <= 0.000000001:
			if a >= minimum and a <= maximum:
				continue
			return false
		var near: float = (minimum - a) / direction
		var far: float = (maximum - a) / direction
		if near > far:
			var saved := near
			near = far
			far = saved
		low = maxf(low, near)
		high = minf(high, far)
		if low > high:
			return false
	return high >= low

static func _error(code: String) -> Dictionary:
	return {"ok": false, "code": code}
