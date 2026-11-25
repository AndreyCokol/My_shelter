extends SceneTree

# Prospective contract test, not runtime transfer/save.
const Batch = preload("res://game/contracts/inventory_batch_command_candidate.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func fixture() -> Dictionary:
	return {"from_id": "player", "to_id": "storage",
		"entries": [{"instance_id": "c", "quantity": 1},
			{"instance_id": "a", "quantity": 3},
			{"instance_id": "b", "quantity": 2}]}

func run() -> void:
	var original: Dictionary = fixture()
	var unchanged: Dictionary = original.duplicate(true)
	var norm: Dictionary = Batch.normalize(original)
	check(norm.ok and norm.payload.entries.size() == 3, "three distinct instances are accepted")
	check(norm.payload.entries.map(func(x): return x.instance_id) == ["a", "b", "c"],
		"click selection order is canonicalized by immutable instance ID")
	check(original == unchanged, "normalization never mutates client payload")
	var reverse: Dictionary = fixture()
	reverse.entries.reverse()
	var other: Dictionary = Batch.normalize(reverse)
	check(other.ok and other.payload == norm.payload,
		"permuted selection produces the same semantic payload")
	check(JSON.stringify(other.payload) == JSON.stringify(norm.payload),
		"canonical JSON fingerprint input independent of selection order")
	check(norm.payload.entries[0].quantity == 3 and norm.payload.entries[1].quantity == 2
		and norm.payload.entries[2].quantity == 1,
		"canonical order retains quantities attached to original instances")
	var distinct: Dictionary = fixture()
	distinct.entries[0].quantity = 2
	check(Batch.normalize(distinct).payload != norm.payload,
		"changing an item quantity changes semantic operation")
	var changed: Dictionary = fixture()
	changed.to_id = "other-storage"
	check(Batch.normalize(changed).payload != norm.payload,
		"changing transfer destination changes semantic operation")
	var changed_source: Dictionary = fixture()
	changed_source.from_id = "warehouse"
	check(Batch.normalize(changed_source).payload != norm.payload,
		"changing source changes semantic operation")
	check(not Batch.normalize({"from_id": "player", "to_id": "storage", "entries": []}).ok,
		"empty batch rejected")
	var duplicates: Dictionary = fixture()
	duplicates.entries.append({"instance_id": "a", "quantity": 1})
	check(not Batch.normalize(duplicates).ok, "repeated instance ID rejected before planner")
	var zero: Dictionary = fixture()
	zero.entries[0].quantity = 0
	check(not Batch.normalize(zero).ok, "zero item quantity rejected")
	var negative: Dictionary = fixture()
	negative.entries[0].quantity = -2
	check(not Batch.normalize(negative).ok, "negative item quantity rejected")
	var floating: Dictionary = fixture()
	floating.entries[0].quantity = 1.0
	check(not Batch.normalize(floating).ok, "fractional float item quantity rejected")
	var missing: Dictionary = fixture()
	missing.erase("from_id")
	check(not Batch.normalize(missing).ok, "missing source rejected")
	var extra: Dictionary = fixture()
	extra.client_mass = 100
	check(not Batch.normalize(extra).ok, "untrusted client mass cannot enter semantic payload")
	var self_transfer: Dictionary = fixture()
	self_transfer.to_id = "player"
	check(not Batch.normalize(self_transfer).ok, "source equals destination rejected")
	var extra_entry: Dictionary = fixture()
	extra_entry.entries[0].mass = 8
	check(not Batch.normalize(extra_entry).ok, "untrusted entry mass rejected")
	var blank_id: Dictionary = fixture()
	blank_id.entries[0].instance_id = ""
	check(not Batch.normalize(blank_id).ok, "empty instance identity rejected")
	var unknown_type: Dictionary = fixture()
	unknown_type.entries[0].quantity = "3"
	check(not Batch.normalize(unknown_type).ok, "string quantity rejected")
	check(not Batch.normalize({}).ok, "empty payload rejected")
	check(not Batch.normalize([]).ok, "wrong payload type rejected")
	var large: Dictionary = fixture()
	large.entries[0].quantity = Batch.MAX_EXACT_JSON_INT
	check(Batch.normalize(large).ok, "maximum exactly representable JSON integer quantity accepted")
	large.entries[0].quantity += 1
	check(not Batch.normalize(large).ok, "overflowing JSON integer quantity rejected")
	print("BATCH CONTRACT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
