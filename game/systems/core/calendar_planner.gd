extends RefCounted

const Numbers = preload("res://game/state/json_numbers.gd")
const MAX_MINUTE: int = 9007199254740991
const MINUTE_EPSILON := 0.000000001

# Trusted domain adapters only. Provider returns all boundaries in (from, target],
# including derived ones (e.g. both maturity and spoilage), without side effects.
# Handler mutates only the candidate and returns {ok, events: Array}.
var provider: Callable
var handler: Callable
var _configured: bool = false

func configure(source: Callable, consumer: Callable) -> bool:
	if source.is_valid() != consumer.is_valid():
		return false
	provider = source
	handler = consumer
	_configured = source.is_valid()
	return true

static func valid_minute(value) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= MAX_MINUTE and value == floor(value)

func advance(candidate: Dictionary, target: int, reason: String) -> Dictionary:
	if _configured and (not provider.is_valid() or not handler.is_valid()):
		return {"ok": false, "code": "UNAVAILABLE"}
	var start: int = candidate.game_time_minutes
	if not valid_minute(target) or target < start:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var entries = provider.call(candidate.duplicate(true), start, target) if provider.is_valid() else []
	# A domain may refuse advancement while a persisted choice/combat gate is pending.
	if entries is Dictionary and entries.get("ok") == false:
		return {"ok": false, "code": "UNAVAILABLE"}
	if not entries is Array:
		return {"ok": false, "code": "INVALID_STATE"}
	var due: Array = []
	var ids: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary or not valid_minute(entry.get("minute")) or not valid_minute(entry.get("priority")) or not entry.get("entity_id") is String or entry.entity_id.is_empty() or not entry.get("interactive", false) is bool:
			return {"ok": false, "code": "INVALID_STATE"}
		entry = Numbers.normalize_numbers(entry.duplicate(true))
		var key := JSON.stringify([entry.minute, entry.priority, entry.entity_id])
		if ids.has(key) or entry.minute <= start or entry.minute > target:
			return {"ok": false, "code": "INVALID_STATE"}
		ids[key] = true
		due.append(entry)
	due.sort_custom(func(a, b):
		if a.minute != b.minute:
			return a.minute < b.minute
		if a.priority != b.priority:
			return a.priority < b.priority
		return a.entity_id < b.entity_id)
	var stop: int = target
	var interrupted: bool = false
	for entry in due:
		if entry.get("interactive", false):
			stop = int(entry.minute)
			interrupted = true
			break
	var drafts: Array = []
	for entry in due:
		if entry.minute > stop:
			break
		candidate.game_time_minutes = int(entry.minute)
		var result = handler.call(candidate, entry.duplicate(true))
		if not result is Dictionary or result.get("ok") != true or not result.get("events", []) is Array or candidate.game_time_minutes != entry.minute:
			return {"ok": false, "code": "INVALID_STATE"}
		for draft in result.get("events", []):
			if not draft is Dictionary:
				return {"ok": false, "code": "INVALID_STATE"}
			var timed: Dictionary = draft.duplicate(true)
			timed.game_minute = int(entry.minute)
			drafts.append(timed)
	candidate.game_time_minutes = stop
	var events: Array = []
	if stop != start:
		events.append({"event_type": "time_advanced", "payload": {"from_minute": start, "to_minute": stop, "reason": reason}})
	events.append_array(drafts)
	return {"ok": true, "data": {"actual_to_minute": stop, "interrupted": interrupted}, "events": events}
