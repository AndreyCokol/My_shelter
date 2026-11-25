extends RefCounted
## A2-01 deterministic 2D locomotion envelope.
## Caller owns CharacterBody2D.move_and_slide, world collisions, water zones
## and InputMap binding; this module NEVER disables collisions or teleports.
## Jump here is strictly a VFX arc; crossing raised geometry requires the
## separately approved 3D world and independent A5 physics/navigation.
const WALK_SPEED := 115.0
const RUN_SPEED := 165.0
const SWIM_SPEED := 68.0
const DODGE_SPEED := 320.0
const JUMP_DURATION := 0.45
const JUMP_VISUAL_HEIGHT := 18.0

static func step(
		input_direction: Vector2, facing: Vector2,
		run_pressed: bool, jump_pressed: bool, in_water: bool,
		dodge_remaining: float, jump_remaining: float, delta: float
) -> Dictionary:
	if not input_direction.is_finite() or not facing.is_finite() 			or not is_finite(dodge_remaining) or dodge_remaining < 0.0 			or not is_finite(jump_remaining) or jump_remaining < 0.0 			or not is_finite(delta) or delta < 0.0 or delta > 1.0:
		return {"ok": false, "code": "INVALID_MOVEMENT_INPUT"}
	if input_direction.length() > 1.000001 or facing.length() > 1.000001:
		return {"ok": false, "code": "INVALID_MOVEMENT_INPUT"}
	# Water wins over a dodge that started just before immersion. This
	# prevents a 320 px/s land dash crossing real non-solid flooded zones.
	if in_water:
		return {
			"ok": true, "code": "OK",
			"mode": "swim" if input_direction.length_squared() > 0.01 else "float",
			"velocity": input_direction * SWIM_SPEED,
			"jump_remaining": 0.0, "visual_height": 0.0,
		}
	if dodge_remaining > 0.0:
		return {
			"ok": true, "code": "OK", "mode": "dodge",
			"velocity": facing.normalized() * DODGE_SPEED,
			"jump_remaining": 0.0, "visual_height": 0.0,
		}
	var remaining := jump_remaining
	if jump_pressed and remaining <= 0.0:
		remaining = JUMP_DURATION
	remaining = maxf(0.0, remaining - delta)
	var speed := RUN_SPEED if run_pressed else WALK_SPEED
	var mode := "run" if run_pressed else "walk"
	if input_direction.length_squared() <= 0.01:
		mode = "idle"
	if remaining > 0.0:
		mode = "jump"
	var progress: float = 1.0 - remaining / JUMP_DURATION
	var visual_height := sin(PI * progress) * JUMP_VISUAL_HEIGHT if remaining > 0.0 else 0.0
	return {
		"ok": true, "code": "OK", "mode": mode,
		"velocity": input_direction * speed,
		"jump_remaining": remaining, "visual_height": visual_height,
	}
