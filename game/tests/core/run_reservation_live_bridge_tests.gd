extends SceneTree

# A1 bridge E2E: real schema4 Campaign + NPC food reservations -> pure
# per-item reservation aggregate -> batch preflight. No batch command is applied.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Reservations = preload("res://game/contracts/item_reservation_totals_candidate.gd")
const Preflight = preload("res://game/contracts/batch_mass_preflight_candidate.gd")

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

func request(session, kind: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": "a1:reservation-live:%d" % serial,
		"command_type": kind, "payload": payload,
		"context": {"actor_id":"player", "scene_id":state.scene.current_scene_id,
			"expected_resource_revisions":revisions}}

func action(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
	return session.execute(request(session, kind, payload), store)

func cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func run() -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	check(Campaign.valid_rules(rules), "real schema4 gameplay rules validate")
	var session = Campaign.new(rules).coordinator
	check(session != null and session.get_snapshot().schema_version == 4,
		"real procedural schema4 session constructed")
	if session == null:
		quit(1)
		return
	var path: String = "user://a1-reservation-live-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	cleanup(path)
	var store = Store.new(path)

	var results: Array = [
		action(session, store, "scene.transition", {"destination_scene_id":"shelter","entry_point_id":"default"}),
		action(session, store, "scene.transition", {"destination_scene_id":"hospital","entry_point_id":"default"}),
		action(session, store, "game.enemy_defeated"),
		action(session, store, "scene.transition", {"destination_scene_id":"shelter","entry_point_id":"default"}),
		action(session, store, "inventory.claim_parcel", {"parcel_id":"starter"})
	]
	check(results.all(func(r): return r.ok), "real story/shelter/starter parcel preparation")
	if not results.all(func(r): return r.ok):
		cleanup(path)
		quit(1)
		return
	for id in ["plot_1", "plot_2"]:
		check(action(session, store, "game.plant", {"plot_id":id}).ok,
			"real schema4 crop planted " + id)
		check(action(session, store, "game.water", {"plot_id":id}).ok,
			"real schema4 crop watered " + id)
	check(action(session, store, "clock.rest", {"target_minute": int(rules.crop.grow_minutes)}).ok,
		"real clock reaches crop maturity")
	for id in ["plot_1", "plot_2"]:
		check(action(session, store, "game.harvest", {"plot_id":id}).ok,
			"real schema4 crop harvested " + id)

	check(action(session, store, "scene.transition",
		{"destination_scene_id":"hospital","entry_point_id":"default"}).ok,
		"can return from shelter to hospital")
	check(action(session, store, "scene.transition",
		{"destination_scene_id":"outside","entry_point_id":"default"}).ok,
		"can travel from hospital to the real outside region")
	check(action(session, store, "scene.transition",
		{"destination_scene_id":"louvre","entry_point_id":"default"}).ok,
		"real schema4 route reaches recruitable NPC")
	var recruit_receipts: Array = []
	for id in ["resident_1", "resident_2"]:
		check(action(session, store, "game.contact", {"resident_id":id}).ok,
			"real NPC contact " + id)
		check(action(session, store, "game.consent", {"resident_id":id, "accept":true}).ok,
			"real voluntary NPC agreement " + id)
		var req: Dictionary = request(session, "game.recruit", {"resident_id":id})
		var result: Dictionary = session.execute(req, store)
		check(result.ok, "real schema4 NPC recruitment reserves food " + id)
		recruit_receipts.append(req)
	if failures > 0:
		cleanup(path)
		print("RESERVATION LIVE BRIDGE TESTS: %d checks, %d failures" % [checks, failures])
		quit(1)
		return

	var saved: Dictionary = session.get_snapshot()
	check(saved.inventory.reservations.size() >= 2,
		"resident food reservations persisted as actual inventory rows")
	var agg: Dictionary = Reservations.aggregate(saved.inventory.items, saved.inventory.reservations)
	check(agg.ok and not agg.reserved_by_instance.is_empty(),
		"pure A1 adapter accepts live gameplay reservation records")
	var reserved_units: int = 0
	if agg.ok:
		for n in agg.reserved_by_instance.values():
			reserved_units += int(n)
	check(reserved_units == int(rules.food.units_per_resident) * 2,
		"totals across rows equal exactly two historical resident rations")
	var by_row: int = 0
	for part in saved.inventory.reservations:
		by_row += int(part.quantity)
	check(by_row == reserved_units, "aggregate conserves actual reserved units across split stacks")

	# Mass numbers are intentionally synthetic one-unit test catalog values.
	var test_mass_catalog: Dictionary = {}
	for id in rules.items:
		test_mass_catalog[id] = 1
	var test_caps: Array = []
	for container in saved.inventory.containers:
		test_caps.append({"id":container.id, "capacity_mass_units":100000})
	var selected: Dictionary = {}
	for item in saved.inventory.items:
		if agg.ok and agg.reserved_by_instance.has(item.instance_id):
			selected = item
			break
	check(not selected.is_empty(), "find a real food stack that contains resident-held units")
	if not selected.is_empty():
		var dest: String = "storage" if selected.container_id != "storage" else "player"
		var move_request: Dictionary = {"from_id":selected.container_id, "to_id":dest,
			"entries":[{"instance_id":selected.instance_id, "quantity":selected.quantity}]}
		var original_snapshot: Dictionary = session.get_snapshot()
		var result: Dictionary = Preflight.prepare_from_rows(move_request, saved.inventory.items,
			test_caps, test_mass_catalog, saved.inventory.reservations)
		check(result.code == "INSUFFICIENT_RESOURCES" and not result.has("preview_items"),
			"real NPC-reserved stack cannot pass full-instance batch preflight")
		check(session.get_snapshot() == original_snapshot,
			"no batch preview may alter actual game state")
	var fresh = Campaign.new(rules).coordinator
	check(fresh.load_checkpoint(store).ok and fresh.get_snapshot() == saved,
		"real schema4 residents and food reservations survive disk reload")
	if agg.ok:
		check(Reservations.aggregate(fresh.get_snapshot().inventory.items,
			fresh.get_snapshot().inventory.reservations) == agg,
			"reservation aggregate stays identical after real save roundtrip")
	check(fresh.execute(recruit_receipts[0], store).code == "ALREADY_APPLIED"
		and fresh.get_snapshot().inventory.reservations == saved.inventory.reservations,
		"recruit receipt replay cannot append another food reservation")
	cleanup(path)
	print("RESERVATION LIVE BRIDGE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
