extends SceneTree

const Quest = preload("res://game/systems/narrative/quest_gate_candidate.gd")
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

func run() -> void:
	var optional: Array = ["Q03", "Q04", "Q05", "Q06", "Q07"]
	check(Quest.QUEST_IDS.size() == 7, "only seven prototype quest IDs registered")
	check(not Quest.optional_quest("Q01") and not Quest.optional_quest("Q02"),
		"first two quests are tutorials not optional task branches")
	for id in optional:
		check(Quest.optional_quest(id), "Q03–Q07 remain optional " + id)
	for capability in Quest.SANDBOX_CAPABILITIES:
		check(Quest.narrative_gate_allows(capability, []),
			"no active quest is required for basic " + capability)
		check(Quest.narrative_gate_allows(capability, ["Q03", "Q05"]),
			"tracking some optional quests does not alter capability " + capability)
	check(Quest.narrative_gate_allows("shelter", []),
		"shelter entry never needs first zombie or Q02 progress")
	check(not Quest.narrative_gate_allows("spatial_shard", []),
		"spatial shard is outside current campaign scope")
	check(not Quest.narrative_gate_allows("shelter", ["Q99"]),
		"unknown quest ID fails validation instead of changing runtime")
	check(not Quest.narrative_gate_allows("shelter", {}),
		"tracking payload must be an array")
	check(Quest.completion_ready("Q01", {"first_enemy_defeated": false}) == {"ok": true, "ready": false},
		"first victory still governs the System tutorial")
	check(Quest.completion_ready("Q01", {"first_enemy_defeated": true}).ready,
		"first victory completes Q01 readiness")
	check(not Quest.completion_ready("Q02", {"first_enemy_defeated": false,
		"shelter_tutorial_visited": true}).ready,
		"visiting shelter early does not award post-victory Q02")
	check(Quest.completion_ready("Q02", {"first_enemy_defeated": true,
		"shelter_tutorial_visited": true}).ready,
		"after first victory the tutorial can be credited")
	check(not Quest.completion_ready("Q02", {"first_enemy_defeated": true,
		"shelter_tutorial_visited": false}).ready,
		"post-victory visit is required for tutorial but never for shelter access")
	check(not Quest.completion_ready("Q02", {"shelter_tutorial_visited": true}).ok,
		"Q02 facts must contain both explicit history flags")
	check(Quest.completion_ready("Q03", {"planted": true}).ready,
		"completed farm action is visible to optional quest")
	check(Quest.completion_ready("Q04", {"harvested": true}).ready,
		"completed harvest may be observed without quest gating")
	check(Quest.completion_ready("Q05", {"contacted": true}).ready,
		"contact objective has independent readiness")
	check(Quest.completion_ready("Q06", {"consented": false}) == {"ok": true, "ready": false},
		"refusal does not count as consent")
	check(Quest.completion_ready("Q07", {"joined_resident_ids": ["a", "b"],
		"required_joined_count": 2}).ready,
		"two unique joined residents satisfy synthetic Q07 policy")
	check(not Quest.completion_ready("Q07", {"joined_resident_ids": ["a", "   "],
		"required_joined_count": 2}).ok,
		"blank NPC identity cannot count toward Q07 recruitment")
	check(not Quest.completion_ready("Q07", {"joined_resident_ids": ["a", " a"],
		"required_joined_count": 2}).ok,
		"padded alias of existing resident cannot satisfy Q07 twice")
	check(not Quest.completion_ready("Q07", {"joined_resident_ids": ["a", "b "],
		"required_joined_count": 2}).ok,
		"padded second resident ID cannot unlock Q07")
	check(not Quest.completion_ready("Q07", {"joined_resident_ids": ["a"],
		"required_joined_count": 2}).ready,
		"one resident cannot be counted twice")
	check(not Quest.completion_ready("Q07", {"joined_resident_ids": ["a", "a"],
		"required_joined_count": 2}).ok,
		"duplicate stable resident IDs are rejected")
	check(not Quest.completion_ready("Q07", {"joined_resident_ids": ["a"]}).ok,
		"required resident count is never silently guessed")
	check(not Quest.completion_ready("Q06", {"consented": "yes"}).ok,
		"nonboolean story flag rejected")
	check(not Quest.completion_ready("Q08", {}).ok, "unknown late-game quest rejected")
	check(not Quest.completion_ready("Q01", {}).ok, "missing historic fact rejected")

	# A4 Q07 legacy bridge must not accept a free-form UI-provided joined IDs
	# list as evidence. Input records must come from A1-validated actual state.
	var legacy_a: Dictionary = {"id":"resident_1", "status":"unknown",
		"consent":false, "food_receipt_id":""}
	var legacy_b: Dictionary = {"id":"resident_2", "status":"contacted",
		"consent":false, "food_receipt_id":""}
	var prior_a: Dictionary = legacy_a.duplicate(true)
	var prior_b: Dictionary = legacy_b.duplicate(true)
	var empty_ready: Dictionary = Quest.completion_ready_legacy_q07([legacy_a, legacy_b], 2)
	check(empty_ready.ok and not empty_ready.ready
		and empty_ready.joined_resident_ids.is_empty(),
		"Q07 real legacy roster without joined residents is not ready")
	var joined_a: Dictionary = legacy_a.duplicate(true)
	joined_a.status = "joined"
	joined_a.consent = true
	joined_a.food_receipt_id = "historical-receipt-a"
	var partial: Dictionary = Quest.completion_ready_legacy_q07([joined_a, legacy_b], 2)
	check(partial.ok and not partial.ready
		and partial.joined_resident_ids == ["resident_1"],
		"Q07 legacy roster sees exactly one joined resident")
	var joined_b: Dictionary = legacy_b.duplicate(true)
	joined_b.status = "joined"
	joined_b.consent = true
	joined_b.food_receipt_id = "historical-receipt-b"
	var complete: Dictionary = Quest.completion_ready_legacy_q07([joined_b, joined_a], 2)
	check(complete.ok and complete.ready
		and complete.joined_resident_ids == ["resident_1", "resident_2"],
		"Q07 legacy result uses sorted stable ids regardless of roster order")
	check(Quest.completion_ready_legacy_q07([joined_a, joined_b], 1).ready,
		"Q07 explicit policy count need not be invented by the helper")
	check(not Quest.completion_ready_legacy_q07([joined_a, joined_b], 3).ready,
		"Q07 explicit greater count is not silently reduced to two")
	check(not Quest.completion_ready_legacy_q07([joined_a, joined_b], 0).ok,
		"Q07 required count must be explicitly positive")
	check(not Quest.completion_ready_legacy_q07([joined_a, joined_b], "2").ok,
		"Q07 required count cannot come from a UI string")
	check(not Quest.completion_ready_legacy_q07({"joined_resident_ids":["resident_1", "resident_2"]}, 2).ok,
		"Q07 free-form UI assertion cannot impersonate the authoritative roster")
	check(not Quest.completion_ready_legacy_q07([joined_a], 1).ok,
		"Q07 incomplete legacy roster fails closed")
	check(not Quest.completion_ready_legacy_q07([joined_a, joined_b, joined_b], 2).ok,
		"Q07 injected third record fails closed")
	check(not Quest.completion_ready_legacy_q07([joined_a, joined_a], 2).ok,
		"Q07 duplicated stable resident id fails closed")
	var foreign: Dictionary = joined_b.duplicate(true)
	foreign.id = "npc.generated.example"
	check(not Quest.completion_ready_legacy_q07([joined_a, foreign], 2).ok,
		"Q07 foreign generated id cannot masquerade as a legacy resident")
	foreign = joined_b.duplicate(true)
	foreign.id = "resident_2 "
	check(not Quest.completion_ready_legacy_q07([joined_a, foreign], 2).ok,
		"Q07 padded ID cannot add another joined resident")
	foreign = joined_b.duplicate(true)
	foreign.food_receipt_id = ""
	check(not Quest.completion_ready_legacy_q07([joined_a, foreign], 2).ok,
		"Q07 legacy joined actor must carry food receipt ID shape")
	foreign = joined_b.duplicate(true)
	foreign.consent = false
	check(not Quest.completion_ready_legacy_q07([joined_a, foreign], 2).ok,
		"Q07 actor cannot be joined without informed consent")
	check(legacy_a == prior_a and legacy_b == prior_b,
		"Q07 roster derivation never changes its source")
	check(not Quest.completion_ready_legacy_q07(null, 2).ok,
		"Q07 null legacy roster cannot be treated as zero residents")
	check(not Quest.completion_ready_legacy_q07([], 2).ok,
		"Q07 empty list cannot be treated as no validated NPCs")
	print("A4 QUEST GATE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
