extends Node2D
## A2-01 water contact volumes for real CharacterBody2D actors.
##
## Water rectangles are supplied explicitly by an authored world layout.
## Historical WorldLayout v4/v5 are NOT changed or retroactively flooded.
## Every area is non-solid; blockers remain owned by the physical world.
## Consumers (A1 staged safe-return) may obtain hazard_rectangles().
##
## Contact tracking is by ACTOR + AREA index. A plain boolean body_exited
## handler would incorrectly end swimming when two water areas overlap.
const MAX_ZONES := 32

var _zones: Array[Rect2] = []
var _occupants: Dictionary = {}

func configure(rectangles: Array, bounds: Rect2) -> bool:
	if is_inside_tree() or get_child_count() != 0 or not _zones.is_empty():
		return false
	if rectangles.size() > MAX_ZONES or not bounds.is_finite() or not bounds.has_area():
		return false
	var accepted: Array[Rect2] = []
	for item in rectangles:
		if not item is Rect2 or not item.is_finite() or not item.has_area():
			return false
		if not bounds.encloses(item):
			return false
		accepted.append(item)
	_zones = accepted
	for index in range(_zones.size()):
		var rect: Rect2 = _zones[index]
		var zone := Area2D.new()
		zone.name = "Water_%02d" % index
		zone.position = rect.get_center()
		zone.collision_layer = 0 # Water never acts as a solid wall.
		zone.collision_mask = 1 # Hero physics layer; not a UI hitbox.
		zone.monitoring = true
		zone.monitorable = false
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collider.shape = shape
		zone.add_child(collider)
		zone.body_entered.connect(_body_entered.bind(index))
		zone.body_exited.connect(_body_exited.bind(index))
		add_child(zone)
	queue_redraw()
	return true

func hazard_rectangles() -> Array[Rect2]:
	# Non-solid physics areas are deliberately NOT in collision_rects().
	# Returning independent values lets SceneRouter pass them to A2-07 as
	# hazards and refuse an underwater shelter return.
	return _zones.duplicate()

func active_water_zone_count() -> int:
	return _zones.size()

func _body_entered(body: Node2D, index: int) -> void:
	if not body.has_method("set_water_contact"):
		return
	var actor_id: int = body.get_instance_id()
	var entry: Dictionary = _occupants.get(actor_id, {"actor": weakref(body), "zones": {}})
	var active: Dictionary = entry.zones
	active[index] = true
	entry.zones = active
	_occupants[actor_id] = entry
	body.set_water_contact(true)

func _body_exited(body: Node2D, index: int) -> void:
	var actor_id: int = body.get_instance_id()
	if not _occupants.has(actor_id):
		return
	var entry: Dictionary = _occupants[actor_id]
	var active: Dictionary = entry.zones
	active.erase(index)
	if active.is_empty():
		_occupants.erase(actor_id)
		if is_instance_valid(body):
			body.set_water_contact(false)
	else:
		entry.zones = active
		_occupants[actor_id] = entry

func _physics_process(_delta: float) -> void:
	# A1 load/Player.restore may temporarily clear the flag while an actor
	# remains submerged; resync with actual overlap on the next physics tick.
	for actor_id in _occupants.keys():
		var entry: Dictionary = _occupants[actor_id]
		var actor = entry.actor.get_ref()
		if is_instance_valid(actor) and actor.has_method("set_water_contact"):
			actor.set_water_contact(true)
		else:
			_occupants.erase(actor_id)

func _exit_tree() -> void:
	# SceneRouter destroys the previous WorldHost on transition. Avoid stale
	# water state on the one persistent Player when that world's areas vanish.
	for entry in _occupants.values():
		var actor = entry.actor.get_ref()
		if is_instance_valid(actor) and actor.has_method("set_water_contact"):
			actor.set_water_contact(false)
	_occupants.clear()

func _draw() -> void:
	for rect in _zones:
		draw_rect(rect, Color(0.15, 0.31, 0.36, 0.66), true)
		draw_rect(rect, Color(0.36, 0.55, 0.58, 0.88), false, 2.0)
