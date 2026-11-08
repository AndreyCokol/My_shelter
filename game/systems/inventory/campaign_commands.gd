extends RefCounted

const Layout = preload("res://game/systems/world/world_layout.gd")
const Gameplay = preload("res://game/systems/gameplay/gameplay_commands.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Core = preload("res://game/systems/core/core_session.gd")
var calendar
var rules: Dictionary

func _init(config: Dictionary) -> void:
	rules = config.duplicate(true)

# Ordered typed payloads make the semantic fingerprint independent of JSON order.
func normalize(request: Dictionary) -> Dictionary:
	var fields := {
		"inventory.transfer": ["instance_id", "from_id", "to_id", "quantity"],
		"inventory.purchase": ["offer_id"], "inventory.claim_parcel": ["parcel_id"],
		"progression.claim_reward": ["reward_id"], "clock.rest": ["target_minute"],
		"scene.transition": ["destination_scene_id", "entry_point_id"], "session.save": [], "session.upgrade_world": []
	}
	var kind = request.get("command_type")
	if rules.get("gameplay", false) and kind is String and kind.begins_with("game."):
		return Gameplay.normalize(request)
	var payload = request.get("payload")
	if not fields.has(kind) or not payload is Dictionary or payload.size() != fields[kind].size():
		return {"ok": false}
	var normalized: Dictionary = {}
	for key in fields[kind]:
		var value = payload.get(key)
		if key in ["quantity", "target_minute"]:
			if not Core.valid_integer(value) or (key == "quantity" and value <= 0):
				return {"ok": false}
			normalized[key] = int(value)
		else:
			if not value is String or value.is_empty():
				return {"ok": false}
			normalized[key] = value
	return {"ok": true, "payload": normalized}

func plan(state: Dictionary, request: Dictionary) -> Dictionary:
	var before := state.duplicate(true)
	var result := _plan(state, request)
	if result.get("ok", false):
		if rules.get("gameplay", false):
			Gameplay.refresh_quests(state)
		if request.command_type != "clock.rest":
			result.events = command_events(before, state, request, result)
			if request.command_type.begins_with("game."):
				result.events.append({"event_type": "gameplay_changed", "payload": {"command_type": request.command_type}})
	return result

func _plan(state: Dictionary, request: Dictionary) -> Dictionary:
	var p: Dictionary = request.payload
	var kind: String = request.command_type
	if request.context.actor_id != "player":
		return fail("INVALID_ARGUMENT")
	# Scene validation happens AFTER receipt replay in CoreSession.
	if request.context.get("scene_id") != state.scene.current_scene_id:
		return fail("INVALID_STATE")
	if kind in ["scene.transition", "session.save"] and request.context.has("departure_position"):
		if not Model.valid_position(request.context.departure_position):
			return fail("INVALID_ARGUMENT")
		state.player.position = request.context.departure_position.duplicate(true)
		state.scene.positions[state.scene.current_scene_id] = state.player.position.duplicate(true)
	# Portal and shelter transitions are durable checkpoints: keep live combat HP.
	if kind in ["scene.transition", "session.save"] and request.context.has("health"):
		if not Core.valid_integer(request.context.health) or request.context.health > 100:
			return fail("INVALID_ARGUMENT")
		state.player.hp = int(request.context.health)
	if rules.get("gameplay", false):
		if not state.world_states.first_enemy_defeated:
			# The shelter is an unconditional player escape, including onboarding.
			# Only ordinary world travel and locked System resources need the first victory.
			var returning_from_shelter: bool = kind == "scene.transition" and state.scene.current_scene_id == "shelter" and p.get("destination_scene_id") == state.scene.return_scene_id
			var entering_shelter: bool = kind == "scene.transition" and p.get("destination_scene_id") == "shelter"
			if kind == "scene.transition" and not entering_shelter and not returning_from_shelter:
				return fail("UNAVAILABLE")
			if kind in ["inventory.purchase", "inventory.claim_parcel"]:
				return fail("UNAVAILABLE")
		if kind.begins_with("game."):
			var keys := ["world", "farm", "residents", "inventory:player", "inventory:storage"]
			if kind in ["game.expand_farm", "game.fulfill_contract", "game.trade_camp", "game.claim_expedition", "game.resolve_district"]:
				keys.append("wallet")
			var checked := revisions(state, request, keys)
			if not checked.ok:
				return checked
			return Gameplay.plan(state, request, rules)
	match kind:
		"inventory.transfer":
			var rev := revisions(state, request, ["inventory:" + p.from_id, "inventory:" + p.to_id])
			if not rev.ok:
				return rev
			if p.from_id == p.to_id:
				return fail("INVALID_ARGUMENT")
			for item in state.inventory.items:
				if item.instance_id != p.instance_id:
					continue
				if item.container_id != p.from_id:
					return fail("INVALID_STATE")
				if Gameplay.available(state, item) < p.quantity:
					return fail("INSUFFICIENT_RESOURCES")
				if not room(state, p.to_id, p.quantity):
					return fail("CAPACITY_EXCEEDED")
				if item.quantity == p.quantity:
					item.container_id = p.to_id
				else:
					item.quantity -= p.quantity
					state.inventory.items.append({"instance_id": "split:" + request.action_id, "type_id": item.type_id, "quantity": p.quantity, "container_id": p.to_id})
				bump(state, ["inventory:" + p.from_id, "inventory:" + p.to_id])
				return success({"quantity": p.quantity})
			return fail("NOT_FOUND")
		"inventory.purchase":
			if not rules.offers.has(p.offer_id):
				return fail("NOT_FOUND")
			var rev := revisions(state, request, ["inventory:player", "wallet", "offer:" + p.offer_id])
			if not rev.ok:
				return rev
			var offer: Dictionary = rules.offers[p.offer_id]
			if state.wallet.system_coins < offer.price:
				return fail("INSUFFICIENT_RESOURCES")
			var granted := grant(state, offer, request.action_id)
			if not granted.ok:
				return granted
			state.wallet.system_coins -= offer.price
			bump(state, ["wallet"])
			return granted
		"inventory.claim_parcel", "progression.claim_reward":
			var parcel := kind == "inventory.claim_parcel"
			var id: String = p.parcel_id if parcel else p.reward_id
			var catalog: Dictionary = rules.parcels if parcel else rules.rewards
			var claimed: Array = state.shelter.claimed_parcel_ids if parcel else state.claimed_reward_ids
			if not catalog.has(id):
				return fail("NOT_FOUND")
			if claimed.has(id):
				return fail("INVALID_STATE")
			# Reward grants are trusted core entry points, not generic UI loot payloads.
			# Eligibility is a pure predicate over persisted state, not event delivery.
			if not catalog[id].get("eligible", false):
				return fail("UNAVAILABLE")
			var rev := revisions(state, request, ["inventory:player"])
			if not rev.ok:
				return rev
			var granted := grant(state, catalog[id], request.action_id)
			if not granted.ok:
				return granted
			claimed.append(id)
			state.player.xp += catalog[id].get("hero_xp", 0)
			state.wallet.system_coins += catalog[id].get("coins", 0)
			bump(state, ["wallet"])
			return granted
		"clock.rest":
			if state.scene.current_scene_id != "shelter":
				return fail("NOT_IN_SAFE_AREA")
			if p.target_minute <= state.game_time_minutes:
				return fail("INVALID_ARGUMENT")
			var advanced: Dictionary = calendar.advance(state, int(p.target_minute), "rest")
			if advanced.ok:
				state.clock_remainder = 0.0
			return advanced
		"scene.transition":
			var rev := revisions(state, request, ["scene"])
			if not rev.ok:
				return rev
			if not p.destination_scene_id in rules.scenes or not p.entry_point_id in rules.scenes[p.destination_scene_id] or p.destination_scene_id == state.scene.current_scene_id:
				return fail("INVALID_ARGUMENT")
			var old: String = state.scene.current_scene_id
			if state.schema_version == 4:
				var linked := Layout.linked(rules.scenes, old, p.destination_scene_id, state.world_states.layout)
				var shelter_warp: bool = p.entry_point_id == "default" and (p.destination_scene_id == "shelter" or (old == "shelter" and p.destination_scene_id == state.scene.return_scene_id))
				if not linked and not shelter_warp:
					return fail("INVALID_ARGUMENT")
				if p.entry_point_id != "default" and p.entry_point_id != "from_" + old:
					return fail("INVALID_ARGUMENT")
			elif p.destination_scene_id not in ["hospital", "outside", "shelter", "louvre"] and rules.has("world_seed"):
				return fail("INVALID_ARGUMENT")
			var arrival = request.context.get("arrival_position", state.scene.positions.get(p.destination_scene_id, {"x": 0.0, "y": 0.0}))
			if not Model.valid_position(arrival):
				return fail("INVALID_ARGUMENT")
			state.scene.positions[old] = state.player.position.duplicate(true)
			if old != "shelter":
				state.scene.last_outside_position = state.player.position.duplicate(true)
			state.player.position = arrival.duplicate(true)
			state.scene.current_scene_id = p.destination_scene_id
			state.scene.entry_point_id = p.entry_point_id
			if old != "shelter":
				state.scene.return_scene_id = old
			bump(state, ["scene"])
			return success({"from_scene_id": old, "to_scene_id": p.destination_scene_id})
		"session.upgrade_world":
			if not rules.has("world_seed"):
				return fail("UNAVAILABLE")
			var legacy: bool = state.schema_version == 3
			if not legacy and (state.schema_version != 4 or state.world_states.layout.generator_version == Layout.VERSION):
				return fail("UNAVAILABLE")
			var rev := revisions(state, request, ["world", "scene"])
			if not rev.ok:
				return rev
			var seed_value: int = rules.world_seed if legacy else int(state.world_states.layout.seed)
			if legacy:
				state.schema_version = 4
				state.world_states.locations = {}
			state.world_states.layout = Layout.manifest(seed_value)
			var previous_entry: String = state.scene.entry_point_id
			if previous_entry != "default" and not Layout.linked(rules.scenes, previous_entry.trim_prefix("from_"), state.scene.current_scene_id, state.world_states.layout):
				state.scene.entry_point_id = "default"
			var nodes := Layout.from_manifest(state.world_states.layout)
			for id in state.scene.positions:
				state.scene.positions[id] = safe_legacy_position(nodes[id], state.scene.positions[id])
			state.player.position = safe_legacy_position(nodes[state.scene.current_scene_id], request.context.get("departure_position", state.player.position))
			state.scene.positions[state.scene.current_scene_id] = state.player.position.duplicate()
			if state.scene.last_outside_position != null:
				state.scene.last_outside_position = safe_legacy_position(nodes[state.scene.return_scene_id], state.scene.last_outside_position)
			if request.context.has("health"):
				if not Core.valid_integer(request.context.health) or request.context.health > 100:
					return fail("INVALID_ARGUMENT")
				state.player.hp = int(request.context.health)
			bump(state, ["world", "scene"])
			return success({"seed": seed_value})
		"session.save":
			if rules.get("gameplay", false) and request.context.has("health"):
				if not Core.valid_integer(request.context.health) or request.context.health > 100:
					return fail("INVALID_ARGUMENT")
				state.player.hp = int(request.context.health)
			return success({})
	return fail("UNAVAILABLE")

static func safe_legacy_position(node: Dictionary, position) -> Dictionary:
	var bounds: Rect2 = node.bounds.grow(-15)
	if Model.valid_position(position):
		var point := Vector2(position.x, position.y)
		if bounds.has_point(point) and node.obstacles.all(func(rect): return not rect.grow(10).has_point(point)):
			return position.duplicate()
	return {"x": node.spawn.x, "y": node.spawn.y}

func revisions(state: Dictionary, request: Dictionary, required: Array) -> Dictionary:
	var expected = request.context.get("expected_resource_revisions")
	if not expected is Array:
		return fail("INVALID_ARGUMENT")
	var versions: Dictionary = {}
	for entry in expected:
		if not entry is Dictionary or not entry.get("key") is String or not Core.valid_integer(entry.get("revision")) or versions.has(entry.key):
			return fail("INVALID_ARGUMENT")
		versions[entry.key] = entry.revision
	var conflicts: Array = []
	for key in required:
		if not state.resource_revisions.has(key) or not versions.has(key):
			return fail("INVALID_ARGUMENT")
		if versions[key] != state.resource_revisions[key]:
			conflicts.append(key)
	if not conflicts.is_empty():
		return {"ok": false, "code": "STALE_REVISION", "data": {"conflict_keys": conflicts}}
	return success({})

func room(state: Dictionary, container_id: String, quantity: int) -> bool:
	for container in state.inventory.containers:
		if container.id == container_id:
			var used: int = 0
			for item in state.inventory.items:
				if item.container_id == container_id:
					used += int(item.quantity)
			return used + quantity <= container.capacity_units
	return false

func grant(state: Dictionary, definition: Dictionary, action_id: String) -> Dictionary:
	if not room(state, "player", int(definition.quantity)):
		return fail("CAPACITY_EXCEEDED")
	state.inventory.items.append({"instance_id": "grant:" + action_id, "type_id": definition.type_id, "quantity": int(definition.quantity), "container_id": "player"})
	if not definition.type_id in state.shelter.discovered_item_type_ids:
		state.shelter.discovered_item_type_ids.append(definition.type_id)
		state.shelter.xp += rules.discovery_xp
	bump(state, ["inventory:player"])
	return success({"instance_id": "grant:" + action_id, "type_id": definition.type_id, "quantity": int(definition.quantity)})

static func bump(state: Dictionary, keys: Array) -> void:
	for key in keys:
		state.resource_revisions[key] += 1

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func success(data: Dictionary) -> Dictionary:
	return {"ok": true, "data": data}

func command_events(before: Dictionary, after: Dictionary, request: Dictionary, result: Dictionary) -> Array:
	var drafts: Array = []
	var p: Dictionary = request.payload
	match request.command_type:
		"inventory.transfer":
			var type_id: String = ""
			var moved_id: String = p.instance_id
			for item in before.inventory.items:
				if item.instance_id == p.instance_id:
					type_id = item.type_id
					if item.quantity > p.quantity:
						moved_id = "split:" + request.action_id
			drafts.append({"event_type": "item_transferred", "payload": {"instance_id": moved_id, "type_id": type_id, "quantity": p.quantity, "from_id": p.from_id, "to_id": p.to_id}})
		"inventory.purchase", "inventory.claim_parcel", "progression.claim_reward":
			var payload: Dictionary = result.data.duplicate(true)
			payload.container_id = "player"
			drafts.append({"event_type": "item_granted", "payload": payload})
		"scene.transition":
			drafts.append({"event_type": "scene_changed", "payload": {"from_scene_id": before.scene.current_scene_id, "to_scene_id": after.scene.current_scene_id, "entry_point_id": p.entry_point_id, "return_scene_id": after.scene.return_scene_id}})
		"clock.rest":
			drafts.append({"event_type": "time_advanced", "payload": {"from_minute": before.game_time_minutes, "to_minute": after.game_time_minutes, "reason": "rest"}})
		"session.save":
			drafts.append({"event_type": "checkpoint_saved", "payload": {"save_id": after.save_id}})
	for type_id in after.shelter.discovered_item_type_ids:
		if not type_id in before.shelter.discovered_item_type_ids:
			drafts.append({"event_type": "first_item_type_discovered", "payload": {"type_id": type_id, "xp_awarded": rules.discovery_xp}})
	if request.command_type == "inventory.claim_parcel":
		drafts.append({"event_type": "parcel_claimed", "payload": {"parcel_id": p.parcel_id, "receipt_id": request.action_id}})
	if request.command_type == "progression.claim_reward":
		drafts.append({"event_type": "reward_claimed", "payload": {"reward_id": p.reward_id, "receipt_id": request.action_id}})
	if before.player.xp != after.player.xp or before.shelter.xp != after.shelter.xp:
		drafts.append({"event_type": "progression_changed", "payload": {"hero_xp": after.player.xp, "shelter_xp": after.shelter.xp}})
	if before.wallet.system_coins != after.wallet.system_coins:
		drafts.append({"event_type": "wallet_changed", "payload": {"system_coins": after.wallet.system_coins}})
	return drafts

static func time_events(before: Dictionary, after: Dictionary) -> Array:
	if before.game_time_minutes == after.game_time_minutes:
		return []
	return [{"event_type": "time_advanced", "payload": {"from_minute": before.game_time_minutes, "to_minute": after.game_time_minutes, "reason": "tick"}}]
