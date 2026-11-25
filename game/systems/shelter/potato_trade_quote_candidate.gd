extends RefCounted

# A3-only proposal. Caller MUST supply authoritative, validated snapshot,
# free quantities aggregated by A1, and explicitly versioned potato rates.
# A quote is NOT authorization, inventory preflight, or a durable receipt.
const Camp = preload("res://game/systems/world/camp_network.gd")
const POTATO := "crop.potato"
const MAX_UNITS := 2147483647
const MAX_MINUTE := 2147483647

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= minimum and value <= maximum and value == floor(value)

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value == value.strip_edges()

# No fallback to old Camp.reward or Camp.price: those are system coins.
# This candidate retains existing market schedule/limits; price policy is injected.
static func quote(kind: String, faction_id: String, requested_day: int, snapshot: Dictionary, ratebook: Dictionary) -> Dictionary:
	if kind not in ["contract", "buy"] or not Camp.FACTIONS.has(faction_id):
		return _fail("INVALID_ARGUMENT")
	if not _whole(snapshot.get("minute"), 0, MAX_MINUTE) or not _whole(snapshot.get("seed"), 0, MAX_UNITS):
		return _fail("INVALID_SNAPSHOT")
	if snapshot.get("actor_id") != "player" or not _id(snapshot.get("slot_key")) or not _id(snapshot.get("ruleset_version")) or not _id(snapshot.get("action_id")):
		return _fail("INVALID_SNAPSHOT")
	if snapshot.get("scene_id") != "louvre":
		return _fail("UNAVAILABLE")
	var network: Variant = snapshot.get("network")
	var minute := int(snapshot.minute)
	if not Camp.valid_record(network, minute):
		return _fail("INVALID_SNAPSHOT")
	var schedule := Camp.schedule(minute, int(snapshot.seed))
	var day := int(schedule.day)
	if requested_day != day:
		return _fail("UNAVAILABLE")
	if kind == "contract":
		if not schedule.active or schedule.faction != faction_id or network.last_contract_day == day:
			return _fail("UNAVAILABLE")
	else:
		# Preserve legacy buy gate: reputation + one purchase/faction/day;
		# don't silently introduce a new market opening-hours product rule.
		if not network.reputation.has(faction_id) or network.last_trade.get(faction_id, -1) == day:
			return _fail("UNAVAILABLE")
	if ratebook.get("currency_domain") != "potato" or ratebook.get("ruleset_version") != snapshot.ruleset_version:
		return _fail("RATEBOOK_REQUIRED")
	var rates: Variant = ratebook.get("factions")
	if not rates is Dictionary or not rates.get(faction_id) is Dictionary:
		return _fail("RATEBOOK_REQUIRED")
	var row: Dictionary = rates[faction_id]
	var rate_key := "contract_reward_potato" if kind == "contract" else "buy_cost_potato"
	if not _whole(row.get(rate_key), 1, MAX_UNITS):
		return _fail("INVALID_RATE")
	var rate := int(row[rate_key])
	var definition: Dictionary = Camp.FACTIONS[faction_id]
	var debit_type: String = definition.request if kind == "contract" else POTATO
	var credit_type: String = POTATO if kind == "contract" else definition.goods
	var debit_qty: int = int(definition.quantity) if kind == "contract" else rate
	var credit_qty: int = rate if kind == "contract" else int(definition.goods_quantity)
	var free: Variant = snapshot.get("free_quantity_by_type")
	if not free is Dictionary:
		return _fail("INVALID_SNAPSHOT")
	for key in free:
		if not _id(key) or not _whole(free[key], 0, MAX_UNITS):
			return _fail("INVALID_SNAPSHOT")
	if int(free.get(debit_type, 0)) < debit_qty:
		return _fail("INSUFFICIENT_FREE_ITEMS")
	var revisions: Variant = snapshot.get("revisions")
	if not revisions is Dictionary:
		return _fail("INVALID_SNAPSHOT")
	for key in ["inventory:player", "inventory:storage", "residents", "world", "scene", "wallet"]:
		if not revisions.has(key):
			return _fail("INVALID_SNAPSHOT")
	for key in revisions:
		if not _id(key) or not _whole(revisions[key], 0, MAX_UNITS):
			return _fail("INVALID_SNAPSHOT")
	# Even potato-for-potato contracts return two gross legs; never net away
	# the debit (reserved stacks and actual receipt allocation still matter).
	return {"ok": true, "quote_version": 2, "currency_domain": "potato",
		"kind": kind, "faction_id": faction_id, "day": day,
		"minute": minute, "seed": int(snapshot.seed), "scene_id": snapshot.scene_id,
		"slot_key": snapshot.slot_key, "ruleset_version": snapshot.ruleset_version,
		"action_id": snapshot.action_id, "actor_id": snapshot.actor_id,
		"revisions": revisions.duplicate(true), "free_quantity_by_type": free.duplicate(true),
		"network": network.duplicate(true),
		"debit": {"type_id": debit_type, "quantity": debit_qty},
		"credit": {"type_id": credit_type, "quantity": credit_qty},
		"requires_atomic_inventory_preflight": true}

# Compare the previously retained INTERNAL quote with a fresh authoritative
# snapshot and ratebook. No mutation, no durable receipt, no reservation lock.
# The caller supplies the original command independently of the old quote.
# Never accept a UI-supplied quote as authorization; A1 must revalidate and
# commit within the same transaction, including exact instance allocation.
static func revalidate(previous: Dictionary, kind: String, faction_id: String, requested_day: int, snapshot: Dictionary, ratebook: Dictionary) -> Dictionary:
	if previous.get("ok") != true or previous.get("quote_version") != 2:
		return _fail("INVALID_QUOTE")
	var fresh := quote(kind, faction_id, requested_day, snapshot, ratebook)
	if not fresh.ok or fresh != previous:
		return _fail("STALE_QUOTE")
	return fresh
