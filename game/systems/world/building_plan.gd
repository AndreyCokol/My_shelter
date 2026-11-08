extends RefCounted

const INNER := Rect2(30, 95, 1180, 500)
const WALL := 10.0
const DOOR := 54.0
const APARTMENTS := [
	["studio", "bath"],
	["living", "bedroom", "bath"],
	["living", "bedroom", "bedroom", "bath"],
]
const HOSPITAL := [
	["reception", "triage", "storage", "ward", "office", "bath"],
	["ward", "ward", "bath", "office", "ward", "storage"],
	["surgery", "prep", "storage", "recovery", "surgery", "bath"],
	["lab", "office", "storage", "lab", "prep", "bath"],
]
const LABELS := {
	"corridor": "Коридор", "lobby": "Вестибюль", "foyer": "Прихожая",
	"studio": "Студия", "living": "Кухня-гостиная", "bedroom": "Спальня", "bath": "Санузел",
	"storage": "Кладовая", "ward": "Палата", "office": "Кабинет", "reception": "Приёмная",
	"triage": "Осмотровая", "surgery": "Операционная", "prep": "Подготовительная",
	"recovery": "Палата восстановления", "lab": "Лаборатория",
}
static var _catalog := {}

# The optional v5 architectural slot adds real physical partitions and must
# never affect historical v4 plans or saved procedural manifests.
static func get_plan(kind: String, floor: int, pattern: int, architectural_slot: int = -1) -> Dictionary:
	var key := "%s:%d:%d:%d" % [kind, floor, pattern, architectural_slot]
	if not _catalog.has(key):
		var plan: Dictionary = checked(_generate(kind, floor, pattern), kind, floor, pattern)
		if kind == "hospital" and architectural_slot >= 0:
			plan = _with_hospital_alcove(plan, architectural_slot)
		_catalog[key] = plan
	return _catalog[key]

# V5: 2 different upper rooms x 2 alcove depths x 4 partition lengths.
# These are L-shaped physical wall segments visible in the floor artwork and
# traversable around by the actor. All variants are in the northern part of
# an upper room, far from its south corridor door and its north-west furniture.
# Historical v4 saves never request an architectural_slot.
static func _with_hospital_alcove(source: Dictionary, architectural_slot: int) -> Dictionary:
	var plan: Dictionary = source.duplicate(true)
	if architectural_slot < 0 or architectural_slot >= 16:
		push_error("Invalid hospital architectural slot")
		return plan
	var room_id := "room_%02d" % (1 + architectural_slot % 2)
	var room: Dictionary = plan.rooms.get(room_id, {})
	if room.is_empty():
		push_error("Hospital floor is missing an upper room")
		return plan
	var length := 64.0 + float(architectural_slot / 4) * 22.0
	var height_offset := 16.0 + float((architectural_slot / 2) % 2) * 12.0
	var alcove := Rect2(
		Vector2(room.rect.end.x - length - 20, room.rect.position.y + height_offset),
		Vector2(length, 10))
	var return_wall := Rect2(
		Vector2(room.rect.end.x - 29, alcove.end.y),
		Vector2(9, 16))
	var inset: Rect2 = room.rect.grow(-14)
	if not inset.encloses(alcove) or not inset.encloses(return_wall):
		push_error("Hospital alcove does not fit room geometry")
		return plan
	# The existing floor generator puts furnishings on the north-west side
	# of upper rooms. Keep these architectural walls clear of every fixture.
	for fixture in plan.furniture:
		if fixture.room == room_id and (fixture.rect.grow(8).intersects(alcove)
				or fixture.rect.grow(8).intersects(return_wall)):
			push_error("Hospital alcove would intersect room furniture")
			return plan
	plan.walls.append(alcove)
	plan.walls.append(return_wall)
	assert(valid(plan), "The specialized hospital plan must pass wall, room and door validation")
	return plan

static func _generate(kind: String, floor: int, pattern: int) -> Dictionary:
	var plan := structure(kind, floor, pattern)
	populate(plan, pattern)
	compile(plan)
	return plan

static func checked(plan: Dictionary, kind: String, floor: int, pattern: int) -> Dictionary:
	if valid(plan):
		return plan
	# Preserve the corridor alignment so that the floor across a staircase still matches.
	var fallback := _generate(kind, floor, posmod(pattern, 3))
	assert(valid(fallback), "The fallback floor plan must pass validation")
	return fallback

