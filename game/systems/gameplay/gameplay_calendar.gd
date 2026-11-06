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
	return due

static func apply(state: Dictionary, entry: Dictionary) -> Dictionary:
	for plot in state.crops.plots:
		if plot.id == entry.entity_id:
			plot.status = entry.phase
			state.resource_revisions.farm += 1
			return {"ok": true, "events": [{"event_type": "crop_changed", "payload": {"plot_id": plot.id, "status": plot.status}}]}
	return {"ok": false}
