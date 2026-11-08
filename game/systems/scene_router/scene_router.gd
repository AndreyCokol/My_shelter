extends RefCounted

const Layout = preload("res://game/systems/world/world_layout.gd")
const Model = preload("res://game/state/campaign_model.gd")
var _host: Node2D
var _actor: Node2D
var _session
var _store
var _registry: Dictionary
var _world: Node2D
var _mounted_schema := 0
var _mounted_generator := 0
var _scene_id: String = ""
var _pending_world: Node2D
var _pending_scene: String = ""
var _transitioning: bool = false

func _init(host: Node2D, actor: Node2D, session, store, registry: Dictionary) -> void:
	_host = host
	_actor = actor
	_session = session
	_store = store
	_registry = registry.duplicate()
	_session.runtime_preparer = prepare_runtime
	_session.runtime_required = true

# World scenes are trusted project resources, never paths loaded from save data.
# Retain this router in the composition root for the lifetime of the session.
func mount_current() -> bool:
	if _session.is_busy():
		return false
	var ticket := prepare_runtime(_session.get_snapshot(), "load")
	return ticket.get("ok", false) and bool(ticket.install.call())

func try_transition(action_id: String, destination_scene_id: String, entry_point_id: String, actor_health: int = -1) -> Dictionary:
	if _transitioning or _session.is_busy():
		return _error("UNAVAILABLE", action_id)
	var state: Dictionary = _session.get_snapshot()
	var request := _request(action_id, "scene.transition", {"destination_scene_id": destination_scene_id, "entry_point_id": entry_point_id})
	# Replay must not depend on a now-missing target resource or current position.
	if state.completed_actions.has(action_id):
		return _session.execute(request, _store)
	if not is_instance_valid(_actor):
		return _error("UNAVAILABLE", action_id)
	var staged := _stage(destination_scene_id, entry_point_id, state)
	if not staged.get("ok", false):
		return _error("UNAVAILABLE", action_id)
	request.context.departure_position = _position(_actor.position)
	if actor_health >= 0:
		request.context.health = actor_health
	var restore_position: bool = state.schema_version != 4 or (
		state.scene.current_scene_id == "shelter" and destination_scene_id == state.scene.return_scene_id and entry_point_id == "default")
	request.context.arrival_position = state.scene.positions.get(destination_scene_id, staged.position).duplicate(true) if restore_position else staged.position
	_pending_world = staged.world
	_pending_scene = destination_scene_id
	_transitioning = true
	var result: Dictionary = _session.execute(request, _store)
	_transitioning = false
	if is_instance_valid(_pending_world):
		_pending_world.free()
	_pending_world = null
	_pending_scene = ""
	return result

func save(action_id: String) -> Dictionary:
	if not is_instance_valid(_actor):
		return _error("UNAVAILABLE", action_id)
	var request := _request(action_id, "session.save", {})
	request.context.departure_position = _position(_actor.position)
	return _session.execute(request, _store)

func load_saved(use_backup: bool = false) -> Dictionary:
	return _session.load_checkpoint(_store, use_backup)

func current_world() -> Node2D:
	return _world

func _request(action_id: String, kind: String, payload: Dictionary) -> Dictionary:
	var state: Dictionary = _session.get_snapshot()
	return {"action_id": action_id, "command_type": kind, "payload": payload, "context": {
		"actor_id": "player", "scene_id": state.scene.current_scene_id,
		"expected_resource_revisions": [{"key": "scene", "revision": state.resource_revisions.scene}]}}

func prepare_runtime(candidate: Dictionary, reason: String) -> Dictionary:
	var target: String = candidate.scene.current_scene_id
	var generator: int = int(candidate.world_states.layout.generator_version) if candidate.schema_version == 4 else 0
	if reason == "command" and target == _scene_id and candidate.schema_version == _mounted_schema and generator == _mounted_generator and is_instance_valid(_world):
		return {"ok": true}
	var staged: Dictionary
	if reason == "command" and is_instance_valid(_pending_world) and _pending_scene == target:
		staged = {"ok": true, "world": _pending_world}
		_pending_world = null
	else:
		staged = _stage(target, candidate.scene.entry_point_id, candidate)
	if not staged.get("ok", false):
		return {"ok": false}
	var world: Node2D = staged.world
	var position: Vector2 = Vector2(candidate.player.position.x, candidate.player.position.y)
	return {"ok": true, "discard": func():
		if is_instance_valid(world):
			world.free(),
		"install": func(): return _install(world, target, position, int(candidate.schema_version), generator)}

func _stage(scene_id: String, entry_id: String, state: Dictionary) -> Dictionary:
	if not is_instance_valid(_host) or not is_instance_valid(_actor) or not _registry.get(scene_id) is PackedScene:
		return {"ok": false}
	var world = _registry[scene_id].instantiate()
	if not world is Node2D:
		world.free()
		return {"ok": false}
	if state.schema_version == 4 and world.has_method("configure_layout"):
		var nodes := Layout.from_manifest(state.world_states.layout)
		if not nodes.has(scene_id):
			world.free()
			return {"ok": false}
		world.configure_layout(nodes, scene_id)
	var entries = world.get_node_or_null("EntryPoints")
	var entry = entries.get_node_or_null(NodePath(entry_id)) if entries is Node2D and entry_id.is_valid_identifier() else null
	if not entry is Marker2D or world.transform != Transform2D.IDENTITY or entries.transform != Transform2D.IDENTITY:
		world.free()
		return {"ok": false}
	return {"ok": true, "world": world, "position": _position(entry.position)}

func _install(world: Node2D, scene_id: String, position: Vector2, schema: int, generator: int) -> bool:
	if not is_instance_valid(_host) or not is_instance_valid(_actor):
		world.free()
		return false
	# One actor owned by A2, separate from disposable world scenery.
	if _actor.get_parent() != _host:
		if _actor.get_parent() != null:
			_actor.reparent(_host, false)
		else:
			_host.add_child(_actor)
	var old := _world
	if is_instance_valid(old):
		_host.remove_child(old)
	_actor.position = position
	_world = world
	_scene_id = scene_id
	_mounted_schema = schema
	_mounted_generator = generator
	_host.add_child(world)
	if is_instance_valid(old):
		# A door interaction can still be executing on the detached world.
		old.queue_free()
	return is_instance_valid(_world) and _world.get_parent() == _host

static func _position(position: Vector2) -> Dictionary:
	return {"x": position.x, "y": position.y}

func _error(code: String, action_id: String) -> Dictionary:
	return {"ok": false, "code": code, "action_id": action_id,
		"state_revision": _session.get_snapshot().state_revision, "data": {},
		"message_key": "core." + code.to_lower()}
