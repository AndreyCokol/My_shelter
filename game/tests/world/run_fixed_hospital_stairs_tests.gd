extends SceneTree
## A2-03: test the actual, pure staircase arrival contract without touching A1.
const Stairs = preload("res://game/systems/world/fixed_hospital_stairs.gd")
const Fixed = preload("res://game/systems/world/fixed_start_hospital.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
const Plans = preload("res://game/systems/world/building_plan.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + title)

func _run() -> void:
	var floor_ids := ["hospital", "hospital_0_2", "hospital_0_3", "hospital_0_4"]

	for floor in range(1, 5):
		check(Stairs.floor_number(floor_ids[floor - 1]) == floor,
			"floor %d maps to canonical historical scene ID" % floor)

	for floor in range(1, 4):
		var source_scene: String = floor_ids[floor - 1]
		var up: Dictionary = Stairs.stairs_transition(source_scene, "up")
		check(up.ok and up.source_floor == floor and up.target_floor == floor + 1,
			"floor %d ascends to the next floor only" % floor)
		check(up.ok and up.source_scene == source_scene and up.target_scene == floor_ids[floor],
			"floor %d ascent has exact source and target IDs" % floor)
		check(up.ok and up.source_position.is_equal_approx(up.target_position),
			"floor %d ascent has no unreviewed coordinate jump" % floor)

		var source_plan: Dictionary = Fixed.plan_for_floor(floor)
		var target_plan: Dictionary = Fixed.plan_for_floor(floor + 1)
		check(Plans.valid(source_plan) and Plans.valid(target_plan)
			and up.source_position == source_plan.stairs_up
			and up.target_position == target_plan.stairs_down,
			"floor %d up transition points to the actual configured stair anchors" % floor)
		check(up.ok and up.target_is_roof == (floor == 3),
			"floor %d roof metadata only true for 3 -> 4" % floor)

		var down: Dictionary = Stairs.stairs_transition(floor_ids[floor], "down")
		check(down.ok and down.source_floor == floor + 1 and down.target_floor == floor,
			"floor %d down transition reverses the floor pair" % (floor + 1))
		check(down.ok and down.target_scene == source_scene and down.source_scene == up.target_scene,
			"floor %d descending targets the original scene ID" % (floor + 1))
		check(down.ok and down.source_position == up.target_position and down.target_position == up.source_position,
			"floor %d down transition exactly reverses physical stair anchors" % (floor + 1))
		check(up == Stairs.stairs_transition(source_scene, "up")
			and down == Stairs.stairs_transition(floor_ids[floor], "down"),
			"floor %d staircase plans remain deterministic" % floor)

	check(Stairs.stairs_transition("hospital", "down").code == "NO_STAIR_CONNECTION",
		"first floor rejects a non-existent basement stair")
	check(Stairs.stairs_transition("hospital_0_4", "up").code == "NO_STAIR_CONNECTION",
		"open roof rejects a non-existent fifth floor")
	check(Stairs.stairs_transition("hospital_0_3", "sideways").code == "INVALID_DIRECTION",
		"unrecognized direction rejected without side effects")
	check(Stairs.stairs_transition("outside", "up").code == "UNKNOWN_SCENE",
		"world street is not a hospital stair entrance")
	check(Stairs.stairs_transition("", "down").code == "UNKNOWN_SCENE",
		"empty scene ID rejected without side effects")

	# All historic generator layouts must keep these scene identifiers even
	# though new starter plans are not installed into v4/v5 old campaigns.
	for seed_value in [0, 42, 127]:
		for version in [4, 5]:
			var historical: Dictionary = Layout.build(seed_value, version)
			var preserved := true
			for identifier in floor_ids:
				preserved = preserved and historical.has(identifier)
			check(preserved,
				"old v%d seed %d still provides all four scene IDs" % [version, seed_value])

	# Caller cannot mutate the fixed plan through a returned stair contract.
	var before: Dictionary = Stairs.stairs_transition("hospital_0_3", "up")
	var damaged := before.duplicate(true)
	damaged["target_scene"] = "outside"
	damaged["target_position"] = Vector2(-1000, -1000)
	check(Stairs.stairs_transition("hospital_0_3", "up") == before,
		"external modifications to transition result cannot poison subsequent routes")

	print("A2 FIXED STAIR TRANSITION TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
