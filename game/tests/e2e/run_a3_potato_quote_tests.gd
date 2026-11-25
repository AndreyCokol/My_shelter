extends SceneTree

const Quote = preload("res://game/systems/shelter/potato_trade_quote_candidate.gd")
const Camp = preload("res://game/systems/world/camp_network.gd")
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

func snapshot(seed_value: int) -> Dictionary:
	return {"minute": Camp.OPEN, "seed": seed_value, "scene_id": "louvre",
		"slot_key": "test-slot", "ruleset_version": "synthetic-qa-v2", "action_id": "qa-1",
		"network": Camp.empty_state(),
		"free_quantity_by_type": {"crop.potato": 20, "material.salvage": 20},
		"revisions": {"inventory:player": 0, "inventory:storage": 0, "residents": 0, "world": 0, "scene": 0, "wallet": 0}}

func rates() -> Dictionary:
	# Deliberately synthetic and different from old system-coin values.
	return {"currency_domain": "potato", "ruleset_version": "synthetic-qa-v2",
		"factions": {"scouts": {"contract_reward_potato": 11, "buy_cost_potato": 9},
		"settlers": {"contract_reward_potato": 13, "buy_cost_potato": 7}}}

func rejected(result: Dictionary, code: String, label: String) -> void:
	check(result.get("ok") == false and result.get("code") == code and result.size() == 2, label)

func run() -> void:
	for seed_value in [54, 127]:
		var s := snapshot(seed_value)
		var r := rates()
		var faction: String = Camp.schedule(s.minute, seed_value).faction
		var other := "settlers" if faction == "scouts" else "scouts"
		var original := s.duplicate(true)
		var rates_original := r.duplicate(true)
		var contract := Quote.quote("contract", faction, 0, s, r)
		check(contract.get("ok") == true, "valid contract")
		check(contract.get("currency_domain") == "potato", "potato domain")
		check(contract.get("credit", {}).get("type_id") == "crop.potato", "contract credit is physical potato")
		check(contract.get("debit", {}).get("type_id") == Camp.FACTIONS[faction].request, "correct contract input")
		check(contract.get("credit", {}).get("quantity") == r.factions[faction].contract_reward_potato, "explicit synthetic rate")
		check(contract.get("requires_atomic_inventory_preflight") == true, "not executable receipt")
		check(contract == Quote.quote("contract", faction, 0, s, r), "deterministic repeat")
		check(s == original and r == rates_original, "no mutation")
		rejected(Quote.quote("contract", other, 0, s, r), "UNAVAILABLE", "wrong scheduled faction")
		rejected(Quote.quote("contract", faction, 1, s, r), "UNAVAILABLE", "wrong day")
		rejected(Quote.quote("sell", faction, 0, s, r), "INVALID_ARGUMENT", "unknown kind")
		rejected(Quote.quote("contract", "unknown", 0, s, r), "INVALID_ARGUMENT", "unknown faction")
		rejected(Quote.quote("contract", faction, 0, s, {}), "RATEBOOK_REQUIRED", "missing explicit rates")
		for bad_rate in [0, -1, 1.5, INF, NAN, true, "7", 2147483648]:
			var bad := r.duplicate(true)
			bad.factions[faction].contract_reward_potato = bad_rate
			rejected(Quote.quote("contract", faction, 0, s, bad), "INVALID_RATE", "invalid numeric rate")
		var wrong_currency := r.duplicate(true)
		wrong_currency.currency_domain = "system_coins"
		rejected(Quote.quote("contract", faction, 0, s, wrong_currency), "RATEBOOK_REQUIRED", "system coins rejected")
		var wrong_version := r.duplicate(true)
		wrong_version.ruleset_version = "old"
		rejected(Quote.quote("contract", faction, 0, s, wrong_version), "RATEBOOK_REQUIRED", "wrong rates version")
		var missing := s.duplicate(true)
		missing.free_quantity_by_type[Camp.FACTIONS[faction].request] = 0
		rejected(Quote.quote("contract", faction, 0, missing, r), "INSUFFICIENT_FREE_ITEMS", "no free item (reserved or absent)")
		var bad_free := s.duplicate(true)
		bad_free.free_quantity_by_type["crop.potato"] = -1
		rejected(Quote.quote("contract", faction, 0, bad_free, r), "INVALID_SNAPSHOT", "negative free amount")
		var outside := s.duplicate(true)
		outside.scene_id = "shelter"
		rejected(Quote.quote("contract", faction, 0, outside, r), "UNAVAILABLE", "wrong scene")
		var closed := s.duplicate(true)
		closed.minute = Camp.CLOSE
		rejected(Quote.quote("contract", faction, 0, closed, r), "UNAVAILABLE", "closed contract window")
		var no_rev := s.duplicate(true)
		no_rev.revisions.erase("residents")
		rejected(Quote.quote("contract", faction, 0, no_rev, r), "INVALID_SNAPSHOT", "missing resident revision")
		var blank_slot := s.duplicate(true)
		blank_slot.slot_key = " "
		rejected(Quote.quote("contract", faction, 0, blank_slot, r), "INVALID_SNAPSHOT", "invalid slot key")
		var invalid_network := s.duplicate(true)
		invalid_network.network = {}
		rejected(Quote.quote("contract", faction, 0, invalid_network, r), "INVALID_SNAPSHOT", "invalid network")
		rejected(Quote.quote("buy", faction, 0, s, r), "UNAVAILABLE", "buy requires relationship")
		s.network.last_contract_day = 0
		s.network.reputation[faction] = 1
		rejected(Quote.quote("contract", faction, 0, s, r), "UNAVAILABLE", "contract daily cap")
		var purchase := Quote.quote("buy", faction, 0, s, r)
		check(purchase.get("ok") == true, "valid buy")
		check(purchase.get("debit", {}).get("type_id") == "crop.potato", "buy debit physical potato")
		check(purchase.get("debit", {}).get("quantity") == r.factions[faction].buy_cost_potato, "explicit buy rate")
		check(purchase.get("credit", {}).get("type_id") == Camp.FACTIONS[faction].goods, "buy credit goods")
		var no_cash := s.duplicate(true)
		no_cash.free_quantity_by_type["crop.potato"] = 0
		no_cash["system_coins"] = 999999
		rejected(Quote.quote("buy", faction, 0, no_cash, r), "INSUFFICIENT_FREE_ITEMS", "coins cannot replace potato")
		s.network.last_trade[faction] = 0
		rejected(Quote.quote("buy", faction, 0, s, r), "UNAVAILABLE", "buy daily cap")
		s.minute += Camp.DAY
		check(Quote.quote("buy", faction, 1, s, r).get("ok") == true, "buy next day")
		if faction == "settlers":
			check(contract.get("debit", {}).get("type_id") == contract.get("credit", {}).get("type_id"), "same-type contract preserves gross legs")
	print("A3 POTATO QUOTE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
