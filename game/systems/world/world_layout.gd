extends RefCounted

const VERSION = 3
const SEGMENT_VERSION = 1
const ORIGINAL_ROADS = [[0, 1], [0, 2], [1, 3], [2, 3]]
const CATALOG_VERSION = 1
const DISTRICTS = 4
const FLOORS = 4
const MAX_SEED = 2147483647
const DOORS = [Vector2(65, 125), Vector2(575, 125), Vector2(65, 215), Vector2(575, 215), Vector2(65, 305), Vector2(575, 305)]
const LEGACY_FLOOR := Rect2(20, 85, 600, 260)
const STREET_SIZE := Vector2(2400, 780)
const INTERIOR_SIZE := Vector2(1200, 520)
const DEFAULT_SPAWN := Vector2(120, 260)
const DEFAULT_LOOT := Vector2(300, 267)
const WORLD_BOUNDS := Rect2(30, 95, 580, 240)
# These connected lanes protect the door approaches, default arrival and supply points.
const PROTECTED_LANES := [
	Rect2(60, 120, 30, 191), Rect2(550, 120, 30, 191),
	Rect2(60, 297, 520, 20), Rect2(115, 252, 10, 55), Rect2(295, 262, 10, 55),
]
const FALLBACK_BLOCKS := [Rect2(210, 148, 50, 32)]
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

