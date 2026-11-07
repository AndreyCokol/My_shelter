extends RefCounted

const VERSION = 1
const CATALOG_VERSION = 1
const DISTRICTS = 4
const FLOORS = 4
const MAX_SEED = 2147483647
const DOORS = [Vector2(65, 125), Vector2(575, 125), Vector2(65, 215), Vector2(575, 215), Vector2(65, 305), Vector2(575, 305)]
const STREET_BLOCKS = [
	[Rect2(185, 115, 118, 42), Rect2(382, 187, 96, 40)],
	[Rect2(230, 160, 138, 34), Rect2(420, 105, 75, 52)],
	[Rect2(135, 180, 83, 45), Rect2(352, 113, 140, 38)],
	[Rect2(151, 115, 97, 56), Rect2(343, 180, 125, 40)],
]
const ROOM_BLOCKS = [
	[Rect2(175, 110, 54, 83), Rect2(389, 171, 107, 34)],
	[Rect2(154, 158, 121, 37), Rect2(423, 106, 59, 83)],
	[Rect2(250, 108, 46, 101), Rect2(401, 164, 90, 41)],
	[Rect2(160, 105, 108, 37), Rect2(388, 148, 46, 70)],
]

static func street(district: int) -> String:
	return "outside" if district == 0 else "street_%d" % district

static func hospital(district: int, floor_index: int) -> String:
	return "hospital" if district == 0 and floor_index == 0 else "hospital_%d_%d" % [district, floor_index + 1]

static func house(district: int) -> String:
	return "house_%d" % district

static func kind(id: String) -> String:
	if id == "outside" or id.begins_with("street_"):
		return "outside"
	if id == "hospital" or id.begins_with("hospital_"):
		return "hospital"
	if id.begins_with("house_"):
		return "house"
	return id

static func manifest(world_seed: int) -> Dictionary:
	return {"seed": world_seed, "generator_version": VERSION, "catalog_version": CATALOG_VERSION}

static func valid_manifest(value) -> bool:
	if not value is Dictionary or value.size() != 3:
		return false
	var seed_value = value.get("seed")
	return (seed_value is int or seed_value is float) and is_finite(seed_value) and seed_value >= 0 and seed_value <= MAX_SEED and seed_value == floor(seed_value) and value.get("generator_version") == VERSION and value.get("catalog_version") == CATALOG_VERSION

# Local streams prevent future loot rolls from changing the geometry.
static func _variant_order(world_seed: int, stream: String) -> Array:
	var result := [0, 1, 2, 3]
	for index in range(result.size() - 1, 0, -1):
		var digest := ("%d:%d:%s:%d" % [world_seed, VERSION, stream, index]).sha256_text()
		var other := digest.substr(0, 8).hex_to_int() % (index + 1)
		var saved = result[index]
		result[index] = result[other]
		result[other] = saved
	return result

static func _record(type: String, label: String, segment: String, obstacles: Array) -> Dictionary:
	return {"kind": type, "label": label, "segment": segment, "obstacles": obstacles, "links": []}

static func _connect(nodes: Dictionary, left: String, right: String) -> void:
	nodes[left].links.append(right)
	nodes[right].links.append(left)

static func build(world_seed: int) -> Dictionary:
	var nodes: Dictionary = {
		"shelter": _record("shelter", "Убежище", "shelter", []),
		"louvre": _record("louvre", "Стоянка", "camp", []),
	}
	var streets := _variant_order(world_seed, "streets")
	var houses := _variant_order(world_seed, "houses")
	var floors: Array = []
	for floor_index in range(FLOORS):
		floors.append(_variant_order(world_seed, "floor:%d" % floor_index))
	for district in range(DISTRICTS):
		var exterior := street(district)
		var residence := house(district)
		nodes[exterior] = _record("outside", "Район %d" % (district + 1), "street:%d" % streets[district], STREET_BLOCKS[streets[district]])
		nodes[residence] = _record("house", "Жилой дом · район %d" % (district + 1), "house:%d" % houses[district], ROOM_BLOCKS[houses[district]])
		_connect(nodes, exterior, residence)
		for floor_index in range(FLOORS):
			var id := hospital(district, floor_index)
			var variant: int = floors[floor_index][district]
			var obstacles: Array = ROOM_BLOCKS[variant].duplicate()
			# Each functional floor has a distinct obstacle in the west room.
			obstacles.append(Rect2(101 + 18 * floor_index, 112 + 11 * floor_index, 20, 26))
			nodes[id] = _record("hospital", "Больница %d · этаж %d" % [district + 1, floor_index + 1], "hospital:%d:%d" % [floor_index, variant], obstacles)
			_connect(nodes, exterior if floor_index == 0 else hospital(district, floor_index - 1), id)
	for edge in [[0, 1], [0, 2], [1, 3], [2, 3]]:
		_connect(nodes, street(edge[0]), street(edge[1]))
	_connect(nodes, "outside", "louvre")
	_connect(nodes, "outside", "shelter")
	return nodes

static func entries() -> Dictionary:
	# Graph topology is fixed for this catalog version. Seed changes segments.
	var nodes := build(0)
	var result := {}
	for id in nodes:
		var markers: Array = ["default"]
		for neighbor in nodes[id].links:
			markers.append("from_" + neighbor)
		result[id] = markers
	return result
