extends RefCounted

signal committed(result: Dictionary)
signal state_loaded

const PauseRegistry = preload("res://game/systems/core/pause_registry.gd")
var pauses = PauseRegistry.new()
var _state: Dictionary = initial_state()
var _busy: bool = false
var _recovery_token: int = 0

static func initial_state() -> Dictionary:
	return {"schema_version": 1, "scope": "core-bootstrap", "state_revision": 0, "counter": 0, "completed_actions": {}}

func get_snapshot() -> Dictionary:
	return _state.duplicate(true)

static func valid_integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 0 and value <= 9007199254740991

static func validate(state: Dictionary) -> bool:
	if state.get("schema_version") != 1 or state.get("scope") != "core-bootstrap":
		return false
	if not valid_integer(state.get("counter")) or not valid_integer(state.get("state_revision")) or not state.get("completed_actions") is Dictionary:
		return false
	for action_id in state.completed_actions:
		var receipt = state.completed_actions[action_id]
		if not action_id is String or action_id.is_empty() or not receipt is Dictionary:
			return false
		if not receipt.get("fingerprint") is String or not receipt.get("result") is Dictionary:
			return false
		var result: Dictionary = receipt.result
		if result.get("action_id") != action_id or result.get("ok") != true or result.get("code") != "OK":
			return false
		if not valid_integer(result.get("state_revision")) or result.state_revision > state.state_revision:
			return false
		if not result.get("data") is Dictionary:
			return false
	return true

func load_checkpoint(store, use_backup: bool = false) -> Dictionary:
	if _busy:
		return _result(false, "UNAVAILABLE", "")
	_busy = true
	var token: int = pauses.acquire_pause("load")
	var loaded: Dictionary = store.read_checkpoint(store.path + ".bak" if use_backup else "")
	if not loaded.ok or not validate(loaded.get("state", {})):
		pauses.release_pause(token)
		_busy = false
		return _result(false, "INVALID_STATE", "")
	# Explicit recovery preserves damaged primary and restores selected backup.
	if use_backup and not store.restore_checkpoint(loaded.state):
		pauses.release_pause(token)
		_busy = false
		return _result(false, "SAVE_FAILED", "")
	# One root swap after all validation. Domain validators join here in G1b.
	_state = loaded.state.duplicate(true)
	if _recovery_token != 0:
		pauses.release_pause(_recovery_token)
		_recovery_token = 0
	pauses.release_pause(token)
	state_loaded.emit()
	_busy = false
	return _result(true, "OK", "")

# Internal contract fixture, NOT a gameplay reward/inventory API.
func execute(request: Dictionary, store) -> Dictionary:
	var action_id = request.get("action_id", "")
	var payload = request.get("payload", {})
	if not action_id is String or action_id.is_empty() or not payload is Dictionary:
		return _result(false, "INVALID_ARGUMENT", "")
	if request.get("command_type") != "core.increment" or not valid_integer(payload.get("amount")) or payload.amount <= 0:
		return _result(false, "INVALID_ARGUMENT", action_id)
	var context = request.get("context", {})
	if not context is Dictionary:
		return _result(false, "INVALID_ARGUMENT", action_id)
	var actor = context.get("actor_id", "")
	if not actor is String or actor.is_empty():
		return _result(false, "INVALID_ARGUMENT", action_id)
	# Only meaningful fields of this typed command participate; JSON key order,
	# scene and optimistic revisions are transport context.
	var fingerprint := JSON.stringify(["core.increment", actor, int(payload.amount)]).sha256_text()
	if _recovery_token != 0 or _busy:
		return _result(false, "UNAVAILABLE", action_id)
	if _state.completed_actions.has(action_id):
		var receipt: Dictionary = _state.completed_actions[action_id]
		if receipt.fingerprint != fingerprint:
			return _result(false, "ACTION_CONFLICT", action_id)
		var replay: Dictionary = receipt.result.duplicate(true)
		replay.code = "ALREADY_APPLIED"
		return replay
	if pauses.is_paused():
		return _result(false, "PAUSED", action_id)
	_busy = true
	var tentative := _state.duplicate(true)
	tentative.counter += int(payload.amount)
	tentative.state_revision += 1
	var result := _result(true, "OK", action_id)
	result.state_revision = tentative.state_revision
	result.data = {"counter": tentative.counter}
	tentative.completed_actions[action_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	if not validate(tentative):
		_busy = false
		return _result(false, "INVALID_STATE", action_id)
	var written: Dictionary = store.write_checkpoint(tentative, validate)
	if not written.get("committed", false):
		_busy = false
		return _result(false, "SAVE_FAILED", action_id)
	if written.get("recover", false):
		_recovery_token = pauses.acquire_pause("recovery")
		_busy = false
		return _result(false, "UNAVAILABLE", action_id)
	_state = tentative
	committed.emit(result.duplicate(true))
	_busy = false
	return result

func _result(ok: bool, code: String, action_id: String) -> Dictionary:
	return {"ok": ok, "code": code, "action_id": action_id, "state_revision": _state.state_revision, "data": {}, "message_key": "core." + code.to_lower()}
