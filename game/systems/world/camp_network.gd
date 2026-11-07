extends RefCounted

const DAY := 1440
const OPEN := 360
const CLOSE := 1080
const FACTIONS := {
	"scouts": {"name": "Дозорные", "request": "material.salvage", "quantity": 3, "reward": 6,
		"goods": "seed.basic", "goods_quantity": 3, "price": 4},
	"settlers": {"name": "Поселенцы", "request": "crop.potato", "quantity": 2, "reward": 5,
		"goods": "material.salvage", "goods_quantity": 3, "price": 5},
}

static func day_at(minute: int) -> int:
	@warning_ignore("integer_division")
	return minute / DAY

static func empty_state() -> Dictionary:
	return {"last_contract_day": -1, "reputation": {}, "last_trade": {}}

static func schedule(minute: int, seed_value: int) -> Dictionary:
	var day := day_at(minute)
	var time := minute % DAY
	var faction := "scouts" if (day + seed_value) % 2 == 0 else "settlers"
	return {"day": day, "faction": faction, "active": time >= OPEN and time < CLOSE}

static func valid_record(record, minute: int) -> bool:
	if not record is Dictionary or record.size() != 3 or not record.get("reputation") is Dictionary or not record.get("last_trade") is Dictionary:
		return false
	var last = record.get("last_contract_day")
	var day := day_at(minute)
	if not _whole(last, -1, day):
		return false
	var completed := 0
	for id in record.reputation:
		if not FACTIONS.has(id) or not _whole(record.reputation[id], 1, day + 1):
			return false
		completed += int(record.reputation[id])
	if (last < 0 and completed != 0) or completed > last + 1:
		return false
	for id in record.last_trade:
		if not record.reputation.has(id) or not _whole(record.last_trade[id], 0, day):
			return false
	return true

static func _whole(value, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= lower and value <= upper and value == floor(value)
