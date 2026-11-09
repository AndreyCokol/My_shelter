extends SceneTree

# CORE-05 / NX-17+18: 3/7/14-day real-command campaign regression.
# Uses a validated System-unlocked starting checkpoint, not fake UI or empty
# 108000-tick synthetic receipts; thereafter ALL changes are real session ops.
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")

const HORIZONS := [3, 7, 14]
const MINUTES_PER_DAY := 1440
var checks := 0
var failures := 0
var serial := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + description)
	if not ok:
		failures += 1
		push_error(description)

func request(session, kind: String, payload: Dictionary = {}) -> Dictionary:
	serial += 1
	var state: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": "longterm:%d" % serial, "command_type": kind,
		"payload": payload, "context": {"actor_id": "player", "scene_id": state.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

func execute(session, store, kind: String, payload: Dictionary = {}) -> Dictionary:
	return session.execute(request(session, kind, payload), store)

func cleanup(path: String) -> void:
	for suffix in ["", ".bak", ".bak.tmp", ".tmp", ".rejected"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func setup(rules: Dictionary, path: String) -> Dictionary:
	cleanup(path)
	# Trusted precondition only: first System unlock and NPC contact location.
	# It is validated before being written and loaded by the real coordinator.
	var state: Dictionary = Campaign.new(rules).coordinator.get_snapshot()
	state.scene.current_scene_id = "louvre"
	state.scene.entry_point_id = "default"
	state.world_states.first_enemy_defeated = true
	state.story_flags.append("system_unlocked")
	state.claimed_reward_ids.append("system")
	var stocked: bool = Logic.give(state, rules, "crop.potato", 6, "longterm-start-food")
	stocked = Logic.give(state, rules, "seed.basic", 4, "longterm-start-seeds") and stocked
	check(stocked and Model.validate(state, rules), "valid initial unlocked checkpoint with actual configured food and seeds")
	if not stocked or not Model.validate(state, rules):
		return {"ok": false}
	var store = Store.new(path)
	check(store.write_checkpoint(state, Model.validate.bind(rules)).get("committed", false),
		"initial 3/7/14-day fixture is durable")
	var campaign = Campaign.new(rules)
	var loaded: Dictionary = campaign.coordinator.load_checkpoint(store)
	check(loaded.ok and campaign.coordinator.get_snapshot() == state,
		"initial longterm fixture loads into real coordinator")
	return {"ok": loaded.ok, "campaign": campaign, "store": store}

func actual_food(state: Dictionary) -> int:
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

func healthy(state: Dictionary, rules: Dictionary) -> bool:
	if not Model.validate(state, rules) or state.wallet.system_coins < 0:
		return false
	for item in state.inventory.items:
		if item.quantity <= 0 or Logic.available(state, item) < 0:
			return false
	for reservation in state.inventory.reservations:
		if reservation.quantity <= 0:
			return false
	for plot in state.crops.plots:
		if not plot.status in ["empty", "planted", "growing", "ripe", "spoiled"]:
			return false
	return true

func transfer_food(session, store) -> bool:
	var state: Dictionary = session.get_snapshot()
	for item in state.inventory.items:
		if item.type_id != "crop.potato" or item.container_id != "player":
			continue
		if Logic.available(state, item) < 2:
			continue
		return execute(session, store, "inventory.transfer", {
			"instance_id": item.instance_id, "from_id": "player",
			"to_id": "storage", "quantity": 2}).ok
	return false

func join_voluntarily(session, store) -> void:
	check(execute(session, store, "game.contact", {"resident_id": "resident_1"}).ok,
		"NPC #1 can be contacted using real command")
	var attempted: Dictionary = execute(session, store, "game.recruit", {"resident_id": "resident_1"})
	check(attempted.code == "REQUIRES_CONSENT", "resident cannot be recruited without active consent")
	check(execute(session, store, "game.consent", {"resident_id": "resident_1", "accept": true}).ok,
		"NPC #1 consents voluntarily")
	check(execute(session, store, "game.recruit", {"resident_id": "resident_1"}).ok,
		"NPC #1 recruitment reserves configurable food")
	check(execute(session, store, "game.contact", {"resident_id": "resident_2"}).ok,
		"NPC #2 can be contacted independently")
	check(execute(session, store, "game.consent", {"resident_id": "resident_2", "accept": false}).ok,
		"NPC #2 may refuse settlement without forced Q07 completion")
	check(execute(session, store, "game.recruit", {"resident_id": "resident_2"}).code == "REQUIRES_CONSENT",
		"refused NPC #2 cannot be forcibly recruited")
	check(execute(session, store, "scene.transition",
		{"destination_scene_id": "shelter", "entry_point_id": "default"}).ok,
		"gameplay remains accessible in shelter despite declined optional NPC")
	var s: Dictionary = session.get_snapshot()
	check(s.residents.records[0].status == "joined" and s.residents.records[1].status == "declined"
		and s.inventory.reservations.size() == 1 and Logic.quantity(s, "crop.potato") == 4,
		"voluntary recruitment reserves two existing potatoes; refused NPC does not consume food")

func run_horizon(days: int, path: String) -> void:
	var rules: Dictionary = Rules.build()
	rules.world_seed = 54
	rules.scenes = Layout.entries()
	check(Rules.validate(rules) and Campaign.valid_rules(rules) and rules.crop.yield_units == 3,
		"day %d test uses current validated live balance catalog" % days)
	var fixture: Dictionary = setup(rules, path)
	if not fixture.get("ok", false):
		return
	var campaign = fixture.campaign
	var store = fixture.store
	var session = campaign.coordinator
	join_voluntarily(session, store)
	for day in range(days):
		var current: Dictionary = session.get_snapshot()
		check(current.game_time_minutes == day * MINUTES_PER_DAY and healthy(current, rules),
			"%dd at day %d: exact day boundary and valid persisted resource graph" % [days, day])
		if day == 1:
			check(current.crops.plots[1].status == "spoiled",
				"%dd second plot naturally spoils when left unattended" % days)
			check(execute(session, store, "game.harvest", {"plot_id": "plot_2"}).code == "INVALID_STATE",
				"%dd spoiled crops cannot be double harvested" % days)
			check(execute(session, store, "game.clear", {"plot_id": "plot_2"}).ok,
				"%dd spoiled plot can be cleared without extra food" % days)
		check(execute(session, store, "game.plant", {"plot_id": "plot_1"}).ok,
			"%dd day %d consumes real seed to plant" % [days, day])
		check(execute(session, store, "game.water", {"plot_id": "plot_1"}).ok,
			"%dd day %d watering schedules current crop deadlines" % [days, day])
		if day == 0:
			check(execute(session, store, "game.plant", {"plot_id": "plot_2"}).ok
				and execute(session, store, "game.water", {"plot_id": "plot_2"}).ok,
				"%dd second plot planted for natural spoilage regression" % days)
		# Actual CampaignSession clock path for part of each day, not an empty
		# synthetic receipt or a fake frontend, followed by real rest commands.
		check(campaign.tick(60.0) and session.get_snapshot().game_time_minutes == day * MINUTES_PER_DAY + 60,
			"%dd day %d advances 60 game minutes through real CampaignSession.tick" % [days, day])
		var ripe_at := day * MINUTES_PER_DAY + int(rules.crop.grow_minutes)
		check(execute(session, store, "clock.rest", {"target_minute": ripe_at}).ok
			and session.get_snapshot().crops.plots[0].status == "ripe",
			"%dd day %d advances across verified growth deadline" % [days, day])
		var harvest := request(session, "game.harvest", {"plot_id": "plot_1"})
		check(session.execute(harvest, store).ok, "%dd day %d harvests a real ripe crop" % [days, day])
		var after_harvest: Dictionary = session.get_snapshot()
		check(session.execute(harvest, store).code == "ALREADY_APPLIED"
			and session.get_snapshot() == after_harvest,
			"%dd day %d harvest receipt replay cannot double food output" % [days, day])
		var paid := request(session, "game.assign_shift", {"resident_id": "resident_1", "job": "seed"})
		var shift_result: Dictionary = session.execute(paid, store)
		check(shift_result.ok and shift_result.data.get("work_ration", {}).get("type_id") == "crop.potato",
			"%dd day %d real NPC shift consumes exactly configured edible food" % [days, day])
		var after_shift: Dictionary = session.get_snapshot()
		check(session.execute(paid, store).code == "ALREADY_APPLIED" and session.get_snapshot() == after_shift,
			"%dd day %d worker cannot consume a second ration on replay" % [days, day])
		var due: int = int(after_shift.residents.records[0].shift.due)
		check(execute(session, store, "clock.rest", {"target_minute": due}).ok
			and session.get_snapshot().residents.records[0].shift.ready,
			"%dd day %d shift deadline is resolved by the real calendar" % [days, day])
		var collect := request(session, "game.collect_shift", {"resident_id": "resident_1"})
		check(session.execute(collect, store).ok, "%dd day %d receives two new seed units from paid work" % [days, day])
		var produced: Dictionary = session.get_snapshot()
		check(session.execute(collect, store).code == "ALREADY_APPLIED" and session.get_snapshot() == produced,
			"%dd day %d completed shift reward cannot be duplicated" % [days, day])
		check(transfer_food(session, store), "%dd day %d transfers two unreserved food units to storage" % [days, day])
		check(execute(session, store, "clock.rest", {"target_minute": (day + 1) * MINUTES_PER_DAY}).ok,
			"%dd day %d completes a real gameplay day via rest" % [days, day])
		var day_state: Dictionary = session.get_snapshot()
		check(healthy(day_state, rules) and actual_food(day_state) == 6 + 2 * (day + 1)
			and stored_food(day_state) == 2 * (day + 1) and Logic.quantity(day_state, "seed.basic") >= 2,
			"%dd day %d conserves food/seed balances, storage and reserved NPC ration" % [days, day])
		# Explicit durable save → new campaign → replay every day, not just
		# a final JSON roundtrip. Q03–Q07 are never used to unlock gameplay.
		var save_action := request(session, "session.save")
		check(session.execute(save_action, store).ok,
			"%dd day %d commits a real save action with receipt" % [days, day])
		var durable: Dictionary = session.get_snapshot()
		var reopened = Campaign.new(rules)
		check(reopened.coordinator.load_checkpoint(store).ok and reopened.coordinator.get_snapshot() == durable,
			"%dd day %d reopens identical full state from disk" % [days, day])
		check(reopened.coordinator.execute(save_action, store).code == "ALREADY_APPLIED"
			and reopened.coordinator.get_snapshot() == durable,
			"%dd day %d preserves idempotency after independent reload" % [days, day])
		campaign = reopened
		session = reopened.coordinator
	var final_state: Dictionary = session.get_snapshot()
	check(final_state.game_time_minutes == days * MINUTES_PER_DAY and healthy(final_state, rules)
		and stored_food(final_state) == 2 * days and final_state.residents.records[1].status == "declined",
		"%dd horizon completes without negative resources, forced NPC or time softlock" % days)
	cleanup(path)

func run() -> void:
	var directory := "user://core-longterm-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		check(false, "create isolated 3/7/14-day longterm fixtures directory")
	else:
		for days in HORIZONS:
			run_horizon(days, directory.path_join("%d-days.json" % days))
		DirAccess.remove_absolute(absolute)
	print("CAMPAIGN LONGTERM TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
