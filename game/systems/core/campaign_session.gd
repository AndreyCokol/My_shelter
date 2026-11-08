extends RefCounted

const Core = preload("res://game/systems/core/core_session.gd")
const Model = preload("res://game/state/campaign_model.gd")
const Calendar = preload("res://game/systems/core/calendar_planner.gd")
const Commands = preload("res://game/systems/inventory/campaign_commands.gd")
var coordinator
var _rules: Dictionary
var _commands
var calendar = Calendar.new()

func _init(rules: Dictionary) -> void:
	if not valid_rules(rules):
		return
	_rules = rules.duplicate(true)
	_commands = Commands.new(_rules)
	_commands.calendar = calendar
	var state := Model.new_state(_rules)
	for container in state.inventory.containers:
		state.resource_revisions["inventory:" + container.id] = 0
	for offer_id in _rules.offers:
		state.resource_revisions["offer:" + offer_id] = 0
	coordinator = Core.new(state, Model.validate.bind(_rules), _commands.normalize, _commands.plan)
	coordinator._domain_owner = _commands
	if _rules.get("gameplay", false):
		var adapter = preload("res://game/systems/gameplay/gameplay_calendar.gd")
		configure_calendar(adapter.deadlines, adapter.apply)

func get_rules() -> Dictionary:
	return _rules.duplicate(true)

# Adapters are installed during campaign setup, never through player payloads.
func configure_calendar(source: Callable, consumer: Callable) -> bool:
	if coordinator == null or coordinator.is_busy():
		return false
	return calendar.configure(source, consumer)

func tick(delta: float) -> bool:
	if coordinator == null or not is_finite(delta) or delta < 0:
		return false
	# Safe fast path: never clone/validate the entire campaign for a fractional
	# frame. If a whole minute is due, fall back to the full calendar planner.
	if coordinator.try_accumulate_fractional_clock(delta, _rules.minutes_per_real_second):
		return true
	var drafts: Array = []
	return coordinator.apply_runtime(func(state):
		var accumulated: float = state.clock_remainder + delta * _rules.minutes_per_real_second
		# Check before float-to-int conversion, including overflow of finite inputs.
		if not is_finite(accumulated) or accumulated > Calendar.MAX_MINUTE - state.game_time_minutes:
			return false
		var minutes := int(floor(accumulated + 0.000000001))
		var result: Dictionary = calendar.advance(state, int(state.game_time_minutes) + minutes, "tick")
		if not result.ok:
			return false
		state.clock_remainder = 0.0 if result.data.interrupted else maxf(0.0, accumulated - minutes)
		drafts.assign(result.events)
		return true, func(_before, _after): return drafts)

static func valid_rules(rules: Dictionary) -> bool:
	if rules.get("gameplay", false) and not preload("res://game/data/game_rules.gd").validate(rules):
		return false
	if not rules.get("version") is String or rules.version.is_empty() or not Core.valid_integer(rules.get("discovery_xp")):
		return false
	var rate = rules.get("minutes_per_real_second")
	if not (rate is float or rate is int) or not is_finite(rate) or rate <= 0:
		return false
	for key in ["items", "offers", "parcels", "rewards", "scenes"]:
		if not rules.get(key) is Dictionary:
			return false
	for scene_id in rules.scenes:
		if not scene_id is String or not Model.unique_strings(rules.scenes[scene_id]) or rules.scenes[scene_id].is_empty():
			return false
	for required in ["shelter", "outside"]:
		if not rules.scenes.has(required) or not "default" in rules.scenes[required]:
			return false
	if not rules.get("containers") is Array:
		return false
	var container_ids: Dictionary = {}
	for container in rules.containers:
		if not container is Dictionary or not container.get("id") is String or container.id.is_empty() or container_ids.has(container.id) or not Core.valid_integer(container.get("capacity_units")):
			return false
		container_ids[container.id] = true
	if not container_ids.has("player") or not container_ids.has("storage"):
		return false
	for type_id in rules.items:
		if not type_id is String or type_id.is_empty():
			return false
	for key in ["offers", "parcels", "rewards"]:
		for id in rules[key]:
			var definition = rules[key][id]
			if not id is String or id.is_empty() or not definition is Dictionary or not rules.items.has(definition.get("type_id")) or not Core.valid_integer(definition.get("quantity")) or definition.quantity <= 0:
				return false
			for amount_key in ["coins", "hero_xp"]:
				if not Core.valid_integer(definition.get(amount_key, 0)):
					return false
			if key == "offers" and not Core.valid_integer(definition.get("price")):
				return false
			if key != "offers" and not definition.get("eligible", false) is bool:
				return false
	return true
