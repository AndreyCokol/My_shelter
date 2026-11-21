extends SceneTree

# A1 pure guard and actual schema4 stale-preview regression. The binding
# digest is NOT player-facing authority and is not a substitute for commit.
const Guard = preload("res://game/contracts/batch_snapshot_guard_candidate.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")

var checks: int = 0
var failures: int = 0
var serial: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS " + message)
	else:
		failures += 1
		push_error("FAIL " + message)

func items() -> Array:
	return [
		{"instance_id": "food-a", "type_id": "food", "quantity": 5, "container_id": "player"},
		{"instance_id": "food-b", "type_id": "food", "quantity": 4, "container_id": "player"},
		{"instance_id": "lamp", "type_id": "whole", "quantity": 2, "container_id": "player"},
		{"instance_id": "stored", "type_id": "misc", "quantity": 1, "container_id": "storage"}
	]

func caps() -> Array:
	return [{"id": "player", "capacity_mass_units": 25},
		{"id": "storage", "capacity_mass_units": 17}]

func mass() -> Dictionary:
	return {"food": 2, "whole": 3, "misc": 1}

func policy() -> Dictionary:
	return {"food": "fungible_stack", "whole": "whole_object", "misc": "whole_object"}

func rows() -> Array:
	return [{"instance_id": "food-a", "resident_id": "npc-1", "quantity": 1},
		{"instance_id": "food-a", "resident_id": "npc-2", "quantity": 1}]

func revisions() -> Dictionary:
	return {"inventory:player": 7, "inventory:storage": 3, "residents": 5, "world": 88}

func batch() -> Dictionary:
	return {"from_id": "player", "to_id": "storage", "entries": [
		{"instance_id": "food-a", "quantity": 3},
		{"instance_id": "food-b", "quantity": 2},
		{"instance_id": "lamp", "quantity": 2}]}

# Test-only convenience: production Guard requires explicit CoreSession identity.
func synthetic_identity() -> Dictionary:
	return {"save_id": "slot-01", "actor_id": "player", "ruleset_version": "test-v1",
		"storage_slot_key": "user://synthetic-slot-a.json"}

func identity(snapshot: Dictionary, slot_path: String) -> Dictionary:
	return {"save_id": snapshot.save_id, "actor_id": "player",
		"ruleset_version": snapshot.ruleset_version, "storage_slot_key": slot_path}

func bind(action_id, req, stock, containers, catalog, reserves, divisibility, revisions_map, source_identity = null) -> Dictionary:
	var trusted = synthetic_identity() if source_identity == null else source_identity
	return Guard.bind(action_id, req, stock, containers, catalog, reserves, divisibility, revisions_map, trusted)

func verify(quote, action_id, req, stock, containers, catalog, reserves, divisibility, revisions_map, source_identity = null) -> Dictionary:
	var trusted = synthetic_identity() if source_identity == null else source_identity
	return Guard.revalidate(quote, action_id, req, stock, containers, catalog, reserves, divisibility, revisions_map, trusted)

