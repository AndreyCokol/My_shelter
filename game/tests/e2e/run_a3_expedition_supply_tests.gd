extends SceneTree

const Quote = preload("res://game/systems/shelter/expedition_supply_quote_candidate.gd")
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

func reject(result: Dictionary, code: String, label: String) -> void:
	check(result == {"ok": false, "code": code}, label)

func run() -> void:
	var c := {"action_id": "qa-1", "expedition_proposal_id": "proposal-1",
		"destination_id": "qa-target", "slot_key": "qa-slot", "policy_version": "qa-only",
		"resident_ids": ["r2", "r1"], "minute": 10, "requested_departure_minute": 20, "valid_until_minute": 15,
		"revisions": {"inventory:player": 0, "inventory:storage": 0, "residents": 0, "world": 0}}
	# Synthetic amounts, not adopted economy.
	var p := {"version": "qa-only", "per_resident": {"crop.potato": 2, "material.salvage": 1},
		"source_containers": ["storage", "player"]}
	var items := [
		{"instance_id": "b", "type_id": "crop.potato", "container_id": "player", "quantity": 4},
		{"instance_id": "a", "type_id": "crop.potato", "container_id": "storage", "quantity": 5},
		{"instance_id": "c", "type_id": "material.salvage", "container_id": "storage", "quantity": 2},
		{"instance_id": "0", "type_id": "crop.potato", "container_id": "excluded", "quantity": 100}]
	var rows := [{"instance_id": "a", "resident_id": "r1", "quantity": 2},
		{"instance_id": "a", "resident_id": "r2", "quantity": 2},
		{"instance_id": "b", "resident_id": "r1", "quantity": 1}]
	var before := [c.duplicate(true), p.duplicate(true), items.duplicate(true), rows.duplicate(true)]
	var q := Quote.quote(c, p, items, rows)
	check(q.get("ok") == true, "valid quote")
	check(q.get("resident_ids") == ["r1", "r2"], "canonical group")
	check(q.get("item_requirements") == [{"type_id": "crop.potato", "quantity": 4}, {"type_id": "material.salvage", "quantity": 2}], "per-resident exact totals")
	check(q.get("selected_item_instances") == [
		{"instance_id": "a", "type_id": "crop.potato", "quantity": 1, "source_container": "storage"},
		{"instance_id": "b", "type_id": "crop.potato", "quantity": 3, "source_container": "player"},
		{"instance_id": "c", "type_id": "material.salvage", "quantity": 2, "source_container": "storage"}], "exact free instance allocation excluding other container")
	check(q.get("requires_atomic_dispatch_preflight") == true, "not dispatch receipt")
	check(q.get("reserved_food_excluded") == true, "reservations excluded")
	check([c, p, items, rows] == before, "no mutation")
	var reversed_items := items.duplicate(true)
	reversed_items.reverse()
	var reversed_rows := rows.duplicate(true)
	reversed_rows.reverse()
	var reversed_context := c.duplicate(true)
	reversed_context.resident_ids.reverse()
	check(q == Quote.quote(reversed_context, p, reversed_items, reversed_rows), "stable under input permutation")
	var short_rows := rows.duplicate(true)
	short_rows[2].quantity = 2
	reject(Quote.quote(c, p, items, short_rows), "INSUFFICIENT_RESOURCES", "reserved food cannot be spent")
	var bad_rows := rows.duplicate(true)
	bad_rows[0].quantity = 5
	reject(Quote.quote(c, p, items, bad_rows), "RESERVATION_OVERFLOW", "overbooked stack")
	bad_rows = rows.duplicate(true)
	bad_rows.append(rows[0].duplicate(true))
	reject(Quote.quote(c, p, items, bad_rows), "INVALID_RESERVATION", "duplicate resident instance row")
	bad_rows = rows.duplicate(true)
	bad_rows[0].instance_id = "missing"
	reject(Quote.quote(c, p, items, bad_rows), "INVALID_RESERVATION", "orphan reservation")
	var bad_items := items.duplicate(true)
	bad_items.append(items[0].duplicate(true))
	reject(Quote.quote(c, p, bad_items, rows), "INVALID_ITEM", "duplicate item instance")
	bad_items = items.duplicate(true)
	bad_items[2].quantity = 1
	reject(Quote.quote(c, p, bad_items, rows), "INSUFFICIENT_RESOURCES", "second requirement fails without partial allocation")
	for group in [[], ["r1"], ["r1", "r1"], ["r1", " r2"], ["r1", 2]]:
		var changed := c.duplicate(true)
		changed.resident_ids = group
		reject(Quote.quote(changed, p, items, rows), "INVALID_GROUP", "invalid group")
	reject(Quote.quote(c, {}, items, rows), "NEEDS_SUPPLY_POLICY", "missing policy")
	var wrong := p.duplicate(true)
	wrong.version = "old"
	reject(Quote.quote(c, wrong, items, rows), "NEEDS_SUPPLY_POLICY", "wrong version")
	for value in [0, -1, 1.5, true, 2147483647]:
		var invalid := p.duplicate(true)
		invalid.per_resident["crop.potato"] = value
		reject(Quote.quote(c, invalid, items, rows), "INVALID_POLICY", "invalid or overflowing rate")
	var time := c.duplicate(true)
	time.minute = 16
	reject(Quote.quote(time, p, items, rows), "INVALID_TIME", "expired quote window")
	time = c.duplicate(true)
	time.valid_until_minute = 21
	reject(Quote.quote(time, p, items, rows), "INVALID_TIME", "expiry beyond departure")
	var revision := c.duplicate(true)
	revision.revisions.erase("residents")
	reject(Quote.quote(revision, p, items, rows), "INVALID_CONTEXT", "missing resident revision")
	var empty_source := p.duplicate(true)
	empty_source.source_containers = []
	reject(Quote.quote(c, empty_source, items, rows), "NEEDS_SUPPLY_POLICY", "missing allowed sources")
	var no_storage := p.duplicate(true)
	no_storage.source_containers = ["player"]
	reject(Quote.quote(c, no_storage, items, rows), "INSUFFICIENT_RESOURCES", "excluded container unavailable")
	c.revisions.world = 1
	check(q.get("inventory_revisions_snapshot", {}).get("world") == 0, "quote evidence deep copied")

	c.revisions.world = 0
	var live := c.duplicate(true)
	var accepted := {"ok": true, "code": "SUPPLY_QUOTE_CURRENT", "requires_atomic_dispatch_preflight": true}
	check(Quote.revalidate(q, live, p, items, rows) == accepted, "fresh quote remains advisory")
	live.minute = 15
	check(Quote.revalidate(q, live, p, items, rows) == accepted, "inclusive deadline")
	live.minute = 16
	reject(Quote.revalidate(q, live, p, items, rows), "INVALID_TIME", "expired prior cannot proceed")
	live.minute = 9
	reject(Quote.revalidate(q, live, p, items, rows), "STALE_SUPPLY_QUOTE", "clock rollback")
	live.minute = 11
	live.revisions.world = 1
	reject(Quote.revalidate(q, live, p, items, rows), "STALE_SUPPLY_QUOTE", "changed trusted revision")
	live.revisions.world = 0
	for key in ["action_id", "expedition_proposal_id", "destination_id", "slot_key"]:
		var changed := live.duplicate(true)
		changed[key] = "other"
		reject(Quote.revalidate(q, changed, p, items, rows), "STALE_SUPPLY_QUOTE", "changed identity " + key)
	var changed_group := live.duplicate(true)
	changed_group.resident_ids = ["r1", "r3"]
	reject(Quote.revalidate(q, changed_group, p, items, rows), "STALE_SUPPLY_QUOTE", "changed residents")
	var changed_deadline := live.duplicate(true)
	changed_deadline.valid_until_minute = 16
	reject(Quote.revalidate(q, changed_deadline, p, items, rows), "STALE_SUPPLY_QUOTE", "deadline cannot be extended")
	var changed_policy := p.duplicate(true)
	changed_policy.per_resident["crop.potato"] = 1
	reject(Quote.revalidate(q, live, changed_policy, items, rows), "STALE_SUPPLY_QUOTE", "changed policy amounts")
	var changed_rows := rows.duplicate(true)
	changed_rows[0].quantity = 1
	reject(Quote.revalidate(q, live, p, items, changed_rows), "STALE_SUPPLY_QUOTE", "changed exact allocation despite unchanged revision")
	reject(Quote.revalidate(q, live, p, items, short_rows), "INSUFFICIENT_RESOURCES", "new reservation prevents reuse")
	var tampered := q.duplicate(true)
	tampered.selected_item_instances[0].quantity = 2
	reject(Quote.revalidate(tampered, live, p, items, rows), "STALE_SUPPLY_QUOTE", "altered allocation")
	reject(Quote.revalidate({}, live, p, items, rows), "INVALID_PRIOR_QUOTE", "missing prior")
	var live_permuted := live.duplicate(true)
	live_permuted.resident_ids.reverse()
	var prior_snapshot := q.duplicate(true)
	var live_snapshot := live_permuted.duplicate(true)
	check(Quote.revalidate(q, live_permuted, p, reversed_items, reversed_rows) == accepted, "canonical revalidation")
	check(q == prior_snapshot and live_permuted == live_snapshot and [c, p, items, rows] == before, "revalidation is nonmutating")
	print("A3 EXPEDITION SUPPLY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
