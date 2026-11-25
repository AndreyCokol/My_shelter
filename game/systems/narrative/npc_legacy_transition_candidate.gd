extends RefCounted
# A4-only PURE adapter for the two EXISTING schema3/schema4 legacy survivors.
# It does not change GameplayCommands, CoreSession, Save, actor authority or food.
# Only A1 can pass trustworthy high-reputation decisions from a committed state;
# a client supplied boolean is NOT authorization. Not suitable for new NPC rosters.
const NPC = preload("res://game/systems/narrative/npc_policy_candidate.gd")
const LEGACY_IDS := ["resident_1", "resident_2"]

static func valid_legacy(record) -> bool:
	if not record is Dictionary or not record.get("id") is String \
			or not LEGACY_IDS.has(record.id) or not record.get("status") in NPC.STATUSES \
			or not record.get("consent") is bool or not record.get("food_receipt_id") is String:
		return false
	# The authoritative A1 model additionally authenticates the historical
	# food receipt and the exact corresponding inventory reservations.
	if record.status == "joined":
		if not record.consent or record.food_receipt_id.is_empty():
			return false
	elif not record.food_receipt_id.is_empty():
		return false
	if record.status == "AWAITING_SUPPLIES" and not record.consent:
		return false
	if record.status in ["unknown", "contacted", "declined"] and record.consent:
		return false
	return true

static func _candidate(record: Dictionary) -> Dictionary:
	return {"id": record.id, "role": "resident" if record.status == "joined" else "recruitable",
		"scripted": true, "faction_leader": false, "status": record.status,
		"consent": record.consent, "available_for_expedition": false}

static func _denied(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func _project(record: Dictionary, outcome: Dictionary) -> Dictionary:
	if not outcome.get("ok", false):
		return _denied(str(outcome.get("code", "INVALID_STATE")))
	# A1 must verify the expected ID/status/revisions at transaction time.
	# A patch is a PROPOSAL, not a consent authorization or Save receipt.
	return {"ok": true, "code": outcome.code,
		"expected_id": record.id, "expected_status": record.status,
		"patch": {"status": outcome.record.status, "consent": outcome.record.consent}}

static func plan_contact(record, personal_reputation_high: bool, faction_reputation_high: bool) -> Dictionary:
	if not valid_legacy(record):
		return _denied("INVALID_ARGUMENT")
	return _project(record, NPC.plan_contact(_candidate(record),
		personal_reputation_high, faction_reputation_high))

static func plan_consent(record, npc_decision_accept: bool) -> Dictionary:
	if not valid_legacy(record):
		return _denied("INVALID_ARGUMENT")
	# npc_decision_accept MUST originate from A4 policy evaluated by A1
	# against authoritative NPC context, NEVER a raw UI accept flag.
	return _project(record, NPC.plan_consent(_candidate(record), npc_decision_accept))
