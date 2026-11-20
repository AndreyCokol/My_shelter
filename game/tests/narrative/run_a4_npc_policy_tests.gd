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
	check(not NPC.valid_npc({"id":"a"}), "incomplete NPC data fails closed")
	var bad: Dictionary = fixture("bad")
	bad.status = "joined"
	check(not NPC.valid_npc(bad), "joined NPC without consent is invalid")
	check(NPC.plan_group_expedition(party, true, true, 1).code == "INVALID_ARGUMENT",
		"invalid minimum party size is rejected")
	print("A4 NPC POLICY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
