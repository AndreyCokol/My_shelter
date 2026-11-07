extends RefCounted

const COLUMNS := 5
const ROWS := 2
const ORIGIN := Vector2(200, 264)
const SPACING := 44
const FOOTPRINT := Vector2(24, 22)
const SALVAGE_POINT := Vector2(300, 308)
const SALVAGE_INTERVAL := 120
const SALVAGE_AMOUNT := 3
const CABINET_CAPACITY := 12
const STRUCTURES := {
	"bench": {"label": "Верстак", "item": "material.salvage", "cost": 3},
	"lamp": {"label": "Фонарь", "item": "material.lamp_kit", "cost": 1},
	"cabinet": {"label": "Шкаф", "item": "material.salvage", "cost": 4},
	"bed": {"label": "Кровать", "item": "material.salvage", "cost": 4},
}
const RECIPES := {
	"lamp_kit": {"label": "Комплект фонаря", "input": "material.salvage", "cost": 2, "output": "material.lamp_kit"},
}

static func valid_cell(cell: String) -> bool:
	return cell.is_valid_int() and str(int(cell)) == cell and int(cell) >= 0 and int(cell) < COLUMNS * ROWS

static func cell_rect(cell: String) -> Rect2:
	var index := int(cell)
	var center := ORIGIN + Vector2((index % COLUMNS) * SPACING, floori(float(index) / COLUMNS) * SPACING)
	return Rect2(center - FOOTPRINT / 2, FOOTPRINT)

static func count(buildings: Dictionary, type: String) -> int:
	return buildings.values().count(type)

static func storage_containers(base: Array, buildings: Dictionary) -> Array:
	var containers := base.duplicate(true)
	var additional := count(buildings, "cabinet") * CABINET_CAPACITY
	for container in containers:
		if container.id == "storage":
			container.capacity_units += additional
	return containers

static func validate(buildings, salvage, scenes: Dictionary) -> bool:
	if not buildings is Dictionary or not salvage is Dictionary:
		return false
	for cell in buildings:
		if not cell is String or not valid_cell(cell) or not buildings[cell] is String or not STRUCTURES.has(buildings[cell]):
			return false
	for id in salvage:
		if not id is String or not scenes.has(id) or not (id == "outside" or id.begins_with("street_")):
			return false
		var minute = salvage[id]
		if not (minute is int or minute is float) or not is_finite(minute) or minute <= 0 or minute > 9007199254740991 or minute != floor(minute):
			return false
	return true
