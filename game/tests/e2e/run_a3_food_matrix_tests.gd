extends SceneTree

# A3 prototype for issue #42. Do not merge before A1/A5 contract review.
# Godot 4.7.2 target; test code was not executed in authoring environment.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")

const SEEDS := [54, 127]
const FOOD_UNITS := [1, 2, 3]
const FOOD_MODES := ["reserve", "consume"]
const HORIZONS := [3, 7, 14]
const DAY_MINUTES := 1440
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
    return {"action_id": "a3matrix:%d" % serial, "command_type": kind,
        "payload": payload, "context": {"actor_id": "player",
        "scene_id": state.scene.current_scene_id,
        "expected_resource_revisions": revisions}}

func execute(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
    return session.execute(request(session, kind, payload), store)

func rules_for(seed_value: int, mode: String, units: int) -> Dictionary:
    var rules: Dictionary = Rules.build()
    rules.world_seed = seed_value
    rules.scenes = Layout.entries()
    rules.food.reserve_mode = mode
    rules.food.units_per_resident = units
    return rules

func cleanup(path: String) -> void:
    for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected", ".ready"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func raw_food(state: Dictionary) -> int:
    var total := 0
    for item in state.inventory.items:
        if item.type_id == "crop.potato":
            total += int(item.quantity)
    return total

func stored_food(state: Dictionary) -> int:
    var total := 0
    for item in state.inventory.items:
        if item.type_id == "crop.potato" and item.container_id == "storage":
            total += int(item.quantity)
    return total

func setup(rules: Dictionary, path: String) -> Dictionary:
    cleanup(path)
    if not Rules.validate(rules) or not Campaign.valid_rules(rules):
        check(false, "invalid matrix configuration")
        return {"ok": false}
    var state: Dictionary = Campaign.new(rules).coordinator.get_snapshot()
    # Same validated precondition as the existing PR #148 longterm test:
    # already unlocked System and a contacted-eligible location.
    state.scene.current_scene_id = "louvre"
    state.scene.entry_point_id = "default"
    state.world_states.first_enemy_defeated = true
    state.story_flags.append("system_unlocked")
    state.claimed_reward_ids.append("system")
    var stocked: bool = Logic.give(state, rules, "crop.potato", 6, "a3matrix-food")
    stocked = Logic.give(state, rules, "seed.basic", 4, "a3matrix-seed") and stocked
    if not stocked or not Model.validate(state, rules):
        check(false, "invalid matrix starting checkpoint")
        return {"ok": false}
    var store = Store.new(path)
    var written: Dictionary = store.write_checkpoint(state, Model.validate.bind(rules))
    if not written.get("committed", false):
        check(false, "matrix checkpoint save failed")
        return {"ok": false}
    var campaign = Campaign.new(rules)
    var loaded: Dictionary = campaign.coordinator.load_checkpoint(store)
    var ok: bool = loaded.get("ok", false) and campaign.coordinator.get_snapshot() == state
    check(ok, "matrix fixture persists across reload")
    return {"ok": ok, "store": store, "campaign": campaign}

func join_one(session, store, mode: String, units: int) -> bool:
    for action in [
        ["game.contact", {"resident_id": "resident_1"}],
        ["game.consent", {"resident_id": "resident_1", "accept": true}],
        ["game.recruit", {"resident_id": "resident_1"}],
        ["scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}],
    ]:
        var result: Dictionary = execute(session, store, action[0], action[1])
        if not result.get("ok", false):
            check(false, "failed contact/consent/recruit/enter step " + str(action[0]))
            return false
    var state: Dictionary = session.get_snapshot()
    var expected_raw := 6 if mode == "reserve" else 6 - units
    var valid: bool = state.residents.records[0].status == "joined" and raw_food(state) == expected_raw
    valid = valid and Logic.quantity(state, "crop.potato") == 6 - units
    valid = valid and state.inventory.reservations.size() == (1 if mode == "reserve" else 0)
    check(valid, "recruitment food reserve mode " + mode + " units " + str(units))
    return valid

func smoke_mode(seed_value: int, mode: String, units: int, path: String) -> void:
    var rules: Dictionary = rules_for(seed_value, mode, units)
    var fixture: Dictionary = setup(rules, path)
    if not fixture.get("ok", false):
        return
    var session = fixture.campaign.coordinator
    var store = fixture.store
    if not join_one(session, store, mode, units):
        cleanup(path)
        return
    var cmd: Dictionary = request(session, "game.assign_shift", {"resident_id": "resident_1", "job": "seed"})
    var applied: Dictionary = session.execute(cmd, store)
    if not applied.get("ok", false):
        check(false, "work ration not funded")
        cleanup(path)
        return
    var after: Dictionary = session.get_snapshot()
    check(Logic.quantity(after, "crop.potato") == 5 - units
        and after.inventory.reservations.size() == (1 if mode == "reserve" else 0)
        and Model.validate(after, rules), "shift consumes only available edible ration")
    check(session.execute(cmd, store).get("code") == "ALREADY_APPLIED"
        and session.get_snapshot() == after, "work replay does not charge twice")
    var reopened = Campaign.new(rules)
    check(reopened.coordinator.load_checkpoint(store).get("ok", false)
        and reopened.coordinator.get_snapshot() == after, "shift survives reload in matrix")
    cleanup(path)

func transfer_two_food(session, store) -> bool:
    var state: Dictionary = session.get_snapshot()
    for item in state.inventory.items:
        if item.type_id == "crop.potato" and item.container_id == "player" and Logic.available(state, item) >= 2:
            return execute(session, store, "inventory.transfer", {
                "instance_id": item.instance_id, "from_id": "player",
                "to_id": "storage", "quantity": 2}).get("ok", false)
    return false

func horizon(seed_value: int, days: int, path: String) -> void:
    var rules: Dictionary = rules_for(seed_value, "reserve", 2)
    var fixture: Dictionary = setup(rules, path)
    if not fixture.get("ok", false):
        return
    var campaign = fixture.campaign
    var session = campaign.coordinator
    var store = fixture.store
    if not join_one(session, store, "reserve", 2):
        cleanup(path)
        return
    for day in range(days):
        var start: Dictionary = session.get_snapshot()
        if start.game_time_minutes != DAY_MINUTES * day or not Model.validate(start, rules):
            check(false, "invalid day boundary")
            break
        if not execute(session, store, "game.plant", {"plot_id": "plot_1"}).get("ok", false) or not execute(session, store, "game.water", {"plot_id": "plot_1"}).get("ok", false):
            check(false, "plant/water without quests or purchases")
            break
        if not campaign.tick(60.0) or session.get_snapshot().game_time_minutes != DAY_MINUTES * day + 60:
            check(false, "real tick must advance 60 game minutes")
            break
        var ripe_at: int = DAY_MINUTES * day + int(rules.crop.grow_minutes)
        if not execute(session, store, "clock.rest", {"target_minute": ripe_at}).get("ok", false):
            check(false, "growth deadline cannot be reached")
            break
        var harvest: Dictionary = request(session, "game.harvest", {"plot_id": "plot_1"})
        if not session.execute(harvest, store).get("ok", false):
            check(false, "ripe crop cannot be harvested")
            break
        var once: Dictionary = session.get_snapshot()
        check(session.execute(harvest, store).get("code") == "ALREADY_APPLIED"
            and session.get_snapshot() == once, "harvest idempotency")
        var shift: Dictionary = request(session, "game.assign_shift", {"resident_id": "resident_1", "job": "seed"})
        if not session.execute(shift, store).get("ok", false):
            check(false, "edible funded resident shift")
            break
        var due: int = int(session.get_snapshot().residents.records[0].shift.due)
        if not execute(session, store, "clock.rest", {"target_minute": due}).get("ok", false) or not execute(session, store, "game.collect_shift", {"resident_id": "resident_1"}).get("ok", false):
            check(false, "paid shift cannot finish")
            break
        if not transfer_two_food(session, store):
            check(false, "unreserved food transfer")
            break
        if not execute(session, store, "clock.rest", {"target_minute": DAY_MINUTES * (day + 1)}).get("ok", false):
            check(false, "next day boundary")
            break
        var end: Dictionary = session.get_snapshot()
        check(Model.validate(end, rules) and end.game_time_minutes == DAY_MINUTES * (day + 1)
            and raw_food(end) == 6 + 2 * (day + 1)
            and stored_food(end) == 2 * (day + 1), "day resource accounting")
        var save_action: Dictionary = request(session, "session.save")
        if not session.execute(save_action, store).get("ok", false):
            check(false, "daily durable save failed")
            break
        var expected: Dictionary = session.get_snapshot()
        var reopened = Campaign.new(rules)
        if not reopened.coordinator.load_checkpoint(store).get("ok", false):
            check(false, "daily checkpoint cannot reload")
            break
        check(reopened.coordinator.get_snapshot() == expected
            and reopened.coordinator.execute(save_action, store).get("code") == "ALREADY_APPLIED",
            "daily save replay after reload")
        campaign = reopened
        session = reopened.coordinator
    var final_state: Dictionary = session.get_snapshot()
    check(final_state.game_time_minutes == days * DAY_MINUTES and Model.validate(final_state, rules),
        "completed horizon " + str(days) + " on seed " + str(seed_value))
    cleanup(path)


# Narrow command-level resource recovery from zero starter food/seeds.
# This intentionally tests the existing domain command, NOT world navigation/GUI.
func recovery_from_empty(seed_value: int, path: String) -> void:
    var rules: Dictionary = rules_for(seed_value, "reserve", 2)
    cleanup(path)
    if not Rules.validate(rules) or not Campaign.valid_rules(rules):
        check(false, "resource recovery rules invalid")
        return
    var state: Dictionary = Campaign.new(rules).coordinator.get_snapshot()
    state.scene.current_scene_id = "outside"
    state.scene.entry_point_id = "default"
    state.world_states.first_enemy_defeated = true
    state.story_flags.append("system_unlocked")
    state.claimed_reward_ids.append("system")
    var empty: bool = Logic.quantity(state, "crop.potato") == 0 and Logic.quantity(state, "seed.basic") == 0
    if not empty or not Model.validate(state, rules):
        check(false, "resource recovery empty starter fixture")
        return
    var store = Store.new(path)
    if not store.write_checkpoint(state, Model.validate.bind(rules)).get("committed", false):
        check(false, "save empty recovery fixture")
        return
    var campaign = Campaign.new(rules)
    if not campaign.coordinator.load_checkpoint(store).get("ok", false):
        check(false, "load empty recovery fixture")
        cleanup(path)
        return
    var session = campaign.coordinator
    var first: Dictionary = request(session, "game.resource_collect")
    if not session.execute(first, store).get("ok", false):
        check(false, "initial renewable external seed pickup")
        cleanup(path)
        return
    var once: Dictionary = session.get_snapshot()
    check(Logic.quantity(once, "seed.basic") == rules.resource_quantity
        and session.execute(first, store).get("code") == "ALREADY_APPLIED"
        and session.get_snapshot() == once, "first pickup creates only one seed reward")
    if not execute(session, store, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}).get("ok", false):
        check(false, "return to shelter with recovered seeds")
        cleanup(path)
        return
    if not execute(session, store, "clock.rest", {"target_minute": rules.resource_respawn_minutes}).get("ok", false):
        check(false, "wait for external seed regeneration")
        cleanup(path)
        return
    if not execute(session, store, "scene.transition", {"destination_scene_id": "outside", "entry_point_id": "default"}).get("ok", false):
        check(false, "return from shelter to seed source")
        cleanup(path)
        return
    var second: Dictionary = execute(session, store, "game.resource_collect")
    if not second.get("ok", false):
        check(false, "regenerated seed source can be collected")
        cleanup(path)
        return
    check(Logic.quantity(session.get_snapshot(), "seed.basic") == 2 * rules.resource_quantity,
        "external source recovers after its configured cooldown")
    if not execute(session, store, "scene.transition", {"destination_scene_id": "shelter", "entry_point_id": "default"}).get("ok", false):
        check(false, "take seeds into shelter")
        cleanup(path)
        return
    if not execute(session, store, "game.plant", {"plot_id": "plot_1"}).get("ok", false) or not execute(session, store, "game.water", {"plot_id": "plot_1"}).get("ok", false):
        check(false, "plant from externally recovered seed")
        cleanup(path)
        return
    var ripe_at: int = int(session.get_snapshot().game_time_minutes) + int(rules.crop.grow_minutes)
    if not execute(session, store, "clock.rest", {"target_minute": ripe_at}).get("ok", false):
        check(false, "ripening time after recovery")
        cleanup(path)
        return
    var harvested: Dictionary = execute(session, store, "game.harvest", {"plot_id": "plot_1"})
    var after: Dictionary = session.get_snapshot()
    check(harvested.get("ok", false) and Logic.quantity(after, "crop.potato") == rules.crop.yield_units
        and Model.validate(after, rules), "zero-stock player restores edible harvest without purchase/quest")
    var reopened = Campaign.new(rules)
    check(reopened.coordinator.load_checkpoint(store).get("ok", false)
        and reopened.coordinator.get_snapshot() == after, "seed recovery and food survive reload")
    cleanup(path)

func run() -> void:
    var zero := rules_for(54, "reserve", 0)
    var negative := rules_for(54, "reserve", -1)
    check(not Rules.validate(zero) and not Campaign.valid_rules(zero), "zero food ratio rejected")
    check(not Rules.validate(negative) and not Campaign.valid_rules(negative), "negative food ratio rejected")
    var folder := "user://a3-food-matrix-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    var absolute: String = ProjectSettings.globalize_path(folder)
    if DirAccess.make_dir_recursive_absolute(absolute) != OK:
        check(false, "isolated fixture directory cannot be created")
    else:
        for seed_value in SEEDS:
            for mode in FOOD_MODES:
                for units in FOOD_UNITS:
                    smoke_mode(seed_value, mode, units,
                        folder.path_join("smoke-%d-%s-%d.json" % [seed_value, mode, units]))
        for seed_value in SEEDS:
            for days in HORIZONS:
                horizon(seed_value, days,
                    folder.path_join("long-%d-%d.json" % [seed_value, days]))
        for seed_value in SEEDS:
            recovery_from_empty(seed_value, folder.path_join("recovery-%d.json" % seed_value))
        DirAccess.remove_absolute(absolute)
    print("A3 FOOD MATRIX TESTS: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)
