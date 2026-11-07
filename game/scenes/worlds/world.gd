extends Node2D

@export var scene_id: String = "hospital"
var app
var foe
var portals: Array = []
var layout: Dictionary = {}
var location_id: String = ""
var location_label: String = ""
var resource_point := Vector2(300, 190)
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
	var walls := [Rect2(20, 85, 600, 10), Rect2(20, 335, 600, 10), Rect2(20, 85, 10, 260), Rect2(610, 85, 10, 260)]
	walls.append_array(layout.get("obstacles", []))
	for rect in walls:
		var wall := StaticBody2D.new()
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collider.shape = shape
		wall.position = rect.get_center()
		wall.add_child(collider)
		add_child(wall)
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

func bind(runtime) -> void:
	app = runtime
	if is_instance_valid(foe):
		foe.free()
	foe = null
	var state: Dictionary = app.snapshot()
	var defeated: bool = state.world_states.first_enemy_defeated if location_id in ["", "hospital"] else state.world_states.get("locations", {}).get(location_id, {}).get("defeated", false)
	if scene_id == "hospital" and not defeated:
		foe = preload("res://game/entities/enemies/enemy.gd").new()
		foe.app = app
		foe.position = Vector2(330, 190)
		add_child(foe)
	queue_redraw()

func interact() -> void:
	for portal in portals:
		if app.hero.position.distance_to(portal.position) < (48 if layout.is_empty() else 36):
			app.transition(portal.to, portal.get("entry", "default"))
			return
	if scene_id in ["outside", "house"] and app.hero.position.distance_to(resource_point) < 55:
		app.command("game.resource_collect")
	elif scene_id == "shelter":
		if app.hero.position.distance_to(Vector2(220, 195)) < 58:
			app.ui.open_panel("farm")
		elif app.hero.position.distance_to(Vector2(400, 180)) < 58:
			app.ui.open_panel("rest")
		else:
			app.ui.open_panel("inventory")
	elif scene_id == "louvre":
		app.ui.open_panel("residents")

func _draw() -> void:
	var colors := {"hospital": Color("222b38"), "outside": Color("202c37"), "shelter": Color("3d5743"), "louvre": Color("383744"), "house": Color("282d38")}
	draw_rect(Rect2(20, 85, 600, 260), colors[scene_id])
	for x in range(30, 610, 32):
		for y in range(95, 335, 32):
			draw_rect(Rect2(x, y, 31, 31), Color(1, 1, 1, 0.025))
	for portal in portals:
		draw_circle(portal.position, 21, Color("315957"))
		draw_arc(portal.position, 21, 0, TAU, 24, Color("8cd3b3"), 2)
		draw_string(ThemeDB.fallback_font, Vector2(34 if portal.position.x < 320 else 400, portal.position.y - 22), portal.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e0e7d8"))
	for obstacle in layout.get("obstacles", []):
		draw_rect(obstacle, Color("424a57"))
		draw_rect(obstacle.grow(-3), Color("353e49"))
	if scene_id == "hospital" and layout.is_empty():
		for x in [75, 170, 450]:
			draw_rect(Rect2(x, 120, 44, 68), Color("62747c"))
			draw_rect(Rect2(x + 5, 125, 34, 16), Color("d3d6c8"))
	elif scene_id == "shelter":
		draw_colored_polygon(PackedVector2Array([Vector2(360, 205), Vector2(405, 130), Vector2(450, 205)]), Color("bda16c"))
		draw_rect(Rect2(392, 170, 27, 35), Color("594c39"))
		var plots: Array = app.snapshot().crops.plots if app != null else []
		for i in range(plots.size()):
			var status: String = plots[i].status
			draw_rect(Rect2(170 + i * 65, 175, 55, 50), Color("705442"))
			if status != "empty":
				var leaf := Color("98c46c") if status != "spoiled" else Color("907560")
				for dx in [12, 30, 44]:
					draw_circle(Vector2(170 + i * 65 + dx, 198), 5 if status == "ripe" else 3, leaf)
		draw_string(ThemeDB.fallback_font, Vector2(185, 162), "Грядки", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce5ce"))
	elif scene_id in ["outside", "house"]:
		var exhausted: bool = scene_id == "house" and app != null and app.snapshot().world_states.locations.get(location_id, {}).get("looted", false)
		var resource_label := "Пустой тайник" if exhausted else "Запасы семян"
		draw_rect(Rect2(resource_point - Vector2(16, 12), Vector2(32, 24)), Color("8e7954"))
		draw_string(ThemeDB.fallback_font, resource_point + Vector2(-49, -17), resource_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dce5ce"))
	elif scene_id == "louvre":
		for x in [230, 340]:
			draw_circle(Vector2(x, 190), 11, Color("d9bca5"))
			draw_rect(Rect2(x - 10, 200, 20, 22), Color("a191b8"))
