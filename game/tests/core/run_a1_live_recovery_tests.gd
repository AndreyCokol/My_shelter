extends SceneTree

# A1-05 actual schema4 campaign save fault isolation. No gameplay edits.
# Simulates errors immediately before and after primary replacement. This
# does NOT simulate arbitrary hardware loss or a live Windows GUI.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Reservations = preload("res://game/contracts/item_reservation_totals_candidate.gd")

var checks: int = 0
var failures: int = 0
var serial: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func request(session, kind: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	var s: Dictionary = session.get_snapshot()
	var versions: Array = []
	for key in s.resource_revisions:
		versions.append({"key": key, "revision": s.resource_revisions[key]})
	return {"action_id": "a1-fault:%d" % serial, "command_type": kind,
		"payload": payload, "context": {"actor_id": "player",
			"scene_id": s.scene.current_scene_id,
			"expected_resource_revisions": versions}}

func act(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
	return session.execute(request(session, kind, payload), store)

func cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".rejected", ".rejected.1"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func item_with_type(snapshot: Dictionary, type_id: String) -> Dictionary:
	for item in snapshot.inventory.items:
		if item.type_id == type_id and item.container_id == "player":
			return item
	return {}

func npc(snapshot: Dictionary, resident_id: String) -> Dictionary:
	for record in snapshot.residents.records:
		if record.id == resident_id:
			return record
	return {}

func create_ready_campaign(rules: Dictionary, store):
	var session = Campaign.new(rules).coordinator
	check(session.get_snapshot().schema_version == 4, "real schema4 source state")
	var preparations: Array = [
		act(session, store, "scene.transition",
			{"destination_scene_id": "shelter", "entry_point_id": "default"}),
		act(session, store, "scene.transition",
			{"destination_scene_id": "hospital", "entry_point_id": "default"}),
		act(session, store, "game.enemy_defeated"),
		act(session, store, "scene.transition",
			{"destination_scene_id": "shelter", "entry_point_id": "default"}),
		act(session, store, "inventory.claim_parcel", {"parcel_id": "starter"})
	]
	check(preparations.all(func(r): return r.ok), "real Q01 and starter parcel setup")
	if not preparations.all(func(r): return r.ok):
		return null
	for plot in ["plot_1", "plot_2"]:
		check(act(session, store, "game.plant", {"plot_id": plot}).ok,
			"plant " + plot + " without optional quests")
		check(act(session, store, "game.water", {"plot_id": plot}).ok,
			"water " + plot + " without optional quests")
	check(act(session, store, "clock.rest",
		{"target_minute": int(rules.crop.grow_minutes)}).ok,
		"real farm clock matures both plots")
	for plot in ["plot_1", "plot_2"]:
		check(act(session, store, "game.harvest", {"plot_id": plot}).ok,
			"real harvest " + plot)
	for destination in ["hospital", "outside", "louvre"]:
		check(act(session, store, "scene.transition",
			{"destination_scene_id": destination, "entry_point_id": "default"}).ok,
			"procedural route to " + destination)
	check(act(session, store, "game.contact",
		{"resident_id": "resident_1"}).ok, "contact historical resident_1")
	check(act(session, store, "game.consent",
		{"resident_id": "resident_1", "accept": true}).ok,
		"voluntary NPC consent committed before injected save failure")
	check(npc(session.get_snapshot(), "resident_1").status == "AWAITING_SUPPLIES",
		"NPC still waiting before actual food receipt")
	return session

func count_allocations(snapshot: Dictionary, resident_id: String) -> int:
	var total: int = 0
	for row in snapshot.inventory.reservations:
		if row.resident_id == resident_id:
			total += int(row.quantity)
	return total

func test_recruit_fault(rules: Dictionary, path: String) -> Dictionary:
	cleanup(path)
	var store = Store.new(path)
	var session = create_ready_campaign(rules, store)
	if session == null:
		return {}
	var old: Dictionary = session.get_snapshot()
	var old_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var old_backup: PackedByteArray = FileAccess.get_file_as_bytes(path + ".bak")
	var req: Dictionary = request(session, "game.recruit", {"resident_id": "resident_1"})
	var committed_signals: Array = [0]
	session.committed.connect(func(_result): committed_signals[0] += 1)
	store.fault = "before_replace"
	check(session.execute(req, store).code == "SAVE_FAILED",
		"before_replace refuses real NPC recruit without committing")
	check(session.get_snapshot() == old and not session.requires_recovery(),
		"before_replace keeps original RAM and does not pause for recovery")
	check(FileAccess.get_file_as_bytes(path) == old_bytes
		and FileAccess.get_file_as_bytes(path + ".bak") == old_backup,
		"before_replace preserves primary and historical backup byte-for-byte")
	check(committed_signals[0] == 0,
		"pre-commit failure emits no committed callback")
	store.fault = "after_replace"
	check(session.execute(req, store).code == "UNAVAILABLE",
		"after_replace reports uncertain result instead of false failure")
	check(session.requires_recovery()
		and session.get_snapshot() == old and committed_signals[0] == 0,
		"after durable primary replacement RAM remains old and recovery is mandatory")
	var durable: Dictionary = store.read_checkpoint()
	check(durable.ok and durable.state != old
		and npc(durable.state, "resident_1").status == "joined",
		"primary checkpoint contains exactly the completed recruit state")
	if not durable.ok:
		store.fault = ""
		cleanup(path)
		return {}
	check(Model.validate(durable.state, rules) and durable.state.completed_actions.has(req.action_id),
		"uncertain primary includes a valid linked historic recruit receipt")
	check(FileAccess.get_file_as_bytes(path + ".bak") == old_bytes,
		"post-replace backup retains immediate pre-recruit snapshot")
	check(session.execute(request(session, "session.save"), store).code == "UNAVAILABLE",
		"blocked live session cannot write another command during uncertainty")
	check(session.execute(req, store).code == "UNAVAILABLE",
		"replay is also held until mandatory recovery rather than re-planned")
	store.fault = ""
	check(session.load_checkpoint(store).ok and not session.requires_recovery(),
		"explicit reload restores durable primary and clears recovery lock")
	var restored: Dictionary = session.get_snapshot()
	check(restored == durable.state and count_allocations(restored, "resident_1") ==
		int(rules.food.units_per_resident), "reload restores exact food allocations once")
	var canonical: Dictionary = Reservations.aggregate(restored.inventory.items,
		restored.inventory.reservations)
	check(canonical.ok and not canonical.reserved_by_instance.is_empty(),
		"restored NPC reservations remain valid for A1 trusted aggregation")
	var persisted_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(session.execute(req, store).code == "ALREADY_APPLIED"
		and session.get_snapshot() == restored,
		"original recruit request replays its historic receipt after recovery")
	var bad: Dictionary = req.duplicate(true)
	bad.context.actor_id = "different-actor"
	check(session.execute(bad, store).code == "ACTION_CONFLICT",
		"same receipt ID from different actor cannot recruit again")
	check(act(session, store, "game.recruit", {"resident_id": "resident_1"}).code == "INVALID_STATE",
		"a new action ID cannot join an already admitted NPC again")
	check(FileAccess.get_file_as_bytes(path) == persisted_bytes
		and session.get_snapshot().inventory.reservations == restored.inventory.reservations,
		"all replay and conflict paths leave disk bytes and allocations unchanged")
	check(committed_signals[0] == 0,
		"no duplicate commit callback emitted for uncertain transaction or its replay")
	return {"session": session, "store": store, "old_bytes": old_bytes}

func test_partial_transfer_fault(state: Dictionary, path: String, rules: Dictionary) -> void:
	var session = state.get("session")
	var store = state.get("store")
	if session == null or store == null:
		return
	var before: Dictionary = session.get_snapshot()
	var seeds: Dictionary = item_with_type(before, "seed.basic")
	check(not seeds.is_empty() and int(seeds.get("quantity", 0)) >= 2,
		"real unreserved starter seeds remain available for partial transfer")
	if seeds.is_empty() or int(seeds.quantity) < 2:
		cleanup(path)
		return
	var qty: int = 1
	var req: Dictionary = request(session, "inventory.transfer",
		{"instance_id": seeds.instance_id, "from_id": "player",
			"to_id": "storage", "quantity": qty})
	var primary_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var backup_before: PackedByteArray = FileAccess.get_file_as_bytes(path + ".bak")
	store.fault = "before_replace"
	check(session.execute(req, store).code == "SAVE_FAILED",
		"partial-stack transfer cannot commit during before_replace fault")
	check(session.get_snapshot() == before
		and FileAccess.get_file_as_bytes(path) == primary_before
		and FileAccess.get_file_as_bytes(path + ".bak") == backup_before,
		"pre-replace split failure preserves inventory, primary and backup")
	store.fault = "after_replace"
	check(session.execute(req, store).code == "UNAVAILABLE" and session.requires_recovery(),
		"post-replace split enters recovery instead of creating another source")
	var committed: Dictionary = store.read_checkpoint()
	check(committed.ok and committed.state.completed_actions.has(req.action_id),
		"durable split receipt committed exactly once before uncertain reply")
	if not committed.ok:
		store.fault = ""
		cleanup(path)
		return
	var split_id: String = "split:" + req.action_id
	var split_stack: Array = committed.state.inventory.items.filter(
		func(item): return item.instance_id == split_id)
	var remaining: Array = committed.state.inventory.items.filter(
		func(item): return item.instance_id == seeds.instance_id)
	check(split_stack.size() == 1
		and split_stack[0].quantity == qty and split_stack[0].container_id == "storage"
		and remaining.size() == 1 and remaining[0].quantity == seeds.quantity - qty,
		"one stable split ID and one reduced source, with quantity conserved")
	check(FileAccess.get_file_as_bytes(path + ".bak") == primary_before,
		"split post-replace backup is exactly the pre-split save")
	store.fault = ""
	check(session.load_checkpoint(store).ok and session.get_snapshot() == committed.state,
		"split receipt and inventory state recover precisely from disk")
	var persisted: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(session.execute(req, store).code == "ALREADY_APPLIED"
		and session.get_snapshot() == committed.state,
		"identical partial transfer replay never creates second split")
	var changed: Dictionary = req.duplicate(true)
	changed.payload.quantity = 2
	check(session.execute(changed, store).code == "ACTION_CONFLICT",
		"same ID with changed split quantity conflicts after restart")
	check(FileAccess.get_file_as_bytes(path) == persisted,
		"split replay and collision do not rewrite a valid primary")
	var next_session = Campaign.new(rules).coordinator
	check(next_session.load_checkpoint(store).ok
		and next_session.execute(req, store).code == "ALREADY_APPLIED"
		and next_session.get_snapshot().inventory.items == committed.state.inventory.items,
		"second independent reload preserves split receipt and no duplicate items")
	check(Model.validate(next_session.get_snapshot(), rules),
		"recovered schema4 with split stack and NPC ration remains valid")
	cleanup(path)

func run() -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	check(Campaign.valid_rules(rules), "real schema4 fault fixture rules validate")
	var path: String = "user://a1-fault-recovery-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var fixture: Dictionary = test_recruit_fault(rules, path)
	if not fixture.is_empty():
		test_partial_transfer_fault(fixture, path, rules)
	else:
		cleanup(path)
	print("A1 LIVE RECOVERY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
