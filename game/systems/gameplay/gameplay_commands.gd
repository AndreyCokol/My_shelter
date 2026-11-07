extends RefCounted

const DistrictEvents = preload("res://game/systems/world/district_events.gd")
const Expedition = preload("res://game/systems/world/expedition_order.gd")
const Camp = preload("res://game/systems/world/camp_network.gd")
const Work = preload("res://game/systems/shelter/resident_work.gd")
const Construction = preload("res://game/systems/shelter/construction.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")

const Numbers = preload("res://game/state/gameplay_state.gd")

static func normalize(request: Dictionary) -> Dictionary:
	var fields := {
		"game.enemy_defeated": [], "game.player_defeated": [], "game.resource_collect": [],
		"game.salvage": [], "game.hospital_cache": [], "game.build": ["cell", "structure"], "game.dismantle": ["cell"], "game.craft": ["recipe"],
		"game.expand_farm": [], "game.plant": ["plot_id"], "game.water": ["plot_id"], "game.harvest": ["plot_id"], "game.clear": ["plot_id"],
		"game.resolve_district": ["choice"], "game.accept_expedition": [], "game.claim_expedition": [],
		"game.fulfill_contract": ["day", "faction"], "game.trade_camp": ["faction"],
		"game.assign_shift": ["resident_id", "job"], "game.collect_shift": ["resident_id"],
		"game.contact": ["resident_id"], "game.consent": ["resident_id", "accept"], "game.recruit": ["resident_id"],
		"game.quest_track": ["quest_id"]}
	var kind = request.get("command_type")
	var payload = request.get("payload")
	if not fields.has(kind) or not payload is Dictionary or payload.size() != fields[kind].size():
		return {"ok": false}
	var normalized: Dictionary = {}
	for key in fields[kind]:
		var value = payload.get(key)
		if key == "day":
			if not Numbers.integer(value):
				return {"ok": false}
			value = int(value)
		elif key == "accept":
			if not value is bool:
				return {"ok": false}
		elif not value is String or value.is_empty():
			return {"ok": false}
		normalized[key] = value
	return {"ok": true, "payload": normalized}

static func available(state: Dictionary, item: Dictionary) -> int:
	var amount: int = int(item.quantity)
	for reservation in state.inventory.reservations:
		if reservation.instance_id == item.instance_id:
			amount -= int(reservation.quantity)
	return amount

static func quantity(state: Dictionary, type_id: String) -> int:
	var total: int = 0
	for item in state.inventory.items:
		if item.type_id == type_id:
			total += available(state, item)
	return total

static func take(state: Dictionary, type_id: String, count: int) -> bool:
	if quantity(state, type_id) < count:
		return false
	for item in state.inventory.items.duplicate():
		if item.type_id != type_id:
			continue
		var used := mini(count, available(state, item))
		item.quantity -= used
		count -= used
		if item.quantity == 0:
			state.inventory.items.erase(item)
		if count == 0:
			break
	bump(state, ["inventory:player", "inventory:storage"])
	return true

static func give(state: Dictionary, rules: Dictionary, type_id: String, count: int, id: String) -> bool:
	var used: int = 0
	var capacity: int = 0
	for container in state.inventory.containers:
		if container.id == "player":
			capacity = int(container.capacity_units)
	for item in state.inventory.items:
		if item.container_id == "player":
			used += int(item.quantity)
	if used + count > capacity:
		return false
	state.inventory.items.append({"instance_id": "game:" + id, "type_id": type_id, "quantity": count, "container_id": "player"})
	if not type_id in state.shelter.discovered_item_type_ids:
		state.shelter.discovered_item_type_ids.append(type_id)
		state.shelter.xp += rules.discovery_xp
	bump(state, ["inventory:player"])
	return true

static func bump(state: Dictionary, keys: Array) -> void:
	for key in keys:
		state.resource_revisions[key] += 1

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func success(data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "data": data}

static func flag(state: Dictionary, name: String) -> void:
	if not name in state.story_flags:
		state.story_flags.append(name)

