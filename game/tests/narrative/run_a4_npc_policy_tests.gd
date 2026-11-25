extends SceneTree

const NPC = preload("res://game/systems/narrative/npc_policy_candidate.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func fixture(id: String) -> Dictionary:
	return {"id": id, "role": "recruitable", "scripted": false,
		"faction_leader": false, "status": "unknown", "consent": false,
		"available_for_expedition": true}

func run() -> void:
	var traveller: Dictionary = fixture("traveller-01")
	var original: Dictionary = traveller.duplicate(true)
	check(NPC.valid_npc(traveller), "well-formed generated NPC")
	check(not NPC.plan_consent(traveller, true).ok, "cannot consent before first contact")
	var contacted: Dictionary = NPC.plan_contact(traveller, false, false)
	check(contacted.ok and contacted.record.status == "contacted" and not contacted.record.consent,
		"first contact is not automatic consent")
	check(traveller == original, "contact planning never mutates source NPC")
	var refused: Dictionary = NPC.plan_consent(contacted.record, false)
	check(refused.ok and refused.record.status == "declined" and not refused.record.consent,
		"explicit refusal is stored without recruitment")
	check(not NPC.plan_recruit(refused.record, true, true).ok,
		"food cannot override a refused agreement")
	check(NPC.plan_consent(refused.record, true).code == "REQUIRES_CONTACT",
		"direct player consent cannot bypass a declined NPC and reputation gate")
	check(NPC.eligibility(refused.record, false, false).code == "REPUTATION_REQUIRED",
		"declined NPC requires positive personal or faction reputation condition")
	check(NPC.eligibility(refused.record, true, false).ok,
		"personal reputation may reopen contact")
	check(NPC.eligibility(refused.record, false, true).ok,
		"faction reputation may reopen contact")
	var renewed: Dictionary = NPC.plan_contact(refused.record, true, false)
	check(renewed.ok and renewed.record.status == "contacted" and not renewed.record.consent,
		"reputation never creates consent by itself")
	var accepted: Dictionary = NPC.plan_consent(renewed.record, true)
	check(accepted.ok and accepted.record.status == "AWAITING_SUPPLIES" and accepted.record.consent,
		"explicit consent enters waiting for supplies")
	check(NPC.eligibility(accepted.record, false, false).code == "ALREADY_CONSENTED",
		"already consenting NPC is not eligible for duplicate new offer")
	check(NPC.plan_contact(accepted.record, true, true).code == "ALREADY_CONSENTED",
		"even high reputation cannot reopen an already accepted proposal")
	check(NPC.plan_consent(accepted.record, true).code == "ALREADY_CONSENTED",
		"repeated positive decision does not create a second consent event")
	check(accepted.record.status == "AWAITING_SUPPLIES" and accepted.record.consent,
		"duplicate decision denials cannot alter the accepted waiting record")
	var withdrawn: Dictionary = NPC.plan_consent(accepted.record, false)
	check(withdrawn.ok and withdrawn.record.status == "declined" and not withdrawn.record.consent,
		"NPC can retract consent before settlement without losing history")
	check(NPC.plan_recruit(withdrawn.record, true, true).code == "REQUIRES_CONSENT",
		"withdrawn consent cannot be overridden by existing stored resources")
	var no_food: Dictionary = NPC.plan_recruit(accepted.record, false, true)
	check(not no_food.ok and no_food.code == "INSUFFICIENT_RESOURCES"
		and no_food.record == accepted.record, "food shortage preserves consent and waiting state")
	var no_housing: Dictionary = NPC.plan_recruit(accepted.record, true, false)
	check(not no_housing.ok and no_housing.code == "NEEDS_HOUSING"
		and no_housing.record == accepted.record, "housing shortage does not erase consent")
	var joined: Dictionary = NPC.plan_recruit(accepted.record, true, true)
	check(joined.ok and joined.record.status == "joined" and joined.record.consent
		and joined.record.role == "resident",
		"recruitment updates status and shelter resident role together")
	check(not NPC.plan_recruit(joined.record, true, true).ok,
		"recruiting same joined NPC twice is rejected")
	check(not NPC.plan_consent(joined.record, false).ok,
		"joined NPC cannot silently lose confirmed contract by repeat input")
	check(accepted.record.status == "AWAITING_SUPPLIES", "recruit plan never mutates saved waiting record")
	var leader: Dictionary = fixture("leader")
	leader.faction_leader = true
	check(not NPC.eligibility(leader, true, true).ok, "faction leader never recruitable even at high reputation")
	check(not NPC.plan_consent(leader, true).ok, "leader cannot enter contract through consent path")
	var non_recruitable: Dictionary = fixture("story-guide")
	non_recruitable.role = "non_recruitable"
	non_recruitable.scripted = true
	check(not NPC.eligibility(non_recruitable, true, true).ok,
		"scripted nonrecruitable NPC cannot bypass protected role")
	var second: Dictionary = fixture("traveller-02")
	second.status = "joined"
	second.role = "resident"
	second.consent = true
	var first: Dictionary = joined.record.duplicate(true)
	var party: Array = [second, first]
	var before_party: Array = party.duplicate(true)
	check(not NPC.plan_group_expedition(party, false, true, 2).ok,
		"expedition without player permission is forbidden")
	check(not NPC.plan_group_expedition(party, true, false, 2).ok,
		"expedition without resources cannot depart")
	check(not NPC.plan_group_expedition([first], true, true, 2).ok,
		"group size requirement comes from explicit policy")
	var order: Dictionary = NPC.plan_group_expedition(party, true, true, 2)
	check(order.ok and order.resident_ids == ["traveller-01", "traveller-02"],
		"group consent returns deterministic stable participant IDs")
	check(party == before_party, "expedition planning cannot move or mutate NPC")
	var reversed: Array = [first, second]
	check(NPC.plan_group_expedition(reversed, true, true, 2).resident_ids == order.resident_ids,
		"participant selection order does not change identity")
	check(NPC.plan_group_expedition([first, first], true, true, 2).code == "DUPLICATE_PARTICIPANT",
		"same NPC cannot join expedition twice")
	var unavailable: Dictionary = second.duplicate(true)
	unavailable.available_for_expedition = false
	check(NPC.plan_group_expedition([first, unavailable], true, true, 2).code == "UNAVAILABLE_PARTICIPANT",
		"unavailable resident cannot be forced into group")
	var ghost: Dictionary = fixture("ghost")
	ghost.role = "resident"
	check(not NPC.valid_npc(ghost), "shelter-resident role without joined status invalid")
	var unconverted: Dictionary = fixture("unconverted")
	unconverted.status = "joined"
	unconverted.consent = true
	check(not NPC.valid_npc(unconverted), "joined status must carry resident role")
	var illicit: Dictionary = fixture("illicit")
	illicit.role = "non_recruitable"
	illicit.status = "joined"
	illicit.consent = true
	check(not NPC.valid_npc(illicit), "nonrecruitable contact cannot be serialized as joined resident")
	var nameless: Dictionary = fixture("   ")
	check(not NPC.valid_npc(nameless), "blank padded NPC identity cannot enter a roster")
	var padded: Dictionary = fixture("traveller-01 ")
	check(not NPC.valid_npc(padded), "trailing spaces cannot create a duplicate actor ID")
	padded = fixture(" traveller-01")
	check(not NPC.valid_npc(padded), "leading spaces cannot create another actor identity")
	var normal_internal_spaces: Dictionary = fixture("resident Marie Curie")
	check(NPC.valid_npc(normal_internal_spaces),
		"canonical identifiers may preserve meaningful internal spaces")
	var padded_joined: Dictionary = first.duplicate(true)
	padded_joined.id = "traveller-01 "
	check(NPC.plan_group_expedition([first, padded_joined], true, true, 2).code == "UNAVAILABLE_PARTICIPANT",
		"padded alias cannot depart as a second expedition member")
	check(not NPC.valid_npc({"id":"a"}), "incomplete NPC data fails closed")
	var bad: Dictionary = fixture("bad")
	bad.status = "joined"
	check(not NPC.valid_npc(bad), "joined NPC without consent is invalid")
	check(NPC.plan_group_expedition(party, true, true, 1).code == "INVALID_ARGUMENT",
		"invalid minimum party size is rejected")

	# A3 quote-shaped fixtures; integration with the real A3 producer is pending.
	var ctx := {"action_id": "act-1", "expedition_proposal_id": "exp-1",
		"destination_id": "region-1", "slot_key": "slot-1", "save_id": "save-1",
		"actor_id": "player-1", "ruleset_version": "rules-1", "policy_version": "test-v2",
		"resident_ids": ["traveller-01", "traveller-02"], "minute": 12,
		"source_containers": ["storage", "player"],
		"requested_departure_minute": 20, "valid_until_minute": 18,
		"revisions": {"inventory:player": 1, "inventory:storage": 2, "residents": 3, "world": 4}}
	var quote := {"ok": true, "code": "SUPPLY_QUOTE_READY", "quote_version": 2,
		"action_id": "act-1", "expedition_proposal_id": "exp-1",
		"destination_id": "region-1", "slot_key": "slot-1", "save_id": "save-1",
		"actor_id": "player-1", "ruleset_version": "rules-1", "policy_version": "test-v2",
		"resident_ids": ["traveller-01", "traveller-02"], "quoted_at_minute": 10,
		"source_containers": ["player", "storage"],
		"requested_departure_minute": 20, "valid_until_minute": 18,
		"inventory_revisions_snapshot": ctx.revisions.duplicate(true)}
	var before_ctx := ctx.duplicate(true)
	var before_quote := quote.duplicate(true)
	var match_result := NPC.check_expedition_quote(party, true, 2, ctx, quote)
	check(match_result.ok and match_result.code == "EXPEDITION_QUOTE_MATCHED"
		and match_result.requires_atomic_dispatch_preflight, "quote matches trusted proposal but never authorizes dispatch")
	check(NPC.check_expedition_quote(reversed, true, 2, ctx, quote) == match_result,
		"party ordering does not alter quote binding")
	check(ctx == before_ctx and quote == before_quote and party == before_party, "binding leaves all inputs intact")
	check(NPC.check_expedition_quote(party, false, 2, ctx, quote).code == "PERMISSION_REQUIRED", "quote cannot grant player permission")
	check(NPC.check_expedition_quote([first, unavailable], true, 2, ctx, quote).code == "UNAVAILABLE_PARTICIPANT", "quote cannot force unavailable NPC")
	check(NPC.check_expedition_quote([first, first], true, 2, ctx, quote).code == "DUPLICATE_PARTICIPANT", "quote cannot duplicate NPC")
	for key in ["action_id", "expedition_proposal_id", "destination_id", "slot_key", "save_id", "actor_id", "ruleset_version", "policy_version"]:
		var changed := quote.duplicate(true)
		changed[key] = "other"
		check(NPC.check_expedition_quote(party, true, 2, ctx, changed).code == "QUOTE_CONTEXT_MISMATCH", "foreign quote rejected: " + key)
	var changed_quote := quote.duplicate(true)
	changed_quote.resident_ids = ["traveller-01", "foreign"]
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "PARTICIPANT_MISMATCH", "foreign resident quote rejected")
	changed_quote.resident_ids = ["traveller-01", "traveller-01"]
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "PARTICIPANT_MISMATCH", "duplicate resident quote rejected")
	var changed_ctx := ctx.duplicate(true)
	changed_ctx.resident_ids = ["traveller-01", "foreign"]
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "PARTICIPANT_MISMATCH", "context cannot replace authoritative party")
	changed_quote = quote.duplicate(true)
	changed_quote.ok = false
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "SUPPLY_QUOTE_REQUIRED", "failed quote cannot advance")
	changed_quote = quote.duplicate(true)
	changed_quote.quote_version = 1
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "UNSUPPORTED_QUOTE_VERSION", "obsolete quote v1 rejected")
	changed_ctx = ctx.duplicate(true)
	changed_ctx.minute = 19
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "STALE_QUOTE", "expired quote rejected")
	changed_ctx.minute = 18
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).ok, "inclusive expiration boundary")
	changed_quote = quote.duplicate(true)
	changed_quote.quoted_at_minute = 13
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "INVALID_QUOTE_TIME", "future quote rejected")
	for key in ["requested_departure_minute", "valid_until_minute"]:
		changed_quote = quote.duplicate(true)
		changed_quote[key] = 17
		check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "QUOTE_CONTEXT_MISMATCH", "changed quote time rejected: " + key)
	for key in ctx.revisions:
		changed_ctx = ctx.duplicate(true)
		changed_ctx.revisions[key] += 1
		check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "STALE_QUOTE", "revision drift rejected: " + key)
	changed_ctx = ctx.duplicate(true)
	changed_ctx.revisions.erase("world")
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "INVALID_CONTEXT", "missing current revision rejected")
	changed_quote = quote.duplicate(true)
	changed_quote.inventory_revisions_snapshot["extra"] = 0
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "STALE_QUOTE", "extra quoted revision rejected")

	changed_quote = quote.duplicate(true)
	changed_quote.quote_version = 3
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "UNSUPPORTED_QUOTE_VERSION", "future version rejected")
	changed_ctx = ctx.duplicate(true)
	changed_ctx.source_containers.reverse()
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).ok, "source order canonicalized")
	changed_ctx.source_containers = ["player"]
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "QUOTE_CONTEXT_MISMATCH", "trusted source policy changed")
	changed_ctx.source_containers = ["player", "player"]
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "INVALID_CONTEXT", "duplicate source rejected")
	changed_ctx.source_containers = ["player", "remote"]
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "INVALID_CONTEXT", "source without revision rejected")
	changed_ctx = ctx.duplicate(true)
	changed_ctx.erase("save_id")
	check(NPC.check_expedition_quote(party, true, 2, changed_ctx, quote).code == "INVALID_CONTEXT", "missing trusted save identity rejected")
	changed_quote = quote.duplicate(true)
	changed_quote.source_containers.reverse()
	check(NPC.check_expedition_quote(party, true, 2, ctx, changed_quote).code == "QUOTE_CONTEXT_MISMATCH", "noncanonical quote source order rejected")
	print("A4 NPC POLICY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