const HOSPITAL_CACHES = [
	{"label": "Склад приёмного отделения", "item": "material.salvage", "quantity": 2},
	{"label": "Провизия персонала", "item": "crop.potato", "quantity": 1},
	{"label": "Разобранное оборудование", "item": "material.salvage", "quantity": 3},
	{"label": "Аварийное освещение", "item": "material.lamp_kit", "quantity": 1},
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

static func hospital_cache(id: String, data: Dictionary) -> Dictionary:
	if int(data.generator_version) < 2 or kind(id) != "hospital":
		return {}
	var floor_index := 0 if id == "hospital" else int(id.get_slice("_", 2)) - 1
	return HOSPITAL_CACHES[floor_index]

static func street_has_patrol(id: String, data: Dictionary) -> bool:
	return int(data.generator_version) >= 2 and id in ["street_1", "street_2", "street_3"]

static func manifest(world_seed: int) -> Dictionary:
	return {"seed": world_seed, "generator_version": VERSION, "catalog_version": CATALOG_VERSION}

static func valid_manifest(value) -> bool:
	if not value is Dictionary or value.size() != 3:
		return false
	var seed_value = value.get("seed")
	return (seed_value is int or seed_value is float) and is_finite(seed_value) and seed_value >= 0 and seed_value <= MAX_SEED and seed_value == floor(seed_value) and value.get("generator_version") in [1, 2, VERSION] and value.get("catalog_version") == CATALOG_VERSION

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

static func checked_obstacles(obstacles: Array) -> Array:
	for obstacle in obstacles:
		if not obstacle is Rect2 or not obstacle.is_finite() or obstacle.size.x <= 0 or obstacle.size.y <= 0 or not WORLD_BOUNDS.encloses(obstacle):
			return FALLBACK_BLOCKS
		for lane in PROTECTED_LANES:
			if obstacle.grow(10).intersects(lane):
				return FALLBACK_BLOCKS
	return obstacles

static func _record(type: String, label: String, segment: String, obstacles: Array) -> Dictionary:
	return {"kind": type, "label": label, "segment": segment, "obstacles": checked_obstacles(obstacles), "links": [],
		"bounds": LEGACY_FLOOR, "spawn": DEFAULT_SPAWN, "loot": DEFAULT_LOOT, "enemy": Vector2(330, 190),
		"patrol": PackedVector2Array([Vector2(235, 248), Vector2(455, 248), Vector2(455, 296), Vector2(235, 296)])}

static func _expand_street(node: Dictionary, variant: int) -> void:
	node.bounds = Rect2(LEGACY_FLOOR.position, STREET_SIZE)
	node.aprons = [Rect2(517, 181, 54, 49), Rect2(1283, 181, 54, 49), Rect2(436, 478, 54, 41)]
	node.roadways = [
		Rect2(20, 230, 2400, 84), Rect2(110, 519, 2160, 84),
		Rect2(698, 254, 84, 316), Rect2(1606, 254, 84, 316),
	]
	node.facades = {
		"house": Rect2(440, 101, 208, 81), "hospital": Rect2(1190, 101, 240, 81),
		"shelter": Rect2(400, 415, 126, 64),
	}
	node.obstacles = node.obstacles.duplicate()
	node.obstacles.append_array(node.facades.values())
	node.obstacles.append_array([
		Rect2(892, 357, 145, 96), Rect2(1757, 350, 163, 111),
		Rect2(1030 + variant * 115, 659, 145, 85), Rect2(2015, 668, 164, 100),
		Rect2(2090, 111, 192, 75),
	])
	node.loot = Vector2(912 + variant * 111, 564)
	node.salvage = Vector2(405 + variant * 93, 550)
	node.event = Vector2(1780, 635)
	node.patrol = PackedVector2Array([Vector2(1110, 535), Vector2(1480, 535), Vector2(1480, 580), Vector2(1110, 580)])

static func _expand_interior(node: Dictionary, variant: int) -> void:
	node.bounds = Rect2(LEGACY_FLOOR.position, INTERIOR_SIZE)
	node.obstacles = node.obstacles.duplicate()
	node.obstacles.append_array([
		Rect2(585, 100, 13, 97), Rect2(585, 258, 13, 100),
		Rect2(35, 363, 105, 13), Rect2(220, 363, 319, 13),
		Rect2(643, 363, 227, 13), Rect2(950, 363, 253, 13),
		Rect2(585, 399, 13, 95), Rect2(585, 551, 13, 35),
		Rect2(35, 583, 111, 12), Rect2(214, 583, 990, 12),
		Rect2(680 + variant * 44, 140, 134, 32), Rect2(1002, 204 + variant * 21, 75, 44),
		Rect2(718, 487 - variant * 15, 98, 27), Rect2(1058 - variant * 29, 526, 108, 32),
	])
	node.rooms = [
		Rect2(599, 95, 611, 268), Rect2(30, 377, 555, 217), Rect2(599, 377, 611, 217),
	]
	if node.kind == "house":
		node.loot = Vector2(850 + variant * 35, 442)
	elif not node.segment.begins_with("hospital:0:"):
		node.loot = Vector2(769 + variant * 75, 326)
		node.enemy = Vector2(902, 253)

static func _expand_service(node: Dictionary) -> void:
	node.bounds = Rect2(LEGACY_FLOOR.position, INTERIOR_SIZE)
	node.rooms = [Rect2(684, 147, 360, 239), Rect2(206, 389, 345, 147)]
	node.obstacles = [
		Rect2(683, 146, 95, 15), Rect2(897, 146, 149, 15),
		Rect2(685, 147, 14, 120), Rect2(1031, 147, 14, 120),
		Rect2(317, 465, 126, 31), Rect2(826, 446, 152, 31),
		Rect2(1008, 576, 66, 12), Rect2(1146, 576, 58, 12),
	]

static func _make_exits(nodes: Dictionary, world_seed: int, version: int) -> void:
	var road_edges: Array = roads(world_seed, version).map(func(edge): return [street(edge[0]), street(edge[1])])
	for id in nodes:
		var node: Dictionary = nodes[id]
		node.exits = {}
		for target in node.links:
			var destination: String = nodes[target].kind
			var position := Vector2(1110, 560)
			var inward := Vector2.UP
			var form := "door"
			if node.kind == "outside":
				inward = Vector2.DOWN
				match destination:
					"outside":
						var east := [id, target] in road_edges
						position = Vector2(2388 if east else 52, 272)
						inward = Vector2.LEFT if east else Vector2.RIGHT
						form = "road"
					"house", "hospital", "shelter":
						var facade: Rect2 = node.facades[destination]
						position = Vector2(facade.get_center().x, facade.end.y + 14)
					"louvre":
						position = Vector2(2010, 561)
						inward = Vector2.LEFT
						form = "gate"
			elif node.kind == "house" or node.kind == "hospital":
				position = Vector2(180, 566)
				if destination == "hospital":
					var upward := hospital_floor(target) > hospital_floor(id)
					position = Vector2(1035, 415) if upward else Vector2(176, 440)
					inward = Vector2.DOWN
					form = "stairs_up" if upward else "stairs_down"
			node.exits[target] = {
				"position": position, "arrival": position + inward * 25, "inward": inward, "form": form,
				"area": Rect2(position - Vector2(27, 23), Vector2(54, 46)),
			}
		if node.kind == "outside":
			var main_road: Rect2 = node.roadways[0]
			var has_west: bool = node.exits.values().any(func(exit): return exit.form == "road" and exit.inward == Vector2.RIGHT)
			var has_east: bool = node.exits.values().any(func(exit): return exit.form == "road" and exit.inward == Vector2.LEFT)
			var start := main_road.position.x if has_west else main_road.position.x + 90
			var finish := main_road.end.x if has_east else main_road.end.x - 150
			node.roadways[0] = Rect2(start, main_road.position.y, finish - start, main_road.size.y)

static func hospital_floor(id: String) -> int:
	return 1 if id == "hospital" else int(id.get_slice("_", 2))

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
		if version >= 3:
			_expand_street(nodes[exterior], streets[district])
		var interiors := ROOM_BLOCKS if version == 1 else HOUSE_BLOCKS
		nodes[residence] = _record("house", "Жилой дом · район %d" % (district + 1), "house:%d" % houses[district], interiors[houses[district]])
		if version >= 3:
			_expand_interior(nodes[residence], houses[district])
		_connect(nodes, exterior, residence)
		for floor_index in range(FLOORS):
			var id := hospital(district, floor_index)
			var variant: int = floors[floor_index][district]
			var obstacles: Array = ROOM_BLOCKS[variant].duplicate()
			# Each functional floor has a distinct obstacle in the west room.
			obstacles.append(Rect2(101 + 18 * floor_index, 112 + 11 * floor_index, 20, 26))
			nodes[id] = _record("hospital", "Больница %d · этаж %d" % [district + 1, floor_index + 1], "hospital:%d:%d" % [floor_index, variant], obstacles)
			if version >= 3:
				_expand_interior(nodes[id], variant)
			_connect(nodes, exterior if floor_index == 0 else hospital(district, floor_index - 1), id)
	for edge in roads(world_seed, version):
		_connect(nodes, street(edge[0]), street(edge[1]))
	_connect(nodes, "outside", "louvre")
	_connect(nodes, "outside", "shelter")
	if version >= 3:
		_expand_service(nodes.shelter)
		_expand_service(nodes.louvre)
		_make_exits(nodes, world_seed, version)
	return nodes

static func route(nodes: Dictionary, origin: String, destination: String) -> Array[String]:
	var visited := {origin: ""}
	var frontier: Array[String] = [origin]
	while not frontier.is_empty() and not visited.has(destination):
		var id: String = frontier.pop_front()
		for neighbor in nodes[id].links:
			if not visited.has(neighbor):
				visited[neighbor] = id
				frontier.append(neighbor)
	var result: Array[String] = []
	var cursor := destination
	while visited.has(cursor) and not cursor.is_empty():
		result.push_front(cursor)
		cursor = visited[cursor]
	return result

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
