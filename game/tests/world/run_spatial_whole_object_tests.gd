extends SceneTree
## A2-05 pure interaction acceptance. NEVER alters CoreSession or world nodes.
const Guard = preload("res://game/systems/world/spatial_whole_object_intent.gd")
const Receipts = preload("res://game/systems/core/action_receipt.gd")
const Bounds := Rect2(0, 0, 480, 360)
const ACTOR := Vector2(80, 160)
const OBJECT := Vector2(110, 160)
const ACTION := "a2:pick:0001"

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + title)

func thing(kind: String = "loot", state: String = "loose") -> Dictionary:
	return {
		"scene_id": "hospital_0_3", "object_id": "cache:pack-17",
		"type_id": "material.salvage", "kind": kind,
		"state": state, "position": OBJECT, "quantity": 1,
	}

func intent(item: Dictionary, blockers: Array = [], actor: Vector2 = ACTOR, action_id: String = ACTION) -> Dictionary:
	return Guard.prepare_intent("hospital_0_3", actor, item, Bounds, blockers, action_id)

func matched_receipt(prepared: Dictionary, state_revision: int = 17) -> Dictionary:
	return {
		"ok": true, "code": "OK", "action_id": prepared.action_id,
		"state_revision": state_revision,
		"data": {
			"scene_id": prepared.scene_id, "object_id": prepared.object_id,
			"type_id": prepared.type_id, "operation": prepared.operation,
			"quantity": prepared.quantity,
			"object_identity_sha256": prepared.object_identity_sha256,
		},
		"message_key": "core.ok",
	}

func stored(receipt: Dictionary, fingerprint: String = "fingerprint:one", revision: int = 17) -> Dictionary:
	return {
		"state_revision": revision,
		"completed_actions": {
			ACTION: Receipts.pack(fingerprint, receipt),
		},
	}

