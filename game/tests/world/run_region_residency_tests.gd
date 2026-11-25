extends SceneTree
## A2-04 actual Node2D residency, bounded LRU, dirty-checkpoint gate.
## Tests region-scene object lifecycles; DOES NOT claim A1 save integration.
const Cache = preload("res://game/systems/world/region_residency_cache.gd")
const Regions = preload("res://game/systems/world/region_seams.gd")

var checks := 0
var failures := 0
var factory_calls := 0
var durable: Dictionary = {}
var active_cache
var reentrant_result: Dictionary = {}
var reentrant_mutations: Array = []
var reentrant_durable_result: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _factory(manifest: Dictionary) -> Node2D:
	factory_calls += 1
	var node := Node2D.new()
	node.name = "AuthoredRegion"
	node.position = Vector2(float(manifest.x) * Regions.REGION_SIZE.x,
		float(manifest.y) * Regions.REGION_SIZE.y)
	var body := StaticBody2D.new()
	body.position = Vector2(120, 90)
	var collider := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 28)
	collider.shape = rect
	body.add_child(collider)
	node.add_child(body)
	node.set_meta("canonical_manifest", manifest.duplicate(true))
	return node

func _bad_factory(_manifest: Dictionary):
	factory_calls += 1
	return null

func _reentrant_factory(manifest: Dictionary) -> Node2D:
	reentrant_result = active_cache.acquire(700, 80, Callable(self, "_factory"))
	reentrant_mutations = [
		active_cache.set_focus("region:8:8"),
		active_cache.mark_dirty("region:8:8"),
		active_cache.evict_clean("region:8:8"),
		active_cache.clear_focus(),
	]
	return _factory(manifest)

func _reentrant_verifier(id: String, revision: int) -> bool:
	reentrant_durable_result = active_cache.clear_focus()
	return _durable_check(id, revision)

func _durable_check(id: String, revision: int) -> bool:
	return int(durable.get(id, -1)) == revision

func _untrusted_ack(_id: String, _revision: int) -> bool:
	return false

