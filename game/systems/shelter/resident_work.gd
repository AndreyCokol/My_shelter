extends RefCounted

const DURATION := 120
const RESTED_DURATION := 90
const Construction = preload("res://game/systems/shelter/construction.gd")
const JOBS := {
	"sort": {"label": "Разобрать утиль", "output": "material.salvage", "quantity": 3},
	"seed": {"label": "Подготовить семена", "output": "seed.basic", "quantity": 2},
}

static func duration(state: Dictionary, resident_id: String) -> int:
	var beds := Construction.count(state.shelter.get("buildings", {}), "bed")
	for resident in state.residents.records:
		if resident.status == "joined":
			if resident.id == resident_id:
				return RESTED_DURATION if beds > 0 else DURATION
			beds -= 1
	return DURATION

static func valid_shift(shift, current_minute: int) -> bool:
	if not shift is Dictionary or shift.size() != 3 or not JOBS.has(shift.get("job")) or not shift.get("ready") is bool:
		return false
	var due = shift.get("due")
	if not (due is int or due is float) or not is_finite(due) or due <= 0 or due > 9007199254740991 or due != floor(due):
		return false
	return shift.ready == (due <= current_minute)
