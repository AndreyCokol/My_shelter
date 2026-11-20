extends SceneTree

# A3-06 isolated regression of the CURRENT camp prototype, not approval of
# system_coins as a future survivor-trade currency (see Issue #170).
# No Core/save/gameplay modifications; two seeds and real domain commands.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Gameplay = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Camp = preload("res://game/systems/world/camp_network.gd")
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

func cleanup(path: String) -> void:
    for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected", ".ready"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func request(session, kind: String, payload: Dictionary = {}) -> Dictionary:
    serial += 1
    var state: Dictionary = session.get_snapshot()
    var revisions: Array = []
    for key in state.resource_revisions:
        revisions.append({"key": key, "revision": state.resource_revisions[key]})
    return {"action_id": "a3market:%d" % serial, "command_type": kind,
        "payload": payload, "context": {"actor_id": "player",
        "scene_id": state.scene.current_scene_id,
        "expected_resource_revisions": revisions}}

func execute(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
    return session.execute(request(session, kind, payload), store)

func rules_for(seed_value: int) -> Dictionary:
    var rules: Dictionary = Rules.build()
    rules.world_seed = seed_value
    rules.scenes = Layout.entries()
    return rules

func fixture(rules: Dictionary, path: String, full_player: bool) -> Dictionary:
    cleanup(path)
    if not Rules.validate(rules) or not Campaign.valid_rules(rules):
        check(false, "market fixture rules invalid")
        return {"ok": false}
    var initial: Dictionary = Campaign.new(rules).coordinator.get_snapshot()
    initial.world_states.first_enemy_defeated = true
    initial.story_flags.append("system_unlocked")
    initial.claimed_reward_ids.append("system")
    var stock_ok: bool = true
    if full_player:
        var first_faction: String = str(Camp.schedule(Camp.OPEN, rules.world_seed).faction)
        var definition: Dictionary = Camp.FACTIONS[first_faction]
        stock_ok = Gameplay.give(initial, rules, definition.request, int(definition.quantity), "a3market-input")
        if stock_ok:
            for item in initial.inventory.items:
                if item.type_id == definition.request:
                    item.container_id = "storage"
        stock_ok = Gameplay.give(initial, rules, "seed.basic", 30, "a3market-capacity") and stock_ok
        initial.scene.current_scene_id = "louvre"
        initial.scene.entry_point_id = "default"
        initial.game_time_minutes = Camp.OPEN
    else:
        stock_ok = Gameplay.give(initial, rules, "material.salvage", 10, "a3market-salvage")
        stock_ok = Gameplay.give(initial, rules, "crop.potato", 8, "a3market-potato") and stock_ok
    if not stock_ok or not Model.validate(initial, rules):
        check(false, "market fixture state invalid")
        return {"ok": false}
    var store = Store.new(path)
    if not store.write_checkpoint(initial, Model.validate.bind(rules)).get("committed", false):
        check(false, "market fixture save failed")
        return {"ok": false}
    var campaign = Campaign.new(rules)
    var loaded: Dictionary = campaign.coordinator.load_checkpoint(store)
    var ok: bool = loaded.get("ok", false) and campaign.coordinator.get_snapshot() == initial
    check(ok, "market fixture checkpoint roundtrip")
    return {"ok": ok, "campaign": campaign, "store": store}

func travel(session, store, destination: String) -> bool:
    return execute(session, store, "scene.transition",
        {"destination_scene_id": destination, "entry_point_id": "default"}).get("ok", false)

func three_day_market(seed_value: int, path: String) -> void:
    var rules: Dictionary = rules_for(seed_value)
    var data: Dictionary = fixture(rules, path, false)
    if not data.get("ok", false):
        return
    var session = data.campaign.coordinator
    var store = data.store
    var initial: Dictionary = session.get_snapshot()
    check(execute(session, store, "game.trade_camp", {"faction": "scouts"}).get("code") == "UNAVAILABLE"
        and session.get_snapshot() == initial, "trade unavailable from shelter without camp")
    if not travel(session, store, "outside") or not travel(session, store, "louvre"):
        check(false, "market route shelter -> outside -> camp")
        cleanup(path)
        return
    var closed: Dictionary = session.get_snapshot()
    var closed_faction: String = str(Camp.schedule(0, seed_value).faction)
    check(execute(session, store, "game.fulfill_contract",
        {"day": 0, "faction": closed_faction}).get("code") == "UNAVAILABLE"
        and session.get_snapshot() == closed, "closed market does not debit resources")
    if not travel(session, store, "shelter") or not execute(session, store, "clock.rest",
        {"target_minute": Camp.OPEN}).get("ok", false) or not travel(session, store, "louvre"):
        check(false, "market day zero opening transition")
        cleanup(path)
        return
    for day in range(3):
        var start: Dictionary = session.get_snapshot()
        var active: Dictionary = Camp.schedule(int(start.game_time_minutes), seed_value)
        if int(start.game_time_minutes) != day * Camp.DAY + Camp.OPEN or not active.active:
            check(false, "market day window invalid")
            break
        var faction_id: String = str(active.faction)
        var faction: Dictionary = Camp.FACTIONS[faction_id]
        var before_wallet: int = int(start.wallet.system_coins)
        var input_before: int = Gameplay.quantity(start, str(faction.request))
        var output_before: int = Gameplay.quantity(start, str(faction.goods))
        var payload: Dictionary = {"day": day, "faction": faction_id}
        check(execute(session, store, "game.fulfill_contract",
            {"day": day - 1, "faction": faction_id}).get("code") == "UNAVAILABLE"
            and session.get_snapshot() == start, "expired or wrong-day offer cannot debit stock")
        check(execute(session, store, "game.fulfill_contract",
            {"day": day, "faction": "not_a_faction"}).get("code") == "INVALID_ARGUMENT"
            and session.get_snapshot() == start, "unknown faction cannot create payment")
        var fulfil: Dictionary = request(session, "game.fulfill_contract", payload)
        if not session.execute(fulfil, store).get("ok", false):
            check(false, "active market contract could not be fulfilled")
            break
        var paid: Dictionary = session.get_snapshot()
        check(int(paid.wallet.system_coins) == before_wallet + int(faction.reward)
            and Gameplay.quantity(paid, str(faction.request)) == input_before - int(faction.quantity)
            and paid.world_states.camp_network.last_contract_day == day
            and Camp.valid_record(paid.world_states.camp_network, int(paid.game_time_minutes)),
            "current prototype fulfils one limited daily request with exact resources")
        check(session.execute(fulfil, store).get("code") == "ALREADY_APPLIED"
            and session.get_snapshot() == paid, "daily contract replay cannot grant twice")
        check(execute(session, store, "game.fulfill_contract", payload).get("code") == "UNAVAILABLE"
            and session.get_snapshot() == paid, "distinct action ID cannot claim daily contract twice")
        var trade: Dictionary = request(session, "game.trade_camp", {"faction": faction_id})
        if not session.execute(trade, store).get("ok", false):
            check(false, "trusted camp trade failed")
            break
        var traded: Dictionary = session.get_snapshot()
        check(int(traded.wallet.system_coins) == before_wallet + int(faction.reward) - int(faction.price)
            and Gameplay.quantity(traded, str(faction.goods)) == output_before + int(faction.goods_quantity)
            and traded.world_states.camp_network.last_trade[faction_id] == day
            and Model.validate(traded, rules), "existing trade spends once and grants goods once")
        check(session.execute(trade, store).get("code") == "ALREADY_APPLIED"
            and session.get_snapshot() == traded, "trade replay does not duplicate goods")
        check(execute(session, store, "game.trade_camp", {"faction": faction_id}).get("code") == "UNAVAILABLE"
            and session.get_snapshot() == traded, "daily market stock has hard cap")
        var saved: Dictionary = request(session, "session.save")
        check(session.execute(saved, store).get("ok", false), "daily camp ledger saved")
        var reopened = Campaign.new(rules)
        if not reopened.coordinator.load_checkpoint(store).get("ok", false):
            check(false, "daily camp checkpoint reload failed")
            break
        check(reopened.coordinator.get_snapshot() == session.get_snapshot()
            and reopened.coordinator.execute(trade, store).get("code") == "ALREADY_APPLIED",
            "camp trust, daily stock and receipt persist through reload")
        session = reopened.coordinator
        if day < 2:
            if not travel(session, store, "shelter") or not execute(session, store,
                "clock.rest", {"target_minute": (day + 1) * Camp.DAY + Camp.OPEN}).get("ok", false) or not travel(session, store, "louvre"):
                check(false, "next market day not reachable from shelter")
                break
    var final_state: Dictionary = session.get_snapshot()
    check(int(final_state.game_time_minutes) == 2 * Camp.DAY + Camp.OPEN
        and Model.validate(final_state, rules)
        and Camp.valid_record(final_state.world_states.camp_network, int(final_state.game_time_minutes)),
        "two-seed market survives three daily windows with valid ledger")
    cleanup(path)

func full_inventory_rollback(seed_value: int, path: String) -> void:
    var rules: Dictionary = rules_for(seed_value)
    var data: Dictionary = fixture(rules, path, true)
    if not data.get("ok", false):
        return
    var session = data.campaign.coordinator
    var store = data.store
    var active: Dictionary = Camp.schedule(int(session.get_snapshot().game_time_minutes), seed_value)
    var faction_id: String = str(active.faction)
    var faction: Dictionary = Camp.FACTIONS[faction_id]
    var pay: Dictionary = request(session, "game.fulfill_contract",
        {"day": 0, "faction": faction_id})
    if not session.execute(pay, store).get("ok", false):
        check(false, "storage-funded contract must be payable before overflow trade")
        cleanup(path)
        return
    var before: Dictionary = session.get_snapshot()
    var attempt: Dictionary = request(session, "game.trade_camp", {"faction": faction_id})
    check(session.execute(attempt, store).get("code") == "CAPACITY_EXCEEDED"
        and session.get_snapshot() == before,
        "full player inventory aborts trade without spending money or creating goods")
    check(session.execute(attempt, store).get("code") == "CAPACITY_EXCEEDED"
        and session.get_snapshot() == before,
        "rejected trade retry leaves receipt and wallet untouched")
    var reopened = Campaign.new(rules)
    check(reopened.coordinator.load_checkpoint(store).get("ok", false)
        and reopened.coordinator.get_snapshot() == before
        and Gameplay.quantity(before, str(faction.goods)) == (30 if faction.goods == "seed.basic" else 0),
        "failed trade preserves prior durable checkpoint")
    cleanup(path)

func run() -> void:
    var folder := "user://a3-market-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
        check(false, "market QA fixture directory unavailable")
    else:
        for seed_value in [54, 127]:
            three_day_market(seed_value, folder.path_join("days-%d.json" % seed_value))
            full_inventory_rollback(seed_value, folder.path_join("full-%d.json" % seed_value))
        DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
    print("A3 CAMP MARKET TESTS: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)
