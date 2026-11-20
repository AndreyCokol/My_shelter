extends SceneTree

# A4 black-box gameplay E2E. Exercises the ACTUAL A1 CoreSession/Save and
# gameplay commands; does not import A4 candidate helpers or change production.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Model = preload("res://game/state/campaign_model.gd")

var checks: int = 0
var failures: int = 0
var serial: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + message)
	else:
		print("PASS " + message)

func request(session, kind: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": "a4-live:%d" % serial, "command_type": kind, "payload": payload,
		"context": {"actor_id": "player", "scene_id": state.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

func act(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
	return session.execute(request(session, kind, payload), store)

func cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func quest(state: Dictionary, id: String) -> String:
	for entry in state.quests.records:
		if entry.id == id:
			return entry.status
	return "NOT_FOUND"

func resident(state: Dictionary, id: String) -> Dictionary:
	for entry in state.residents.records:
		if entry.id == id:
			return entry
	return {}

func begin(rules: Dictionary, path: String) -> Dictionary:
	cleanup(path)
	var campaign = Campaign.new(rules)
	var session = campaign.coordinator
	var store = Store.new(path)
	check(Model.validate(session.get_snapshot(), rules), "initial state accepted by real model")
	for id in ["Q03", "Q04", "Q05", "Q06", "Q07"]:
		check(quest(session.get_snapshot(), id) == "inactive", id + " starts optional and inactive")
	check(act(session, store, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}).ok,
		"shelter remains available before first victory")
	check(quest(session.get_snapshot(), "Q02") != "completed",
		"entering shelter before first kill does not falsely finish Q02")
	check(act(session, store, "scene.transition", {"destination_scene_id": "hospital", "entry_point_id": "default"}).ok,
		"early shelter return preserves hospital route")
	check(act(session, store, "game.enemy_defeated").ok,
		"first kill records System progression")
	check(quest(session.get_snapshot(), "Q01") == "completed",
		"first victory finishes Q01 once")
	check(act(session, store, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}).ok,
		"player can visit shelter after victory")
	check(quest(session.get_snapshot(), "Q02") == "completed",
		"Q02 credits post-victory shelter tutorial, without gate to G")
	return {"campaign": campaign, "store": store, "session": session}

func grow_two(session, store, rules: Dictionary) -> void:
	check(act(session, store, "inventory.claim_parcel", {"parcel_id": "starter"}).ok,
		"one-time parcel provides actual seeds")
	for id in ["plot_1", "plot_2"]:
		check(act(session, store, "game.plant", {"plot_id": id}).ok,
			id + " planted without tracking Q03")
		check(act(session, store, "game.water", {"plot_id": id}).ok,
			id + " watered without tracking Q03")
	check(act(session, store, "clock.rest", {"target_minute": int(rules.crop.grow_minutes)}).ok,
		"real game clock advances to plant maturity")
	for id in ["plot_1", "plot_2"]:
		check(act(session, store, "game.harvest", {"plot_id": id}).ok,
			id + " harvested despite inactive optional quests")
	check(quest(session.get_snapshot(), "Q03") == "inactive"
		and quest(session.get_snapshot(), "Q04") == "inactive",
		"farm and inventory work without activating Q03–Q04")

func free_sandbox(rules: Dictionary, path: String) -> void:
	var setup: Dictionary = begin(rules, path)
	var session = setup.session
	var store = setup.store
	grow_two(session, store, rules)
	check(act(session, store, "scene.transition", {"destination_scene_id": "outside", "entry_point_id": "default"}).ok,
		"outside remains explorable with Q03–Q07 inactive")
	check(act(session, store, "game.resource_collect").ok,
		"city has collectable resources without tracking quests")
	check(act(session, store, "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}).ok,
		"contact area available without tracking quests")
	check(act(session, store, "game.contact", {"resident_id": "resident_1"}).ok,
		"real contact is independent of optional quest activation")
	check(act(session, store, "game.consent", {"resident_id": "resident_1", "accept": false}).ok,
		"voluntary refusal is persisted")
	var after_refusal: Dictionary = session.get_snapshot()
	check(resident(after_refusal, "resident_1").status == "declined"
		and not resident(after_refusal, "resident_1").consent,
		"refused candidate does not become a shelter resident")
	check(act(session, store, "game.recruit", {"resident_id": "resident_1"}).code == "REQUIRES_CONSENT",
		"cannot recruit a refused candidate with abundant food")
	check(session.get_snapshot().inventory.reservations.is_empty()
		and quest(session.get_snapshot(), "Q07") == "inactive",
		"refusal creates neither reserved food nor quest completion")
	var saved: Dictionary = session.get_snapshot()
	var reloaded = Campaign.new(rules)
	check(reloaded.coordinator.load_checkpoint(store).ok
		and reloaded.coordinator.get_snapshot() == saved,
		"refusal, idle quests and exploration survive real checkpoint restart")
	check(act(reloaded.coordinator, store, "game.quest_track", {"quest_id": "Q03"}).ok
		and quest(reloaded.coordinator.get_snapshot(), "Q03") == "completed",
		"optional Q03 can be tracked after actual farm action")
	check(act(reloaded.coordinator, store, "game.quest_track", {"quest_id": "Q04"}).ok
		and quest(reloaded.coordinator.get_snapshot(), "Q04") == "completed",
		"optional Q04 can be credited after earlier harvest")
	check(quest(reloaded.coordinator.get_snapshot(), "Q07") == "inactive",
		"Q07 is not silently forced by declining optional NPC")
	cleanup(path)

func waiting_then_join(rules: Dictionary, path: String) -> void:
	var setup: Dictionary = begin(rules, path)
	var session = setup.session
	var store = setup.store
	check(act(session, store, "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}).ok,
		"player can contact people before farming")
	check(act(session, store, "game.contact", {"resident_id": "resident_1"}).ok,
		"contact real NPC before obtaining food")
	check(act(session, store, "game.consent", {"resident_id": "resident_1", "accept": true}).ok,
		"candidate records explicit voluntary agreement")
	var before: Dictionary = session.get_snapshot()
	var failed := request(session, "game.recruit", {"resident_id": "resident_1"})
	check(session.execute(failed, store).code == "INSUFFICIENT_RESOURCES"
		and session.get_snapshot() == before,
		"food shortage makes no partial NPC/inventory/receipt mutation")
	check(resident(session.get_snapshot(), "resident_1").status == "AWAITING_SUPPLIES",
		"shortage preserves accepted consent and waiting status")
	var loaded = Campaign.new(rules)
	check(loaded.coordinator.load_checkpoint(store).ok and loaded.coordinator.get_snapshot() == before,
		"waiting and consent survive reload before food is available")
	session = loaded.coordinator
	check(act(session, store, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}).ok,
		"waiting does not block travel to farm")
	grow_two(session, store, rules)
	check(act(session, store, "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}).ok,
		"harvest can be brought back to waiting NPC")
	var join := request(session, "game.recruit", {"resident_id": "resident_1"})
	check(session.execute(join, store).ok
		and resident(session.get_snapshot(), "resident_1").status == "joined"
		and session.get_snapshot().inventory.reservations.size() == 1,
		"first resident is joined and food reservation written atomically")
	var after_join: Dictionary = session.get_snapshot()
	check(session.execute(join, store).code == "ALREADY_APPLIED"
		and session.get_snapshot() == after_join,
		"identical recruit action cannot duplicate resident or food")
	check(act(session, store, "game.contact", {"resident_id": "resident_2"}).ok,
		"second NPC contact is independent")
	check(act(session, store, "game.consent", {"resident_id": "resident_2", "accept": true}).ok,
		"second NPC consents independently")
	check(act(session, store, "game.recruit", {"resident_id": "resident_2"}).ok,
		"second NPC enters shelter after actual food check")
	var held: Dictionary = {}
	for reservation in session.get_snapshot().inventory.reservations:
		var owner: String = reservation.resident_id
		held[owner] = int(held.get(owner, 0)) + int(reservation.quantity)
	check(held.size() == 2
		and held.get("resident_1", 0) == rules.food.units_per_resident
		and held.get("resident_2", 0) == rules.food.units_per_resident
		and quest(session.get_snapshot(), "Q07") == "inactive",
		"both residents have correct ration totals independent of fragmented item stacks")
	for id in ["Q05", "Q06", "Q07"]:
		check(act(session, store, "game.quest_track", {"quest_id": id}).ok
			and quest(session.get_snapshot(), id) == "completed",
			"late tracking " + id + " observes already committed NPC facts")
	var final_state: Dictionary = session.get_snapshot()
	var reload = Campaign.new(rules)
	check(reload.coordinator.load_checkpoint(store).ok
		and reload.coordinator.get_snapshot() == final_state,
		"joined roster, reservations and quest completion survive reload")
	check(reload.coordinator.execute(join, store).code == "ALREADY_APPLIED",
		"first recruitment retains same action receipt across restart")
	check(act(reload.coordinator, store, "game.recruit", {"resident_id": "resident_1"}).code == "INVALID_STATE",
		"new action ID cannot recruit joined NPC twice")
	check(reload.coordinator.get_snapshot().inventory.reservations == final_state.inventory.reservations,
		"replay preserves exact reserved food allocations without duplicating stacks")
	cleanup(path)

func consume_mode_replay(base_rules: Dictionary, path: String) -> void:
	# Alternate, synthetic policy; no game-balancing proposal.
	var rules: Dictionary = base_rules.duplicate(true)
	rules.food.reserve_mode = "consume"
	rules.food.units_per_resident = 3
	check(Campaign.valid_rules(rules), "synthetic three-unit consume-ration policy validates")
	var setup: Dictionary = begin(rules, path)
	var session = setup.session
	var store = setup.store
	grow_two(session, store, rules)
	check(act(session, store, "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}).ok,
		"consume-mode NPC contact area available")
	for id in ["resident_1", "resident_2"]:
		check(act(session, store, "game.contact", {"resident_id": id}).ok,
			"consume-mode contact " + id)
		check(act(session, store, "game.consent", {"resident_id": id, "accept": true}).ok,
			"consume-mode consent " + id)
		var join := request(session, "game.recruit", {"resident_id": id})
		check(session.execute(join, store).ok and resident(session.get_snapshot(), id).status == "joined",
			"consume-mode recruit " + id)
		var after: Dictionary = session.get_snapshot()
		check(session.execute(join, store).code == "ALREADY_APPLIED"
			and session.get_snapshot() == after,
			"consume-mode receipt cannot charge extra food for " + id)
	var potato_units: int = 0
	for item in session.get_snapshot().inventory.items:
		if item.type_id == "crop.potato":
			potato_units += int(item.quantity)
	check(potato_units == 0 and session.get_snapshot().inventory.reservations.is_empty(),
		"consume policy spends six food once and does not create phantom reservations")
	var saved: Dictionary = session.get_snapshot()
	check(Model.validate(saved, rules), "two consumed food receipts form a valid real save")
	var reloaded = Campaign.new(rules)
	check(reloaded.coordinator.load_checkpoint(store).ok and reloaded.coordinator.get_snapshot() == saved,
		"consume-mode joined NPCs and historical food receipts survive reload")
	check(act(reloaded.coordinator, store, "game.recruit", {"resident_id": "resident_1"}).code == "INVALID_STATE"
		and reloaded.coordinator.get_snapshot().inventory.reservations.is_empty(),
		"new action cannot recharge consumed ration after restart")
	cleanup(path)

func run() -> void:
	var rules: Dictionary = Rules.build()
	check(Campaign.valid_rules(rules), "current P0 food rules validate")
	var prefix: String = "user://a4-live-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var base: String = ProjectSettings.globalize_path(prefix)
	check(DirAccess.make_dir_recursive_absolute(base) == OK,
		"dedicated isolated test save directory exists")
	free_sandbox(rules, prefix.path_join("free.json"))
	waiting_then_join(rules, prefix.path_join("waiting.json"))
	consume_mode_replay(rules, prefix.path_join("consume.json"))
	DirAccess.remove_absolute(base)
	print("A4 LIVE STORY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
