extends RefCounted

const DistrictEvents = preload("res://game/systems/world/district_events.gd")
const Expedition = preload("res://game/systems/world/expedition_order.gd")
const Camp = preload("res://game/systems/world/camp_network.gd")
const Work = preload("res://game/systems/shelter/resident_work.gd")
const Construction = preload("res://game/systems/shelter/construction.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Enemy = preload("res://game/entities/enemies/enemy.gd")
const Receipts = preload("res://game/systems/core/action_receipt.gd")

static func integer(value) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= 9007199254740991 and value == floor(value)

static func empty_plot(id: String) -> Dictionary:
	return {"id": id, "status": "empty", "planted_at": 0, "ripe_at": 0, "spoil_at": 0}

static func seed(state: Dictionary) -> void:
	state.schema_version = 3
	state.scene.current_scene_id = "hospital"
	state.player.position = {"x": 120, "y": 260}
	state.player.hp = 100
	state.crops.plots = []
	for id in ["plot_1", "plot_2"]:
		state.crops.plots.append(empty_plot(id))
	state.residents.records = []
	for id in ["resident_1", "resident_2"]:
		state.residents.records.append({"id": id, "status": "unknown", "consent": false, "food_receipt_id": ""})
	state.quests.records = []
	for number in range(1, 8):
		state.quests.records.append({"id": "Q%02d" % number, "status": "active" if number <= 2 else "inactive"})
	state.world_states = {"first_enemy_defeated": false, "resource_ready_at": 0, "defeats": 0}
	for id in ["farm", "residents", "world"]:
		state.resource_revisions[id] = 0

static func validate(state: Dictionary, rules: Dictionary) -> bool:
	if not integer(state.player.get("hp")) or state.player.hp > 100:
		return false
	var plot_counts := [2, 3] if state.schema_version == 4 else [2]
	if not state.crops.get("plots") is Array or not state.crops.plots.size() in plot_counts:
		return false
	var ids: Array = []
	var allowed_plots := ["plot_1", "plot_2", "plot_3"] if state.crops.plots.size() == 3 else ["plot_1", "plot_2"]
	for plot in state.crops.plots:
		if not plot is Dictionary or not plot.get("id") in allowed_plots or plot.id in ids or not plot.get("status") in ["empty", "planted", "growing", "ripe", "spoiled"]:
			return false
		ids.append(plot.id)
		for key in ["planted_at", "ripe_at", "spoil_at"]:
			if not integer(plot.get(key)):
				return false
		# A planted crop carries its own authoritative deadlines. Live balance can
		# change for new plantings without invalidating old checkpoint deadlines.
		var has_grow: bool = plot.has("grow_minutes_at_planting")
		var has_spoil: bool = plot.has("spoil_minutes_at_planting")
		if has_grow != has_spoil:
			return false
		if plot.status in ["growing", "ripe", "spoiled"]:
			var grow_duration: int = int(plot.ripe_at) - int(plot.planted_at)
			var spoil_duration: int = int(plot.spoil_at) - int(plot.ripe_at)
			if grow_duration <= 0 or spoil_duration <= 0:
				return false
			# Old saves lack these fields; their persisted deadlines are sufficient
			# to derive the original positive durations without changing the file.
			if has_grow and (not integer(plot.grow_minutes_at_planting) or not integer(plot.spoil_minutes_at_planting) or int(plot.grow_minutes_at_planting) != grow_duration or int(plot.spoil_minutes_at_planting) != spoil_duration):
				return false
		elif has_grow:
			return false
		if plot.status == "growing" and not (plot.planted_at <= state.game_time_minutes and state.game_time_minutes < plot.ripe_at):
			return false
		if plot.status == "ripe" and not (plot.ripe_at <= state.game_time_minutes and state.game_time_minutes < plot.spoil_at):
			return false
		if plot.status == "spoiled" and state.game_time_minutes < plot.spoil_at:
			return false
	if not state.residents.get("records") is Array or state.residents.records.size() != 2:
		return false
	ids = []
	var reserved_by_resident := {}
	for resident in state.residents.records:
		if not resident is Dictionary or not resident.get("id") in ["resident_1", "resident_2"] or resident.id in ids or not resident.get("status") in ["unknown", "contacted", "declined", "AWAITING_SUPPLIES", "joined"] or not resident.get("consent") is bool or not resident.get("food_receipt_id") is String:
			return false
		ids.append(resident.id)
		if resident.has("shift") and (state.schema_version != 4 or resident.status != "joined" or not Work.valid_shift(resident.shift, int(state.game_time_minutes))):
			return false
		if resident.status in ["AWAITING_SUPPLIES", "joined"] and not resident.consent:
			return false
		if resident.status == "joined" and (resident.food_receipt_id.is_empty() or not state.completed_actions.has(resident.food_receipt_id)):
			return false
		if resident.status == "joined":
			var action = state.completed_actions[resident.food_receipt_id]
			var fingerprint := JSON.stringify(["game.recruit", "player", {"resident_id": resident.id}]).sha256_text()
			var receipt: Dictionary = Receipts.data(action)
			if Receipts.fingerprint(action) != fingerprint or receipt.get("resident_id") != resident.id or not receipt.get("reserve_mode") in ["reserve", "consume"] or not integer(receipt.get("units")) or receipt.units <= 0 or not receipt.get("food_allocations") is Array:
				return false
			var allocations := {}
			var total: int = 0
			for part in receipt.food_allocations:
				if not part is Dictionary or not part.get("instance_id") is String or part.instance_id.is_empty() or allocations.has(part.instance_id) or not part.get("type_id") is String or part.type_id.is_empty() or not integer(part.get("quantity")) or part.quantity <= 0 or part.quantity > receipt.units - total:
					return false
				allocations[part.instance_id] = part
				total += int(part.quantity)
			if total != receipt.units:
				return false
			if receipt.reserve_mode == "reserve":
				reserved_by_resident[resident.id] = allocations
	if not state.quests.get("records") is Array or state.quests.records.size() != 7:
		return false
	ids = []
	for quest in state.quests.records:
		if not quest is Dictionary or not quest.get("id") in ["Q01", "Q02", "Q03", "Q04", "Q05", "Q06", "Q07"] or quest.id in ids or not quest.get("status") in ["inactive", "active", "completed"]:
			return false
		ids.append(quest.id)
	if not state.story_flags is Array:
		return false
	ids = []
	for flag in state.story_flags:
		if not flag in ["system_unlocked", "planted", "harvested", "contacted", "consented"] or flag in ids:
			return false
		ids.append(flag)
	if not state.world_states.get("first_enemy_defeated") is bool or not integer(state.world_states.get("resource_ready_at")) or not integer(state.world_states.get("defeats")):
		return false
	var has_enemy_health: int = int(state.world_states.has("enemy_health"))
	if state.schema_version == 4:
		var known_fields := 5 + has_enemy_health
		for key in ["salvage_ready_at", "camp_network", "cleared_patrols", "district_events"]:
			known_fields += int(state.world_states.has(key))
		if state.world_states.size() != known_fields or not state.world_states.get("locations") is Dictionary:
			return false
		if not Construction.validate(state.shelter.get("buildings", {}), state.world_states.get("salvage_ready_at", {}), rules.scenes):
			return false
		if state.world_states.has("camp_network") and not Camp.valid_record(state.world_states.camp_network, int(state.game_time_minutes)):
			return false
		var cleared = state.world_states.get("cleared_patrols", [])
		if not cleared is Array or cleared.size() > 3:
			return false
		var seen := {}
		for id in cleared:
			if not id is String or seen.has(id) or not Layout.street_has_patrol(id, state.world_states.layout):
				return false
			seen[id] = true
		if not DistrictEvents.validate(state.world_states.get("district_events", {}), cleared):
			return false
		for id in state.world_states.locations:
			if not id is String or not rules.scenes.has(id) or not Layout.building_exists(id, int(state.world_states.layout.generator_version)):
				return false
			var record = state.world_states.locations[id]
			if not record is Dictionary or record.is_empty():
				return false
			match Layout.kind(id):
				"outside":
					if id == "outside" or record.size() != 1 or not integer(record.get("resource_ready_at")):
						return false
				"house":
					if record.size() != 1 or not record.get("looted") is bool or not record.looted:
						return false
				"hospital":
					for key in record:
						if not record[key] is bool or not record[key]:
							return false
						if key == "defeated" and id != "hospital":
							continue
						if key != "cache_looted" or Layout.hospital_cache(id, state.world_states.layout).is_empty():
							return false
				_:
					return false
		if state.quests.has("expedition") and not Expedition.validate(state.quests.expedition, state, rules.scenes):
			return false
	elif state.world_states.size() != 3 + has_enemy_health:
		return false
	var enemy_health = state.world_states.get("enemy_health", {})
	if not enemy_health is Dictionary:
		return false
	for id in enemy_health:
		if not id is String or not rules.scenes.has(id) or not has_live_enemy(state, id) or not integer(enemy_health[id]) or enemy_health[id] >= Enemy.MAX_HEALTH:
			return false
	if state.world_states.first_enemy_defeated != ("system_unlocked" in state.story_flags) or state.world_states.first_enemy_defeated != ("system" in state.claimed_reward_ids):
		return false
	for key in ["farm", "residents", "world"]:
		if not integer(state.resource_revisions.get(key)):
			return false
	if not state.inventory.reservations is Array:
		return false
	var reserved: Dictionary = {}
	for reservation in state.inventory.reservations:
		if not reservation is Dictionary or not reservation.get("resident_id") in ["resident_1", "resident_2"] or not reservation.get("instance_id") is String or not integer(reservation.get("quantity")) or reservation.quantity <= 0:
			return false
		var item: Dictionary = {}
		for entry in state.inventory.items:
			if entry.instance_id == reservation.instance_id:
				item = entry
		var allocations: Dictionary = reserved_by_resident.get(reservation.resident_id, {})
		var part: Dictionary = allocations.get(reservation.instance_id, {})
		if item.is_empty() or part.is_empty() or item.type_id != part.type_id or reservation.quantity != part.quantity:
			return false
		allocations.erase(reservation.instance_id)
		reserved[item.instance_id] = reserved.get(item.instance_id, 0) + reservation.quantity
		if reserved[item.instance_id] > item.quantity:
			return false
	for allocations in reserved_by_resident.values():
		if not allocations.is_empty():
			return false
	if state.schema_version == 4 and rules.get("housing_required", false):
		var housed: Array = state.residents.records.filter(func(resident): return resident.status == "joined")
		if Construction.count(state.shelter.get("buildings", {}), "bed") < housed.size():
			return false
	return true

static func has_live_enemy(state: Dictionary, id: String) -> bool:
	if id == "hospital":
		return not state.world_states.first_enemy_defeated
	if state.schema_version != 4:
		return false
	if Layout.kind(id) == "hospital":
		return not state.world_states.locations.get(id, {}).get("defeated", false)
	return Layout.street_has_patrol(id, state.world_states.layout) and not id in state.world_states.get("cleared_patrols", [])
