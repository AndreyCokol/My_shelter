extends RefCounted

const VERSION = 2
const SEGMENT_VERSION = 1
const ORIGINAL_ROADS = [[0, 1], [0, 2], [1, 3], [2, 3]]
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

const HOUSE_BLOCKS = [
	[Rect2(162, 105, 14, 130), Rect2(240, 221, 96, 13), Rect2(419, 110, 17, 93)],
	[Rect2(180, 107, 17, 92), Rect2(205, 155, 103, 14), Rect2(425, 207, 106, 17)],
	[Rect2(144, 178, 94, 18), Rect2(351, 111, 17, 102), Rect2(465, 176, 68, 20)],
	[Rect2(199, 109, 17, 102), Rect2(277, 112, 128, 15), Rect2(426, 217, 16, 67)],
]
const STREET_PROFILES = ["Перекрёсток", "Разбитое КПП", "Заросший квартал", "Площадь"]
const HOUSE_PROFILES = ["Студия", "Семейная квартира", "Коммунальная квартира", "Мастерская в доме"]
const HOSPITAL_PROFILES = ["Приёмное отделение", "Палаты", "Операционный блок", "Лаборатория"]

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
	return (seed_value is int or seed_value is float) and is_finite(seed_value) and seed_value >= 0 and seed_value <= MAX_SEED and seed_value == floor(seed_value) and value.get("generator_version") in [1, VERSION] and value.get("catalog_version") == CATALOG_VERSION

# Local streams prevent future loot rolls from changing the geometry.
static func _variant_order(world_seed: int, stream: String) -> Array:
	var result := [0, 1, 2, 3]
	for index in range(result.size() - 1, 0, -1):
		var digest := ("%d:%d:%s:%d" % [world_seed, SEGMENT_VERSION, stream, index]).sha256_text()
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

static func from_manifest(data: Dictionary) -> Dictionary:
	return build(int(data.seed), int(data.generator_version))

static func roads(world_seed: int, version: int) -> Array:
	if version == 1:
		return ORIGINAL_ROADS
	var order := _variant_order(world_seed, "roads")
	var edges: Array = []
	for index in range(order.size() - 1):
		edges.append([order[index], order[index + 1]])
	if ("%d:road-loop" % world_seed).sha256_text().substr(0, 2).hex_to_int() % 2 == 0:
		edges.append([order.back(), order.front()])
	return edges

static func linked(entries: Dictionary, from: String, to: String, data: Dictionary) -> bool:
	if kind(from) != "outside" or kind(to) != "outside":
		return "from_" + from in entries.get(to, [])
	for edge in roads(int(data.seed), int(data.generator_version)):
		if (from == street(edge[0]) and to == street(edge[1])) or (from == street(edge[1]) and to == street(edge[0])):
			return true
	return false

static func build(world_seed: int, version: int = VERSION) -> Dictionary:
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
		var interiors := ROOM_BLOCKS if version == 1 else HOUSE_BLOCKS
		nodes[residence] = _record("house", "Жилой дом · район %d" % (district + 1), "house:%d" % houses[district], interiors[houses[district]])
		_connect(nodes, exterior, residence)
		for floor_index in range(FLOORS):
			var id := hospital(district, floor_index)
			var variant: int = floors[floor_index][district]
			var obstacles: Array = ROOM_BLOCKS[variant].duplicate()
			# Each functional floor has a distinct obstacle in the west room.
			obstacles.append(Rect2(101 + 18 * floor_index, 112 + 11 * floor_index, 20, 26))
			nodes[id] = _record("hospital", "Больница %d · этаж %d" % [district + 1, floor_index + 1], "hospital:%d:%d" % [floor_index, variant], obstacles)
			_connect(nodes, exterior if floor_index == 0 else hospital(district, floor_index - 1), id)
	for edge in roads(world_seed, version):
		_connect(nodes, street(edge[0]), street(edge[1]))
	_connect(nodes, "outside", "louvre")
	_connect(nodes, "outside", "shelter")
	return nodes

static func entries() -> Dictionary:
	# Trusted registry includes every possible marker. Actual links are checked against the save.
	var nodes := build(0, 1)
	var result := {}
	for id in nodes:
		var markers: Array = ["default"]
		for neighbor in nodes[id].links:
			if kind(id) != "outside" or kind(neighbor) != "outside":
				markers.append("from_" + neighbor)
		if kind(id) == "outside":
			for district in range(DISTRICTS):
				if street(district) != id:
					markers.append("from_" + street(district))
		result[id] = markers
	return result