static func plan(state: Dictionary, request: Dictionary, rules: Dictionary) -> Dictionary:
	var p: Dictionary = request.payload
	var kind: String = request.command_type
	var scene: String = state.scene.current_scene_id
	if kind == "game.enemy_defeated":
		if state.schema_version == 4 and Layout.street_has_patrol(scene, state.world_states.layout):
			var cleared: Array = state.world_states.get("cleared_patrols", [])
			if not state.world_states.first_enemy_defeated or scene in cleared:
				return fail("INVALID_STATE")
			cleared.append(scene)
			state.world_states.cleared_patrols = cleared
			state.player.xp += 1
			state.wallet.system_coins += 1
			bump(state, ["world", "wallet"])
			return success()
		if state.schema_version == 4 and scene != "hospital" and Layout.kind(scene) == "hospital":
			var location: Dictionary = state.world_states.locations.get(scene, {})
			if not state.world_states.first_enemy_defeated or location.get("defeated", false):
				return fail("INVALID_STATE")
			location.defeated = true
			state.world_states.locations[scene] = location
			state.player.xp += 2
			state.wallet.system_coins += 2
			bump(state, ["world", "wallet"])
			return success()
		if scene != "hospital" or state.world_states.first_enemy_defeated:
			return fail("INVALID_STATE")
		if not give(state, rules, "tool.basic", 1, request.action_id):
			return fail("CAPACITY_EXCEEDED")
		state.world_states.first_enemy_defeated = true
		flag(state, "system_unlocked")
		state.player.xp += rules.rewards.system.hero_xp
		state.wallet.system_coins += rules.rewards.system.coins
		state.claimed_reward_ids.append("system")
		bump(state, ["world", "wallet"])
		return success()
	if kind == "game.player_defeated":
		state.player.hp = 100
		state.world_states.defeats += 1
		state.scene.current_scene_id = "shelter" if state.world_states.first_enemy_defeated else "hospital"
		state.scene.entry_point_id = "default"
		state.player.position = {"x": 120, "y": 260}
		state.scene.positions[state.scene.current_scene_id] = state.player.position.duplicate(true)
		bump(state, ["world", "scene"])
		return success()
	if not state.world_states.first_enemy_defeated:
		return fail("UNAVAILABLE")
	if kind == "game.resource_collect":
		var type := Layout.kind(scene) if state.schema_version == 4 else scene
		if type not in ["outside", "house"]:
			return fail("UNAVAILABLE")
		var local_state: Dictionary = state.world_states if scene == "outside" else state.world_states.locations.get(scene, {})
		if local_state.get("looted", false) or state.game_time_minutes < local_state.get("resource_ready_at", 0):
			return fail("UNAVAILABLE")
		if not give(state, rules, "seed.basic", rules.resource_quantity, request.action_id):
			return fail("CAPACITY_EXCEEDED")
		bump(state, ["world"])
		if type == "house":
			state.world_states.locations[scene] = {"looted": true}
			return success()
		var ready_at: int = state.game_time_minutes + rules.resource_respawn_minutes
		if scene == "outside":
			state.world_states.resource_ready_at = ready_at
		else:
			state.world_states.locations[scene] = {"resource_ready_at": ready_at}
		return success({"ready_at": ready_at})
	if kind == "game.hospital_cache":
		if state.schema_version != 4:
			return fail("UNAVAILABLE")
		var cache := Layout.hospital_cache(scene, state.world_states.layout)
		var location: Dictionary = state.world_states.locations.get(scene, {})
		if cache.is_empty() or location.get("cache_looted", false):
			return fail("UNAVAILABLE")
		if not give(state, rules, cache.item, cache.quantity, request.action_id):
			return fail("CAPACITY_EXCEEDED")
		location.cache_looted = true
		state.world_states.locations[scene] = location
		bump(state, ["world"])
		return success({"type_id": cache.item, "quantity": cache.quantity})
	if kind == "game.salvage":
		if state.schema_version != 4 or Layout.kind(scene) != "outside":
			return fail("UNAVAILABLE")
		var ready: Dictionary = state.world_states.get("salvage_ready_at", {})
		if state.game_time_minutes < ready.get(scene, 0):
			return fail("UNAVAILABLE")
		if not give(state, rules, "material.salvage", Construction.SALVAGE_AMOUNT, request.action_id):
			return fail("CAPACITY_EXCEEDED")
		ready[scene] = state.game_time_minutes + Construction.SALVAGE_INTERVAL
		state.world_states.salvage_ready_at = ready
		bump(state, ["world"])
		return success({"ready_at": ready[scene]})
	if kind == "game.resolve_district":
		if not p.choice in ["helped", "declined"]:
			return fail("INVALID_ARGUMENT")
		if not DistrictEvents.available(state, scene):
			return fail("UNAVAILABLE")
		if p.choice == "helped":
			var event := DistrictEvents.event_for(state, scene)
			if not take(state, event.item, event.cost):
				return fail("INSUFFICIENT_RESOURCES")
			state.wallet.system_coins += event.reward
			bump(state, ["wallet"])
		var outcomes: Dictionary = state.world_states.get("district_events", {})
		outcomes[scene] = p.choice
		state.world_states.district_events = outcomes
		bump(state, ["world"])
		return success({"choice": p.choice})
	if kind in ["game.accept_expedition", "game.claim_expedition"]:
		return plan_expedition(state, request)
	if kind in ["game.fulfill_contract", "game.trade_camp"]:
		return plan_camp(state, request, rules)
	if kind in ["game.assign_shift", "game.collect_shift"]:
		return plan_shift(state, request, rules)
	if kind in ["game.build", "game.dismantle", "game.craft"]:
		return plan_workshop(state, request, rules)
	if kind == "game.expand_farm":
		if state.schema_version != 4:
			return fail("UNAVAILABLE")
		if scene != "shelter":
			return fail("NOT_IN_SAFE_AREA")
		if state.crops.plots.size() != 2:
			return fail("INVALID_STATE")
		var cost: int = rules.farm_expansion_cost
		if state.wallet.system_coins < cost:
			return fail("INSUFFICIENT_RESOURCES")
		state.wallet.system_coins -= cost
		state.crops.plots.append(Numbers.empty_plot("plot_3"))
		bump(state, ["wallet", "farm"])
		return success({"plot_id": "plot_3", "cost": cost})
	if kind in ["game.plant", "game.water", "game.harvest", "game.clear"]:
		if scene != "shelter":
			return fail("NOT_IN_SAFE_AREA")
		var plot: Dictionary = {}
		for entry in state.crops.plots:
			if entry.id == p.plot_id:
				plot = entry
		if plot.is_empty():
			return fail("NOT_FOUND")
		match kind:
			"game.plant":
				if plot.status != "empty":
					return fail("INVALID_STATE")
				if not take(state, "seed.basic", 1):
					return fail("INSUFFICIENT_RESOURCES")
				plot.status = "planted"
				flag(state, "planted")
			"game.water":
				if plot.status != "planted":
					return fail("INVALID_STATE")
				plot.status = "growing"
				plot.planted_at = state.game_time_minutes
				plot.ripe_at = state.game_time_minutes + rules.crop.grow_minutes
				plot.spoil_at = plot.ripe_at + rules.crop.spoil_minutes
			"game.harvest":
				if plot.status != "ripe":
					return fail("INVALID_STATE")
				if not give(state, rules, "crop.potato", rules.crop.yield_units, request.action_id):
					return fail("CAPACITY_EXCEEDED")
				plot.status = "empty"
				plot.planted_at = 0
				plot.ripe_at = 0
				plot.spoil_at = 0
				flag(state, "harvested")
			"game.clear":
				if plot.status != "spoiled":
					return fail("INVALID_STATE")
				plot.status = "empty"
				plot.planted_at = 0
				plot.ripe_at = 0
				plot.spoil_at = 0
		bump(state, ["farm"])
		return success()
	if kind == "game.quest_track":
		for quest in state.quests.records:
			if quest.id == p.quest_id and quest.id not in ["Q01", "Q02"]:
				if quest.status != "completed":
					quest.status = "inactive" if quest.status == "active" else "active"
				return success()
		return fail("INVALID_ARGUMENT")
	if kind in ["game.contact", "game.consent", "game.recruit"]:
		if scene != "louvre":
			return fail("INVALID_STATE")
		var resident: Dictionary = {}
		for entry in state.residents.records:
			if entry.id == p.resident_id:
				resident = entry
		if resident.is_empty():
			return fail("NOT_FOUND")
		if resident.status == "joined":
			return fail("INVALID_STATE")
		match kind:
			"game.contact":
				if resident.status == "unknown":
					resident.status = "contacted"
				flag(state, "contacted")
			"game.consent":
				if resident.status == "unknown":
					return fail("REQUIRES_CONSENT")
				resident.consent = p.accept
				resident.status = "AWAITING_SUPPLIES" if p.accept else "declined"
				if p.accept:
					flag(state, "consented")
			"game.recruit":
				if not resident.consent:
					return fail("REQUIRES_CONSENT")
				if state.schema_version == 4 and rules.get("housing_required", false):
					var housed: Array = state.residents.records.filter(func(entry): return entry.status == "joined")
					if Construction.count(state.shelter.get("buildings", {}), "bed") <= housed.size():
						return fail("NEEDS_HOUSING")
				var needed: int = int(rules.food.units_per_resident)
				var allocation: Array = []
				var available_food: int = 0
				for item in state.inventory.items:
					if item.type_id in rules.food.accepted_food_type_ids:
						available_food += available(state, item)
				if available_food < needed:
					return fail("INSUFFICIENT_RESOURCES")
				for item in state.inventory.items.duplicate():
					if not item.type_id in rules.food.accepted_food_type_ids:
						continue
					var used := mini(needed, available(state, item))
					if used <= 0:
						continue
					allocation.append({"instance_id": item.instance_id, "type_id": item.type_id, "quantity": used})
					if rules.food.reserve_mode == "reserve":
						state.inventory.reservations.append({"instance_id": item.instance_id, "resident_id": resident.id, "quantity": used})
					else:
						item.quantity -= used
						if item.quantity == 0:
							state.inventory.items.erase(item)
					needed -= used
					if needed == 0:
						break
				resident.status = "joined"
				resident.food_receipt_id = request.action_id
				bump(state, ["inventory:player", "inventory:storage"])
				bump(state, ["residents"])
				return success({"resident_id": resident.id, "food_allocations": allocation, "reserve_mode": rules.food.reserve_mode, "units": rules.food.units_per_resident})
		bump(state, ["residents"])
		return success()
	return fail("INVALID_ARGUMENT")

