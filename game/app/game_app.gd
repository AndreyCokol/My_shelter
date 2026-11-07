extends "res://game/scenes/main/main.gd"

const Layout = preload("res://game/systems/world/world_layout.gd")
const Rules = preload("res://game/data/game_rules.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
var hero
var ui
var save_store
var action_serial: int = 0
var hud_elapsed: float = 0
var save_location: String = "user://saves/prototype-v3.json"
var last_result: Dictionary = {}
var starting_seed: int = -1

func _ready() -> void:
	super._ready()
	hero = preload("res://game/entities/player/player.gd").new()
	hero.app = self
	var maps: Dictionary = {}
	var settings := Rules.build()
	settings.world_seed = randi_range(0, Layout.MAX_SEED) if starting_seed < 0 else starting_seed
	settings.scenes = Layout.entries()
	for id in settings.scenes:
		var scene_type := Layout.kind(id)
		if scene_type == "house":
			scene_type = "hospital"
		maps[id] = load("res://game/scenes/worlds/" + scene_type + ".tscn")
	var started := start_campaign(settings, maps, hero, save_location)
	if not started.ok:
		push_error("Unable to start campaign")
		return
	save_store = preload("res://game/systems/core/checkpoint_store.gd").new(save_location)
	ui = preload("res://game/ui/game_ui.gd").new()
	ui.app = self
	$UILayer.add_child(ui)
	session.committed.connect(_committed)
	session.state_loaded.connect(_loaded)
	bind_world()
	var camera := Camera2D.new()
	camera.position = Vector2(320, 180)
	$WorldHost.add_child(camera)
	ui.open_panel("welcome")
	print("Playable prototype initialized; schema v4")

func _process(delta: float) -> void:
	super._process(delta)
	hud_elapsed += delta
	if hud_elapsed >= 0.2:
		hud_elapsed = 0
		update_hud()

func snapshot() -> Dictionary:
	return session.get_snapshot()

func rules() -> Dictionary:
	return campaign.get_rules()

func running() -> bool:
	return campaign != null and not session.pauses.is_paused() and not session.is_busy()

func enemy():
	var world = scene_router.current_world()
	return world.foe if is_instance_valid(world) else null

func next_action() -> String:
	action_serial += 1
	return "%s:%s:%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), action_serial]

func _request(kind: String, payload: Dictionary) -> Dictionary:
	var state := snapshot()
	var revisions: Array = []
	for key in state.resource_revisions:
		revisions.append({"key": key, "revision": state.resource_revisions[key]})
	return {"action_id": next_action(), "command_type": kind, "payload": payload, "context": {"actor_id": "player", "scene_id": state.scene.current_scene_id, "expected_resource_revisions": revisions}}

func command(kind: String, payload: Dictionary = {}) -> Dictionary:
	if kind in ["game.enemy_defeated", "game.player_defeated"]:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	return _execute(kind, payload)

func _execute(kind: String, payload: Dictionary = {}) -> Dictionary:
	var request := _request(kind, payload)
	if kind == "game.build":
		request.context.live_position = {"x": hero.position.x, "y": hero.position.y}
	last_result = session.execute(request, save_store)
	if ui != null:
		ui.show_result(last_result)
	return last_result

func transition(destination: String, entry_id: String = "default") -> Dictionary:
	var result: Dictionary = scene_router.try_transition(next_action(), destination, entry_id)
	last_result = result
	ui.show_result(result)
	if result.ok:
		bind_world()
	return result

func bind_world() -> void:
	var world = scene_router.current_world()
	if is_instance_valid(world):
		world.bind(self)

func _committed(_result: Dictionary) -> void:
	var world = scene_router.current_world()
	if is_instance_valid(world):
		world.refresh_buildings()
		world.queue_redraw()
	update_hud()

func _loaded() -> void:
	hero.restore(int(snapshot().player.hp))
	bind_world()
	update_hud()

func update_hud() -> void:
	if ui != null and is_instance_valid(ui):
		ui.update_hud()

func enemy_defeated() -> void:
	var target = enemy()
	if not is_instance_valid(target) or target.health > 0 or not running():
		if is_instance_valid(target):
			target.reported = false
		return
	var result := _execute("game.enemy_defeated")
	if result.ok:
		target.queue_free()
		scene_router.current_world().foe = null
	else:
		target.reported = false

func player_defeated() -> void:
	if not hero.defeated:
		return
	var result := _execute("game.player_defeated")
	if result.ok:
		hero.restore(100)
		hero.position = Vector2(120, 260)
		bind_world()
	else:
		# Keep the defeated actor blocked; explicit recovery/retry is available.
		ui.open_panel("save")

func save_game() -> Dictionary:
	var request := _request("session.save", {})
	request.context.departure_position = {"x": hero.position.x, "y": hero.position.y}
	request.context.health = hero.health
	last_result = session.execute(request, save_store)
	ui.show_result(last_result)
	return last_result

func load_game(backup: bool = false) -> Dictionary:
	last_result = scene_router.load_saved(backup)
	ui.show_result(last_result)
	if last_result.ok:
		ui.close_panel()
	return last_result

func new_game() -> void:
	# Explicit user choice: preserve the previous primary/backup before resetting.
	for suffix in ["", ".bak"]:
		var path: String = save_location + str(suffix)
		if FileAccess.file_exists(path):
			var archive: String = path + ".archive-" + str(Time.get_ticks_usec())
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(archive)) != OK:
				ui.show_result({"ok": false, "code": "SAVE_FAILED"})
				return
	ui.close_panel()
	if snapshot().state_revision > 0:
		get_tree().reload_current_scene()

func preview_rest(target: int) -> Dictionary:
	var candidate := snapshot()
	if candidate.scene.current_scene_id != "shelter" or target <= candidate.game_time_minutes:
		return {"ok": false}
	var result: Dictionary = campaign.calendar.advance(candidate, target, "rest")
	if result.ok:
		result.data.spoiled_plots = candidate.crops.plots.filter(func(p): return p.status == "spoiled").size()
	return result

func next_harvest_minute() -> int:
	var target: int = 9007199254740991
	var state := snapshot()
	for plot in state.crops.plots:
		if plot.status == "growing":
			target = mini(target, int(plot.ripe_at))
	return int(state.game_time_minutes) + 60 if target == 9007199254740991 else target

func _unhandled_input(event: InputEvent) -> void:
	if ui == null:
		return
	if event.is_action_pressed("pause"):
		if ui.panel_id.is_empty():
			ui.open_panel("menu")
		else:
			ui.close_panel()
		get_viewport().set_input_as_handled()
		return
	if not running():
		return
	if event.is_action_pressed("inventory"):
		ui.open_panel("inventory")
	elif event.is_action_pressed("system_menu"):
		ui.open_panel("quests")
	elif event.is_action_pressed("interact"):
		scene_router.current_world().interact()
	elif event.is_action_pressed("shelter_skill") and snapshot().world_states.first_enemy_defeated:
		if snapshot().scene.current_scene_id == "shelter":
			transition(snapshot().scene.return_scene_id)
		else:
			transition("shelter")