func _run() -> void:
	var original := thing()
	var original_copy := original.duplicate(true)
	var prepared: Dictionary = intent(original)
	check(prepared.ok and prepared.operation == "collect_whole" and prepared.quantity == 1,
		"one loose physical object creates one whole-object intent")
	check(prepared.needs_core_commit and not prepared.hide_before_commit,
		"A2 never authorizes hiding or grants inventory before A1 commit")
	check(original == original_copy,
		"spatial planning does not mutate source object metadata")
	check(prepared == intent(original),
		"same action and scene create deterministic immutable-value intent")

	var failed_commit := {"ok": false, "code": "SAVE_FAILED", "action_id": ACTION}
	check(Guard.after_durable_commit(prepared, failed_commit, {}, "fingerprint:one").code == "NOT_COMMITTED",
		"failed durability never hides the object")
	var good_receipt := matched_receipt(prepared)
	var snapshot := stored(good_receipt)
	check(Guard.after_durable_commit(prepared, good_receipt, {}, "fingerprint:one").code == "UNVERIFIED_RECEIPT",
		"a positive UI response alone cannot hide a world object")
	var ack := Guard.after_durable_commit(prepared, good_receipt, snapshot, "fingerprint:one")
	check(ack.ok and ack.can_hide_world_object and ack.object_id == prepared.object_id,
		"matching committed A1 receipt authorizes hiding exactly one physical object")

	var replay := good_receipt.duplicate(true)
	replay.code = "ALREADY_APPLIED"
	check(Guard.after_durable_commit(prepared, replay, snapshot, "fingerprint:one").ok,
		"idempotent A1 replay may acknowledge the same original saved object")
	var changed_ack := replay.duplicate(true)
	changed_ack.action_id = "a2:pick:other"
	check(Guard.after_durable_commit(prepared, changed_ack, snapshot, "fingerprint:one").code == "NOT_COMMITTED",
		"other action_id can never hide this object")
	var changed_object := replay.duplicate(true)
	changed_object.data.object_id = "other-world-object"
	check(Guard.after_durable_commit(prepared, changed_object, snapshot, "fingerprint:one").code == "UNVERIFIED_RECEIPT",
		"response and durable receipt must identify precisely the same object")
	check(Guard.after_durable_commit(prepared, good_receipt, snapshot, "fingerprint:other").code == "ACTION_CONFLICT",
		"wrong semantic fingerprint rejects a different replay command")

	var no_record := snapshot.duplicate(true)
	no_record.completed_actions.clear()
	check(Guard.after_durable_commit(prepared, good_receipt, no_record, "fingerprint:one").code == "UNVERIFIED_RECEIPT",
		"unpersisted receipt cannot hide the world instance")
	var stale_revision := snapshot.duplicate(true)
	stale_revision.state_revision = 15
	check(Guard.after_durable_commit(prepared, good_receipt, stale_revision, "fingerprint:one").code == "UNVERIFIED_RECEIPT",
		"receipt from a future state revision rejected")
	var substituted_receipt := snapshot.duplicate(true)
	substituted_receipt.completed_actions[ACTION] = Receipts.pack("fingerprint:one",
		matched_receipt(intent(thing("debris", "destroyed"))))
	check(Guard.after_durable_commit(prepared, good_receipt, substituted_receipt, "fingerprint:one").code == "WRONG_OBJECT_RECEIPT",
		"changed operation cannot be substituted into committed receipt")
	var fake_result := good_receipt.duplicate(true)
	fake_result.state_revision = 999
	check(Guard.after_durable_commit(prepared, fake_result, snapshot, "fingerprint:one").code == "UNVERIFIED_RECEIPT",
		"response revision must match A1 durable receipt")

	var objects := [
		["loot", "loose", "collect_whole"],
		["debris", "destroyed", "collect_whole"],
		["door", "intact", "break_structure"],
		["door", "destroyed", "salvage_destroyed_structure"],
		["wall", "intact", "break_structure"],
		["wall", "destroyed", "salvage_destroyed_structure"],
		["vehicle", "intact", "transport_whole_to_processing"],
		["pole", "intact", "transport_whole_to_processing"],
	]
	for entry in objects:
		var next: Dictionary = intent(thing(entry[0], entry[1]))
		check(next.ok and next.operation == entry[2] and next.quantity == 1,
			"%s %s produces the correct WHOLE-object lifecycle intent" % [entry[0], entry[1]])
	for entry in [
		["loot", "intact"], ["debris", "intact"], ["wall", "loose"],
		["door", "loose"], ["furniture", "intact"], ["vehicle", "destroyed"],
	]:
		check(intent(thing(entry[0], entry[1])).code == "UNAVAILABLE",
			"forbid unsupported %s %s object shortcut" % [entry[0], entry[1]])
	check(intent(thing("vehicle_part", "loose")).code == "PART_EXTRACTION_FORBIDDEN",
		"cannot touch-extract vehicle engine or other parts without processing")

	var far := original.duplicate(true)
	far.position = Vector2(250, 300)
	check(intent(far).code == "OUT_OF_REACH", "too distant real object is not collectible")
	var wrong_scene := original.duplicate(true)
	wrong_scene.scene_id = "outside"
	check(intent(wrong_scene).code == "WRONG_SCENE", "another scene cannot be looted remotely")
	var partial := original.duplicate(true)
	partial.quantity = 2
	check(intent(partial).code == "INVALID_OBJECT", "world object cannot be partially moved")
	var malformed_id := original.duplicate(true)
	malformed_id.object_id = "cache\nnext"
	check(intent(malformed_id).code == "INVALID_OBJECT", "embedded newline object identity invalid")
	var extra := original.duplicate(true)
	extra["invented"] = true
	check(intent(extra).code == "INVALID_OBJECT", "unexpected mutable fields are rejected")
	check(Guard.prepare_intent("hospital_0_3", ACTOR, original, Bounds,
		[], "").code == "INVALID_ARGUMENT", "empty action_id rejected")
	check(Guard.prepare_intent("hospital_0_3", ACTOR, original, Bounds,
		[], ACTION, 0.0).code == "INVALID_ARGUMENT", "zero reach rejected")
	check(Guard.prepare_intent("hospital_0_3", Vector2(-50, 50), original, Bounds,
		[], ACTION).code == "OUT_OF_BOUNDS", "actor outside current scene rejected")
	check(Guard.prepare_intent("hospital_0_3", ACTOR, original, Rect2(0, 0, 0, 100),
		[], ACTION).code == "INVALID_BOUNDS", "degenerate world bounds rejected")
	check(intent(original, [Rect2(93, 150, 5, 20)]).code == "BLOCKED_LINE_OF_INTERACTION",
		"wall between actor and object blocks interaction")
	check(intent(original, [Rect2(86, 160, 12, 10)]).code == "BLOCKED_LINE_OF_INTERACTION",
		"collision that touches segment boundary is blocked")
	check(intent(original, [Rect2(95, 210, 10, 10)]).ok,
		"off-line wall does not block reachable whole object")
	check(intent(original, [Rect2(5, 5, 0, 10)]).code == "INVALID_GEOMETRY",
		"invalid collider data fails closed")
	check(intent(original, ["not a collider"]).code == "INVALID_GEOMETRY",
		"wrong geometry type fails closed")

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	for k in range(160):
		var object_at := original.duplicate(true)
		object_at.position = Vector2(rng.randf_range(80.1, 122.0), rng.randf_range(135.0, 185.0))
		var obstacle := Rect2(rng.randf_range(75.0, 122.0), rng.randf_range(130, 185),
			rng.randf_range(1.0, 13.0), rng.randf_range(1.0, 13.0))
		var this: Dictionary = intent(object_at, [obstacle])
		check(this == intent(object_at, [obstacle])
			and (this.ok or this.code == "BLOCKED_LINE_OF_INTERACTION"),
			"deterministic seeded geometry %d returns valid intent or line obstruction" % k)
		if this.ok:
			check(this.needs_core_commit and not this.hide_before_commit and this.quantity == 1,
				"random-case %d still cannot remove uncommitted whole object" % k)

	print("A2 WHOLE OBJECT INTENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
