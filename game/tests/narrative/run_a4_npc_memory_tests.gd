extends SceneTree

const History = preload("res://game/systems/narrative/npc_chronicle_candidate.gd")
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

func fact(event_id: String, minute: int, kind: String, other: String) -> Dictionary:
	return {"event_id": event_id, "minute": minute, "kind": kind, "subject_id": other}

func run() -> void:
	var id1: Dictionary = History.generated_id(5, 54, "paris:region:3:-2", "spawn:traveller:01")
	check(id1.ok and str(id1.npc_id).begins_with("npc.generated."),
		"generated identity is namespaced and stable")
	check(History.generated_id(5, 54, "paris:region:3:-2", "spawn:traveller:01") == id1,
		"same generated identity reappears across reload or camera mode")
	check(History.generated_id(5, 55, "paris:region:3:-2", "spawn:traveller:01").npc_id != id1.npc_id,
		"changing world seed produces a distinct identity")
	check(History.generated_id(6, 54, "paris:region:3:-2", "spawn:traveller:01").npc_id != id1.npc_id,
		"changing generator version cannot steal an old NPC ID")
	check(History.generated_id(5, 54, "paris:region:3:-2", "spawn:traveller:02").npc_id != id1.npc_id,
		"two separate spawn keys never alias under test")
	check(History.generated_id(5, 54, "paris:region:3:-3", "spawn:traveller:01").npc_id != id1.npc_id,
		"region coordinate participates in identity")
	check(not History.generated_id(0, 54, "paris", "a").ok,
		"generator version zero is rejected")
	check(not History.generated_id(5, -1, "paris", "a").ok,
		"negative world seed is rejected")
	check(not History.generated_id(5, 54, "", "spawn").ok,
		"missing region identity rejected")
	check(not History.generated_id(5, 54, "paris", "   ").ok,
		"whitespace-only spawn identity rejected")
	check(not History.generated_id(5, 1.0, "paris", "spawn").ok,
		"floating seed cannot masquerade as integer")
	check(not History.generated_id(5, History.MAX_EXACT_JSON_INT + 1, "paris", "a").ok,
		"JSON-unsafe enormous seed rejected")
	var named: Dictionary = History.scripted_id("resident_alice")
	check(named.ok and str(named.npc_id).begins_with("npc.scripted."),
		"authored NPC identity is in a different stable namespace")
	check(History.scripted_id("resident_alice") == named,
		"scripted unique actor survives redraw and reload")
	check(History.scripted_id("resident_bob").npc_id != named.npc_id,
		"distinct authored keys are distinct IDs")
	check(not History.scripted_id("").ok and not History.scripted_id(4).ok,
		"scripted NPC requires an explicit stable string key")
	var relation: Dictionary = History.relationship_id(id1.npc_id, named.npc_id)
	check(relation.ok and relation.member_ids.size() == 2,
		"pair relationship receives stable member IDs")
	check(History.relationship_id(named.npc_id, id1.npc_id) == relation,
		"social relation is symmetric under participant selection order")
	check(not History.relationship_id(id1.npc_id, id1.npc_id).ok,
		"actor cannot accidentally create self friendship")
	check(not History.relationship_id("", named.npc_id).ok,
		"blank actor reference rejected")
	var initial: Dictionary = History.fresh_chronicle(id1.npc_id)
	check(initial.ok and initial.record.facts.is_empty(),
		"fresh generated actor has empty valid personal history")
	check(not History.fresh_chronicle("  ").ok,
		"cannot initialize a nameless NPC history")
	var first: Dictionary = fact("cmd-1:event", 60, "met", named.npc_id)
	var append1: Dictionary = History.add_fact(initial.record, first)
	check(append1.ok and append1.code == "ADDED" and append1.record.facts.size() == 1,
		"one witnessed event records precisely one historical fact")
	check(initial.record.facts.is_empty(), "history planner does not modify input")
	check(History.add_fact(append1.record, first).code == "ALREADY_APPLIED",
		"same event ID and same payload replay idempotently")
	var conflict: Dictionary = first.duplicate(true)
	conflict.kind = "conflict"
	check(History.add_fact(append1.record, conflict).code == "ACTION_CONFLICT",
		"same event ID with another outcome is a conflict")
	var last: Dictionary = History.add_fact(append1.record, fact("cmd-3", 120, "helped", named.npc_id))
	var middle: Dictionary = History.add_fact(last.record, fact("cmd-2", 100, "friendship", named.npc_id))
	check(middle.ok and middle.record.facts.map(func(x): return x.event_id) == ["cmd-1:event", "cmd-2", "cmd-3"],
		"out-of-order observation retains deterministic game-minute chronology")
	var same_time: Dictionary = History.add_fact(middle.record, fact("cmd-0", 100, "trained", named.npc_id))
	check(same_time.ok and same_time.record.facts[1].event_id == "cmd-0"
		and same_time.record.facts[2].event_id == "cmd-2",
		"events sharing minute are stably ordered by event ID")
	var tampered: Dictionary = same_time.record.duplicate(true)
	tampered.facts.append(tampered.facts[0].duplicate(true))
	check(not History.add_fact(tampered, fact("new", 200, "met", named.npc_id)).ok,
		"corrupt repeated event IDs inside historical record rejected")
	check(not History.add_fact(same_time.record, fact("bad", -1, "met", named.npc_id)).ok,
		"negative game minute rejected")
	check(not History.add_fact(same_time.record, fact("bad", 55, "unapproved_magic", named.npc_id)).ok,
		"unknown event categories cannot introduce unreviewed story effects")
	var bad: Dictionary = fact("bad", 60, "met", named.npc_id)
	bad.minute = 60.0
	check(not History.add_fact(same_time.record, bad).ok,
		"float timestamp rejected rather than silently rounded")
	bad = fact("bad", 60, "met", named.npc_id)
	bad.free_resources = 1000
	check(not History.add_fact(same_time.record, bad).ok,
		"untrusted extra payload cannot grant resources through the story ledger")
	check(same_time.record.facts.size() == 4 and append1.record.facts.size() == 1,
		"adding later events never mutates previous snapshots")
	print("A4 NPC MEMORY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
