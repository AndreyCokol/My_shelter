extends SceneTree

# A3-05 standalone regression of EXISTING workshop commands.
# This is not a new production/economy engine and does not modify Core/save.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Gameplay = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
var checks := 0
var failures := 0
var serial := 0

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, label: String) -> void:
    checks += 1
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        failures += 1
        push_error(label)

func request(session, kind: String, payload: Dictionary = {}) -> Dictionary:
    serial += 1
    var state: Dictionary = session.get_snapshot()
    var revisions: Array = []
    for key in state.resource_revisions:
        revisions.append({"key": key, "revision": state.resource_revisions[key]})
    return {"action_id": "a3workshop:%d" % serial, "command_type": kind,
        "payload": payload, "context": {"actor_id": "player",
        "scene_id": state.scene.current_scene_id,
        "expected_resource_revisions": revisions}}

func execute(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
    return session.execute(request(session, kind, payload), store)

func cleanup(path: String) -> void:
    for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected", ".ready"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func rules_for(seed_value: int) -> Dictionary:
    var rules: Dictionary = Rules.build()
    rules.world_seed = seed_value
    rules.scenes = Layout.entries()
    return rules

func fixture(rules: Dictionary, path: String, full_player: bool) -> Dictionary:
    cleanup(path)
    if not Campaign.valid_rules(rules):
        check(false, "workshop rules invalid")
        return {"ok": false}
    var state: Dictionary = Campaign.new(rules).coordinator.get_snapshot()
    state.world_states.first_enemy_defeated = true
    state.story_flags.append("system_unlocked")
    state.claimed_reward_ids.append("system")
    state.scene.current_scene_id = "shelter"
    state.scene.entry_point_id = "default"
    if full_player:
        state.shelter.buildings = {"0": "bench"}
        if not Gameplay.give(state, rules, "material.salvage", 2, "workshop-stock"):
            check(false, "workshop stock fixture grant")
            return {"ok": false}
        for item in state.inventory.items:
            if item.type_id == "material.salvage":
                item.container_id = "storage"
        if not Gameplay.give(state, rules, "seed.basic", 30, "workshop-full-player"):
            check(false, "full-player fixture grant")
            return {"ok": false}
    else:
        if not Gameplay.give(state, rules, "material.salvage", 5, "workshop-starter-stock"):
            check(false, "workshop starter fixture grant")
            return {"ok": false}
    if not Model.validate(state, rules):
        check(false, "workshop initial state invalid")
        return {"ok": false}
    var store = Store.new(path)
    if not store.write_checkpoint(state, Model.validate.bind(rules)).get("committed", false):
        check(false, "workshop fixture durable write")
        return {"ok": false}
    var campaign = Campaign.new(rules)
    var loaded: Dictionary = campaign.coordinator.load_checkpoint(store)
    var valid: bool = loaded.get("ok", false) and campaign.coordinator.get_snapshot() == state
    check(valid, "workshop initial checkpoint equality")
    return {"ok": valid, "campaign": campaign, "store": store}

func case_recipe(seed_value: int, path: String) -> void:
    var rules: Dictionary = rules_for(seed_value)
    var f: Dictionary = fixture(rules, path, false)
    if not f.get("ok", false):
        return
    var session = f.campaign.coordinator
    var store = f.store
    var before: Dictionary = session.get_snapshot()
    check(execute(session, store, "game.craft", {"recipe": "lamp_kit"}).get("code") == "UNAVAILABLE"
        and session.get_snapshot() == before, "no bench means no crafting and no inventory mutation")
    check(execute(session, store, "game.craft", {"recipe": "unknown_recipe"}).get("code") == "INVALID_ARGUMENT"
        and session.get_snapshot() == before, "unknown recipe rejected before any spending")
    var build: Dictionary = request(session, "game.build", {"cell": "0", "structure": "bench"})
    check(session.execute(build, store).get("ok", false)
        and Gameplay.quantity(session.get_snapshot(), "material.salvage") == 2
        and session.get_snapshot().shelter.buildings.get("0") == "bench",
        "bench costs exactly three salvage and occupies own slot")
    var built: Dictionary = session.get_snapshot()
    check(session.execute(build, store).get("code") == "ALREADY_APPLIED"
        and session.get_snapshot() == built, "replaying bench action never double-spends")
    check(execute(session, store, "game.build", {"cell": "0", "structure": "bench"}).get("code") == "INVALID_ARGUMENT"
        and session.get_snapshot() == built, "occupied building slot cannot be bought twice")
    var craft: Dictionary = request(session, "game.craft", {"recipe": "lamp_kit"})
    check(session.execute(craft, store).get("ok", false)
        and Gameplay.quantity(session.get_snapshot(), "material.salvage") == 0
        and Gameplay.quantity(session.get_snapshot(), "material.lamp_kit") == 1,
        "one recipe costs two salvage and creates one lamp kit")
    var once: Dictionary = session.get_snapshot()
    check(session.execute(craft, store).get("code") == "ALREADY_APPLIED"
        and session.get_snapshot() == once, "craft replay does not mint duplicate kits")
    check(execute(session, store, "game.craft", {"recipe": "lamp_kit"}).get("code") == "INSUFFICIENT_RESOURCES"
        and session.get_snapshot() == once, "craft without input leaves output unchanged")
    check(execute(session, store, "game.build", {"cell": "1", "structure": "lamp"}).get("ok", false)
        and Gameplay.quantity(session.get_snapshot(), "material.lamp_kit") == 0
        and session.get_snapshot().shelter.buildings.get("1") == "lamp",
        "one kit is committed to one real lamp structure")
    var final_state: Dictionary = session.get_snapshot()
    check(Model.validate(final_state, rules)
        and final_state.shelter.buildings.size() == 2, "workshop post-production state remains valid")
    var save: Dictionary = request(session, "session.save")
    check(session.execute(save, store).get("ok", false), "workshop checkpoint saved")
    var reopened = Campaign.new(rules)
    check(reopened.coordinator.load_checkpoint(store).get("ok", false)
        and reopened.coordinator.get_snapshot() == session.get_snapshot(),
        "workshop recipe, structures and item ledger survive reload")
    cleanup(path)

func case_full_inventory(seed_value: int, path: String) -> void:
    var rules: Dictionary = rules_for(seed_value)
    var f: Dictionary = fixture(rules, path, true)
    if not f.get("ok", false):
        return
    var session = f.campaign.coordinator
    var store = f.store
    var original: Dictionary = session.get_snapshot()
    var attempted: Dictionary = request(session, "game.craft", {"recipe": "lamp_kit"})
    var result: Dictionary = session.execute(attempted, store)
    check(result.get("code") == "CAPACITY_EXCEEDED",
        "craft cannot grant output if player container is full")
    check(session.get_snapshot() == original
        and Gameplay.quantity(session.get_snapshot(), "material.salvage") == 2
        and Gameplay.quantity(session.get_snapshot(), "material.lamp_kit") == 0,
        "failed craft rolls back input removal and grants no output")
    check(session.execute(attempted, store).get("code") == "CAPACITY_EXCEEDED"
        and session.get_snapshot() == original, "failed craft retry is not a hidden debit")
    var reopened = Campaign.new(rules)
    check(reopened.coordinator.load_checkpoint(store).get("ok", false)
        and reopened.coordinator.get_snapshot() == original,
        "failed craft cannot corrupt durable checkpoint")
    cleanup(path)

func run() -> void:
    var folder := "user://a3-workshop-qa-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
        check(false, "workshop temporary root unavailable")
    else:
        for seed_value in [54, 127]:
            case_recipe(seed_value, folder.path_join("recipe-%d.json" % seed_value))
            case_full_inventory(seed_value, folder.path_join("full-%d.json" % seed_value))
        DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
    print("A3 WORKSHOP TESTS: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)
