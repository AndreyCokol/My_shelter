extends RefCounted
## A2-08: pure 2D-legacy <-> 3D-world coordinate adapter.
## No saved schema / SceneRouter changes. Godot Y is elevation; legacy
## 2D X,Y become 3D X,Z. All 3D distances are in metres.
const PIXELS_PER_METRE := 32.0
const WALL_HEIGHT_METRES := 2.4
const EYE_OFFSET_FROM_BODY_CENTER_METRES := 0.7

static func valid_legacy_point(point: Vector2) -> bool:
	return point.is_finite()

static func legacy_to_3d(point: Vector2, elevation: float = 0.0) -> Vector3:
	if not valid_legacy_point(point) or not is_finite(elevation):
		return Vector3(INF, INF, INF)
	return Vector3(point.x / PIXELS_PER_METRE, elevation, point.y / PIXELS_PER_METRE)

static func world_to_legacy(point: Vector3) -> Vector2:
	if not point.is_finite():
		return Vector2(INF, INF)
	return Vector2(point.x * PIXELS_PER_METRE, point.z * PIXELS_PER_METRE)

static func box_from_legacy_rect(rect: Rect2, height: float = WALL_HEIGHT_METRES) -> Dictionary:
	if not rect.is_finite() or not rect.has_area() or not is_finite(height) or height <= 0.0:
		return {"ok": false, "code": "INVALID_GEOMETRY"}
	return {
		"ok": true,
		"position": legacy_to_3d(rect.get_center(), height * 0.5),
		"size": Vector3(rect.size.x / PIXELS_PER_METRE, height, rect.size.y / PIXELS_PER_METRE),
	}

static func topdown_rotation() -> Vector3:
	# Camera3D looks down its local -Z; rotating -90 degrees around X
	# points exactly down world -Y, with screen-up along world -Z.
	return Vector3(-PI * 0.5, 0.0, 0.0)

static func topdown_origin(actor_position: Vector3, altitude: float = 22.0) -> Vector3:
	if not actor_position.is_finite() or not is_finite(altitude) or altitude <= 0.0:
		return Vector3(INF, INF, INF)
	return Vector3(actor_position.x, actor_position.y + altitude, actor_position.z)

static func fps_origin(actor_position: Vector3) -> Vector3:
	if not actor_position.is_finite():
		return Vector3(INF, INF, INF)
	return Vector3(actor_position.x, actor_position.y + EYE_OFFSET_FROM_BODY_CENTER_METRES, actor_position.z)

static func yaw_for_legacy_facing(facing: Vector2) -> float:
	if not facing.is_finite() or facing.length_squared() <= 0.000001:
		return 0.0
	var normalized := facing.normalized()
	return -atan2(normalized.x, -normalized.y)

static func facing_for_yaw(yaw: float) -> Vector2:
	if not is_finite(yaw):
		return Vector2.ZERO
	return Vector2(-sin(yaw), -cos(yaw))

static func world_motion(input_2d: Vector2, yaw: float, fps_mode: bool) -> Vector3:
	if not input_2d.is_finite() or not is_finite(yaw):
		return Vector3.ZERO
	var motion := input_2d.limit_length(1.0)
	if fps_mode:
		var forward := facing_for_yaw(yaw)
		var right := Vector2(-forward.y, forward.x)
		motion = right * motion.x - forward * motion.y
	return Vector3(motion.x, 0.0, motion.y)
