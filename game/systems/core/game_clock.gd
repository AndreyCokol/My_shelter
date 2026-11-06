extends RefCounted

var minute: int = 0
var remainder: float = 0.0
var minutes_per_real_second: float = 1.0

func tick(delta: float, paused: bool) -> int:
	if paused or not is_finite(delta) or delta < 0.0:
		return 0
	remainder += delta * minutes_per_real_second
	var whole := int(floor(remainder + 0.000000001))
	remainder = maxf(0.0, remainder - whole)
	minute += whole
	return whole

# Core scheduler consumes domain-owned deadlines, without implementing farming.
static func ordered_deadlines(entries: Array, from_minute: int, target_minute: int) -> Array:
	var due: Array = []
	for entry in entries:
		if entry.minute > from_minute and entry.minute <= target_minute:
			due.append(entry.duplicate(true))
	due.sort_custom(func(a, b):
		if a.minute != b.minute:
			return a.minute < b.minute
		if a.priority != b.priority:
			return a.priority < b.priority
		return a.entity_id < b.entity_id)
	return due