static func valid(plan: Dictionary) -> bool:
	if not plan.rooms.has("corridor") or (plan.floor == 1) != plan.has("entrance"):
		return false
	var obstacles: Array = plan.walls.duplicate()
	for fixture in plan.furniture:
		if not plan.rooms.has(fixture.room) or not plan.rooms[fixture.room].rect.grow(-5).encloses(fixture.rect):
			return false
		obstacles.append(fixture.rect)
	var anchors := [plan.spawn, plan.loot, plan.enemy, plan.stairs_up, plan.stairs_down]
	var rooms: Array = plan.rooms.values()
	var links := {}
	for index in range(rooms.size()):
		var room: Dictionary = rooms[index]
		var rect: Rect2 = room.rect
		if not INNER.encloses(rect) or rect.size.x < DOOR or rect.size.y < DOOR:
			return false
		for other in range(index):
			if rect.intersects(rooms[other].rect):
				return false
		if room.unit != "" and (not plan.units.has(room.unit) or room.id not in plan.units[room.unit].rooms):
			return false
		links[room.id] = []
		anchors.append(rect.get_center())
	for unit in plan.units.values():
		if not _valid_unit(plan, unit):
			return false
	var door_ids := {}
	var exterior_count := 0
	for door in plan.doors:
		if door_ids.has(door.id) or door.width != DOOR or not plan.rooms.has(door.from):
			return false
		door_ids[door.id] = true
		var source: Dictionary = plan.rooms[door.from]
		var target: Dictionary
		if door.to == "street":
			if source.kind != "lobby" or door.position != plan.get("entrance") or door.position.y != INNER.end.y:
				return false
			target = {"rect": Rect2(INNER.end.x - INNER.size.x, INNER.end.y, INNER.size.x, 32)}
			exterior_count += 1
		else:
			if not plan.rooms.has(door.to):
				return false
			target = plan.rooms[door.to]
			if source.unit != target.unit and (source.kind != "corridor" or target.kind != "foyer"):
				return false
			links[door.from].append(door.to)
			links[door.to].append(door.from)
		var normal := Vector2.DOWN if door.horizontal else Vector2.RIGHT
		var tangent := Vector2.RIGHT if door.horizontal else Vector2.DOWN
		var direction := signf((target.rect.get_center() - source.rect.get_center()).dot(normal))
		var edge: Vector2 = door.position - normal * direction
		var other_edge: Vector2 = door.position + normal * direction
		for side in [-1, 1]:
			var shift: Vector2 = tangent * side * (DOOR / 2 + WALL / 2)
			if not source.rect.has_point(edge + shift) or not target.rect.has_point(other_edge + shift):
				return false
		anchors.append_array([door.position, door.position - normal * 13, door.position + normal * 13])
	if exterior_count != int(plan.floor == 1):
		return false
	for obstacle in obstacles:
		for point in anchors:
			if obstacle.grow(9).has_point(point):
				return false
	var visited := {"corridor": true}
	var pending := ["corridor"]
	while not pending.is_empty():
		for neighbor in links[pending.pop_back()]:
			if not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return visited.size() == rooms.size()

static func _valid_unit(plan: Dictionary, unit: Dictionary) -> bool:
	var expected := ["foyer"] + apartment_rooms(unit.template)
	if unit.rooms.size() != expected.size() or unit.entry != unit.rooms[0]:
		return false
	for index in range(unit.rooms.size()):
		var room: Dictionary = plan.rooms.get(unit.rooms[index], {})
		if room.is_empty() or room.unit != unit.id or room.kind != expected[index] or not unit.rect.encloses(room.rect):
			return false
	return true

static func structure(kind: String, floor: int, pattern: int) -> Dictionary:
	var split := 205.0 if kind == "hospital" else 276.0 + (pattern % 3) * 12.0
	var hall := Rect2(INNER.position.x, split, INNER.size.x, 94)
	var plan := {"kind": kind, "floor": floor, "pattern": pattern, "rooms": {}, "doors": [], "units": {},
		"spawn": Vector2(120, 260) if kind == "hospital" else Vector2(120, hall.get_center().y),
		"stairs_up": Vector2(970 if floor % 2 == 1 else 1115, hall.get_center().y),
		"stairs_down": Vector2(1115 if floor % 2 == 1 else 970, hall.get_center().y)}
	add_room(plan, "corridor", "corridor", hall)
	var bottom := hall.end.y
	if floor == 1:
		add_room(plan, "lobby", "lobby", Rect2(140, bottom, 106, INNER.end.y - bottom))
		connect_rooms(plan, "corridor", "lobby")
		plan.entrance = Vector2(193, INNER.end.y)
		plan.doors.append({"id": "lobby_street", "from": "lobby", "to": "street",
			"position": plan.entrance, "horizontal": true, "width": DOOR})
	return plan