static func plan_expedition(state: Dictionary, request: Dictionary) -> Dictionary:
	if state.schema_version != 4 or state.scene.current_scene_id != "louvre":
		return fail("UNAVAILABLE")
	var order: Dictionary = state.quests.get("expedition", {})
	if request.command_type == "game.accept_expedition":
		if not order.is_empty():
			return fail("INVALID_STATE")
		order = {"target": Expedition.choose_target(state), "claimed": false}
	else:
		if order.is_empty() or order.claimed:
			return fail("UNAVAILABLE")
		if order.target.is_empty():
			if not take(state, "material.salvage", Expedition.SUPPLY_COST):
				return fail("INSUFFICIENT_RESOURCES")
		elif not state.world_states.locations.get(order.target, {}).get("defeated", false):
			return fail("UNAVAILABLE")
		order.claimed = true
		state.wallet.system_coins += Expedition.REWARD
		bump(state, ["wallet"])
	state.quests.expedition = order
	bump(state, ["world"])
	return success(order.duplicate())

static func plan_camp(state: Dictionary, request: Dictionary, rules: Dictionary) -> Dictionary:
	if state.schema_version != 4 or state.scene.current_scene_id != "louvre":
		return fail("UNAVAILABLE")
	var p: Dictionary = request.payload
	if not Camp.FACTIONS.has(p.faction):
		return fail("INVALID_ARGUMENT")
	var faction: Dictionary = Camp.FACTIONS[p.faction]
	var current := Camp.schedule(int(state.game_time_minutes), int(state.world_states.layout.seed))
	var network: Dictionary = state.world_states.get("camp_network", Camp.empty_state())
	if request.command_type == "game.fulfill_contract":
		if not current.active or current.day != p.day or current.faction != p.faction or network.last_contract_day == current.day:
			return fail("UNAVAILABLE")
		if not take(state, faction.request, faction.quantity):
			return fail("INSUFFICIENT_RESOURCES")
		state.wallet.system_coins += faction.reward
		network.last_contract_day = current.day
		network.reputation[p.faction] = network.reputation.get(p.faction, 0) + 1
	else:
		if not network.reputation.has(p.faction) or network.last_trade.get(p.faction, -1) == current.day:
			return fail("UNAVAILABLE")
		if state.wallet.system_coins < faction.price:
			return fail("INSUFFICIENT_RESOURCES")
		if not give(state, rules, faction.goods, faction.goods_quantity, request.action_id):
			return fail("CAPACITY_EXCEEDED")
		state.wallet.system_coins -= faction.price
		network.last_trade[p.faction] = current.day
	state.world_states.camp_network = network
	bump(state, ["wallet", "world"])
	return success({"faction": p.faction})

