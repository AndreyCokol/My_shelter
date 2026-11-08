extends "res://game/scenes/main/main.gd"

const Layout = preload("res://game/systems/world/world_layout.gd")
const NEXT_GAME_META := &"shelter_next_campaign"
const Rules = preload("res://game/data/game_rules.gd")
const Logic = preload("res://game/systems/gameplay/gameplay_commands.gd")
var hero
var camera: Camera2D
var ui
var save_store
var action_serial: int = 0
var hud_elapsed: float = 0
var save_location: String = "user://saves/prototype-v3.json"
var last_result: Dictionary = {}
var starting_seed: int = -1

func _ready() -> void:
	var next_game: Dictionary = get_tree().get_meta(NEXT_GAME_META, {})
	if not next_game.is_empty():
		get_tree().remove_meta(NEXT_GAME_META)
		starting_seed = next_game.seed
		save_location = next_game.save_location
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
	camera = Camera2D.new()
	$WorldHost.add_child(camera)
	bind_world()
	if next_game.is_empty():
		ui.open_panel("welcome")
	print("Playable prototype initialized; schema v4")

func _process(delta: float) -> void:
	super._process(delta)
	update_camera()
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
	if kind == "session.upgrade_world":
		request.context.departure_position = {"x": hero.position.x, "y": hero.position.y}
		request.context.health = hero.health
	last_result = session.execute(request, save_store)
	if last_result.ok and kind == "session.upgrade_world":
		bind_world()
	if ui != null:
		ui.show_result(last_result)
	return last_result

func transition(destination: String, entry_id: String = "default") -> Dictionary:
	var result: Dictionary = scene_router.try_transition(next_action(), destination, entry_id, hero.health)
	last_result = result
	ui.show_result(result)
	if result.ok:
		bind_world()
		var direction: Vector2 = scene_router.current_world().entry_direction(entry_id)
		if direction != Vector2.ZERO:
			hero.facing = direction
	return result

# One player-controlled round trip to the Shelter, independent of story unlocks.
# Keep all writes inside SceneRouter/CoreSession for durable position and return state.
func toggle_shelter() -> Dictionary:
	if scene_router == null or campaign == null or not is_instance_valid(hero) or hero.defeated:
		return {"ok": false, "code": "UNAVAILABLE"}
	var state: Dictionary = snapshot()
	var destination: String = state.scene.return_scene_id if state.scene.current_scene_id == "shelter" else "shelter"
	return transition(destination)

func bind_world() -> void:
	var world = scene_router.current_world()
	if is_instance_valid(world):
		world.bind(self)
	update_camera()

func update_camera() -> void:
	if camera == null or scene_router == null:
		return
	var world = scene_router.current_world()
	if not is_instance_valid(world):
		return
	var floor: Rect2 = world.floor_rect()
	if floor == Layout.LEGACY_FLOOR:
		camera.position = Vector2(320, 180)
	else:
		# Reserve the fixed HUD and message bands in screen space.
		var half := get_viewport().get_visible_rect().size * 0.5
		var minimum := floor.position + half - Vector2(0, 80)
		var maximum := floor.end - half + Vector2(0, 15)
		var midpoint := (minimum + maximum) * 0.5
		var target: Vector2 = hero.position - Vector2(0, 32.5)
		camera.position = target.clamp(minimum.min(midpoint), maximum.max(midpoint)).round()
	camera.force_update_scroll()

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

func new_game(seed_text: String = "") -> void:
	var entered := seed_text.strip_edges()
	var seed_value := -1
	if not entered.is_empty():
		if entered.length() > 10 or not entered.is_valid_int() or int(entered) < 0 or int(entered) > Layout.MAX_SEED:
			ui.show_result({"ok": false, "code": "INVALID_WORLD_SEED"})
			return
		seed_value = int(entered)
	var state := snapshot()
	var fresh: bool = state.state_revision == 0 and state.schema_version == 4 and (seed_value < 0 or seed_value == int(state.world_states.layout.seed))
	var archived := {}
	for suffix in ["", ".bak"]:
		var path: String = ProjectSettings.globalize_path(save_location + str(suffix))
		if FileAccess.file_exists(path):
			var archive: String = path + ".archive-" + str(Time.get_ticks_usec())
			if DirAccess.rename_absolute(path, archive) != OK:
				_restore_archives(archived)
				ui.show_result({"ok": false, "code": "SAVE_FAILED"})
				return
			archived[path] = archive
	if fresh:
		ui.close_panel()
		return
	var tree := get_tree()
	tree.set_meta(NEXT_GAME_META, {"seed": seed_value, "save_location": save_location})
	if tree.reload_current_scene() != OK:
		tree.remove_meta(NEXT_GAME_META)
		_restore_archives(archived)
		ui.show_result({"ok": false, "code": "UNAVAILABLE"})

func _restore_archives(archived: Dictionary) -> void:
	for path in archived:
		if DirAccess.rename_absolute(archived[path], path) != OK:
			push_error("Could not restore an archived save after reset failed")

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
	# Shelter access also works with the player's own open modal. UI safely
	# releases just that modal's pause token; recovery or external pause is preserved.
	if event.is_action_pressed("shelter_skill") and not event.is_echo():
		ui.toggle_shelter()
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

