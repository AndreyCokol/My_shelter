extends Node3D
## A2-08 standalone visual proof of concept.
## Run this scene directly for manual inspection. NOT wired to the live game.
##
## WASD/arrows: move a single CharacterBody3D with real wall collision.
## Caps Lock: swap a strictly overhead orthographic view / first-person view.
## Mouse: look around in FPS. Escape: release mouse capture.
## No gameplay/save/UI ownership changes or real combat are claimed.
const Space = preload("res://game/systems/world/dual_view_space.gd")

const PREVIEW_BOUNDS := Rect2(0, 0, 640, 360)
const PREVIEW_WALLS := [
	Rect2(170, 35, 20, 190),
	Rect2(305, 155, 200, 20),
	Rect2(400, 55, 15, 75),
]
const WALK_SPEED := 4.0

var hero: CharacterBody3D
var overhead: Camera3D
var first_person: Camera3D
var hero_visual: MeshInstance3D
var first_person_enabled := false
var look_yaw := 0.0
var look_pitch := 0.0

func _ready() -> void:
	_make_floor()
	for wall in PREVIEW_WALLS:
		_make_wall(wall)
	_make_hero()
	_make_cameras()
	set_first_person(false)
	set_process(true)
	set_physics_process(true)

func _make_floor() -> void:
	var surface := Space.box_from_legacy_rect(PREVIEW_BOUNDS, 0.2)
	_make_static_box("Floor", Vector3(surface.position.x, -0.1, surface.position.z), surface.size, Color("585956"))

func _make_wall(rect: Rect2) -> void:
	var data := Space.box_from_legacy_rect(rect)
	assert(data.ok)
	_make_static_box("PrototypeWall", data.position, data.size, Color("8a7775"))

func _make_static_box(label: String, position_3d: Vector3, size_3d: Vector3, color: Color) -> void:
	var wall := StaticBody3D.new()
	wall.name = label
	wall.position = position_3d
	add_child(wall)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_3d
	collider.shape = box
	wall.add_child(collider)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_3d
	mesh_node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh_node.material_override = material
	wall.add_child(mesh_node)

func _make_hero() -> void:
	hero = CharacterBody3D.new()
	hero.name = "OneSharedHero"
	hero.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	hero.position = Space.legacy_to_3d(Vector2(95, 115), 0.9)
	add_child(hero)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	collision.shape = capsule
	hero.add_child(collision)
	hero_visual = MeshInstance3D.new()
	hero_visual.name = "SharedHeroVisualization"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.48, 1.55, 0.48)
	hero_visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("85b1b0")
	hero_visual.material_override = material
	hero.add_child(hero_visual)

func _make_cameras() -> void:
	overhead = Camera3D.new()
	overhead.name = "Overhead90Camera"
	overhead.projection = Camera3D.PROJECTION_ORTHOGONAL
	overhead.size = 15.0
	overhead.far = 120.0
	overhead.rotation = Space.topdown_rotation()
	add_child(overhead)
	first_person = Camera3D.new()
	first_person.name = "FirstPersonCamera"
	first_person.projection = Camera3D.PROJECTION_PERSPECTIVE
	first_person.fov = 75.0
	first_person.near = 0.05
	first_person.far = 120.0
	add_child(first_person)
	_update_cameras()

func set_first_person(enabled: bool) -> void:
	first_person_enabled = enabled
	if is_instance_valid(overhead) and is_instance_valid(first_person):
		overhead.current = not enabled
		first_person.current = enabled
	if is_instance_valid(hero_visual):
		hero_visual.visible = not enabled
	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE

func _update_cameras() -> void:
	if not is_instance_valid(hero):
		return
	overhead.position = Space.topdown_origin(hero.position)
	first_person.position = Space.fps_origin(hero.position)
	first_person.rotation = Vector3(look_pitch, look_yaw, 0)

func _process(_delta: float) -> void:
	_update_cameras()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(hero):
		return
	var horizontal := (1.0 if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) else 0.0)
	var vertical := (1.0 if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0)
	var axis := Vector2(horizontal, vertical).limit_length(1.0)
	if not first_person_enabled and axis.length_squared() > 0.00001:
		look_yaw = Space.yaw_for_legacy_facing(axis)
	hero.velocity = Space.world_motion(axis, look_yaw, first_person_enabled) * WALK_SPEED
	hero.move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_CAPSLOCK:
			set_first_person(not first_person_enabled)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and first_person_enabled:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
	elif first_person_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw -= event.relative.x * 0.002
		look_pitch = clampf(look_pitch - event.relative.y * 0.002, -1.2, 1.2)
		get_viewport().set_input_as_handled()
