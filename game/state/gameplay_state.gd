extends RefCounted

const Layout = preload("res://game/systems/world/world_layout.gd")

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
		if plot.status in ["growing", "ripe", "spoiled"] and (plot.ripe_at != plot.planted_at + rules.crop.grow_minutes or plot.spoil_at != plot.ripe_at + rules.crop.spoil_minutes):
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
	for resident in state.residents.records:
		if not resident is Dictionary or not resident.get("id") in ["resident_1", "resident_2"] or resident.id in ids or not resident.get("status") in ["unknown", "contacted", "declined", "AWAITING_SUPPLIES", "joined"] or not resident.get("consent") is bool or not resident.get("food_receipt_id") is String:
			return false
		ids.append(resident.id)
		if resident.status in ["AWAITING_SUPPLIES", "joined"] and not resident.consent:
			return false
		if resident.status == "joined" and (resident.food_receipt_id.is_empty() or not state.completed_actions.has(resident.food_receipt_id)):
			return false
		if resident.status == "joined":
			var receipt: Dictionary = state.completed_actions[resident.food_receipt_id].result.data
			if receipt.get("resident_id") != resident.id or receipt.get("reserve_mode") != rules.food.reserve_mode or receipt.get("units") != rules.food.units_per_resident or not receipt.get("food_allocations") is Array:
				return false
			var total: int = 0
			for part in receipt.food_allocations:
				if not part is Dictionary or not part.get("instance_id") is String or not part.get("type_id") in rules.food.accepted_food_type_ids or not integer(part.get("quantity")) or part.quantity <= 0:
					return false
				total += int(part.quantity)
			if total != rules.food.units_per_resident:
				return false
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
	if state.schema_version == 4:
		if state.world_states.size() != 5 or not Layout.valid_manifest(state.world_states.get("layout")) or not state.world_states.get("locations") is Dictionary:
			return false
		for id in state.world_states.locations:
			if not id is String or not rules.scenes.has(id):
				return false
			var record = state.world_states.locations[id]
			if not record is Dictionary or record.size() != 1:
				return false
			match Layout.kind(id):
				"outside":
					if id == "outside" or not integer(record.get("resource_ready_at")):
						return false
				"house":
					if not record.get("looted") is bool or not record.looted:
						return false
				"hospital":
					if id == "hospital" or not record.get("defeated") is bool or not record.defeated:
						return false
				_:
					return false
	elif state.world_states.size() != 3:
		return false
	if state.world_states.first_enemy_defeated != ("system_unlocked" in state.story_flags) or state.world_states.first_enemy_defeated != ("system" in state.claimed_reward_ids):
		return false
	for key in ["farm", "residents", "world"]:
		if not integer(state.resource_revisions.get(key)):
			return false
	if not state.inventory.reservations is Array:
		return false
	var reserved: Dictionary = {}
	var food_by_resident: Dictionary = {}
	for reservation in state.inventory.reservations:
		if not reservation is Dictionary or not reservation.get("resident_id") in ["resident_1", "resident_2"] or not reservation.get("instance_id") is String or not integer(reservation.get("quantity")) or reservation.quantity <= 0:
			return false
		var item: Dictionary = {}
		for entry in state.inventory.items:
			if entry.instance_id == reservation.instance_id:
				item = entry
		if item.is_empty() or not item.type_id in rules.food.accepted_food_type_ids:
			return false
		var joined := false
		for resident in state.residents.records:
			if resident.id == reservation.resident_id:
				joined = resident.status == "joined"
		if not joined:
			return false
		reserved[item.instance_id] = reserved.get(item.instance_id, 0) + reservation.quantity
		food_by_resident[reservation.resident_id] = food_by_resident.get(reservation.resident_id, 0) + reservation.quantity
		if reserved[item.instance_id] > item.quantity:
			return false
	for resident in state.residents.records:
		if resident.status == "joined" and rules.food.reserve_mode == "reserve" and food_by_resident.get(resident.id, 0) != rules.food.units_per_resident:
			return false
	return rules.food.reserve_mode == "reserve" or state.inventory.reservations.is_empty()
