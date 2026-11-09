extends Node2D

@export var scene_id: String = "hospital"
var app
var foe
var portals: Array = []
var nearby_exit := ""
var layout: Dictionary = {}
var location_id: String = ""
var location_label: String = ""
var resource_point := Vector2(300, 190)
var building_bodies := {}
var buildings := {}
var hospital_cache := {}
var occlusion: Node2D
var last_occlusion_position := Vector2.INF
var collision_revision := 0
const DistrictEvents = preload("res://game/systems/world/district_events.gd")
const Construction = preload("res://game/systems/shelter/construction.gd")
const WorldArt = preload("res://game/scenes/worlds/world_art.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const GameplayState = preload("res://game/state/gameplay_state.gd")

func configure_layout(nodes: Dictionary, id: String) -> void:
	location_id = id
	layout = nodes[id]
	location_label = layout.label
	scene_id = layout.kind
	resource_point = layout.loot
	var entries := get_node("EntryPoints")
	entries.get_node("default").position = layout.spawn
	for index in range(layout.links.size()):
		var neighbor: String = layout.links[index]
		var position: Vector2 = Layout.DOORS[index]
		var inward := Vector2.RIGHT if position.x < 320 else Vector2.LEFT
		var placement: Dictionary = layout.get("exits", {}).get(neighbor, {
			"position": position, "arrival": position + inward * 22, "inward": inward,
			"form": "stairs_up" if scene_id == "hospital" and nodes[neighbor].kind == "hospital" else "door",
		})
		var marker := Marker2D.new()
		marker.name = "from_" + neighbor
		marker.position = placement.arrival
		entries.add_child(marker)
		var portal := placement.duplicate()
		portal.merge({"to": neighbor, "entry": "from_" + id, "label": nodes[neighbor].label})
		portals.append(portal)


func _ready() -> void:
	z_index = -10
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var floor := floor_rect()
	var walls := [
		Rect2(floor.position, Vector2(floor.size.x, 10)),
		Rect2(Vector2(floor.position.x, floor.end.y - 10), Vector2(floor.size.x, 10)),
		Rect2(floor.position, Vector2(10, floor.size.y)),
		Rect2(Vector2(floor.end.x - 10, floor.position.y), Vector2(10, floor.size.y)),
	]
	if layout.has("floor_plan"):
		walls.clear()
	walls.append_array(layout.get("obstacles", []))
	for rect in walls:
		add_wall(rect)
	if not layout.get("obstacles", []).is_empty():
		occlusion = Node2D.new()
		occlusion.z_index = 21
		occlusion.draw.connect(draw_occlusion)
		add_child(occlusion)
	if not layout.is_empty():
		queue_redraw()
		return
	if scene_id == "hospital":
		portals = [{"to": "outside", "position": Vector2(560, 260), "label": "Город"}, {"to": "shelter", "position": Vector2(380, 300), "label": "Убежище"}]
	elif scene_id == "outside":
		portals = [{"to": "hospital", "position": Vector2(70, 280), "label": "Больница"}, {"to": "shelter", "position": Vector2(550, 280), "label": "Убежище"}, {"to": "louvre", "position": Vector2(540, 140), "label": "Стоянка"}]
	elif scene_id == "shelter":
		portals = [{"to": "outside", "position": Vector2(550, 280), "label": "Город"}]
	else:
		portals = [{"to": "outside", "position": Vector2(550, 280), "label": "Город"}]
	queue_redraw()

func entry_direction(id: String) -> Vector2:
	for portal in portals:
		if "from_" + portal.to == id:
			return portal.get("inward", Vector2.DOWN)
	return Vector2.ZERO

func salvage_point() -> Vector2:
	return layout.get("salvage", Construction.SALVAGE_POINT)

func event_point() -> Vector2:
	return layout.get("event", DistrictEvents.POINT)

func floor_rect() -> Rect2:
	return layout.get("bounds", Layout.LEGACY_FLOOR)

func add_wall(rect: Rect2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	wall.position = rect.get_center()
	wall.set_meta("collision_rect", rect)
	wall.tree_exited.connect(func(): collision_revision += 1)
	wall.add_child(collider)
	add_child(wall)
	collision_revision += 1
	return wall

# Live physics walls (including player-built shelter structures) are the
# authoritative navigation obstacle set. Rebuilding after changes invalidates
# the zombie chase path; no collision is bypassed by the pathfinder.
func collision_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in get_children():
		if child is StaticBody2D and child.has_meta("collision_rect") and not child.is_queued_for_deletion():
			rects.append(child.get_meta("collision_rect"))
	return rects

func refresh_buildings() -> void:
	if scene_id != "shelter" or layout.is_empty() or app == null:
		return
	var current: Dictionary = app.snapshot(false).shelter.get("buildings", {})
	if buildings == current:
		return
	for cell in building_bodies.keys():
		if not current.has(cell):
			var wall: StaticBody2D = building_bodies[cell]
			remove_child(wall)
			wall.queue_free()
			building_bodies.erase(cell)
	for cell in current:
		if not building_bodies.has(cell):
			building_bodies[cell] = add_wall(Construction.cell_rect(cell))
	buildings = current
	queue_redraw()

func bind(runtime) -> void:
	app = runtime
	if is_instance_valid(foe):
		foe.free()
	foe = null
	var state: Dictionary = app.snapshot()
	if scene_id == "shelter" and not state.world_states.first_enemy_defeated:
		for portal in portals:
			if portal.to == "outside":
				portal.to = state.scene.return_scene_id
				portal.entry = "default"
				portal.label = "Вернуться в больницу"
	hospital_cache = Layout.hospital_cache(location_id, state.world_states.layout) if state.schema_version == 4 else {}
	var current_id: String = state.scene.current_scene_id
	if GameplayState.has_live_enemy(state, current_id):
		foe = preload("res://game/entities/enemies/enemy.gd").new()
		foe.app = app
		foe.health = int(state.world_states.get("enemy_health", {}).get(current_id, foe.health))
		foe.position = layout.get("enemy", Vector2(330, 190))
		if state.schema_version == 4 and Layout.street_has_patrol(location_id, state.world_states.layout):
			foe.patrol = layout.patrol
			foe.patrol_index = floori(float(state.game_time_minutes) / 30) % foe.patrol.size()
			foe.position = foe.patrol[foe.patrol_index]
		# Optional persisted runtime state keeps live pursuit and position through
		# G retreat, ordinary doors and checkpoint reload; old saves still load.
		var previous: Dictionary = state.world_states.get("enemy_runtime", {}).get(current_id, {})
		if not previous.is_empty():
			foe.restore_runtime(previous)
		add_child(foe)
	refresh_buildings()
	queue_redraw()

func interact() -> void:
	for portal in portals:
		if exit_reached(portal):
			app.transition(portal.to, portal.get("entry", "default"))
			return
	if scene_id == "outside" and app.hero.position.distance_to(event_point()) < 28 and DistrictEvents.available(app.snapshot(), location_id):
		app.ui.open_panel("district_event")
		return
	if scene_id == "outside" and not layout.is_empty() and app.hero.position.distance_to(salvage_point()) < 24:
		app.command("game.salvage")
	elif scene_id in ["outside", "house"] and app.hero.position.distance_to(resource_point) < 55:
		app.command("game.resource_collect")
	elif scene_id == "hospital" and not hospital_cache.is_empty() and app.hero.position.distance_to(resource_point) < 37:
		app.command("game.hospital_cache")
	elif scene_id == "shelter":
		if app.hero.position.distance_to(Vector2(220, 195)) < 58:
			app.ui.open_panel("farm")
		elif not layout.is_empty() and Rect2(167, 239, 245, 91).has_point(app.hero.position):
			app.ui.open_panel("workshop")
		elif app.hero.position.distance_to(Vector2(400, 180)) < 58:
			app.ui.open_panel("rest")
		else:
			app.ui.open_panel("inventory")
	elif scene_id == "louvre" and (not layout.has("exits") or app.hero.position.distance_to(Vector2(285, 190)) < 100):
		app.ui.open_panel("residents")

func exit_reached(portal: Dictionary) -> bool:
	if portal.has("area"):
		return portal.area.has_point(app.hero.position)
	return app.hero.position.distance_to(portal.position) < (48 if layout.is_empty() else 36)

func _process(_delta: float) -> void:
	if app == null:
		return
	var current := ""
	for portal in portals:
		if exit_reached(portal):
			current = portal.to
			break
	if nearby_exit != current:
		nearby_exit = current
		queue_redraw()
	if occlusion != null and app != null and app.hero.position != last_occlusion_position:
		last_occlusion_position = app.hero.position
		occlusion.queue_redraw()

func draw_occlusion() -> void:
	if app == null:
		return
	for obstacle in layout.get("floor_plan", {}).get("walls", layout.obstacles):
		if app.hero.position.y < obstacle.end.y and obstacle.grow(18).has_point(app.hero.position):
			WorldArt.obstacle(occlusion, scene_id, obstacle)

func draw_location_detail() -> void:
	if layout.is_empty() or layout.has("floor_plan"):
		return
	var segment: String = layout.segment
	var variant := int(segment.get_slice(":", 1))
	var label := ""
	match scene_id:
		"outside":
			label = Layout.STREET_PROFILES[variant]
		"house":
			label = Layout.HOUSE_PROFILES[variant]
		"hospital":
			label = Layout.HOSPITAL_PROFILES[variant]
			var accents := [Color("677070"), Color("545875"), Color("435f59"), Color("5e526e")]
			draw_rect(Rect2(105, 233, 431, 3), accents[variant])
			for x in [131, 470]:
				draw_rect(Rect2(x, 242, 32, 3), accents[variant])
	if not label.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(103, 323), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b5c5cc"))

func _draw() -> void:
	var variant := int(str(layout.get("segment", "")).get_slice(":", 1))
	WorldArt.ground(self, scene_id, variant, layout)
	draw_location_detail()
	for obstacle in layout.get("floor_plan", {}).get("walls", layout.get("obstacles", [])):
		WorldArt.obstacle(self, scene_id, obstacle)
	if layout.has("floor_plan"):
		WorldArt.plan_details(self, layout.floor_plan)
	for kind in layout.get("facades", {}):
		WorldArt.facade(self, layout.facades[kind], kind)
	if scene_id == "hospital" and layout.is_empty():
		for x in [75, 170, 450]:
			draw_rect(Rect2(x, 120, 44, 68), Color("62747c"))
			draw_rect(Rect2(x + 5, 125, 34, 16), Color("d3d6c8"))
	elif scene_id == "hospital" and not hospital_cache.is_empty():
		var looted: bool = app.snapshot().world_states.locations.get(location_id, {}).get("cache_looted", false)
		draw_rect(Rect2(resource_point - Vector2(11, 8), Vector2(22, 16)), Color("49595d") if looted else Color("8d876b"))
		var label: String = "Пустой ящик" if looted else hospital_cache.label
		draw_string(ThemeDB.fallback_font, resource_point + Vector2(-62, -12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c1cbce"))
	elif scene_id == "shelter":
		# Overhead art remains attached to existing REST and FARM interactions.
		# These helpers create NO entities and NO untracked collision objects.
		WorldArt.shelter_rest(self)
		var plots: Array = app.snapshot(false).crops.plots if app != null else []
		WorldArt.shelter_farm(self, plots)
		if not layout.is_empty():
			for index in range(Construction.COLUMNS * Construction.ROWS):
				var cell := str(index)
				var rect := Construction.cell_rect(cell)
				draw_rect(rect.grow(5), Color("b0a573"), false)
				var built_type := str(buildings.get(cell, ""))
				if not built_type.is_empty():
					WorldArt.shelter_structure(self, built_type, rect)
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, 8), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("fff1d0"))
			draw_string(ThemeDB.fallback_font, Vector2(185, 245), "Стройплощадка [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f4e7be"))
	elif scene_id in ["outside", "house"]:
		var exhausted: bool = scene_id == "house" and app != null and app.snapshot().world_states.locations.get(location_id, {}).get("looted", false)
		var resource_label := "Пустой тайник" if exhausted else "Запасы семян"
		draw_rect(Rect2(resource_point - Vector2(16, 12), Vector2(32, 24)), Color("8e7954"))
		draw_string(ThemeDB.fallback_font, resource_point + Vector2(-49, -17), resource_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce5ce"))
		if scene_id == "outside" and not layout.is_empty():
			var salvage := salvage_point()
			draw_rect(Rect2(salvage - Vector2(10, 7), Vector2(20, 14)), Color("677b83"))
			draw_string(ThemeDB.fallback_font, salvage + Vector2(16, 4), "Утиль [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("dce5ce"))
		if scene_id == "outside" and app != null and DistrictEvents.available(app.snapshot(), location_id):
			var point := event_point()
			draw_circle(point, 9, Color("ad8360"))
			draw_string(ThemeDB.fallback_font, point + Vector2(-45, -13), "Выжившие [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e6d0a6"))
	elif scene_id == "louvre":
		for x in [230, 340]:
			draw_circle(Vector2(x, 190), 11, Color("d9bca5"))
			draw_rect(Rect2(x - 10, 200, 20, 22), Color("a191b8"))
	for portal in portals:
		WorldArt.exit_fixture(self, portal, floor_rect(), scene_id, nearby_exit == portal.to)
