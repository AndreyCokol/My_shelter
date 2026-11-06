extends RefCounted

const Numbers = preload("res://game/state/gameplay_state.gd")

static func normalize(request: Dictionary) -> Dictionary:
	var fields := {
		"game.enemy_defeated": [], "game.player_defeated": [], "game.resource_collect": [],
		"game.plant": ["plot_id"], "game.water": ["plot_id"], "game.harvest": ["plot_id"], "game.clear": ["plot_id"],
		"game.contact": ["resident_id"], "game.consent": ["resident_id", "accept"], "game.recruit": ["resident_id"],
		"game.quest_track": ["quest_id"]}
	var kind = request.get("command_type")
	var payload = request.get("payload")
	if not fields.has(kind) or not payload is Dictionary or payload.size() != fields[kind].size():
		return {"ok": false}
	var normalized: Dictionary = {}
	for key in fields[kind]:
		var value = payload.get(key)
		if key == "accept":
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
		if scene != "outside" or state.game_time_minutes < state.world_states.resource_ready_at:
			return fail("UNAVAILABLE")
		if not give(state, rules, "seed.basic", rules.resource_quantity, request.action_id):
			return fail("CAPACITY_EXCEEDED")
		state.world_states.resource_ready_at = state.game_time_minutes + rules.resource_respawn_minutes
		bump(state, ["world"])
		return success({"ready_at": state.world_states.resource_ready_at})
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
				var needed: int = int(rules.food.units_per_resident)
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
		return success()
	return fail("INVALID_ARGUMENT")

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