static func plan_shift(state: Dictionary, request: Dictionary, rules: Dictionary) -> Dictionary:
	if state.schema_version != 4:
		return fail("UNAVAILABLE")
	if state.scene.current_scene_id != "shelter":
		return fail("NOT_IN_SAFE_AREA")
	var p: Dictionary = request.payload
	for resident in state.residents.records:
		if resident.id != p.resident_id:
			continue
		if resident.status != "joined":
			return fail("UNAVAILABLE")
		if request.command_type == "game.assign_shift":
			if not Work.JOBS.has(p.job):
				return fail("INVALID_ARGUMENT")
			if resident.has("shift"):
				return fail("INVALID_STATE")
			if not take(state, Work.FOOD, 1):
				return fail("INSUFFICIENT_RESOURCES")
			resident.shift = {"job": p.job, "due": state.game_time_minutes + Work.duration(state, resident.id), "ready": false}
		else:
			if not resident.get("shift", {}).get("ready", false):
				return fail("UNAVAILABLE")
			var job: Dictionary = Work.JOBS[resident.shift.job]
			if not give(state, rules, job.output, job.quantity, request.action_id):
				return fail("CAPACITY_EXCEEDED")
			resident.erase("shift")
		bump(state, ["residents"])
		return success({"resident_id": resident.id})
	return fail("NOT_FOUND")

