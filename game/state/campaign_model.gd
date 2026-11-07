extends RefCounted

const Construction = preload("res://game/systems/shelter/construction.gd")
const WorldLayout = preload("res://game/systems/world/world_layout.gd")
const Gameplay = preload("res://game/state/gameplay_state.gd")
const Core = preload("res://game/systems/core/core_session.gd")

static func new_state(rules: Dictionary) -> Dictionary:
	var state: Dictionary = {
		"schema_version": 2, "scope": "campaign-core", "ruleset_version": rules.version,
		"save_id": "slot-01", "state_revision": 0, "game_time_minutes": 0, "clock_remainder": 0.0,
		"resource_revisions": {"wallet": 0, "inventory:player": 0, "inventory:storage": 0, "scene": 0},
		"scene": {"current_scene_id": "shelter", "return_scene_id": "outside", "entry_point_id": "default", "positions": {}, "last_outside_position": null},
		"player": {"xp": 0, "position": {"x": 0.0, "y": 0.0}}, "wallet": {"system_coins": 0},
		"shelter": {"xp": 0, "discovered_item_type_ids": [], "claimed_parcel_ids": []},
		"inventory": {"items": [], "containers": rules.containers.duplicate(true), "reservations": []},
		"crops": {"plots": []}, "residents": {"records": []}, "quests": {"records": []},
		"story_flags": [], "world_states": {}, "completed_actions": {}, "claimed_reward_ids": []
	}

	if rules.get("gameplay", false):
		Gameplay.seed(state)
		if rules.has("world_seed"):
			state.schema_version = 4
			state.world_states.layout = WorldLayout.manifest(rules.world_seed)
			state.world_states.locations = {}
	return state

static func validate(state: Dictionary, rules: Dictionary) -> bool:
	var shape := new_state(rules)
	var legacy: bool = shape.schema_version == 4 and state.get("schema_version") == 3
	if state.size() != shape.size():
		return false
	for key in shape:
		if not state.has(key):
			return false
	if (state.schema_version != shape.schema_version and not legacy) or state.scope != "campaign-core" or state.ruleset_version != rules.version or not state.save_id is String or state.save_id.is_empty():
		return false
	for value in [state.state_revision, state.game_time_minutes]:
		if not Core.valid_integer(value):
			return false
	if not (state.clock_remainder is float or state.clock_remainder is int) or not is_finite(state.clock_remainder) or state.clock_remainder < 0 or state.clock_remainder >= 1:
		return false
	for key in ["player", "wallet", "shelter", "scene", "inventory", "resource_revisions", "completed_actions", "world_states", "crops", "residents", "quests"]:
		if not state[key] is Dictionary:
			return false
	if not Core.valid_integer(state.player.get("xp")) or not Core.valid_integer(state.wallet.get("system_coins")) or not Core.valid_integer(state.shelter.get("xp")):
		return false
	var entries: Dictionary = rules.scenes
	if legacy:
		entries = {"hospital": ["default"], "outside": ["default"], "shelter": ["default"], "louvre": ["default"]}
	if not state.scene.get("current_scene_id") in entries or not state.scene.get("return_scene_id") in entries or not state.scene.get("entry_point_id") in entries[state.scene.current_scene_id]:
		return false
	if state.schema_version == 4:
		var manifest = state.world_states.get("layout")
		if not WorldLayout.valid_manifest(manifest):
			return false
		var entry: String = state.scene.entry_point_id
		if entry != "default" and not WorldLayout.linked(entries, entry.trim_prefix("from_"), state.scene.current_scene_id, manifest):
			return false
	if not valid_position(state.player.get("position")) or not state.scene.get("positions") is Dictionary:
		return false
	for id in state.scene.positions:
		if not id in entries or not valid_position(state.scene.positions[id]):
			return false
	if state.scene.get("last_outside_position") != null and not valid_position(state.scene.last_outside_position):
		return false
	for key in ["items", "containers", "reservations"]:
		if not state.inventory.get(key) is Array:
			return false
	# Until domain import hooks exist, reject unsupported data rather than lose it.
	if not rules.get("gameplay", false) and (state.crops.get("plots") != [] or state.residents.get("records") != [] or state.quests.get("records") != [] or not state.inventory.reservations.is_empty() or not state.world_states.is_empty()):
		return false
	if not rules.get("gameplay", false) and (not state.story_flags is Array or not state.story_flags.is_empty()):
		return false
	for key in ["discovered_item_type_ids", "claimed_parcel_ids"]:
		if not unique_strings(state.shelter.get(key)):
			return false
	for type_id in state.shelter.discovered_item_type_ids:
		if not rules.items.has(type_id):
			return false
	for parcel_id in state.shelter.claimed_parcel_ids:
		if not rules.parcels.has(parcel_id):
			return false
	if not unique_strings(state.claimed_reward_ids):
		return false
	for reward_id in state.claimed_reward_ids:
		if not rules.rewards.has(reward_id):
			return false
	var expected_containers: Array = rules.containers
	if state.schema_version == 4:
		var buildings = state.shelter.get("buildings", {})
		if not buildings is Dictionary:
			return false
		expected_containers = Construction.storage_containers(expected_containers, buildings)
	if state.inventory.containers != expected_containers:
		return false
	var capacities: Dictionary = {}
	for container in state.inventory.containers:
		if not container is Dictionary or not container.get("id") is String or container.id.is_empty() or capacities.has(container.id) or not Core.valid_integer(container.get("capacity_units")):
			return false
		capacities[container.id] = container.capacity_units
		if not state.resource_revisions.has("inventory:" + container.id):
			return false
	for required in ["player", "storage"]:
		if not capacities.has(required):
			return false
	var ids: Dictionary = {}
	for item in state.inventory.items:
		if not item is Dictionary or not item.get("instance_id") is String or item.instance_id.is_empty() or ids.has(item.instance_id) or not rules.items.has(item.get("type_id")) or not capacities.has(item.get("container_id")) or not Core.valid_integer(item.get("quantity")) or item.quantity <= 0:
			return false
		ids[item.instance_id] = true
		capacities[item.container_id] -= item.quantity
		if capacities[item.container_id] < 0:
			return false
	for offer_id in rules.offers:
		if not state.resource_revisions.has("offer:" + offer_id):
			return false
	for key in ["wallet", "scene"]:
		if not state.resource_revisions.has(key):
			return false
	for key in state.resource_revisions:
		if not key is String or not Core.valid_integer(state.resource_revisions[key]):
			return false
	for id in state.completed_actions:
		var receipt = state.completed_actions[id]
		if not id is String or id.is_empty() or not receipt is Dictionary or not receipt.get("fingerprint") is String or not receipt.get("result") is Dictionary:
			return false
		var result: Dictionary = receipt.result
		if result.get("ok") != true or result.get("code") != "OK" or result.get("action_id") != id or not Core.valid_integer(result.get("state_revision")) or result.state_revision > state.state_revision or not result.get("data") is Dictionary or not result.get("message_key") is String:
			return false
	if rules.get("gameplay", false) and not Gameplay.validate(state, rules):
		return false
	return true

static func unique_strings(value) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for entry in value:
		if not entry is String or entry.is_empty() or seen.has(entry):
			return false
		seen[entry] = true
	return true

static func valid_position(value) -> bool:
	if not value is Dictionary or value.size() != 2:
		return false
	for axis in ["x", "y"]:
		var number = value.get(axis)
		if not (number is float or number is int) or not is_finite(number) or abs(number) > 10000000:
			return false
	return true
