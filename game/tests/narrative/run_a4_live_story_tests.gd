extends SceneTree

# A4 black-box gameplay E2E. Exercises the ACTUAL A1 CoreSession/Save and
# gameplay commands; does not import A4 candidate helpers or change production.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const NPCPolicy = preload("res://game/systems/narrative/npc_policy_candidate.gd")

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

# A4-03 command-level bridge: no synthetic food or pre-seeded System state.
# Source seeds are collected using the real outside command; the NPCs use
# the same A1-authoritative recruitment and historical food receipts as schema3.
# This does NOT prove physical pickup or NPC behaviour/GUI on the 3D map.
func schema4_finish_recruitment(rules: Dictionary, session, store, seed_value: int) -> void:
	var tag: String = "schema4 seed %d: " % seed_value
	check(act(session, store, "scene.transition",
		{"destination_scene_id": "outside", "entry_point_id": "default"}).ok,
		tag + "existing outside can provide real farm seed")
	check(act(session, store, "game.resource_collect").ok,
		tag + "real outside command gives two farm seeds with no starter parcel")
	check(act(session, store, "scene.transition",
		{"destination_scene_id": "shelter", "entry_point_id": "default"}).ok,
		tag + "collected seeds travel back to always-accessible shelter")
	for plot_id in ["plot_1", "plot_2"]:
		check(act(session, store, "game.plant", {"plot_id": plot_id}).ok,
			tag + plot_id + " plants with actual collected seed")
		check(act(session, store, "game.water", {"plot_id": plot_id}).ok,
			tag + plot_id + " is watered in shelter")
	var ready_minute: int = int(session.get_snapshot().game_time_minutes) + int(rules.crop.grow_minutes)
	check(act(session, store, "clock.rest", {"target_minute": ready_minute}).ok,
		tag + "existing A1 clock reaches crop readiness")
	for plot_id in ["plot_1", "plot_2"]:
		check(act(session, store, "game.harvest", {"plot_id": plot_id}).ok,
			tag + plot_id + " produces real potato inventory")
	check(act(session, store, "scene.transition",
		{"destination_scene_id": "outside", "entry_point_id": "default"}).ok,
		tag + "NPC return route goes through real outside")
	check(act(session, store, "scene.transition",
		{"destination_scene_id": "louvre", "entry_point_id": "default"}).ok,
		tag + "real generated route reaches waiting survivor")
	var first_join: Dictionary = request(session, "game.recruit", {"resident_id": "resident_1"})
	check(session.execute(first_join, store).ok
		and resident(session.get_snapshot(), "resident_1").status == "joined",
		tag + "waiting and voluntary consenting resident joins after actual harvest")
	var joined_once: Dictionary = session.get_snapshot()
	check(session.execute(first_join, store).code == "ALREADY_APPLIED"
		and session.get_snapshot() == joined_once,
		tag + "same recruit action cannot duplicate resident or food")
	check(act(session, store, "game.contact", {"resident_id": "resident_2"}).ok,
		tag + "second survivor contact independent")
	check(act(session, store, "game.consent",
		{"resident_id": "resident_2", "accept": true}).ok,
		tag + "second survivor explicitly consents")
	check(act(session, store, "game.recruit", {"resident_id": "resident_2"}).ok
		and resident(session.get_snapshot(), "resident_2").status == "joined",
		tag + "second survivor joins using remaining harvested food")
	var paid_by_resident: Dictionary = {}
	for row in session.get_snapshot().inventory.reservations:
		paid_by_resident[row.resident_id] = int(paid_by_resident.get(row.resident_id, 0)) + int(row.quantity)
	check(paid_by_resident.size() == 2
		and paid_by_resident.get("resident_1", 0) == int(rules.food.units_per_resident)
		and paid_by_resident.get("resident_2", 0) == int(rules.food.units_per_resident)
		and quest(session.get_snapshot(), "Q07") == "inactive",
		tag + "food reservations sum per joined NPC while Q07 remains optional")
	check(act(session, store, "game.quest_track", {"quest_id": "Q07"}).ok
		and quest(session.get_snapshot(), "Q07") == "completed",
		tag + "tracking Q07 AFTER recruiting both observes real current state")
	var final_state: Dictionary = session.get_snapshot()
	var reopened = Campaign.new(rules)
	check(reopened.coordinator.load_checkpoint(store).ok
		and reopened.coordinator.get_snapshot() == final_state,
		tag + "joined NPCs, Q07 and inventory reservations survive disk reload")
	check(reopened.coordinator.execute(first_join, store).code == "ALREADY_APPLIED"
		and reopened.coordinator.get_snapshot() == final_state,
		tag + "historical recruit receipt remains once-only after restart")
	check(act(reopened.coordinator, store, "game.recruit",
		{"resident_id": "resident_1"}).code == "INVALID_STATE"
		and reopened.coordinator.get_snapshot() == final_state,
		tag + "new ID cannot recruit the same joined NPC twice")

