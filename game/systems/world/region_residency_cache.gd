extends Node2D
## A2-04 bounded, actually mounted Node2D region residency.
##
## Ownership contract: the A2 factory builds disposable world instances,
## while ONLY A1 can decide whether a dirty world-delta checkpoint is durable.
## A dirty/focused region cannot be evicted. No A1 save or v4/v5 changes.
## This is the lifecycle adapter; it does NOT yet implement a full
## terrain generator, prefetch, multiplayer or seamless SceneRouter swaps.
const Regions = preload("res://game/systems/world/region_seams.gd")
const MAX_CAPACITY := 25
var _configured := false
var _seed := -1
var _capacity := 0
var _entries: Dictionary = {}
var _lru: Array[String] = []
var _protected_focus := ""
var _busy := false
var _evictions := 0

func configure(seed: int, capacity: int = 9) -> Dictionary:
	if _configured or is_inside_tree() or get_child_count() != 0:
		return _error("INVALID_STATE")
	if seed < 0 or seed > Regions.MAX_WORLD_SEED or capacity < 1 or capacity > MAX_CAPACITY:
		return _error("INVALID_ARGUMENT")
	_seed = seed
	_capacity = capacity
	_configured = true
	return {"ok": true, "code": "OK"}

func acquire(x: int, y: int, factory: Callable) -> Dictionary:
	if not _configured or not is_inside_tree():
		return _error("UNMOUNTED")
	if _busy:
		return _error("REENTRANT_ACCESS")
	var manifest: Dictionary = Regions.manifest(_seed, x, y)
	if manifest.is_empty() or not Regions.valid_canonical_manifest(manifest):
		return _error("INVALID_REGION_ID")
	var id: String = manifest.id
	if _entries.has(id):
		var existing: Dictionary = _entries[id]
		if not is_instance_valid(existing.node):
			return _error("CORRUPT_RESIDENCY")
		_touch(id)
		return _view(id, existing, false)
	if not factory.is_valid():
		return _error("INVALID_FACTORY")
	# Preflight before running a possibly expensive/side-effecting factory.
	# Both dirty regions and the focused (current hero) region are pinned.
	var victim := ""
	if _entries.size() >= _capacity:
		for candidate in _lru:
			var entry: Dictionary = _entries[candidate]
			if not entry.dirty and candidate != _protected_focus:
				victim = candidate
				break
		if victim.is_empty():
			return _error("DURABLE_CHECKPOINT_REQUIRED")
	_busy = true
	var node = factory.call(manifest.duplicate(true))
	if not node is Node2D or not is_instance_valid(node) \
			or node.get_parent() != null or node.is_inside_tree() or node == self:
		_busy = false
		return _error("INVALID_FACTORY_RESULT")
	if not victim.is_empty():
		var removed: Dictionary = _entries[victim]
		if not is_instance_valid(removed.node):
			_busy = false
			node.free()
			return _error("CORRUPT_RESIDENCY")
		# Detach immediately to bound active PhysicsServer2D objects.
		# Actual free is deferred to preserve Godot lifecycle safety.
		remove_child(removed.node)
		removed.node.queue_free()
		_entries.erase(victim)
		_lru.erase(victim)
		_evictions += 1
	node.name = "Region_" + id.replace(":", "_")
	add_child(node)
	var record := {"node": node, "manifest": manifest.duplicate(true),
		"revision": 0, "dirty": false}
	_entries[id] = record
	_lru.append(id)
	_busy = false
	return _view(id, record, true)

func set_focus(id: String) -> Dictionary:
	if _busy:
		return _error("REENTRANT_ACCESS")
	if not _entries.has(id):
		return _error("UNKNOWN_REGION")
	if not is_instance_valid(_entries[id].node):
		return _error("CORRUPT_RESIDENCY")
	_protected_focus = id
	_touch(id)
	return {"ok": true, "code": "OK"}

func clear_focus() -> Dictionary:
	if _busy:
		return _error("REENTRANT_ACCESS")
	_protected_focus = ""
	return {"ok": true, "code": "OK"}

func mark_dirty(id: String) -> Dictionary:
	if _busy:
		return _error("REENTRANT_ACCESS")
	if not _entries.has(id):
		return _error("UNKNOWN_REGION")
	var record: Dictionary = _entries[id]
	if not is_instance_valid(record.node):
		return _error("CORRUPT_RESIDENCY")
	# Every edit increments revision; an ACK for an older revision cannot
	# silently permit eviction of uncommitted new actor/world changes.
	record.revision = int(record.revision) + 1
	record.dirty = true
	_entries[id] = record
	return {"ok": true, "code": "OK", "revision": record.revision}

func acknowledge_durable(id: String, revision: int, a1_verifier: Callable) -> Dictionary:
	if _busy:
		return _error("REENTRANT_ACCESS")
	if not _entries.has(id):
		return _error("UNKNOWN_REGION")
	var record: Dictionary = _entries[id]
	if not record.dirty or revision < 1 or record.revision != revision:
		return _error("STALE_REVISION")
	if not a1_verifier.is_valid():
		return _error("UNVERIFIED_CHECKPOINT")
	# A callback must not be able to mutate or evict the same cache while
	# the authoritative save receipt is being checked.
	_busy = true
	var durable_response = a1_verifier.call(id, revision)
	_busy = false
	if durable_response != true:
		return _error("UNVERIFIED_CHECKPOINT")
	# Trust boundary: A2 cannot independently attest that bytes were
	# fsynced. A1 must supply a trusted durable-checkpoint verifier.
	record.dirty = false
	_entries[id] = record
	return {"ok": true, "code": "OK"}

func evict_clean(id: String) -> Dictionary:
	if _busy:
		return _error("REENTRANT_ACCESS")
	if not _entries.has(id):
		return _error("UNKNOWN_REGION")
	if _entries[id].dirty or id == _protected_focus:
		return _error("DURABLE_CHECKPOINT_REQUIRED")
	var entry: Dictionary = _entries[id]
	if not is_instance_valid(entry.node):
		return _error("CORRUPT_RESIDENCY")
	remove_child(entry.node)
	entry.node.queue_free()
	_entries.erase(id)
	_lru.erase(id)
	_evictions += 1
	return {"ok": true, "code": "OK"}

func cached_manifest(id: String) -> Dictionary:
	if not _entries.has(id):
		return {}
	return _entries[id].manifest.duplicate(true)

func active_region_ids() -> Array[String]:
	return _lru.duplicate()

func statistics() -> Dictionary:
	var dirty_count := 0
	for entry in _entries.values():
		if entry.dirty:
			dirty_count += 1
	return {"active": _entries.size(), "capacity": _capacity,
		"dirty": dirty_count, "evicted": _evictions, "focus": _protected_focus}

func _touch(id: String) -> void:
	_lru.erase(id)
	_lru.append(id)

func _view(id: String, entry: Dictionary, created: bool) -> Dictionary:
	return {"ok": true, "code": "OK", "id": id, "node": entry.node,
		"manifest": entry.manifest.duplicate(true),
		"revision": entry.revision, "dirty": entry.dirty, "created": created}

func _error(code: String) -> Dictionary:
	return {"ok": false, "code": code}
