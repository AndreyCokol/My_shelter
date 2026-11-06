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
	for action in {"move_up": KEY_UP, "move_down": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT}:
		var arrow = InputEventKey.new()
		arrow.physical_keycode = {"move_up": KEY_UP, "move_down": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT}[action]
		InputMap.action_add_event(action, arrow)
	var attack = InputEventMouseButton.new()
	attack.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", attack)
	print("G1a core bootstrap ready; gameplay and UI pending")

var campaign
var scene_router

# A2 supplies the actor/world PackedScenes; A5 supplies UILayer separately.
# No test catalog or synthetic player is installed into the product by default.
func start_campaign(rules: Dictionary, worlds: Dictionary, actor: Node2D, save_path: String = "user://saves/campaign-v2.json") -> Dictionary:
	if campaign != null:
		return {"ok": false, "code": "INVALID_STATE"}
	var candidate = preload("res://game/systems/core/campaign_session.gd").new(rules)
	if candidate.coordinator == null:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var store = preload("res://game/systems/core/checkpoint_store.gd").new(save_path)
	var router = preload("res://game/systems/scene_router/scene_router.gd").new($WorldHost, actor, candidate.coordinator, store, worlds)
	if not router.mount_current():
		return {"ok": false, "code": "UNAVAILABLE"}
	campaign = candidate
	session = campaign.coordinator
	scene_router = router
	return {"ok": true, "code": "OK"}

func _process(delta: float) -> void:
	if campaign != null:
		campaign.tick(delta)
