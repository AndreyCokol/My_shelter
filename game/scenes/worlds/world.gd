extends Node2D

@export var scene_id: String = "hospital"
var app
var foe
var portals: Array = []
var layout: Dictionary = {}
var location_id: String = ""
var location_label: String = ""
var resource_point := Vector2(300, 190)
var building_bodies := {}
var buildings := {}
var hospital_cache := {}
var occlusion: Node2D
var last_occlusion_position := Vector2.INF
const DistrictEvents = preload("res://game/systems/world/district_events.gd")
const Construction = preload("res://game/systems/shelter/construction.gd")
const WorldArt = preload("res://game/scenes/worlds/world_art.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")

func configure_layout(nodes: Dictionary, id: String) -> void:
	location_id = id
	layout = nodes[id]
	location_label = layout.label
	scene_id = layout.kind
	resource_point = Vector2(300, 267)
	var entries := get_node("EntryPoints")
	for index in range(layout.links.size()):
		var neighbor: String = layout.links[index]
		var position: Vector2 = Layout.DOORS[index]
		var marker := Marker2D.new()
		marker.name = "from_" + neighbor
		marker.position = position + Vector2(22 if position.x < 320 else -22, 0)
		entries.add_child(marker)
		portals.append({"to": neighbor, "entry": "from_" + id, "position": position, "label": nodes[neighbor].label})


func _ready() -> void:
	z_index = -10
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var walls := [Rect2(20, 85, 600, 10), Rect2(20, 335, 600, 10), Rect2(20, 85, 10, 260), Rect2(610, 85, 10, 260)]
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

