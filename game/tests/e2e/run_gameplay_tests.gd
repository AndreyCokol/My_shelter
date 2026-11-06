extends SceneTree

const Rules = preload("res://game/data/game_rules.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var rules := Rules.build()
	check(Campaign.valid_rules(rules), "step4 production candidate catalog validates")
	var seeded = Campaign.new(rules)
	var state: Dictionary = seeded.coordinator.get_snapshot()
	check(Model.validate(state, rules) and state.schema_version == 3, "step3 gameplay schema seed validates")
	var bad := state.duplicate(true)
	bad.crops.plots[0].status = "unknown"
	check(not Model.validate(bad, rules), "step3 malformed crop rejected")
	bad = state.duplicate(true)
	bad.residents.records[1].id = "resident_1"
	check(not Model.validate(bad, rules), "step3 duplicate resident rejected")
	bad = state.duplicate(true)
	bad.quests.records[0].status = "corrupted"
	check(not Model.validate(bad, rules), "step3 malformed quest rejected")
	bad = state.duplicate(true)
	bad.schema_version = 2
	check(not Model.validate(bad, rules), "step3 old schema refused without silent migration")
	var bad_rules := rules.duplicate(true)
	bad_rules.food.units_per_resident = 0
	check(not Campaign.valid_rules(bad_rules), "step4 zero food rule refused")
	bad_rules = rules.duplicate(true)
	bad_rules.crop.grow_minutes = -1
	check(not Campaign.valid_rules(bad_rules), "step4 invalid duration refused")
	_run_domains(rules)
	print("GAMEPLAY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func request(session, id: String, kind: String, payload: Dictionary = {}) -> Dictionary:
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": id, "command_type": kind, "payload": payload, "context": {"actor_id": "player", "scene_id": state.scene.current_scene_id, "expected_resource_revisions": revisions}}

func _run_domains(rules: Dictionary) -> void:
	var campaign = Campaign.new(rules)
	var session = campaign.coordinator
	var store = Store.new("user://gameplay-tests/" + str(Time.get_ticks_usec()) + ".json")
	check(session.execute(request(session, "locked-exit", "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}), store).code == "UNAVAILABLE", "step5 onboarding cannot skip first unlock")
	var kill := request(session, "first-kill", "game.enemy_defeated")
	check(session.execute(kill, store).ok and session.get_snapshot().player.xp == 10, "step5 first defeat gives one System reward")
	check(session.execute(kill, store).code == "ALREADY_APPLIED" and session.execute(request(session, "second-kill", "game.enemy_defeated"), store).code == "INVALID_STATE", "step5 duplicate death never grants reward twice")
	check(session.execute(request(session, "city", "scene.transition", {"destination_scene_id": "outside", "entry_point_id": "default"}), store).ok, "step6 city transition")
	var gather := request(session, "gather", "game.resource_collect")
	check(session.execute(gather, store).ok, "step6 renewable seed source available")
	check(session.execute(request(session, "gather-early", "game.resource_collect"), store).code == "UNAVAILABLE", "step6 cooldown cannot be bypassed with new action ID")
	var restarted = Campaign.new(rules)
	check(restarted.coordinator.load_checkpoint(store).ok and restarted.coordinator.execute(request(restarted.coordinator, "gather-reload", "game.resource_collect"), store).code == "UNAVAILABLE", "step6 cooldown survives restart")
	check(session.execute(request(session, "death", "game.player_defeated"), store).ok and session.get_snapshot().scene.current_scene_id == "shelter" and session.get_snapshot().player.hp == 100, "step6 defeat safely returns hero without resetting unlock")
	check(session.execute(request(session, "parcel", "inventory.claim_parcel", {"parcel_id": "starter"}), store).ok, "step7 starter seeds supplied")
	check(session.execute(request(session, "plant-1", "game.plant", {"plot_id": "plot_1"}), store).ok, "step7 plant consumes seed")
	check(session.execute(request(session, "plant-2", "game.plant", {"plot_id": "plot_2"}), store).ok, "step7 two independent plots")
	check(session.execute(request(session, "water-1", "game.water", {"plot_id": "plot_1"}), store).ok and session.execute(request(session, "water-2", "game.water", {"plot_id": "plot_2"}), store).ok, "step7 watering starts configured deadlines")
	var before: Dictionary = session.get_snapshot()
	check(session.execute(request(session, "early-harvest", "game.harvest", {"plot_id": "plot_1"}), store).code == "INVALID_STATE" and session.get_snapshot() == before, "step8 cannot harvest immature crop")
	check(campaign.tick(float(rules.crop.grow_minutes)) and session.get_snapshot().crops.plots[0].status == "ripe", "step9 natural time matures real crop at boundary")
	check(session.execute(request(session, "harvest-1", "game.harvest", {"plot_id": "plot_1"}), store).ok, "step8 harvest transfers real food to inventory")
	check(session.execute(request(session, "harvest-again", "game.harvest", {"plot_id": "plot_1"}), store).code == "INVALID_STATE", "step8 no double harvest")
	check(session.execute(request(session, "harvest-2", "game.harvest", {"plot_id": "plot_2"}), store).ok, "step8 second plot harvest")
	check(session.get_snapshot().quests.records[2].status == "inactive" and session.get_snapshot().quests.records[3].status == "inactive", "step10 sandbox works with optional quests inactive")
	check(session.execute(request(session, "track", "game.quest_track", {"quest_id": "Q04"}), store).ok and session.get_snapshot().quests.records[3].status == "completed", "step10 optional quest derives completion from persisted state")
	check(session.execute(request(session, "camp", "scene.transition", {"destination_scene_id": "louvre", "entry_point_id": "default"}), store).ok, "step11 reach contact area")
	check(session.execute(request(session, "no-consent", "game.recruit", {"resident_id": "resident_1"}), store).code == "REQUIRES_CONSENT", "step11 recruitment requires voluntary consent")
	for id in ["resident_1", "resident_2"]:
		check(session.execute(request(session, "contact-" + id, "game.contact", {"resident_id": id}), store).ok, "step11 contact " + id)
		check(session.execute(request(session, "consent-" + id, "game.consent", {"resident_id": id, "accept": true}), store).ok, "step11 consent " + id)
		check(session.execute(request(session, "join-" + id, "game.recruit", {"resident_id": id}), store).ok, "step11 food reservation and join " + id)
	check(session.get_snapshot().inventory.reservations.size() >= 2, "step11 food reservations persisted against concrete stacks")
	var loaded = Campaign.new(rules)
	check(loaded.coordinator.load_checkpoint(store).ok and loaded.coordinator.get_snapshot() == session.get_snapshot(), "step14 full domain save/load round trip")
	check(loaded.coordinator.execute(request(loaded.coordinator, "double-join", "game.recruit", {"resident_id": "resident_1"}), store).code == "INVALID_STATE", "step11 reload cannot duplicate resident")
	var reserved_item: Dictionary = session.get_snapshot().inventory.items.filter(func(i): return i.type_id == "crop.potato")[0]
	check(session.execute(request(session, "reserved-transfer", "inventory.transfer", {"instance_id": reserved_item.instance_id, "from_id": "player", "to_id": "storage", "quantity": reserved_item.quantity}), store).code == "INSUFFICIENT_RESOURCES", "step11 reserved food unavailable for other spending")
	var corrupt: Dictionary = session.get_snapshot()
	corrupt.inventory.reservations[0].quantity = 999
	check(not Model.validate(corrupt, rules), "step3 reservation cross references reject overdraw")
	corrupt = session.get_snapshot()
	corrupt.residents.records[0].consent = false
	check(not Model.validate(corrupt, rules), "step3 joined resident without consent rejected")
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path + suffix))