static func plan_workshop(state: Dictionary, request: Dictionary, rules: Dictionary) -> Dictionary:
	if state.schema_version != 4:
		return fail("UNAVAILABLE")
	if state.scene.current_scene_id != "shelter":
		return fail("NOT_IN_SAFE_AREA")
	var p: Dictionary = request.payload
	var buildings: Dictionary = state.shelter.get("buildings", {})
	if request.command_type == "game.craft":
		if not Construction.RECIPES.has(p.recipe):
			return fail("INVALID_ARGUMENT")
		if not "bench" in buildings.values():
			return fail("UNAVAILABLE")
		var recipe: Dictionary = Construction.RECIPES[p.recipe]
		if not take(state, recipe.input, recipe.cost):
			return fail("INSUFFICIENT_RESOURCES")
		if not give(state, rules, recipe.output, 1, request.action_id):
			return fail("CAPACITY_EXCEEDED")
		return success({"type_id": recipe.output})
	if not Construction.valid_cell(p.cell):
		return fail("INVALID_ARGUMENT")
	var previous_cabinets := Construction.count(buildings, "cabinet")
	if request.command_type == "game.dismantle":
		if not buildings.has(p.cell):
			return fail("NOT_FOUND")
		if buildings[p.cell] == "bed" and rules.get("housing_required", false):
			var housed: Array = state.residents.records.filter(func(resident): return resident.status == "joined")
			if Construction.count(buildings, "bed") <= housed.size():
				return fail("NEEDS_HOUSING")
		buildings.erase(p.cell)
	else:
		if not Construction.STRUCTURES.has(p.structure) or buildings.has(p.cell):
			return fail("INVALID_ARGUMENT")
		var pos = request.context.get("live_position", state.player.position)
		if not pos is Dictionary or not (pos.get("x") is float or pos.get("x") is int) or not (pos.get("y") is float or pos.get("y") is int):
			return fail("INVALID_ARGUMENT")
		var actor := Vector2(pos.x, pos.y)
		if not actor.is_finite() or Construction.cell_rect(p.cell).grow(10).has_point(actor):
			return fail("INVALID_STATE")
		var structure: Dictionary = Construction.STRUCTURES[p.structure]
		if not take(state, structure.item, structure.cost):
			return fail("INSUFFICIENT_RESOURCES")
		buildings[p.cell] = p.structure
		state.player.position = {"x": actor.x, "y": actor.y}
		state.scene.positions.shelter = state.player.position.duplicate()
		bump(state, ["scene"])
	if Construction.count(buildings, "cabinet") != previous_cabinets:
		var containers := Construction.storage_containers(rules.containers, buildings)
		var used := 0
		for item in state.inventory.items:
			if item.container_id == "storage":
				used += int(item.quantity)
		for container in containers:
			if container.id == "storage" and used > container.capacity_units:
				return fail("CAPACITY_EXCEEDED")
		state.inventory.containers = containers
		bump(state, ["inventory:storage"])
	state.shelter.buildings = buildings
	bump(state, ["world"])
	return success({"cell": p.cell})

static func refresh_quests(state: Dictionary) -> void:
	var joined: int = 0
	for resident in state.residents.records:
		if resident.status == "joined":
			joined += 1
	var done := {"Q01": state.world_states.first_enemy_defeated, "Q02": state.scene.current_scene_id == "shelter" and state.world_states.first_enemy_defeated,
		"Q03": "planted" in state.story_flags, "Q04": "harvested" in state.story_flags, "Q05": "contacted" in state.story_flags, "Q06": "consented" in state.story_flags, "Q07": joined == 2}
	for quest in state.quests.records:
		if quest.status == "active" and done[quest.id]:
			quest.status = "completed"
