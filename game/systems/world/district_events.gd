extends RefCounted

const POINT := Vector2(496, 298)
const EVENTS := [
	{"title": "Сигнал бедствия", "description": "Раненый выживший просит еды. За помощь он отдаст 4 монеты.",
		"item": "crop.potato", "cost": 1, "reward": 4},
	{"title": "Спор о припасах", "description": "Две группы готовы разойтись, если разделить семена. Они предлагают 5 монет за 2 семени.",
		"item": "seed.basic", "cost": 2, "reward": 5},
]

static func available(state: Dictionary, id: String) -> bool:
	return state.schema_version == 4 and id in state.world_states.get("cleared_patrols", []) and not state.world_states.get("district_events", {}).has(id)

static func event_for(state: Dictionary, id: String) -> Dictionary:
	var district := int(id.get_slice("_", 1))
	return EVENTS[(int(state.world_states.layout.seed) + district) % EVENTS.size()]

static func validate(outcomes, cleared: Array) -> bool:
	if not outcomes is Dictionary:
		return false
	for id in outcomes:
		if not id in cleared or not outcomes[id] in ["helped", "declined"]:
			return false
	return true
