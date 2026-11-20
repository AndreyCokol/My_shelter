extends RefCounted

# A4-04 PURE CANDIDATE. Identity/chronicle are future DTO helpers only.
# No RNG, gameplay actions, Save migration, trait multipliers or UI effects.
const MAX_EXACT_JSON_INT: int = 9007199254740991
const FACT_KINDS := ["met", "helped", "conflict", "friendship", "trained", "injury", "expedition_return"]

static func _key(value) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _minute(value) -> bool:
	return value is int and value >= 0 and value <= MAX_EXACT_JSON_INT

static func generated_id(generator_version, world_seed, region_id, spawn_key) -> Dictionary:
	if not _minute(generator_version) or generator_version == 0 or not _minute(world_seed):
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	if not _key(region_id) or not _key(spawn_key):
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	# Stable source identity is independent of camera mode, loaded scene-tree
	# index, currently active NPC nodes and runtime frame count.
	var canonical: String = JSON.stringify(["npc.generated.v1", generator_version, world_seed, region_id, spawn_key])
	return {"ok": true, "npc_id": "npc.generated." + canonical.sha256_text()}

static func scripted_id(script_key) -> Dictionary:
	if not _key(script_key):
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	# Keep full script key without lossy abbreviations. Story roster owns keys.
	return {"ok": true, "npc_id": "npc.scripted." + JSON.stringify([script_key]).sha256_text()}

static func relationship_id(left, right) -> Dictionary:
	if not _key(left) or not _key(right) or left == right:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var members: Array = [left, right]
	members.sort()
	return {"ok": true, "relation_id": "npc.relation." + JSON.stringify(members).sha256_text(),
		"member_ids": members}

static func fresh_chronicle(npc_id) -> Dictionary:
	if not _key(npc_id):
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	return {"ok": true, "code": "CREATED", "record": {"npc_id": npc_id, "facts": []}}

static func _valid_fact(fact) -> bool:
	return fact is Dictionary and fact.size() == 4 and _key(fact.get("event_id")) \
		and _minute(fact.get("minute")) and fact.get("kind") in FACT_KINDS \
		and _key(fact.get("subject_id"))

static func _valid_chronicle(record) -> bool:
	if not record is Dictionary or record.size() != 2 or not _key(record.get("npc_id")) \
			or not record.get("facts") is Array:
		return false
	var seen: Dictionary = {}
	for entry in record.facts:
		if not _valid_fact(entry) or seen.has(entry.event_id):
			return false
		seen[entry.event_id] = true
	return true

static func add_fact(record, fact) -> Dictionary:
	if not _valid_chronicle(record) or not _valid_fact(fact):
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var copy: Dictionary = record.duplicate(true)
	for past in copy.facts:
		if past.event_id == fact.event_id:
			if past == fact:
				return {"ok": true, "code": "ALREADY_APPLIED", "record": copy}
			return {"ok": false, "code": "ACTION_CONFLICT"}
	copy.facts.append(fact.duplicate(true))
	# Stable order on the same clock minute, independent of network/region
	# observation order. This is not a domain event dispatcher.
	copy.facts.sort_custom(func(a, b):
		if a.minute == b.minute:
			return a.event_id < b.event_id
		return a.minute < b.minute)
	return {"ok": true, "code": "ADDED", "record": copy}
