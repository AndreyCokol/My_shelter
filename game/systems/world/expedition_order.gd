extends RefCounted

const Layout = preload("res://game/systems/world/world_layout.gd")
const SUPPLY_COST := 2
const REWARD := 8

static func choose_target(state: Dictionary) -> String:
	var manifest: Dictionary = state.world_states.layout
	var locations: Dictionary = state.world_states.locations
	for floor_index in range(Layout.FLOORS):
		for offset in range(Layout.DISTRICTS):
			var district: int = (int(manifest.seed) + offset) % Layout.DISTRICTS
			var id := Layout.hospital(district, floor_index)
			if id != "hospital" and not locations.get(id, {}).get("defeated", false):
				return id
	return ""

static func validate(order, state: Dictionary, scenes: Dictionary) -> bool:
	if not order is Dictionary or order.size() != 2 or not order.get("target") is String or not order.get("claimed") is bool:
		return false
	var id: String = order.target
	if id.is_empty():
		return true
	return id != "hospital" and scenes.has(id) and Layout.kind(id) == "hospital" and (not order.claimed or state.world_states.locations.get(id, {}).get("defeated", false))