func schema4_contact_and_reload(base_rules: Dictionary, path: String, seed_value: int) -> void:
	# Cross-check the currently deployed world-seeded schema4, not merely
	# the older four-scene schema3 test world.
	var rules: Dictionary = base_rules.duplicate(true)
	rules.world_seed = seed_value
	rules.scenes = Layout.entries()
	check(Campaign.valid_rules(rules), "world-seeded schema4 real rules validate seed " + str(seed_value))
	var setup: Dictionary = begin(rules, path)
	var session = setup.session
	var store = setup.store
	check(session.get_snapshot().schema_version == 4
		and session.get_snapshot().world_states.layout.seed == seed_value,
		"NPC quest test actually runs in production-style schema4 world")
	check(act(session, store, "scene.transition", {"destination_scene_id": "hospital", "entry_point_id": "default"}).ok,
		"world-seeded shelter return follows saved hospital identity")
	check(act(session, store, "scene.transition", {"destination_scene_id": "outside", "entry_point_id": "default"}).ok,
		"schema4 hospital links physically to first street")
	check(act(session, store, "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}).ok,
		"schema4 real street links to NPC contact area")
	check(act(session, store, "game.contact", {"resident_id": "resident_1"}).ok,
		"schema4 NPC can be contacted after actual routed travel")
	check(act(session, store, "game.consent", {"resident_id": "resident_1", "accept": true}).ok,
		"schema4 contact stores informed-consent state")
	var before: Dictionary = session.get_snapshot()
	check(act(session, store, "game.recruit", {"resident_id": "resident_1"}).code == "INSUFFICIENT_RESOURCES"
		and session.get_snapshot() == before,
		"schema4 food shortage cannot partially recruit NPC")
	var loaded = Campaign.new(rules)
	check(loaded.coordinator.load_checkpoint(store).ok and loaded.coordinator.get_snapshot() == before,
		"schema4 generated-world identity, consent and revisions survive reload")
	check(resident(loaded.coordinator.get_snapshot(), "resident_1").status == "AWAITING_SUPPLIES"
		and quest(loaded.coordinator.get_snapshot(), "Q07") == "inactive",
		"schema4 preserves accepted-but-waiting NPC and optional Q07")
	check(act(loaded.coordinator, store, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}).ok,
		"schema4 NPC visit never disables immediate shelter escape")
	var reloaded = Campaign.new(rules)
	check(reloaded.coordinator.load_checkpoint(store).ok
		and reloaded.coordinator.get_snapshot().scene.current_scene_id == "shelter"
		and resident(reloaded.coordinator.get_snapshot(), "resident_1").status == "AWAITING_SUPPLIES",
		"schema4 shelter save roundtrip preserves NPC consent history")
	schema4_finish_recruitment(rules, reloaded.coordinator, store, seed_value)
	cleanup(path)

# TEMPORARY DIAGNOSTIC ONLY: intentionally verifies a current Core trust gap.
# This must not be treated as a passing acceptance test or cherry-picked to
# the main A4 PR. A1 is responsible for the real refusal/recontact fix.
func diagnostic_current_consent_gap(rules: Dictionary, path: String) -> void:
	var setup: Dictionary = begin(rules, path)
	var session = setup.session
	var store = setup.store
	check(act(session, store, "scene.transition",
		{"destination_scene_id": "louvre", "entry_point_id": "default"}).ok,
		"diagnostic reaches existing NPC area")
	check(act(session, store, "game.contact", {"resident_id": "resident_1"}).ok,
		"diagnostic makes first legitimate contact")
	check(act(session, store, "game.consent",
		{"resident_id": "resident_1", "accept": false}).ok,
		"diagnostic records actual NPC refusal in Core")
	var declined: Dictionary = session.get_snapshot()
	check(resident(declined, "resident_1").status == "declined"
		and not resident(declined, "resident_1").consent,
		"diagnostic refusal persisted as declined")
	var policy_npc: Dictionary = {"id": "resident_1", "role": "recruitable",
		"status": "declined", "consent": false, "faction_leader": false, "scripted": false}
	var policy: Dictionary = NPCPolicy.plan_consent(policy_npc, true)
	check(not policy.ok and policy.code == "REQUIRES_CONTACT",
		"pure A4 policy rejects renewed consent without authorized recontact")
	var current_core: Dictionary = act(session, store, "game.consent",
		{"resident_id": "resident_1", "accept": true})
	var after: Dictionary = session.get_snapshot()
	var gap: bool = current_core.get("ok", false) \
		and resident(after, "resident_1").status == "AWAITING_SUPPLIES" \
		and resident(after, "resident_1").consent
	check(gap, "KNOWN_GAP: current Core accepts direct consent after refusal")
	if gap:
		print("A4_DIAGNOSTIC_KNOWN_GAP_CONFIRMED: declined to AWAITING_SUPPLIES without A4 recontact")
	else:
		print("A4_DIAGNOSTIC_KNOWN_GAP_NOT_REPRODUCED")
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
	for seed_value in [54, 127]:
		schema4_contact_and_reload(rules, prefix.path_join("schema4-%d.json" % seed_value), seed_value)
	diagnostic_current_consent_gap(rules, prefix.path_join("decline-consent-gap.json"))
	DirAccess.remove_absolute(base)
	print("A4 LIVE STORY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
