extends RefCounted

static func deadlines(state: Dictionary, from: int, target: int) -> Array:
	var due: Array = []
	for plot in state.crops.plots:
		if plot.status not in ["growing", "ripe"]:
			continue
		if plot.status == "growing" and plot.ripe_at > from and plot.ripe_at <= target:
			due.append({"minute": plot.ripe_at, "priority": 0, "entity_id": plot.id, "phase": "ripe"})
		if plot.spoil_at > from and plot.spoil_at <= target:
			due.append({"minute": plot.spoil_at, "priority": 1, "entity_id": plot.id, "phase": "spoiled"})
	for resident in state.residents.records:
		var shift: Dictionary = resident.get("shift", {})
		if not shift.is_empty() and not shift.ready and shift.due > from and shift.due <= target:
			due.append({"minute": shift.due, "priority": 2, "entity_id": resident.id, "phase": "shift_ready"})
	return due

static func apply(state: Dictionary, entry: Dictionary) -> Dictionary:
	if entry.phase == "shift_ready":
		for resident in state.residents.records:
			if resident.id == entry.entity_id and resident.has("shift"):
				resident.shift.ready = true
				state.resource_revisions.residents += 1
				return {"ok": true, "events": [{"event_type": "gameplay_changed", "payload": {"command_type": "game.shift_ready"}}]}
		return {"ok": false}
	for plot in state.crops.plots:
		if plot.id == entry.entity_id:
			plot.status = entry.phase
			state.resource_revisions.farm += 1
			return {"ok": true, "events": [{"event_type": "crop_changed", "payload": {"plot_id": plot.id, "status": plot.status}}]}
	return {"ok": false}
