extends RefCounted

# Narrative-only P0 candidate. Does not activate/deactivate game capabilities,
# Q07 identity checks reject invalid/padded IDs to prevent false resident counts.
# award items, mutate story flags, or own the durable quest receipts.
const QUEST_IDS := ["Q01", "Q02", "Q03", "Q04", "Q05", "Q06", "Q07"]
const OPTIONAL_IDS := ["Q03", "Q04", "Q05", "Q06", "Q07"]
const SANDBOX_CAPABILITIES := ["shelter", "farm", "storage", "world_exploration"]
const LegacyNPC = preload("res://game/systems/narrative/npc_legacy_transition_candidate.gd")

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

# A4-only PURE bridge for the two legacy starter residents. It accepts the
# A1-authoritative, ALREADY-VALIDATED campaign residents.records snapshot,
# never a joined_resident_ids array supplied by a dialogue/UI.
# This helper cannot authenticate Save, completed_actions or food receipts.
# A1 must run CampaignModel.validate and use current revisions at commit.
static func completion_ready_legacy_q07(records, required_joined_count) -> Dictionary:
	if not records is Array or records.size() != LegacyNPC.LEGACY_IDS.size() \
			or not required_joined_count is int or required_joined_count <= 0:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var seen: Dictionary = {}
	var joined_ids: Array = []
	for record in records:
		if not LegacyNPC.valid_legacy(record) or seen.has(record.id):
			return {"ok": false, "code": "INVALID_ARGUMENT"}
		seen[record.id] = true
		if record.status == "joined":
			joined_ids.append(record.id)
	# Exact legacy roster, independent of array order. A1 validates the
	# authenticity of food_receipt_id and completed actions before this call.
	for id in LegacyNPC.LEGACY_IDS:
		if not seen.has(id):
			return {"ok": false, "code": "INVALID_ARGUMENT"}
	joined_ids.sort()
	return {"ok": true, "ready": joined_ids.size() >= required_joined_count,
		"joined_resident_ids": joined_ids}
