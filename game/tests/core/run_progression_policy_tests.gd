extends SceneTree
# A1-04 candidate-only regression. Test numbers are synthetic fixtures, not
# accepted balancing thresholds or an executable RPG progression system.
const Policy = preload("res://game/contracts/progression_policy_candidate.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS " + description)
	else:
		failures += 1
		push_error("FAIL " + description)

func run() -> void:
	var example: Dictionary = {"critical_level_gap": 5, "enemy_level_reduction": 2}
	var frozen: Dictionary = example.duplicate(true)
	check(Policy.valid_policy(example), "explicit synthetic test policy accepted")
	check(not Policy.valid_policy({}), "missing critical gap and reduction rejected")
	check(not Policy.valid_policy({"critical_level_gap": 5}), "missing reduction is not defaulted")
	check(not Policy.valid_policy({"enemy_level_reduction": 2}), "missing gap is not defaulted")
	check(not Policy.valid_policy({"critical_level_gap": 0, "enemy_level_reduction": 2}),
		"zero gap is not silently activated")
	check(not Policy.valid_policy({"critical_level_gap": -1, "enemy_level_reduction": 2}),
		"negative critical gap rejected")
	check(not Policy.valid_policy({"critical_level_gap": 5, "enemy_level_reduction": 0}),
		"zero enemy reduction rejected")
	check(not Policy.valid_policy({"critical_level_gap": 5, "enemy_level_reduction": 4}),
		"enemy reduction outside owner-approved 1..3 rejected")
	check(not Policy.valid_policy({"critical_level_gap": "five", "enemy_level_reduction": 2}),
		"string gap rejected")
	check(not Policy.valid_policy({"critical_level_gap": 5, "enemy_level_reduction": 1.5}),
		"fractional enemy levels rejected")
	var active: Dictionary = Policy.evaluate(7, 12, example)
	check(active.ok and active.active and active.hidden_xp_multiplier == 1.5,
		"critical lag uses owner-approved hidden +50 percent XP")
	check(active.enemy_level_reduction == 2 and active.world_level_cap == 12,
		"synthetic reduction remains configured and world cap remains authoritative")
	var boundary: Dictionary = Policy.evaluate(8, 12, example)
	check(boundary.ok and not boundary.active and boundary.hidden_xp_multiplier == 1.0,
		"one level short of critical gap cannot activate hidden assist")
	check(boundary.enemy_level_reduction == 0, "inactive assist does not weaken enemies")
	var equal: Dictionary = Policy.evaluate(12, 12, example)
	check(equal.ok and not equal.active, "equal hero and world level is not lag")
	var leading: Dictionary = Policy.evaluate(15, 12, example)
	check(leading.ok and not leading.active, "hero level ahead of world does not activate relief")
	var alternate: Dictionary = {"critical_level_gap": 3, "enemy_level_reduction": 1}
	var changed: Dictionary = Policy.evaluate(7, 12, alternate)
	check(changed.ok and changed.active and changed.enemy_level_reduction == 1,
		"policy values are injected, never taken from hidden hardcodes")
	check(example == frozen, "evaluation does not mutate caller policy")
	check(not Policy.evaluate(7, 12, {}).ok, "unconfigured runtime fails closed")
	check(not Policy.evaluate(-1, 12, example).ok, "negative hero level fails closed")
	check(not Policy.evaluate(7, -1, example).ok, "negative world level fails closed")
	check(Policy.can_spawn(12, 12), "enemy at world-level cap can spawn")
	check(not Policy.can_spawn(12, 13), "enemy above world-level cap cannot spawn")
	check(not Policy.can_spawn(-1, 0), "invalid world level cannot spawn enemies")
	check(Policy.extra_skill_slots(0) == 0, "no extra skill at level zero")
	check(Policy.extra_skill_slots(49) == 0, "no extra skill before level 50")
	check(Policy.extra_skill_slots(50) == 1, "one extra skill at level 50")
	check(Policy.extra_skill_slots(99) == 1, "no second extra skill before level 100")
	check(Policy.extra_skill_slots(100) == 2, "two extra skills at level 100")
	check(Policy.extra_skill_slots("50") == -1, "invalid level does not grant a skill")
	print("PROGRESSION POLICY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