static func add_room(plan: Dictionary, id: String, kind: String, rect: Rect2, unit: String = "") -> void:
	plan.rooms[id] = {"id": id, "kind": kind, "rect": rect, "unit": unit}

static func connect_rooms(plan: Dictionary, source: String, target: String) -> void:
	var a: Rect2 = plan.rooms[source].rect
	var b: Rect2 = plan.rooms[target].rect
	var position := Vector2.ZERO
	var horizontal := a.end.y == b.position.y or b.end.y == a.position.y
	if horizontal:
		position = Vector2(roundf((maxf(a.position.x, b.position.x) + minf(a.end.x, b.end.x)) * 0.5),
			b.position.y if a.end.y == b.position.y else a.position.y)
	else:
		position = Vector2(b.position.x if a.end.x == b.position.x else a.position.x,
			roundf((maxf(a.position.y, b.position.y) + minf(a.end.y, b.end.y)) * 0.5))
	plan.doors.append({"id": source + "_" + target, "from": source, "to": target, "position": position,
		"horizontal": horizontal, "width": DOOR})

static func apartment_rooms(template: int) -> Array:
	return APARTMENTS[template]

static func hospital_rooms(floor: int) -> Array:
	return HOSPITAL[floor - 1]

# Keep an entire common corridor available before parceling either side into units.
static func populate(plan: Dictionary, pattern: int) -> void:
	var corridor: Rect2 = plan.rooms.corridor.rect
	var upper_count := 2 + (pattern % 2) if plan.kind == "house" else 3 + (pattern % 2)
	var lower_count := 2 + (floori(pattern / 2.0) % 2) if plan.kind == "house" else 6 - upper_count
	var upper := Rect2(INNER.position, Vector2(INNER.size.x, corridor.position.y - INNER.position.y))
	var lower := Rect2(Vector2(INNER.position.x, corridor.end.y), Vector2(INNER.size.x, INNER.end.y - corridor.end.y))
	if plan.floor == 1:
		add_room(plan, "utility", "storage", Rect2(lower.position, Vector2(110, lower.size.y)))
		connect_rooms(plan, "corridor", "utility")
		lower.position.x += 216
		lower.size.x -= 216
	var parts := _divide(upper, upper_count, pattern + plan.floor)
	parts.append_array(_divide(lower, lower_count, pattern + plan.floor + 3))
	for index in range(parts.size()):
		var rect: Rect2 = parts[index]
		if plan.kind == "house":
			_add_apartment(plan, rect, index + 1, (pattern + index + plan.floor - 1) % APARTMENTS.size())
		else:
			var id := "room_%02d" % (index + 1)
			var types := hospital_rooms(plan.floor)
			add_room(plan, id, types[(index + pattern) % types.size()], rect)
			connect_rooms(plan, "corridor", id)
	if plan.kind == "house":
		var unit: Dictionary = plan.units.values()[0]
		plan.loot = plan.rooms[unit.rooms[1]].rect.get_center().round()
	else:
		var room: Dictionary = plan.rooms.room_03
		plan.loot = Vector2(300, 267) if plan.floor == 1 else room.rect.get_center().round()
	plan.enemy = Vector2(330, 260) if plan.floor == 1 else Vector2(875, corridor.get_center().y)

static func _divide(rect: Rect2, count: int, pattern: int) -> Array:
	var result := []
	var left := rect.position.x
	for index in range(1, count + 1):
		var amplitude := clampf((rect.size.x / count - 72.0) / 4.0, 0.0, 8.0)
		var shift := float((pattern + index * 7) % 5 - 2) * amplitude if index < count else 0.0
		var right := roundf(rect.position.x + rect.size.x * index / count + shift)
		result.append(Rect2(left, rect.position.y, right - left, rect.size.y))
		left = right
	return result

