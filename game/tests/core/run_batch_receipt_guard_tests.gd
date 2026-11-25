extends SceneTree

# A1 isolated regression of the EXISTING CoreSession durable receipt contract.
# This tests live inventory.transfer (not an implemented batch command).
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Fixtures = preload("res://game/tests/core/campaign_fixtures.gd")

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

func request(session, action_id: String, kind: String, payload: Dictionary, actor: String = "player") -> Dictionary:
	var state: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in state.resource_revisions:
		versions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": action_id, "command_type": kind, "payload": payload,
		"context": {"actor_id": actor, "scene_id": state.scene.current_scene_id,
			"expected_resource_revisions": versions}}

func cleanup(path: String) -> void:
	for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func seed_instance(state: Dictionary) -> String:
	for item in state.inventory.items:
		if item.type_id == "seed.basic":
			return item.instance_id
	return ""

func run() -> void:
	var rules: Dictionary = Fixtures.rules()
	var session = Campaign.new(rules).coordinator
	check(Campaign.valid_rules(rules) and session != null,
		"current core campaign fixture supports a transactional receipt test")
	if session == null:
		quit(1)
		return
	var path: String = "user://a1-receipt-contract-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	cleanup(path)
	var store = Store.new(path)
	var first: Dictionary = request(session, "receipt:parcel", "inventory.claim_parcel", {"parcel_id": "starter"})
	check(session.execute(first, store).ok, "starter parcel commits a real inventory and receipt")
	var item_id: String = seed_instance(session.get_snapshot())
	check(not item_id.is_empty(), "real parcel created a stable instance ID")
	if item_id.is_empty():
		cleanup(path)
		quit(1)
		return
	var original: Dictionary = request(session, "receipt:move", "inventory.transfer",
		{"instance_id": item_id, "from_id": "player", "to_id": "storage", "quantity": 3})
	var moved: Dictionary = session.execute(original, store)
	check(moved.ok, "inventory transfer commits once under durable action ID")
	var committed: Dictionary = session.get_snapshot()
	var primary_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(session.execute(original, store).code == "ALREADY_APPLIED"
		and session.get_snapshot() == committed,
		"identical transfer returns old receipt without another mutation")
	check(FileAccess.get_file_as_bytes(path) == primary_bytes,
		"identical action replay never rewrites primary save")

	var reordered: Dictionary = original.duplicate(true)
	reordered.payload = {"quantity": 3, "to_id": "storage",
		"from_id": "player", "instance_id": item_id}
	check(session.execute(reordered, store).code == "ALREADY_APPLIED",
		"dictionary insertion order cannot change semantic fingerprint")
	var context_only: Dictionary = original.duplicate(true)
	context_only.context.expected_resource_revisions = []
	context_only.context.scene_id = "some-old-scene"
	check(session.execute(context_only, store).code == "ALREADY_APPLIED",
		"replay resolves by durable receipt before stale scene/revision context")
	var changed_qty: Dictionary = original.duplicate(true)
	changed_qty.payload.quantity = 2
	check(session.execute(changed_qty, store).code == "ACTION_CONFLICT",
		"same action ID with changed selected quantity is rejected")
	var changed_to: Dictionary = original.duplicate(true)
	changed_to.payload.to_id = "player"
	check(session.execute(changed_to, store).code == "ACTION_CONFLICT",
		"same action ID with changed destination is rejected")
	var changed_actor: Dictionary = original.duplicate(true)
	changed_actor.context.actor_id = "other-actor"
	check(session.execute(changed_actor, store).code == "ACTION_CONFLICT",
		"same action ID with changed actor is rejected")
	check(session.get_snapshot() == committed
		and FileAccess.get_file_as_bytes(path) == primary_bytes,
		"all collisions leave in-memory state and save bytes unchanged")

	var revived = Campaign.new(rules).coordinator
	check(revived.load_checkpoint(store).ok and revived.get_snapshot() == committed,
		"disk restart reloads precisely committed receipt ledger")
	check(revived.execute(original, store).code == "ALREADY_APPLIED",
		"identical original action remains idempotent after restart")
	check(revived.execute(changed_qty, store).code == "ACTION_CONFLICT"
		and revived.execute(changed_actor, store).code == "ACTION_CONFLICT",
		"different payload or actor remains conflicting after restart")
	check(FileAccess.get_file_as_bytes(path) == primary_bytes,
		"post-reload replays/collisions do not silently rotate backup or primary")

	var stale: Dictionary = request(revived, "receipt:new-stale", "inventory.transfer",
		{"instance_id": item_id, "from_id": "storage", "to_id": "player", "quantity": 3})
	stale.context.expected_resource_revisions = first.context.expected_resource_revisions.duplicate(true)
	var stale_result: Dictionary = revived.execute(stale, store)
	check(stale_result.code == "STALE_REVISION" and revived.get_snapshot() == committed,
		"fresh action with old optimistic revisions is rejected before mutation")
	check(FileAccess.get_file_as_bytes(path) == primary_bytes,
		"stale action cannot write a checkpoint")
	var fresh: Dictionary = request(revived, "receipt:back", "inventory.transfer",
		{"instance_id": item_id, "from_id": "storage", "to_id": "player", "quantity": 3})
	check(revived.execute(fresh, store).ok,
		"fresh correctly revised action commits after prior stale rejection")
	var returned: Dictionary = revived.get_snapshot()
	check(revived.execute(fresh, store).code == "ALREADY_APPLIED"
		and revived.get_snapshot() == returned,
		"return transfer has its own durable idempotent receipt")
	var again = Campaign.new(rules).coordinator
	check(again.load_checkpoint(store).ok and again.get_snapshot() == returned,
		"post-return checkpoint and receipt survive second independent reload")
	check(again.execute(original, store).code == "ALREADY_APPLIED"
		and again.execute(changed_qty, store).code == "ACTION_CONFLICT",
		"old historical receipt preserves original result despite later transfers")
	cleanup(path)
	print("BATCH RECEIPT GUARD TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
