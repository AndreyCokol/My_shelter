extends RefCounted

signal committed(result: Dictionary)
signal state_loaded

const JsonNumbers = preload("res://game/state/json_numbers.gd")
const EventBus = preload("res://game/systems/core/event_bus.gd")
const PauseRegistry = preload("res://game/systems/core/pause_registry.gd")
var pauses = PauseRegistry.new()
var events = EventBus.new()
var _load_serial: int = 0
var _state: Dictionary = initial_state()
var _busy: bool = false
var _recovery_token: int = 0
var _domain_owner: RefCounted # Retain planner/normalizer lifetime without a session cycle.
var _state_validator: Callable = validate
var _normalizer: Callable = _normalize_core
var _planner: Callable = _plan_core
var runtime_required: bool = false
var runtime_preparer: Callable # Trusted staged runtime adapter; never serialized.

func _init(start: Dictionary = {}, validator: Callable = Callable(), normalizer: Callable = Callable(), planner: Callable = Callable()) -> void:
	if not start.is_empty():
		_state = start.duplicate(true)
	if validator.is_valid():
		_state_validator = validator
	if normalizer.is_valid():
		_normalizer = normalizer
	if planner.is_valid():
		_planner = planner
	_state = JsonNumbers.normalize_numbers(_state)

static func _normalize_core(request: Dictionary) -> Dictionary:
	var payload = request.get("payload", {})
	if request.get("command_type") != "core.increment" or not payload is Dictionary or not valid_integer(payload.get("amount")) or payload.amount <= 0:
		return {"ok": false}
	return {"ok": true, "payload": {"amount": int(payload.amount)}}

static func _plan_core(tentative: Dictionary, request: Dictionary) -> Dictionary:
	tentative.counter += int(request.payload.amount)
	return {"ok": true, "data": {"counter": tentative.counter}}


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
	if not loaded.ok or not _state_validator.call(loaded.get("state", {})):
		pauses.release_pause(token)
		_busy = false
		return _result(false, "INVALID_STATE", "")
	var ticket := _prepare_runtime(loaded.state, "load")
	if not ticket.get("ok", false):
		pauses.release_pause(token)
		_busy = false
		return _result(false, "UNAVAILABLE", "")
	# Explicit recovery preserves damaged primary and restores selected backup.
	if use_backup and not store.restore_checkpoint(loaded.state):
		_discard_runtime(ticket)
		pauses.release_pause(token)
		_busy = false
		return _result(false, "SAVE_FAILED", "")
	# One root swap after all validation. Domain validators join here in G1b.
	_state = loaded.state.duplicate(true)
	if not _install_runtime(ticket):
		_ensure_recovery()
		pauses.release_pause(token)
		_busy = false
		return _result(false, "UNAVAILABLE", "")
	if _recovery_token != 0:
		pauses.release_pause(_recovery_token)
		_recovery_token = 0
	pauses.release_pause(token)
	events.reset_history()
	_load_serial += 1
	_publish_events([{"event_type": "state_loaded", "payload": {"schema_version": _state.schema_version, "state_revision": _state.state_revision}}], "load:%d" % _load_serial)
	state_loaded.emit()
	_busy = false
	return _result(true, "OK", "")

