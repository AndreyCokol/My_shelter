extends SceneTree

# Real A4 policy + real A3 quote/revalidate + A1 reservation aggregator.
# Synthetic trusted-state fixtures, NOT actual campaign dispatch or Save E2E.
const NPC = preload("res://game/systems/narrative/npc_policy_candidate.gd")
const Supply = preload("res://game/systems/shelter/expedition_supply_quote_candidate.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func resident(id: String) -> Dictionary:
	return {"id": id, "role": "resident", "scripted": false, "faction_leader": false,
		"status": "joined", "consent": true, "available_for_expedition": true}

func run() -> void:
	var party := [resident("r2"), resident("r1")]
	var plan := NPC.plan_group_expedition(party, true, true, 2)
	check(plan.ok and plan.resident_ids == ["r1", "r2"], "A4 canonical trusted group")
	var c := {"action_id": "qa-1", "expedition_proposal_id": "proposal-1",
		"destination_id": "qa-target", "slot_key": "qa-slot", "policy_version": "qa-only",
		"resident_ids": plan.get("resident_ids", []), "minute": 10,
		"requested_departure_minute": 20, "valid_until_minute": 15,
		"revisions": {"inventory:player": 0, "inventory:storage": 0, "residents": 0, "world": 0}}
	var p := {"version": "qa-only", "per_resident": {"crop.potato": 2, "material.salvage": 1},
		"source_containers": ["storage", "player"]}
	var items := [
		{"instance_id": "b", "type_id": "crop.potato", "container_id": "player", "quantity": 4},
		{"instance_id": "a", "type_id": "crop.potato", "container_id": "storage", "quantity": 5},
		{"instance_id": "c", "type_id": "material.salvage", "container_id": "storage", "quantity": 2}]
	var rows := [{"instance_id": "a", "resident_id": "r1", "quantity": 2},
		{"instance_id": "a", "resident_id": "r2", "quantity": 2},
		{"instance_id": "b", "resident_id": "r1", "quantity": 1}]
	var before := [party.duplicate(true), c.duplicate(true), p.duplicate(true), items.duplicate(true), rows.duplicate(true)]
	var q := Supply.quote(c, p, items, rows)
	check(q.ok and q.code == "SUPPLY_QUOTE_READY", "real A3 producer")
	if not q.ok:
		quit(1)
		return
	var q_before := q.duplicate(true)
	check(q.resident_ids == plan.resident_ids, "same canonical NPC identities")
	check(q.selected_item_instances == [
		{"instance_id": "a", "type_id": "crop.potato", "quantity": 1, "source_container": "storage"},
		{"instance_id": "b", "type_id": "crop.potato", "quantity": 3, "source_container": "player"},
		{"instance_id": "c", "type_id": "material.salvage", "quantity": 2, "source_container": "storage"}], "A1 reserved food excluded by A3")
	var bound := NPC.check_expedition_quote(party, true, 2, c, q)
	check(bound.ok and bound.code == "EXPEDITION_QUOTE_MATCHED" and bound.requires_atomic_dispatch_preflight, "real producer matches A4 boundary")
	check(Supply.revalidate(q, c, p, items, rows).code == "SUPPLY_QUOTE_CURRENT", "real revalidation still advisory")
	var live := c.duplicate(true)
	live.minute = 15
	check(NPC.check_expedition_quote(party, true, 2, live, q).ok, "A4 inclusive deadline")
	check(Supply.revalidate(q, live, p, items, rows).ok, "A3 inclusive deadline")
	live.minute = 16
	check(not NPC.check_expedition_quote(party, true, 2, live, q).ok, "A4 rejects expiry")
	check(not Supply.revalidate(q, live, p, items, rows).ok, "A3 rejects expiry")
	live.minute = 9
	check(not NPC.check_expedition_quote(party, true, 2, live, q).ok, "A4 rejects clock rollback")
	check(not Supply.revalidate(q, live, p, items, rows).ok, "A3 rejects clock rollback")
	live.minute = 11
	for key in ["action_id", "expedition_proposal_id", "destination_id", "slot_key"]:
		var changed := live.duplicate(true)
		changed[key] = "foreign"
		check(not NPC.check_expedition_quote(party, true, 2, changed, q).ok, "A4 rejects changed " + key)
		check(not Supply.revalidate(q, changed, p, items, rows).ok, "A3 rejects changed " + key)
	for key in live.revisions:
		var changed := live.duplicate(true)
		changed.revisions[key] = 1
		check(not NPC.check_expedition_quote(party, true, 2, changed, q).ok, "A4 revision drift " + key)
		check(not Supply.revalidate(q, changed, p, items, rows).ok, "A3 revision drift " + key)
	check(not NPC.check_expedition_quote(party, false, 2, live, q).ok, "valid supply quote cannot grant permission")
	var unavailable := party.duplicate(true)
	unavailable[0].available_for_expedition = false
	check(not NPC.check_expedition_quote(unavailable, true, 2, live, q).ok, "valid quote cannot make NPC available")
	check(not NPC.check_expedition_quote([party[0], party[0]], true, 2, live, q).ok, "duplicate resident denied")
	var replacement := [resident("r1"), resident("r3")]
	check(not NPC.check_expedition_quote(replacement, true, 2, live, q).ok, "same group size cannot replace identity")
	var short_rows := rows.duplicate(true)
	short_rows[2].quantity = 2
	check(not Supply.quote(live, p, items, short_rows).ok, "new reserve prevents new quote")
	check(not Supply.revalidate(q, live, p, items, short_rows).ok, "A3 protects prior quote despite unchanged revision")
	var changed_rows := rows.duplicate(true)
	changed_rows[0].quantity = 1
	check(not Supply.revalidate(q, live, p, items, changed_rows).ok, "changed allocation without revision is detected")
	var tampered := q.duplicate(true)
	tampered.selected_item_instances[0].quantity = 2
	check(NPC.check_expedition_quote(party, true, 2, live, tampered).ok, "A4 metadata match alone is NOT allocation verification")
	check(not Supply.revalidate(tampered, live, p, items, rows).ok, "A3 rejects tampered allocation")
	var changed_policy := p.duplicate(true)
	changed_policy.per_resident["crop.potato"] = 1
	check(not Supply.revalidate(q, live, changed_policy, items, rows).ok, "A3 detects changed rates without new policy ID")
	check([party, c, p, items, rows] == before and q == q_before, "all source inputs remain unmodified")
	print("A4 A3 EXPEDITION CONTRACT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