func add_wall(rect: Rect2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	wall.position = rect.get_center()
	wall.add_child(collider)
	add_child(wall)
	return wall

func refresh_buildings() -> void:
	if scene_id != "shelter" or layout.is_empty() or app == null:
		return
	var current: Dictionary = app.snapshot().shelter.get("buildings", {})
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
	hospital_cache = Layout.hospital_cache(location_id, state.world_states.layout) if state.schema_version == 4 else {}
	var defeated: bool = state.world_states.first_enemy_defeated if location_id in ["", "hospital"] else state.world_states.get("locations", {}).get(location_id, {}).get("defeated", false)
	var patrol: bool = state.schema_version == 4 and Layout.street_has_patrol(location_id, state.world_states.layout) and not location_id in state.world_states.get("cleared_patrols", [])
	if (scene_id == "hospital" and not defeated) or patrol:
		foe = preload("res://game/entities/enemies/enemy.gd").new()
		foe.app = app
		foe.position = Vector2(330, 190)
		if patrol:
			foe.patrol = PackedVector2Array([Vector2(235, 248), Vector2(455, 248), Vector2(455, 296), Vector2(235, 296)])
			foe.patrol_index = floori(float(state.game_time_minutes) / 30) % foe.patrol.size()
			foe.position = foe.patrol[foe.patrol_index]
		add_child(foe)
	refresh_buildings()
	queue_redraw()

func interact() -> void:
	for portal in portals:
		if app.hero.position.distance_to(portal.position) < (48 if layout.is_empty() else 36):
			app.transition(portal.to, portal.get("entry", "default"))
			return
	if scene_id == "outside" and app.hero.position.distance_to(DistrictEvents.POINT) < 28 and DistrictEvents.available(app.snapshot(), location_id):
		app.ui.open_panel("district_event")
		return
	if scene_id == "outside" and not layout.is_empty() and app.hero.position.distance_to(Construction.SALVAGE_POINT) < 24:
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
	elif scene_id == "louvre":
		app.ui.open_panel("residents")

func _process(_delta: float) -> void:
	if occlusion != null and app != null and app.hero.position != last_occlusion_position:
		last_occlusion_position = app.hero.position
		occlusion.queue_redraw()

func draw_occlusion() -> void:
	if app == null:
		return
	for obstacle in layout.obstacles:
		if app.hero.position.y < obstacle.end.y and obstacle.grow(18).has_point(app.hero.position):
			WorldArt.obstacle(occlusion, scene_id, obstacle)

func draw_location_detail() -> void:
	if layout.is_empty():
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
	WorldArt.ground(self, scene_id, variant)
	draw_location_detail()
	for portal in portals:
		var stairs: bool = scene_id == "hospital" and Layout.kind(portal.to) == "hospital"
		if stairs:
			WorldArt.stamp(self, "stairs", Rect2(portal.position - Vector2(17, 18), Vector2(34, 36)), WorldArt.COLD)
		else:
			draw_circle(portal.position, 21, Color("315957"))
			if scene_id in ["hospital", "house"]:
				WorldArt.stamp(self, "threshold", Rect2(portal.position - Vector2(18, 12), Vector2(36, 24)))
		draw_arc(portal.position, 21, 0, TAU, 24, Color("8cd3b3"), 2)
	for obstacle in layout.get("obstacles", []):
		WorldArt.obstacle(self, scene_id, obstacle)
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
		draw_colored_polygon(PackedVector2Array([Vector2(360, 205), Vector2(405, 130), Vector2(450, 205)]), Color("bda16c"))
		WorldArt.tile(self, "wood", Rect2(386, 168, 40, 38), WorldArt.WARM)
		var plots: Array = app.snapshot().crops.plots if app != null else []
		for i in range(plots.size()):
			var status: String = plots[i].status
			WorldArt.tile(self, "soil", Rect2(170 + i * 65, 175, 55, 50), WorldArt.WARM)
			if status != "empty":
				var leaf := Color("98c46c") if status != "spoiled" else Color("907560")
				for dx in [12, 30, 44]:
					draw_circle(Vector2(170 + i * 65 + dx, 198), 5 if status == "ripe" else 3, leaf)
		draw_string(ThemeDB.fallback_font, Vector2(185, 162), "Грядки", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce5ce"))
		if not layout.is_empty():
			for index in range(Construction.COLUMNS * Construction.ROWS):
				var cell := str(index)
				var rect := Construction.cell_rect(cell)
				draw_rect(rect.grow(5), Color("8da774"), false)
				match buildings.get(cell, ""):
					"bench":
						draw_rect(rect, Color("a66e45"))
						draw_line(rect.position + Vector2(3, 5), rect.position + Vector2(20, 5), Color("e1b282"), 3)
					"lamp":
						draw_circle(rect.get_center(), 27, Color(1, 0.77, 0.33, 0.19))
						draw_circle(rect.get_center(), 9, Color("f4c56f"))
					"cabinet":
						draw_rect(rect, Color("87664c"))
						draw_line(rect.get_center() - Vector2(0, 8), rect.get_center() + Vector2(0, 8), Color("b59162"), 2)
					"bed":
						draw_rect(rect, Color("9c7b61"))
						draw_rect(rect.grow(-3), Color("c2ac80"))
						draw_rect(Rect2(rect.position + Vector2(3, 3), Vector2(7, 16)), Color("f0d4b0"))
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, 8), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("eff0d6"))
			draw_string(ThemeDB.fallback_font, Vector2(185, 245), "Стройплощадка [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("dce5ce"))
	elif scene_id in ["outside", "house"]:
		var exhausted: bool = scene_id == "house" and app != null and app.snapshot().world_states.locations.get(location_id, {}).get("looted", false)
		var resource_label := "Пустой тайник" if exhausted else "Запасы семян"
		draw_rect(Rect2(resource_point - Vector2(16, 12), Vector2(32, 24)), Color("8e7954"))
		draw_string(ThemeDB.fallback_font, resource_point + Vector2(-49, -17), resource_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce5ce"))
		if scene_id == "outside" and not layout.is_empty():
			var salvage := Construction.SALVAGE_POINT
			draw_rect(Rect2(salvage - Vector2(10, 7), Vector2(20, 14)), Color("677b83"))
			draw_string(ThemeDB.fallback_font, salvage + Vector2(16, 4), "Утиль [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("dce5ce"))
		if scene_id == "outside" and app != null and DistrictEvents.available(app.snapshot(), location_id):
			var point := DistrictEvents.POINT
			draw_circle(point, 9, Color("ad8360"))
			draw_string(ThemeDB.fallback_font, point + Vector2(-45, -13), "Выжившие [E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e6d0a6"))
	elif scene_id == "louvre":
		for x in [230, 340]:
			draw_circle(Vector2(x, 190), 11, Color("d9bca5"))
			draw_rect(Rect2(x - 10, 200, 20, 22), Color("a191b8"))
	for portal in portals:
		var position := Vector2(34 if portal.position.x < 320 else 400, portal.position.y - 22)
		draw_string(ThemeDB.fallback_font, position + Vector2(1, 1), portal.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("101818"))
		draw_string(ThemeDB.fallback_font, position, portal.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e0e7d8"))