# Shared transactional executor; its default planner is only a bootstrap fixture.
func execute(request: Dictionary, store) -> Dictionary:
	var action_id = request.get("action_id", "")
	var payload = request.get("payload", {})
	if not action_id is String or action_id.is_empty() or not payload is Dictionary:
		return _result(false, "INVALID_ARGUMENT", "")
	var normalized: Dictionary = _normalizer.call(request)
	if not normalized.get("ok", false):
		return _result(false, "INVALID_ARGUMENT", action_id)
	var context = request.get("context", {})
	if not context is Dictionary:
		return _result(false, "INVALID_ARGUMENT", action_id)
	var actor = context.get("actor_id", "")
	if not actor is String or actor.is_empty():
		return _result(false, "INVALID_ARGUMENT", action_id)
	# Only meaningful fields of this typed command participate; JSON key order,
	# scene and optimistic revisions are transport context.
	var fingerprint := JSON.stringify([request.command_type, actor, normalized.payload]).sha256_text()
	if _recovery_token != 0 or _busy:
		return _result(false, "UNAVAILABLE", action_id)
	if _state.completed_actions.has(action_id):
		var receipt: Dictionary = _state.completed_actions[action_id]
		if receipt.fingerprint != fingerprint:
			return _result(false, "ACTION_CONFLICT", action_id)
		var replay: Dictionary = receipt.result.duplicate(true)
		replay.code = "ALREADY_APPLIED"
		return replay
	if pauses.is_paused() and request.command_type != "session.save":
		return _result(false, "PAUSED", action_id)
	_busy = true
	var tentative := _state.duplicate(true)
	var typed_request := request.duplicate(true)
	typed_request.payload = normalized.payload
	var planned: Dictionary = _planner.call(tentative, typed_request)
	if not planned.get("ok", false):
		_busy = false
		var failed := _result(false, planned.get("code", "INVALID_STATE"), action_id)
		failed.data = planned.get("data", {}).duplicate(true)
		return failed
	tentative = JsonNumbers.normalize_numbers(tentative)
	tentative.state_revision += 1
	var result := _result(true, "OK", action_id)
	result.state_revision = tentative.state_revision
	result.data = planned.get("data", {}).duplicate(true)
	tentative.completed_actions[action_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	if not _state_validator.call(tentative):
		_busy = false
		return _result(false, "INVALID_STATE", action_id)
	var drafts = planned.get("events", [])
	if not _valid_drafts(drafts):
		_busy = false
		return _result(false, "INVALID_STATE", action_id)
	var ticket := _prepare_runtime(tentative, "command")
	if not ticket.get("ok", false):
		_busy = false
		return _result(false, "UNAVAILABLE", action_id)
	var written: Dictionary = store.write_checkpoint(tentative, _state_validator)
	if not written.get("committed", false):
		_discard_runtime(ticket)
		_busy = false
		return _result(false, "SAVE_FAILED", action_id)
	if written.get("recover", false):
		_discard_runtime(ticket)
		_ensure_recovery()
		_busy = false
		return _result(false, "UNAVAILABLE", action_id)
	_state = tentative
	if not _install_runtime(ticket):
		_ensure_recovery()
		_busy = false
		return _result(false, "UNAVAILABLE", action_id)
	_publish_events(drafts, action_id)
	committed.emit(result.duplicate(true))
	_busy = false
	return result

func _result(ok: bool, code: String, action_id: String) -> Dictionary:
	return {"ok": ok, "code": code, "action_id": action_id, "state_revision": _state.state_revision, "data": {}, "message_key": "core." + code.to_lower()}

# Trusted runtime hook for the calendar; never exposed as a player payload.
# It uses the same serialization/validation barrier but does not write each frame.
func apply_runtime(plan: Callable, event_factory: Callable = Callable()) -> bool:
	if _busy or _recovery_token != 0 or pauses.is_paused():
		return false
	_busy = true
	var tentative := _state.duplicate(true)
	if not plan.call(tentative):
		_busy = false
		return false
	tentative = JsonNumbers.normalize_numbers(tentative)
	tentative.state_revision += 1
	var drafts: Array = event_factory.call(_state.duplicate(true), tentative.duplicate(true)) if event_factory.is_valid() else []
	if not _valid_drafts(drafts) or not _state_validator.call(tentative):
		_busy = false
		return false
	_state = tentative
	_publish_events(drafts, "runtime:%d" % _state.state_revision)
	_busy = false
	return true

func _prepare_runtime(candidate: Dictionary, reason: String) -> Dictionary:
	if runtime_preparer.is_valid():
		return runtime_preparer.call(candidate.duplicate(true), reason)
	if runtime_required:
		return {"ok": false}
	return {"ok": true}

static func _discard_runtime(ticket: Dictionary) -> void:
	var discard: Callable = ticket.get("discard", Callable())
	if discard.is_valid():
		discard.call()

static func _install_runtime(ticket: Dictionary) -> bool:
	var install: Callable = ticket.get("install", Callable())
	return bool(install.call()) if install.is_valid() else true

func _ensure_recovery() -> void:
	if _recovery_token == 0:
		_recovery_token = pauses.acquire_pause("recovery")

func is_busy() -> bool:
	return _busy

static func _valid_drafts(drafts) -> bool:
	if not drafts is Array:
		return false
	for draft in drafts:
		if not draft is Dictionary or not (draft.get("event_type") is String or draft.get("event_type") is StringName) or str(draft.event_type).is_empty() or not draft.get("payload") is Dictionary:
			return false
	return true

func _publish_events(drafts: Array, action_id: String) -> void:
	for i in range(drafts.size()):
		var draft: Dictionary = drafts[i]
		events.publish_after_commit({
			"event_id": "%s:%s:%d" % [_state.get("save_id", _state.scope), action_id.sha256_text(), i],
			"event_type": str(draft.event_type), "action_id": action_id,
			"game_minute": _state.get("game_time_minutes", 0),
			"state_revision": _state.state_revision, "payload": JsonNumbers.normalize_numbers(draft.payload)})