func check_pure() -> void:
	var stock: Array = items()
	var containers: Array = caps()
	var catalog: Dictionary = mass()
	var reservations: Array = rows()
	var divisibility: Dictionary = policy()
	var version: Dictionary = revisions()
	var req: Dictionary = batch()
	var expected_stock: Array = stock.duplicate(true)
	var expected_req: Dictionary = req.duplicate(true)
	var expected_rows: Array = reservations.duplicate(true)
	var quote: Dictionary = bind("action-1", req, stock, containers, catalog, reservations, divisibility, version)
	check(quote.ok and quote.binding_fingerprint.length() == 64,
		"binding is a well-formed deterministic SHA-256 digest, not authorization")
	if not quote.ok:
		return
	var fresh: Dictionary = verify(quote, "action-1", req, stock, containers, catalog, reservations, divisibility, version)
	check(fresh.ok and fresh.preview_items == quote.preview_items,
		"identical trusted snapshot yields freshly rebuilt identical preview")
	check(quote.preview_items.size() == 6 and quote.split_instance_ids.size() == 2,
		"quote covers both split resources and one physical whole instance")
	check(stock == expected_stock and req == expected_req and reservations == expected_rows,
		"binding never mutates live snapshot or NPC food rows")
	check(quote == bind("action-1", req, stock, containers, catalog, reservations, divisibility, version),
		"same inputs yield exactly same quote including fingerprint")

	var reordered_items: Array = stock.duplicate(true)
	reordered_items.reverse()
	check(bind("action-1", req, reordered_items, containers, catalog, reservations, divisibility, version).binding_fingerprint ==
		quote.binding_fingerprint, "snapshot item array order has no effect on binding")
	check(verify(quote, "action-1", req, reordered_items, containers, catalog, reservations, divisibility, version).ok,
		"revalidation accepts semantically identical item array order")
	var reordered_caps: Array = containers.duplicate(true)
	reordered_caps.reverse()
	check(verify(quote, "action-1", req, stock, reordered_caps, catalog, reservations, divisibility, version).ok,
		"container array insertion order does not invalidate quote")
	var reordered_rows: Array = reservations.duplicate(true)
	reordered_rows.reverse()
	check(verify(quote, "action-1", req, stock, containers, catalog, reordered_rows, divisibility, version).ok,
		"NPC reservation row order does not invalidate quote")
	var reordered_req: Dictionary = batch()
	reordered_req.entries.reverse()
	check(verify(quote, "action-1", reordered_req, stock, containers, catalog, reservations, divisibility, version).ok,
		"GUI click selection order does not invalidate canonical batch")
	var reversed_catalog: Dictionary = {"misc": 1, "whole": 3, "food": 2}
	check(verify(quote, "action-1", req, stock, containers, reversed_catalog, reservations, divisibility, version).ok,
		"mass catalog dictionary key order does not matter")
	var reversed_policy: Dictionary = {"misc": "whole_object", "whole": "whole_object", "food": "fungible_stack"}
	check(verify(quote, "action-1", req, stock, containers, catalog, reservations, reversed_policy, version).ok,
		"divisibility catalog dictionary key order does not matter")
	var unrelated: Dictionary = revisions()
	unrelated.world += 1
	check(verify(quote, "action-1", req, stock, containers, catalog, reservations, divisibility, unrelated).ok,
		"unrelated world revision does not invalidate unchanged inventory")
	for key in ["inventory:player", "inventory:storage", "residents"]:
		var changed_rev: Dictionary = revisions()
		changed_rev[key] += 1
		check(verify(quote, "action-1", req, stock, containers, catalog, reservations, divisibility, changed_rev).code ==
			"STALE_SNAPSHOT", "changed mandatory revision invalidates quote: " + key)

	var changed_item: Array = items()
	changed_item[1].quantity = 3
	check(verify(quote, "action-1", req, changed_item, containers, catalog, reservations, divisibility, version).code ==
		"STALE_SNAPSHOT", "changing selected item quantity invalidates quote")
	changed_item = items()
	changed_item[3].container_id = "player"
	check(verify(quote, "action-1", req, changed_item, containers, catalog, reservations, divisibility, version).code ==
		"STALE_SNAPSHOT", "changing an unselected item's container invalidates quote")
	var changed_cap: Array = caps()
	changed_cap[1].capacity_mass_units += 1
	check(verify(quote, "action-1", req, stock, changed_cap, catalog, reservations, divisibility, version).code ==
		"STALE_SNAPSHOT", "changed capacity invalidates old quote")
	var changed_mass: Dictionary = mass()
	changed_mass.food = 1
	check(verify(quote, "action-1", req, stock, containers, changed_mass, reservations, divisibility, version).code ==
		"STALE_SNAPSHOT", "changed mass catalog invalidates quote")
	var changed_policy: Dictionary = policy()
	changed_policy.food = "whole_object"
	check(verify(quote, "action-1", req, stock, containers, catalog, reservations, changed_policy, version).code ==
		"STALE_SNAPSHOT", "changing a resource to indivisible invalidates old split")
	var changed_rows: Array = rows()
	changed_rows[0].quantity = 2
	check(verify(quote, "action-1", req, stock, containers, catalog, changed_rows, divisibility, version).code ==
		"STALE_SNAPSHOT", "changing NPC reservation without revision also invalidates quote")
	check(verify(quote, "action-1", req, stock, containers, catalog, [], divisibility, version).code ==
		"STALE_SNAPSHOT", "erasing all resident allocations cannot keep old quote")
	check(verify(quote, "other-action", req, stock, containers, catalog, reservations, divisibility, version).code ==
		"STALE_SNAPSHOT", "different action ID must not reuse generated split IDs or quote")
	var other_save: Dictionary = synthetic_identity()
	other_save.save_id = "different-save-slot"
	check(verify(quote, "action-1", req, stock, containers, catalog, reservations, divisibility, version, other_save).code ==
		"STALE_SNAPSHOT", "same item IDs from another save slot cannot reuse old quote")
	var other_storage: Dictionary = synthetic_identity()
	other_storage.storage_slot_key = "user://synthetic-slot-b.json"
	check(verify(quote, "action-1", req, stock, containers, catalog, reservations, divisibility, version, other_storage).code ==
		"STALE_SNAPSHOT", "two files with identical save_id slot-01 cannot reuse quotes")
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, version, other_storage).binding_fingerprint !=
		quote.binding_fingerprint, "trusted storage scope differentiates identical content and save_id")
	var other_actor: Dictionary = synthetic_identity()
	other_actor.actor_id = "npc-or-companion"
	check(verify(quote, "action-1", req, stock, containers, catalog, reservations, divisibility, version, other_actor).code ==
		"STALE_SNAPSHOT", "same command from a different actor cannot reuse old quote")
	var other_rules: Dictionary = synthetic_identity()
	other_rules.ruleset_version = "test-v2"
	check(verify(quote, "action-1", req, stock, containers, catalog, reservations, divisibility, version, other_rules).code ==
		"STALE_SNAPSHOT", "quote cannot cross ruleset version changes")
	var malformed_identity: Dictionary = synthetic_identity()
	malformed_identity.erase("actor_id")
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, version, malformed_identity).code ==
		"INVALID_IDENTITY", "missing trusted actor identity fails closed")
	malformed_identity = synthetic_identity()
	malformed_identity.save_id = ""
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, version, malformed_identity).code ==
		"INVALID_IDENTITY", "blank trusted save ID fails closed")
	malformed_identity = synthetic_identity()
	malformed_identity.erase("storage_slot_key")
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, version, malformed_identity).code ==
		"INVALID_IDENTITY", "missing trusted storage scope fails closed")
	malformed_identity = synthetic_identity()
	malformed_identity.storage_slot_key = ""
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, version, malformed_identity).code ==
		"INVALID_IDENTITY", "blank trusted storage scope fails closed")

	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, version, []).code ==
		"INVALID_IDENTITY", "identity must be explicitly typed trusted metadata")

	var changed_req: Dictionary = batch()
	changed_req.entries[0].quantity = 2
	check(verify(quote, "action-1", changed_req, stock, containers, catalog, reservations, divisibility, version).code ==
		"STALE_SNAPSHOT", "changed quantity never inherits old approval")

	var invalid_rev: Dictionary = revisions()
	invalid_rev.erase("residents")
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, invalid_rev).code ==
		"INVALID_REVISION", "omitted residents revision rejected")
	invalid_rev = revisions()
	invalid_rev.erase("inventory:player")
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, invalid_rev).code ==
		"INVALID_REVISION", "omitted source inventory revision rejected")
	invalid_rev = revisions()
	invalid_rev.erase("inventory:storage")
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, invalid_rev).code ==
		"INVALID_REVISION", "omitted destination inventory revision rejected")
	invalid_rev = revisions()
	invalid_rev.residents = -1
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, invalid_rev).code ==
		"INVALID_REVISION", "negative revision rejected")
	invalid_rev = revisions()
	invalid_rev.residents = 1.0
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, invalid_rev).code ==
		"INVALID_REVISION", "floating point revision rejected")
	check(bind("action-1", req, stock, containers, catalog, reservations, divisibility, null).code ==
		"INVALID_REVISION", "missing revision map rejected")
	var extra_mass: Dictionary = mass()
	extra_mass.unused = "not-a-mass"
	check(bind("action-1", req, stock, containers, extra_mass, reservations, divisibility, version).code ==
		"INVALID_CATALOG", "invalid extra mass catalog entry rejected")
	var extra_policy: Dictionary = policy()
	extra_policy.unused = "unknown-policy"
	check(bind("action-1", req, stock, containers, catalog, reservations, extra_policy, version).code ==
		"INVALID_CATALOG", "invalid extra divisibility catalog entry rejected")
	check(verify({}, "action-1", req, stock, containers, catalog, reservations, divisibility, version).code ==
		"INVALID_BINDING", "missing quote fingerprint rejected")
	check(verify({"binding_fingerprint": 5}, "action-1", req, stock, containers, catalog, reservations, divisibility, version).code ==
		"INVALID_BINDING", "wrong fingerprint type rejected")
	check(verify({"binding_fingerprint": "short"}, "action-1", req, stock, containers, catalog, reservations, divisibility, version).code ==
		"INVALID_BINDING", "short fingerprint rejected")
	var forged_preview: Dictionary = quote.duplicate(true)
	forged_preview.preview_items[0].quantity = 999999
	var rebuilt: Dictionary = verify(forged_preview, "action-1", req, stock, containers, catalog, reservations, divisibility, version)
	check(rebuilt.ok and rebuilt.preview_items[0].quantity != 999999
		and stock == expected_stock, "old quote preview is ignored and reconstructed from trusted state")
	check(stock == expected_stock and req == expected_req and reservations == expected_rows,
		"all failed revalidations keep original data unchanged")

