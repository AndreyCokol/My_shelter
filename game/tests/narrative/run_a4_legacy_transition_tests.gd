extends SceneTree

# A4-only pure legacy adapter tests. These are NOT Core consent regression
# tests; current Core's bypass remains reproducible in Issue #185.
const Bridge = preload("res://game/systems/narrative/npc_legacy_transition_candidate.gd")

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
	return {"id": id, "status": "unknown", "consent": false, "food_receipt_id": ""}

func run() -> void:
	var survivor: Dictionary = fixture("resident_1")
	var other: Dictionary = fixture("resident_2")
	var initial: Dictionary = survivor.duplicate(true)
	check(Bridge.valid_legacy(survivor) and Bridge.valid_legacy(other),
		"both existing A1 starter residents have a valid legacy shape")
	var contact: Dictionary = Bridge.plan_contact(survivor, false, false)
	check(contact.ok and contact.code == "CONTACTED",
		"unknown starter can be contacted without invented reputation")
	check(contact.expected_id == "resident_1" and contact.expected_status == "unknown",
		"contact proposal carries exact A1 compare-and-commit preconditions")
	check(contact.patch == {"status": "contacted", "consent": false},
		"contact patch contains only fields owned by A4")
	check(survivor == initial, "contact helper does not mutate legacy snapshot")
	var already_refused: Dictionary = fixture("resident_1")
	already_refused.status = "declined"
	var refused_copy: Dictionary = already_refused.duplicate(true)
	check(Bridge.valid_legacy(already_refused),
		"genuine declined resident remains a valid persisted record")
	check(Bridge.plan_consent(already_refused, true).code == "REQUIRES_CONTACT",
		"declined NPC cannot be converted to consent by direct UI request")
	check(Bridge.plan_contact(already_refused, false, false).code == "REPUTATION_REQUIRED",
		"recontact without A1-backed high reputation cannot bypass refusal")
	var personal: Dictionary = Bridge.plan_contact(already_refused, true, false)
	check(personal.ok and personal.code == "CONTACTED",
		"trusted personal-reputation condition can reopen a declined proposal")
	check(personal.patch == {"status": "contacted", "consent": false},
		"high personal reputation alone cannot forge NPC consent")
	var faction: Dictionary = Bridge.plan_contact(already_refused, false, true)
	check(faction.ok and faction.patch == personal.patch,
		"trusted faction-reputation alternative grants only a new contact")
	check(Bridge.plan_contact(already_refused, true, true).ok,
		"either or both reputation sources are accepted as pre-evaluated policy")
	check(already_refused == refused_copy,
		"recontact proposal never changes declined A1 record directly")
	var contacted: Dictionary = fixture("resident_1")
	contacted.status = "contacted"
	var accept: Dictionary = Bridge.plan_consent(contacted, true)
	check(accept.ok and accept.code == "CONSENT_ACCEPTED",
		"contacted NPC decision can propose awaiting supplies")
	check(accept.expected_status == "contacted"
		and accept.patch == {"status": "AWAITING_SUPPLIES", "consent": true},
		"accepted proposal keeps compare-and-swap status and narrow A4 patch")
	check(not accept.patch.has("food_receipt_id") and not accept.patch.has("food_allocations"),
		"A4 adapter never grants food receipts or allocates stock")
	var decline: Dictionary = Bridge.plan_consent(contacted, false)
	check(decline.ok and decline.patch == {"status": "declined", "consent": false},
		"NPC can refuse even after contact and this is not recruitment")
	check(contacted.status == "contacted" and not contacted.consent,
		"consent decisions never mutate source snapshot")
	var waiting: Dictionary = fixture("resident_1")
	waiting.status = "AWAITING_SUPPLIES"
	waiting.consent = true
	check(Bridge.valid_legacy(waiting), "accepted survivor may be waiting for food")
	var withdrawal: Dictionary = Bridge.plan_consent(waiting, false)
	check(withdrawal.ok and withdrawal.patch == {"status": "declined", "consent": false},
		"consent can be withdrawn before a resident joins")
	check(waiting.status == "AWAITING_SUPPLIES" and waiting.consent,
		"withdrawal patch does not release A1 reservations itself")
	check(Bridge.plan_contact(waiting, false, false).ok,
		"contact helper is a pure proposal even when waiting state is presented")
	var joined: Dictionary = fixture("resident_2")
	joined.status = "joined"
	joined.consent = true
	joined.food_receipt_id = "receipt-from-a1"
	check(Bridge.valid_legacy(joined),
		"joined legacy record retains historical food receipt as an opaque field")
	check(Bridge.plan_consent(joined, false).code == "ALREADY_RECRUITED",
		"joined resident cannot lose contract from another consent action")
	check(Bridge.plan_contact(joined, true, true).code == "ALREADY_RECRUITED",
		"trusted reputation does not turn joined resident into recruitable NPC")
	check(joined.food_receipt_id == "receipt-from-a1",
		"A4 never modifies A1 historical receipt identity")
	var invalid: Dictionary = fixture("npc.generated.example")
	check(not Bridge.valid_legacy(invalid) and Bridge.plan_contact(invalid, true, true).code == "INVALID_ARGUMENT",
		"adapter cannot silently authorize a new generated NPC as a legacy actor")
	invalid = fixture("resident_1 ")
	check(not Bridge.valid_legacy(invalid),
		"padded legacy alias is rejected")
	invalid = fixture("resident_1")
	invalid.erase("food_receipt_id")
	check(not Bridge.valid_legacy(invalid), "missing legacy receipt field fails closed")
	invalid = fixture("resident_1")
	invalid.food_receipt_id = "forged"
	check(not Bridge.valid_legacy(invalid), "unjoined survivor cannot carry an arbitrary food receipt")
	invalid = fixture("resident_2")
	invalid.status = "joined"
	invalid.consent = true
	check(not Bridge.valid_legacy(invalid), "joined survivor needs a nonempty historical receipt field")
	invalid = fixture("resident_1")
	invalid.status = "joined"
	invalid.food_receipt_id = "forged"
	check(not Bridge.valid_legacy(invalid), "joined survivor without consent is rejected")
	invalid = fixture("resident_2")
	invalid.status = "AWAITING_SUPPLIES"
	check(not Bridge.valid_legacy(invalid), "awaiting survivor must have saved informed consent")
	invalid = fixture("resident_2")
	invalid.status = "unknown"
	invalid.consent = true
	check(not Bridge.valid_legacy(invalid), "unknown NPC cannot be pre-consented")
	invalid = fixture("resident_1")
	invalid.status = "declined"
	invalid.consent = true
	check(not Bridge.valid_legacy(invalid), "refused NPC cannot have a true consent flag")
	invalid = fixture("resident_1")
	invalid.status = "unrecognized"
	check(not Bridge.valid_legacy(invalid), "unknown state names fail closed")
	invalid = fixture("resident_1")
	invalid.consent = "true"
	check(not Bridge.valid_legacy(invalid), "strings cannot masquerade as consent booleans")
	invalid = fixture("resident_1")
	invalid.food_receipt_id = 5
	check(not Bridge.valid_legacy(invalid), "receipt ID must have the existing type")
	check(not Bridge.valid_legacy(null) and not Bridge.valid_legacy([]),
		"malformed legacy payloads cannot be mapped")
	print("A4 LEGACY TRANSITION TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
