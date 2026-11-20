extends "res://game/scenes/prototypes/dual_view_preview.gd"
## A5 integration preview: actual WorldLayout v5 walls, no campaign mutations.
## F6 cycles floor 3 -> floor 1 -> city. Caps Lock still toggles cameras.
## The current gameplay's Node2D root remains the authoritative playable scene.
const Bridge = preload("res://game/systems/world/dual_view_layout_bridge.gd")
const SCENES := ["hospital_0_3", "hospital", "outside"]
const DEMO_SEED := 42

var selected_scene := 0
var layout_snapshot: Dictionary = {}

func _ready() -> void:
	super._ready()
	_install_layout(SCENES[selected_scene])

func _install_layout(scene_id: String) -> void:
	var candidate: Dictionary = Bridge.snapshot(DEMO_SEED, scene_id)
	if not candidate.get("ok", false):
		push_error("A5 layout preview cannot stage " + scene_id + ": " + candidate.get("code", ""))
		return
	# Delete mock geometry from the isolated parent PoC, not from the live
	# game. The same hero and both Camera3D nodes remain in this scene.
	for child in get_children():
		if child.name in ["Floor", "PrototypeWall"] or child.is_in_group("a5_layout_preview_geometry"):
			remove_child(child)
			child.queue_free()

	_make_static_box("A5LayoutFloor", candidate.floor.position, candidate.floor.size, Color("4f5958"))
	_last_child_as_geometry()
	for box in candidate.wall_boxes:
		_make_static_box("A5LayoutObstacle", box.position, box.size, Color("7d827b"))
		_last_child_as_geometry()

	layout_snapshot = candidate
	hero.position = candidate.hero_position
	hero.velocity = Vector3.ZERO
	look_yaw = -PI * 0.5  # Face east along the hospital corridor, not into the near north wall.
	look_pitch = 0.0
	_update_cameras()
	set_first_person(false)
	print("A5 LAYOUT PREVIEW: ", scene_id, " / ", candidate.wall_count, " real v5 colliders")

func _last_child_as_geometry() -> void:
	var node := get_child(get_child_count() - 1)
	node.add_to_group("a5_layout_preview_geometry")

func cycle_layout() -> void:
	selected_scene = (selected_scene + 1) % SCENES.size()
	_install_layout(SCENES[selected_scene])

func set_first_person(enabled: bool) -> void:
	super.set_first_person(enabled)
	if is_instance_valid(hud):
		hud.get("help_label").text += "\nF6 · больница / улица"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		cycle_layout()
		get_viewport().set_input_as_handled()
	else:
		super._unhandled_input(event)
