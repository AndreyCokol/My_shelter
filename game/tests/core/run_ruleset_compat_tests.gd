extends SceneTree

# Standalone regression for Issue #34: changing ruleset_version is NOT a
# supported silent migration. Reject without mutating the old checkpoint.
# Run: godot --headless --path . --script res://game/tests/core/run_ruleset_compat_tests.gd

const Rules = preload("res://game/data/game_rules.gd")
const Campaign = preload("res://game/systems/core/campaign_session.gd")
const Store = preload("res://game/systems/core/checkpoint_store.gd")
var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1
		push_error(description)

func save_request(session, action_id: String) -> Dictionary:
	var snapshot: Dictionary = session.get_snapshot()
	var revisions: Array = []
	for key in snapshot.resource_revisions:
		revisions.append({"key": key, "revision": snapshot.resource_revisions[key]})
	return {"action_id": action_id, "command_type": "session.save", "payload": {},
		"context": {"actor_id": "player", "scene_id": snapshot.scene.current_scene_id,
			"expected_resource_revisions": revisions}}

func _initialize() -> void:
	var base_rules: Dictionary = Rules.build()
	var changed_rules: Dictionary = base_rules.duplicate(true)
	changed_rules.version = "prototype-v2-test"
	changed_rules.crop.grow_minutes = 240
	changed_rules.crop.spoil_minutes = 150
	check(Campaign.valid_rules(base_rules) and Campaign.valid_rules(changed_rules),
		"both old and changed catalogs are individually valid")
	var old_campaign = Campaign.new(base_rules)
	var old_session = old_campaign.coordinator
	var pathname := "user://ruleset-compat/" + str(Time.get_ticks_usec()) + ".json"
	var store = Store.new(pathname)
	var saved: Dictionary = old_session.execute(save_request(old_session, "initial-save"), store)
	check(saved.get("ok", false), "old campaign creates durable checkpoint")
	var original_bytes := FileAccess.get_file_as_string(pathname)
	var original_state: Dictionary = old_session.get_snapshot()
	check(not original_bytes.is_empty() and store.read_checkpoint().get("ok", false),
		"old primary checkpoint readable before migration attempt")

	var new_campaign = Campaign.new(changed_rules)
	var new_session = new_campaign.coordinator
	var unchanged_new: Dictionary = new_session.get_snapshot()
	var attempted: Dictionary = new_session.load_checkpoint(store)
	check(not attempted.get("ok", false) and new_session.get_snapshot() == unchanged_new,
		"new ruleset does not silently accept incompatible old save")
	check(FileAccess.get_file_as_string(pathname) == original_bytes,
		"failed incompatible load leaves primary checkpoint byte-identical")
	check(not FileAccess.file_exists(pathname + ".rejected"),
		"rejected checkpoint is not created by read-only incompatible load")

	var recovered = Campaign.new(base_rules).coordinator
	check(recovered.load_checkpoint(store).get("ok", false) and recovered.get_snapshot() == original_state,
		"old ruleset can still load the original save after rejection")
	for suffix in ["", ".tmp", ".bak", ".rejected"]:
		var target := ProjectSettings.globalize_path(pathname + suffix)
		if FileAccess.file_exists(pathname + suffix):
			DirAccess.remove_absolute(target)
	print("RULESET TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
