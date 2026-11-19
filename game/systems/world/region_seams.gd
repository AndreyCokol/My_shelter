extends RefCounted
## A2 isolated region-addressing / edge-seam contract prototype.
##
## Does not install chunks, move the player, allocate endless scenes, or change
## Core saves. A1/A5 must approve a new generator and chunk lifecycle contract
## before this can be integrated with the existing four-district world.

const VERSION := 1
const MAX_WORLD_SEED := 2147483647
const REGION_SIZE := Vector2(2400, 780)
const GATE_HALF_WIDTH := 32.0
const GATE_DEPTH := 80.0
const VERTICAL_GATE_Y := [195.0, 390.0, 585.0]
const HORIZONTAL_GATE_X := [600.0, 1200.0, 1800.0]

static func region_id(x: int, y: int) -> String:
	return "region:%d:%d" % [x, y]

static func parse_region_id(value: String) -> Dictionary:
	var parts := value.split(":")
	if parts.size() != 3 or parts[0] != "region" or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {"ok": false, "code": "INVALID_REGION_ID"}
	var x := int(parts[1])
	var y := int(parts[2])
	if value != region_id(x, y):
		return {"ok": false, "code": "INVALID_REGION_ID"}
	return {"ok": true, "x": x, "y": y}

# The hash includes a stream name; adding/changing loot never shifts streets.
# For a shared border, both neighbors call the same edge key:
# vertical(x+1,y) on the east of (x,y) / west of (x+1,y), and
# horizontal(x,y+1) on the south of (x,y) / north of (x,y+1).
static func _hash(seed: int, stream: String, x: int, y: int) -> int:
	var digest := ("%d:%d:%s:%d:%d" % [seed, VERSION, stream, x, y]).sha256_text()
	return digest.substr(0, 8).hex_to_int()

static func _v_gate(seed: int, boundary_x: int, row_y: int) -> float:
	return VERTICAL_GATE_Y[_hash(seed, "vertical-edge", boundary_x, row_y) % VERTICAL_GATE_Y.size()]

static func _h_gate(seed: int, col_x: int, boundary_y: int) -> float:
	return HORIZONTAL_GATE_X[_hash(seed, "horizontal-edge", col_x, boundary_y) % HORIZONTAL_GATE_X.size()]

static func manifest(seed: int, x: int, y: int) -> Dictionary:
	if seed < 0 or seed > MAX_WORLD_SEED:
		return {}
	var gates := {
		"west": Vector2(0, _v_gate(seed, x, y)),
		"east": Vector2(REGION_SIZE.x, _v_gate(seed, x + 1, y)),
		"north": Vector2(_h_gate(seed, x, y), 0),
		"south": Vector2(_h_gate(seed, x, y + 1), REGION_SIZE.y),
	}
	return {
		"id": region_id(x, y), "x": x, "y": y, "version": VERSION, "seed": seed,
		"gates": gates,
		"neighbors": {
			"west": region_id(x - 1, y), "east": region_id(x + 1, y),
			"north": region_id(x, y - 1), "south": region_id(x, y + 1),
		},
		"streams": {
			"geometry": _hash(seed, "geometry", x, y),
			"loot": _hash(seed, "loot", x, y),
			"enemies": _hash(seed, "enemies", x, y),
			"events": _hash(seed, "events", x, y),
		},
	}

static func gate_apron(side: String, gate: Vector2) -> Rect2:
	match side:
		"west":
			return Rect2(0, gate.y - GATE_HALF_WIDTH, GATE_DEPTH, 2.0 * GATE_HALF_WIDTH)
		"east":
			return Rect2(REGION_SIZE.x - GATE_DEPTH, gate.y - GATE_HALF_WIDTH, GATE_DEPTH, 2.0 * GATE_HALF_WIDTH)
		"north":
			return Rect2(gate.x - GATE_HALF_WIDTH, 0, 2.0 * GATE_HALF_WIDTH, GATE_DEPTH)
		"south":
			return Rect2(gate.x - GATE_HALF_WIDTH, REGION_SIZE.y - GATE_DEPTH, 2.0 * GATE_HALF_WIDTH, GATE_DEPTH)
	return Rect2()

static func seams_match(a: Dictionary, b: Dictionary, direction: String) -> bool:
	if a.is_empty() or b.is_empty() or a.seed != b.seed or a.version != b.version:
		return false
	match direction:
		"east":
			return a.neighbors.east == b.id and a.gates.east == b.gates.west + Vector2(REGION_SIZE.x, 0)
		"west":
			return a.neighbors.west == b.id and a.gates.west == b.gates.east - Vector2(REGION_SIZE.x, 0)
		"north":
			return a.neighbors.north == b.id and a.gates.north == b.gates.south - Vector2(0, REGION_SIZE.y)
		"south":
			return a.neighbors.south == b.id and a.gates.south == b.gates.north + Vector2(0, REGION_SIZE.y)
	return false
