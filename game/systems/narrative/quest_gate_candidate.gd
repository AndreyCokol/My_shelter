extends RefCounted

# Narrative-only P0 candidate. Does not activate/deactivate game capabilities,
# Q07 identity checks reject invalid/padded IDs to prevent false resident counts.
# award items, mutate story flags, or own the durable quest receipts.
const QUEST_IDS := ["Q01", "Q02", "Q03", "Q04", "Q05", "Q06", "Q07"]
const OPTIONAL_IDS := ["Q03", "Q04", "Q05", "Q06", "Q07"]
const SANDBOX_CAPABILITIES := ["shelter", "farm", "storage", "world_exploration"]

static func is_known_quest(id: String) -> bool:
	return QUEST_IDS.has(id)

static func optional_quest(id: String) -> bool:
	return OPTIONAL_IDS.has(id)

static func narrative_gate_allows(capability: String, tracked_quest_ids) -> bool:
	if not tracked_quest_ids is Array:
		return false
	for id in tracked_quest_ids:
		if not id is String or not QUEST_IDS.has(id):
			return false
	# Only a narrative-gating assertion. A1/Core still validates world/food/
	# battle rules; A4 must never lock farm or G shelter behind a quest.
	return SANDBOX_CAPABILITIES.has(capability)

static func completion_ready(quest_id: String, facts) -> Dictionary:
	if not is_known_quest(quest_id) or not facts is Dictionary:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var key_by_quest: Dictionary = {
		"Q01": "first_enemy_defeated",
		"Q03": "planted",
		"Q04": "harvested",
		"Q05": "contacted",
		"Q06": "consented"
	}
	if quest_id == "Q02":
		if not facts.get("first_enemy_defeated") is bool or not facts.get("shelter_tutorial_visited") is bool:
			return {"ok": false, "code": "INVALID_ARGUMENT"}
		# Post-victory Q02 earns tutorial progress only.
		# Shelter itself is available to the player before Q01 or Q02.
		return {"ok": true, "ready": facts.first_enemy_defeated and facts.shelter_tutorial_visited}
	if quest_id == "Q07":
		var ids = facts.get("joined_resident_ids")
		var required = facts.get("required_joined_count")
		if not ids is Array or not required is int or required <= 0:
			return {"ok": false, "code": "INVALID_ARGUMENT"}
		var unique: Dictionary = {}
		for id in ids:
			if not id is String or id.strip_edges().is_empty() or id != id.strip_edges() or unique.has(id):
				return {"ok": false, "code": "INVALID_ARGUMENT"}
			unique[id] = true
		return {"ok": true, "ready": unique.size() >= required}
	var field: String = key_by_quest[quest_id]
	if not facts.get(field) is bool:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	return {"ok": true, "ready": facts[field]}
