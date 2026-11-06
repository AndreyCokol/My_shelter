extends Node

const CoreSession = preload("res://game/systems/core/core_session.gd")
var session = CoreSession.new()

func _ready() -> void:
	# Core-only bootstrap. World and UI are supplied by their module owners.
	for action in ["move_up", "move_down", "move_left", "move_right", "interact", "attack", "dodge", "inventory", "system_menu", "pause", "shelter_skill"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var keys = {"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "interact": KEY_E, "dodge": KEY_SPACE, "inventory": KEY_I, "system_menu": KEY_TAB, "pause": KEY_ESCAPE, "shelter_skill": KEY_G}
	for action in keys:
		var event = InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	var attack = InputEventMouseButton.new()
	attack.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", attack)
	print("G1a core bootstrap ready; gameplay and UI pending")
