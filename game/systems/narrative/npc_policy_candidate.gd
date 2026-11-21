extends RefCounted
# A4-only PURE PROTOTYPE. No gameplay, Save or UI integration.
# Requires explicit, already-evaluated context instead of invented reputation thresholds.
# Stable IDs must be canonical; whitespace padding cannot represent another NPC.
const STATUSES := ["unknown", "contacted", "declined", "AWAITING_SUPPLIES", "joined"]
const ROLES := ["resident", "recruitable", "non_recruitable"]

static func valid_npc(npc) -> bool:
	if not npc is Dictionary:
		return false
	if not npc.get("id") is String or npc.id.strip_edges().is_empty() or npc.id != npc.id.strip_edges():
		return false
	if not npc.get("role") in ROLES:
		return false
	if not npc.get("status") in STATUSES:
		return false
	if not npc.get("consent") is bool or not npc.get("faction_leader") is bool:
		return false
	if not npc.get("scripted") is bool:
		return false
	if npc.status in ["AWAITING_SUPPLIES", "joined"] and not npc.consent:
		return false
	if npc.status in ["unknown", "contacted", "declined"] and npc.consent:
		return false
	# An active shelter resident is a role, not another unjoined candidate.
	if npc.role == "resident" and npc.status != "joined":
		return false
	if npc.status == "joined" and npc.role != "resident":
		return false
	if npc.role == "non_recruitable" and (npc.status == "joined" or npc.status == "AWAITING_SUPPLIES"):
		return false
	if npc.faction_leader and npc.status in ["AWAITING_SUPPLIES", "joined"]:
		return false
	return true

static func response(ok: bool, code: String, record: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "code": code, "record": record.duplicate(true)}

static func eligibility(npc, personal_reputation_high: bool, faction_reputation_high: bool) -> Dictionary:
	if not valid_npc(npc):
		return response(false, "INVALID_ARGUMENT")
	if npc.faction_leader or npc.role == "non_recruitable":
		return response(false, "NOT_RECRUITABLE")
	if npc.status == "joined":
		return response(false, "ALREADY_RECRUITED")
	if npc.status == "AWAITING_SUPPLIES":
		return response(false, "ALREADY_CONSENTED")
	if npc.status == "declined" and not (personal_reputation_high or faction_reputation_high):
		return response(false, "REPUTATION_REQUIRED")
	# High reputation only grants the ability to propose again;
	# it NEVER substitutes for the NPC's informed consent.
	return response(true, "ELIGIBLE", npc)

static func plan_contact(npc, personal_reputation_high: bool, faction_reputation_high: bool) -> Dictionary:
	var check: Dictionary = eligibility(npc, personal_reputation_high, faction_reputation_high)
	if not check.ok:
		return check
	var next: Dictionary = npc.duplicate(true)
	if next.status == "unknown" or next.status == "declined":
		next.status = "contacted"
	return response(true, "CONTACTED", next)

static func plan_consent(npc, accept: bool) -> Dictionary:
	if not valid_npc(npc):
		return response(false, "INVALID_ARGUMENT")
	if npc.faction_leader or npc.role == "non_recruitable":
		return response(false, "NOT_RECRUITABLE")
	if npc.status == "unknown" or npc.status == "declined":
		# A fresh contact must be permitted before reconsidering an explicit refusal.
		# For declined candidates plan_contact checks personal OR faction reputation.
		return response(false, "REQUIRES_CONTACT")
	if npc.status == "joined":
		return response(false, "ALREADY_RECRUITED")
	if npc.status == "AWAITING_SUPPLIES" and accept:
		# Already consenting is not another NPC decision/receipt.
		# Withdrawal remains legal before settlement (accept=false).
		return response(false, "ALREADY_CONSENTED")
	var next: Dictionary = npc.duplicate(true)
	next.consent = accept
	next.status = "AWAITING_SUPPLIES" if accept else "declined"
	return response(true, "CONSENT_ACCEPTED" if accept else "CONSENT_DECLINED", next)

static func plan_recruit(npc, food_ready: bool, housing_ready: bool) -> Dictionary:
	if not valid_npc(npc):
		return response(false, "INVALID_ARGUMENT")
	if npc.faction_leader or npc.role == "non_recruitable":
		return response(false, "NOT_RECRUITABLE")
	if npc.status == "joined":
		return response(false, "ALREADY_RECRUITED")
	if npc.status != "AWAITING_SUPPLIES" or not npc.consent:
		return response(false, "REQUIRES_CONSENT")
	if not food_ready:
		return response(false, "INSUFFICIENT_RESOURCES", npc)
	if not housing_ready:
		return response(false, "NEEDS_HOUSING", npc)
	var next: Dictionary = npc.duplicate(true)
	next.status = "joined"
	next.role = "resident"
	# This tentative output is NOT durable. A1 must atomically reserve/consume food
	# and commit this state with an exact historical receipt.
	return response(true, "RECRUIT_READY", next)

static func plan_group_expedition(participants, player_permission: bool, supplies_ready: bool, minimum_group_size: int) -> Dictionary:
	if not participants is Array or minimum_group_size < 2:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	if not player_permission:
		return {"ok": false, "code": "PERMISSION_REQUIRED"}
	if participants.size() < minimum_group_size:
		return {"ok": false, "code": "GROUP_TOO_SMALL"}
	if not supplies_ready:
		return {"ok": false, "code": "INSUFFICIENT_RESOURCES"}
	var ids: Array = []
	var seen: Dictionary = {}
	for npc in participants:
		if not valid_npc(npc) or npc.status != "joined" or npc.faction_leader or npc.role == "non_recruitable":
			return {"ok": false, "code": "UNAVAILABLE_PARTICIPANT"}
		if not npc.get("available_for_expedition") is bool or not npc.available_for_expedition:
			return {"ok": false, "code": "UNAVAILABLE_PARTICIPANT"}
		if seen.has(npc.id):
			return {"ok": false, "code": "DUPLICATE_PARTICIPANT"}
		seen[npc.id] = true
		ids.append(npc.id)
	ids.sort()
	# No teleport or simulation/reward side effects. A3 supplies the resources,
	# A1 commits; A2 updates world and A5 only observes status.
	return {"ok": true, "code": "EXPEDITION_READY", "resident_ids": ids}