static func _add_apartment(plan: Dictionary, rect: Rect2, number: int, template: int) -> void:
	var id := "apt_%02d" % number
	var foyer := id + "_foyer"
	var upper: bool = rect.end.y == plan.rooms.corridor.rect.position.y
	var foyer_y := rect.end.y - 58 if upper else rect.position.y
	add_room(plan, foyer, "foyer", Rect2(rect.position.x, foyer_y, rect.size.x, 58), id)
	connect_rooms(plan, "corridor", foyer)
	var kinds := apartment_rooms(template)
	var private_y := rect.position.y if upper else foyer_y + 58
	var sections := _divide(Rect2(rect.position.x, private_y, rect.size.x, rect.size.y - 58), kinds.size(), number)
	var room_ids: Array[String] = [foyer]
	for index in range(kinds.size()):
		var room_id := "%s_%02d" % [id, index + 1]
		add_room(plan, room_id, kinds[index], sections[index], id)
		connect_rooms(plan, foyer, room_id)
		room_ids.append(room_id)
	plan.units[id] = {"id": id, "number": (plan.floor - 1) * 10 + number, "rect": rect,
		"template": template, "rooms": room_ids, "entry": foyer}

static func compile(plan: Dictionary) -> void:
	var lines := {}
	for room in plan.rooms.values():
		var rect: Rect2 = room.rect
		_add_span(lines, true, rect.position.y, rect.position.x, rect.end.x)
		_add_span(lines, true, rect.end.y, rect.position.x, rect.end.x)
		_add_span(lines, false, rect.position.x, rect.position.y, rect.end.y)
		_add_span(lines, false, rect.end.x, rect.position.y, rect.end.y)
	for door in plan.doors:
		var coordinate: float = door.position.y if door.horizontal else door.position.x
		var center: float = door.position.x if door.horizontal else door.position.y
		var line: Dictionary = lines[_line_key(door.horizontal, coordinate)]
		line.openings.append(Vector2(center - door.width / 2, center + door.width / 2))
	plan.walls = []
	for line in lines.values():
		plan.walls.append_array(_compile_line(line))
	plan.furniture = []
	for room in plan.rooms.values():
		if room.kind in ["corridor", "lobby", "foyer"]:
			continue
		var door: Dictionary = plan.doors.filter(func(connection): return connection.to == room.id)[0]
		var rect: Rect2 = room.rect
		var size := Vector2(31, 31) if room.kind in ["bedroom", "ward", "recovery"] else Vector2(32, 20)
		var y := rect.end.y - size.y - 17 if door.position.y == rect.position.y else rect.position.y + 17
		plan.furniture.append({"room": room.id, "kind": room.kind, "rect": Rect2(Vector2(rect.position.x + 16, y), size)})

static func _line_key(horizontal: bool, coordinate: float) -> Vector2:
	return Vector2(coordinate, 1 if horizontal else 0)

static func _add_span(lines: Dictionary, horizontal: bool, coordinate: float, left: float, right: float) -> void:
	var key := _line_key(horizontal, coordinate)
	if not lines.has(key):
		lines[key] = {"horizontal": horizontal, "coordinate": coordinate, "spans": [], "openings": []}
	lines[key].spans.append(Vector2(left, right))

# Merge shared edges once, then subtract the openings before making collision rectangles.
static func _compile_line(line: Dictionary) -> Array:
	var boundaries := {}
	for span in line.spans + line.openings:
		boundaries[span.x] = true
		boundaries[span.y] = true
	var ordered := boundaries.keys()
	ordered.sort()
	var spans: Array[Vector2] = []
	for index in range(ordered.size() - 1):
		var left: float = ordered[index]
		var right: float = ordered[index + 1]
		var middle := (left + right) * 0.5
		var wall: bool = line.spans.any(func(span): return middle > span.x and middle < span.y)
		var opening: bool = line.openings.any(func(span): return middle > span.x and middle < span.y)
		if wall and not opening:
			if not spans.is_empty() and spans.back().y == left:
				spans[-1].y = right
			else:
				spans.append(Vector2(left, right))
	var walls := []
	for span in spans:
		if line.horizontal:
			walls.append(Rect2(span.x, line.coordinate - WALL / 2, span.y - span.x, WALL))
		else:
			walls.append(Rect2(line.coordinate - WALL / 2, span.x, WALL, span.y - span.x))
	return walls
