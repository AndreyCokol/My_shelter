extends RefCounted

# Persisted receipt v1. An array avoids repeating "action_id", "ok", "code",
# "state_revision" and long JSON property names for each successful action.
# [format, semantic_sha256, original_revision, response_data, message_key]
# Legacy {"fingerprint": ..., "result": ...} remains readable and replayable.
const FORMAT: int = 1

static func pack(fingerprint: String, committed_result: Dictionary) -> Array:
	return [FORMAT, fingerprint, int(committed_result.state_revision), committed_result.data.duplicate(true), str(committed_result.message_key)]

static func fingerprint(entry) -> String:
	if entry is Array and entry.size() == 5 and entry[0] == FORMAT and entry[1] is String:
		return entry[1]
	if entry is Dictionary and entry.get("fingerprint") is String:
		return entry.fingerprint
	return ""

static func replay(action_id: String, entry) -> Dictionary:
	if entry is Array:
		return {"ok": true, "code": "ALREADY_APPLIED", "action_id": action_id,
			"state_revision": int(entry[2]), "data": entry[3].duplicate(true),
			"message_key": entry[4]}
	var response: Dictionary = entry.result.duplicate(true)
	response.code = "ALREADY_APPLIED"
	return response

static func valid(action_id, entry, max_revision, require_message_key: bool = false) -> bool:
	if not action_id is String or action_id.is_empty() or not _valid_revision(max_revision, max_revision):
		return false
	if entry is Array:
		return entry.size() == 5 and entry[0] == FORMAT and entry[1] is String and not entry[1].is_empty() and _valid_revision(entry[2], max_revision) and entry[3] is Dictionary and entry[4] is String and not entry[4].is_empty()
	if not entry is Dictionary or not entry.get("fingerprint") is String or not entry.get("result") is Dictionary:
		return false
	var result: Dictionary = entry.result
	if result.get("action_id") != action_id or result.get("ok") != true or result.get("code") != "OK" or not _valid_revision(result.get("state_revision"), max_revision) or not result.get("data") is Dictionary:
		return false
	if require_message_key and not result.get("message_key") is String:
		return false
	return true

static func has_legacy(book: Dictionary) -> bool:
	for entry in book.values():
		if entry is Dictionary:
			return true
	return false

# Converts only canonical historical success receipts. Non-canonical valid
# legacy receipts remain intact, so no extra response fields are discarded.
# Call on a tentative state: never rewrite the live state before durable commit.
static func compact_canonical_legacy(book: Dictionary, max_revision: int) -> void:
	for action_id in book:
		var old = book[action_id]
		if not old is Dictionary or not valid(action_id, old, max_revision, true):
			continue
		var result: Dictionary = old.result
		if result.size() != 6 or result.message_key != "core.ok":
			continue
		var canonical := true
		for required in ["ok", "code", "action_id", "state_revision", "data", "message_key"]:
			if not result.has(required):
				canonical = false
				break
		if canonical:
			book[action_id] = pack(old.fingerprint, result)

static func _valid_revision(value, max_revision) -> bool:
	if not (value is int or value is float) or not (max_revision is int or max_revision is float):
		return false
	return is_finite(float(value)) and is_finite(float(max_revision)) and value >= 0 and value <= 9007199254740991 and value == floor(float(value)) and value <= max_revision