func _run() -> void:
	var cache = Cache.new()
	active_cache = cache
	check(cache.acquire(0, 0, Callable(self, "_factory")).code == "UNMOUNTED",
		"factory cannot allocate an unmounted physical chunk")
	check(not cache.configure(-1, 3).ok
		and not cache.configure(42, 0).ok
		and not cache.configure(42, 26).ok,
		"invalid seed and capacity are rejected without state mutation")
	check(cache.configure(42, 3).ok and cache.statistics().capacity == 3,
		"configured cache owns a strict three-Node2D residency limit")
	check(cache.configure(42, 3).code == "INVALID_STATE",
		"cache seed and memory budget cannot be changed after first config")
	root.add_child(cache)
	await process_frame

	var a: Dictionary = cache.acquire(0, 0, Callable(self, "_factory"))
	var b: Dictionary = cache.acquire(1, 0, Callable(self, "_factory"))
	var c: Dictionary = cache.acquire(2, 0, Callable(self, "_factory"))
	check(a.ok and b.ok and c.ok and a.created and b.created and c.created,
		"three canonical region scenes load with a real Node2D factory")
	check(cache.get_child_count() == 3 and cache.statistics().active == 3,
		"actual scene tree contains exactly the configured number of regions")
	check(a.node.is_inside_tree() and b.node.is_inside_tree()
		and c.node.is_inside_tree(),
		"all three Node2D chunks are physically mounted in active SceneTree")
	check(PhysicsServer2D.body_get_space(a.node.get_child(0).get_rid()).is_valid()
		and PhysicsServer2D.body_get_space(b.node.get_child(0).get_rid()).is_valid(),
		"two real chunk StaticBody2D colliders are registered in physics space")
	check(a.manifest == Regions.manifest(42, 0, 0)
		and b.manifest == Regions.manifest(42, 1, 0),
		"cached manifests match canonical seed42 region generator")
	var id_a: String = a.id
	var id_b: String = b.id
	var id_c: String = c.id
	var reused: Dictionary = cache.acquire(0, 0, Callable(self, "_factory"))
	check(reused.ok and not reused.created and reused.node == a.node and factory_calls == 3,
		"hot region reuse never allocates duplicate scene nodes")
	check(cache.active_region_ids() == [id_b, id_c, id_a],
		"LRU refresh is deterministic and ordered oldest to newest")

	var d: Dictionary = cache.acquire(3, 0, Callable(self, "_factory"))
	check(d.ok and d.created and cache.statistics().active == 3
		and not cache.active_region_ids().has(id_b),
		"loading fourth region evicts oldest clean B, not recently touched A")
	check(cache.get_child_count() == 3 and b.node.get_parent() == null,
		"evicted physical Node2D is immediately detached from WorldHost")
	await process_frame
	check(not is_instance_valid(b.node), "evicted Node2D is freed by next scene-tree frame")

	check(cache.set_focus(id_a).ok and cache.statistics().focus == id_a,
		"current hero region is protected from LRU eviction")
	check(cache.evict_clean(id_a).code == "DURABLE_CHECKPOINT_REQUIRED",
		"focused hero scene cannot be evicted even if clean")
	var edit_c: Dictionary = cache.mark_dirty(id_c)
	var edit_again: Dictionary = cache.mark_dirty(id_c)
	var edit_d: Dictionary = cache.mark_dirty(d.id)
	check(edit_c.ok and edit_again.ok and edit_d.ok
		and edit_again.revision == edit_c.revision + 1
		and cache.statistics().dirty == 2,
		"successive world-delta edits increment revision without duplicate dirty records")
	var calls_before: int = factory_calls
	var no_room: Dictionary = cache.acquire(4, 0, Callable(self, "_factory"))
	check(no_room.code == "DURABLE_CHECKPOINT_REQUIRED"
		and cache.statistics().active == 3 and factory_calls == calls_before,
		"all chunks focused/dirty: refuse BEFORE generating another scene")
	check(cache.evict_clean(id_c).code == "DURABLE_CHECKPOINT_REQUIRED"
		and cache.evict_clean(d.id).code == "DURABLE_CHECKPOINT_REQUIRED",
		"dirty world deltas cannot be discarded by manual LRU eviction")
	check(cache.acknowledge_durable(id_c, edit_c.revision, Callable(self, "_durable_check")).code == "STALE_REVISION",
		"stale A1 checkpoint version cannot unpin newer world edits")
	check(cache.acknowledge_durable(id_c, edit_again.revision, Callable()).code == "UNVERIFIED_CHECKPOINT",
		"missing authoritative persistence verifier cannot clear dirty bit")
	check(cache.acknowledge_durable(id_c, edit_again.revision, Callable(self, "_untrusted_ack")).code == "UNVERIFIED_CHECKPOINT",
		"failed external durable verification cannot clear dirty bit")
	durable[id_c] = edit_again.revision
	check(cache.acknowledge_durable(id_c, edit_again.revision, Callable(self, "_reentrant_verifier")).ok
		and reentrant_durable_result.code == "REENTRANT_ACCESS",
		"trusted A1 verifier cannot mutate focused residency during acknowledgement")
	check(cache.statistics().dirty == 1,
		"staged transaction does not accidentally acknowledge other dirty regions")

	var e: Dictionary = cache.acquire(4, 0, Callable(self, "_factory"))
	check(e.ok and not cache.active_region_ids().has(id_c)
		and cache.active_region_ids().has(id_a)
		and cache.active_region_ids().has(d.id)
		and cache.get_child_count() == 3,
		"after acknowledgement, evict only verified-clean C, preserve focused A and dirty D")
	var saved_manifest: Dictionary = cache.cached_manifest(id_a)
	saved_manifest.gates["west"] = Vector2.INF
	check(cache.cached_manifest(id_a).gates["west"].is_finite(),
		"cache returns defensive copies; clients cannot corrupt canonical border geometry")

	var before_bad_factory: Array[String] = cache.active_region_ids()
	var bad: Dictionary = cache.acquire(5, 0, Callable(self, "_bad_factory"))
	check(bad.code == "INVALID_FACTORY_RESULT"
		and cache.active_region_ids() == before_bad_factory
		and cache.get_child_count() == 3,
		"failing region factory leaves old physics nodes and LRU intact")
	check(cache.acquire(Regions.MAX_REGION_COORD + 1, 0, Callable(self, "_factory")).code == "INVALID_REGION_ID",
		"out-of-bounds signed region ID rejected before creating scene")

	# A fresh mini-cache permits the factory to attempt a nested acquire.
	# Guard against reentrant callbacks that would otherwise race capacity.
	var nested := Cache.new()
	check(nested.configure(7, 2).ok, "independent world seed creates another isolated cache")
	root.add_child(nested)
	active_cache = nested
	var nested_entry: Dictionary = nested.acquire(8, 8, Callable(self, "_reentrant_factory"))
	check(nested_entry.ok and reentrant_result.code == "REENTRANT_ACCESS"
		and nested.statistics().active == 1,
		"reentrant factory cannot over-allocate the same active cache")
	check(reentrant_mutations.size() == 4
		and reentrant_mutations.all(func(value): return value.code == "REENTRANT_ACCESS"),
		"reentrant factory cannot focus, dirty, evict or clear focus during chunk allocation")
	nested.queue_free()
	await process_frame
	active_cache = cache

	# After the A1 checkpoint is trusted, no pinned delta remains.
	durable[d.id] = edit_d.revision
	check(cache.acknowledge_durable(d.id, edit_d.revision, Callable(self, "_durable_check")).ok,
		"second dirty chunk released only after its matching durable revision")
	cache.clear_focus()
	var old_ids := cache.active_region_ids()
	var evicted_start: int = cache.statistics().evicted
	# 150 distant world-region traversals without keeping old Node2Ds.
	# Yield per step so queued deletes really release engine resources.
	for k in range(150):
		var streamed: Dictionary = cache.acquire(k + 10, -3, Callable(self, "_factory"))
		check(streamed.ok and streamed.created
			and cache.statistics().active <= 3 and cache.get_child_count() <= 3,
			"bounded live chunk %d has at most three active PhysicsServer2D scene nodes" % k)
		await process_frame
	check(cache.statistics().evicted >= evicted_start + 149,
		"150 actual region loads trigger repeated clean eviction, not unbounded resident growth")
	check(cache.statistics().dirty == 0 and cache.statistics().active == 3,
		"after sustained traversal cache stays bounded and clean")
	for region_id in old_ids:
		check(not cache.active_region_ids().has(region_id),
			"old region %s released after long excursion" % region_id)
	var touched: String = cache.active_region_ids().back()
	var too_old: Dictionary = cache.cached_manifest(touched)
	too_old.streams.geometry = 0
	check(cache.cached_manifest(touched).streams.geometry == Regions.manifest(42, 159, -3).streams.geometry,
		"manifest RNG streams immutable despite external copies after 150 unload cycles")
	cache.queue_free()
	await process_frame

	print("A2 REGION RESIDENCY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