func request_action(session, kind: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	var s: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in s.resource_revisions:
		versions.append({"key": key, "revision": s.resource_revisions[key]})
	return {"action_id": "a1-stale-real:%d" % serial, "command_type": kind,
		"payload": payload, "context": {"actor_id": "player",
			"scene_id": s.scene.current_scene_id, "expected_resource_revisions": versions}}

func act(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
	return session.execute(request_action(session, kind, payload), store)

func synthetic_caps(s: Dictionary) -> Array:
	var result: Array = []
	for container in s.inventory.containers:
		result.append({"id": container.id, "capacity_mass_units": 100000})
	return result

func synthetic_mass(rules: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for type_id in rules.items:
		result[type_id] = 1
	return result

func synthetic_policy(rules: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for type_id in rules.items:
		result[type_id] = "fungible_stack"
	return result

func cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func check_real() -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	check(Campaign.valid_rules(rules), "actual schema4 rule set accepted")
	var campaign = Campaign.new(rules)
	var session = campaign.coordinator
	check(session != null and session.get_snapshot().schema_version == 4,
		"actual schema4 session created")
	if session == null:
		return
	var path: String = "user://a1-stale-guard-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	cleanup(path)
	var store = Store.new(path)
	check(act(session, store, "scene.transition", {"destination_scene_id":"shelter",
		"entry_point_id":"default"}).ok, "enter shelter before first victory")
	check(act(session, store, "scene.transition", {"destination_scene_id":"hospital",
		"entry_point_id":"default"}).ok, "return to hospital")
	check(act(session, store, "game.enemy_defeated").ok, "first genuine enemy defeat")
	check(act(session, store, "scene.transition", {"destination_scene_id":"shelter",
		"entry_point_id":"default"}).ok, "return to shelter after first victory")
	check(act(session, store, "inventory.claim_parcel", {"parcel_id":"starter"}).ok,
		"starter parcel grants a real seed stack")
	var snapshot: Dictionary = session.get_snapshot()
	var separate = Campaign.new(rules).coordinator
	check(separate.get_snapshot().save_id == snapshot.save_id
		and snapshot.save_id == "slot-01",
		"real separate campaigns currently share hardcoded slot-01 save_id")
	var seed: Dictionary = {}
	for item in snapshot.inventory.items:
		if item.type_id == "seed.basic" and item.container_id == "player":
			seed = item
			break
	check(not seed.is_empty() and seed.quantity >= 2,
		"real campaign has a partial-transfer-capable seed stack")
	if seed.is_empty():
		cleanup(path)
		return
	var batch_request: Dictionary = {"from_id": "player", "to_id": "storage",
		"entries": [{"instance_id": seed.instance_id, "quantity": 1}]}
	var c: Array = synthetic_caps(snapshot)
	var m: Dictionary = synthetic_mass(rules)
	var p: Dictionary = synthetic_policy(rules)
	var binding: Dictionary = Guard.bind("a1-real-batch-quote", batch_request,
		snapshot.inventory.items, c, m, snapshot.inventory.reservations, p,
		snapshot.resource_revisions, identity(snapshot, path))
	check(binding.ok, "actual inventory snapshot can produce isolated synthetic-mass quote")
	if not binding.ok:
		cleanup(path)
		return
	check(campaign.tick(0.25), "real campaign fractional clock advances without item changes")
	var after_clock: Dictionary = session.get_snapshot()
	check(Guard.revalidate(binding, "a1-real-batch-quote", batch_request,
		after_clock.inventory.items, c, m, after_clock.inventory.reservations, p,
		after_clock.resource_revisions, identity(after_clock, path)).ok,
		"unrelated fractional time does not invalidate unchanged inventory quote")
	check(act(session, store, "inventory.transfer", {"instance_id": seed.instance_id,
		"from_id": "player", "to_id": "storage", "quantity": 1}).ok,
		"actual single transfer modifies inventory after quote was created")
	var after_real: Dictionary = session.get_snapshot()
	check(Guard.revalidate(binding, "a1-real-batch-quote", batch_request,
		after_real.inventory.items, c, m, after_real.inventory.reservations, p,
		after_real.resource_revisions, identity(after_real, path)).code == "STALE_SNAPSHOT",
		"actual durable inventory mutation invalidates old preview before batch")
	var reopened = Campaign.new(rules).coordinator
	check(reopened.load_checkpoint(store).ok, "actual changed inventory reloads from disk")
	var recovered: Dictionary = reopened.get_snapshot()
	check(Guard.revalidate(binding, "a1-real-batch-quote", batch_request,
		recovered.inventory.items, c, m, recovered.inventory.reservations, p,
		recovered.resource_revisions, identity(recovered, path)).code == "STALE_SNAPSHOT",
		"stale quote stays invalid after independent campaign reload")
	check(snapshot.inventory.items != recovered.inventory.items
		and not FileAccess.get_file_as_bytes(path).is_empty(),
		"real transfer was persisted; quote guard had no power to write checkpoint")
	cleanup(path)

func check_real_reservation() -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	var session = Campaign.new(rules).coordinator
	if session == null:
		check(false, "schema4 resident quote fixture initializes")
		return
	var path: String = "user://a1-stale-resident-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	cleanup(path)
	var store = Store.new(path)
	var preparation: Array = [
		act(session, store, "scene.transition", {"destination_scene_id":"shelter", "entry_point_id":"default"}),
		act(session, store, "scene.transition", {"destination_scene_id":"hospital", "entry_point_id":"default"}),
		act(session, store, "game.enemy_defeated"),
		act(session, store, "scene.transition", {"destination_scene_id":"shelter", "entry_point_id":"default"}),
		act(session, store, "inventory.claim_parcel", {"parcel_id":"starter"})
	]
	var ready: bool = preparation.all(func(result): return result.ok)
	check(ready, "real resident quote starts with shelter and first System victory")
	if not ready:
		cleanup(path)
		return
	for id in ["plot_1", "plot_2"]:
		ready = act(session, store, "game.plant", {"plot_id": id}).ok and ready
		ready = act(session, store, "game.water", {"plot_id": id}).ok and ready
	check(ready, "real schema4 farm creates two watered potato plots")
	if not ready:
		cleanup(path)
		return
	ready = act(session, store, "clock.rest", {"target_minute": int(rules.crop.grow_minutes)}).ok
	for id in ["plot_1", "plot_2"]:
		ready = act(session, store, "game.harvest", {"plot_id": id}).ok and ready
	check(ready, "real potatoes harvested before quote")
	if not ready:
		cleanup(path)
		return
	var route: Array = [
		act(session, store, "scene.transition", {"destination_scene_id":"hospital", "entry_point_id":"default"}),
		act(session, store, "scene.transition", {"destination_scene_id":"outside", "entry_point_id":"default"}),
		act(session, store, "scene.transition", {"destination_scene_id":"louvre", "entry_point_id":"default"})
	]
	ready = route.all(func(result): return result.ok)
	check(ready, "procedural scene graph reaches resident contact")
	if not ready:
		cleanup(path)
		return
	check(act(session, store, "game.contact", {"resident_id":"resident_1"}).ok,
		"actual resident contact established")
	check(act(session, store, "game.consent", {"resident_id":"resident_1", "accept":true}).ok,
		"actual NPC gives voluntary consent")
	var before: Dictionary = session.get_snapshot()
	var potato: Dictionary = {}
	for item in before.inventory.items:
		if item.type_id == "crop.potato" and item.container_id == "player":
			potato = item
			break
	check(not potato.is_empty() and potato.quantity >= 3,
		"real potato source available for partial quote before NPC ration")
	if potato.is_empty():
		cleanup(path)
		return
	var request_batch: Dictionary = {"from_id": "player", "to_id": "storage",
		"entries": [{"instance_id": potato.instance_id, "quantity": 1}]}
	var c: Array = synthetic_caps(before)
	var m: Dictionary = synthetic_mass(rules)
	var p: Dictionary = synthetic_policy(rules)
	var quote: Dictionary = Guard.bind("npc-stale-quote", request_batch,
		before.inventory.items, c, m, before.inventory.reservations, p,
		before.resource_revisions, identity(before, path))
	check(quote.ok, "pure quote accepts real unreserved potato stack")
	if not quote.ok:
		cleanup(path)
		return
	var old_primary: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(Guard.revalidate(quote, "npc-stale-quote", request_batch,
		before.inventory.items, c, m, before.inventory.reservations, p,
		before.resource_revisions, identity(before, path)).ok
		and FileAccess.get_file_as_bytes(path) == old_primary,
		"binding/revalidation are pure before NPC food reservation")
	var recruit: Dictionary = act(session, store, "game.recruit", {"resident_id":"resident_1"})
	check(recruit.ok and recruit.data.get("reserve_mode") == "reserve",
		"actual NPC recruitment commits a durable food reservation")
	if not recruit.ok:
		cleanup(path)
		return
	var after: Dictionary = session.get_snapshot()
	check(before.inventory.items == after.inventory.items
		and after.inventory.reservations.size() > before.inventory.reservations.size(),
		"reserve mode changes allocation rows while item quantities stay identical")
	var reserved: int = 0
	for row in after.inventory.reservations:
		if row.instance_id == potato.instance_id:
			reserved += int(row.quantity)
	check(reserved > 0, "reserved NPC ration affects the quoted potato instance")
	var persisted: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(Guard.revalidate(quote, "npc-stale-quote", request_batch,
		after.inventory.items, c, m, after.inventory.reservations, p,
		after.resource_revisions, identity(after, path)).code == "STALE_SNAPSHOT",
		"real NPC reservation invalidates quote despite unchanged food quantities")
	check(FileAccess.get_file_as_bytes(path) == persisted,
		"revalidation rejection never writes or modifies committed food receipt")
	var reopened = Campaign.new(rules).coordinator
	check(reopened.load_checkpoint(store).ok, "food reservation roundtrip reloads in real schema4")
	var fresh: Dictionary = reopened.get_snapshot()
	check(Guard.revalidate(quote, "npc-stale-quote", request_batch,
		fresh.inventory.items, c, m, fresh.inventory.reservations, p,
		fresh.resource_revisions, identity(fresh, path)).code == "STALE_SNAPSHOT",
		"post-reload NPC reservation still invalidates the old food quote")
	cleanup(path)

func run() -> void:
	check_pure()
	check_real()
	check_real_reservation()
	print("BATCH STALE GUARD TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
