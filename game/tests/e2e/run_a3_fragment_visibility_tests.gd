extends SceneTree

# A3 code candidate: contract tests for rendering at most nine spatial fragments.
# NOT a Godot GUI test, economy/offscreen simulation test, or save-migration test.
const Visibility = preload("res://game/systems/shelter/fragment_visibility.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
    checks += 1
    print(("PASS " if condition else "FAIL ") + label)
    if not condition:
        failures += 1
        push_error(label)

func make_square(center: Vector2i, radius: int) -> Array[Vector2i]:
    var occupied: Array[Vector2i] = []
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            occupied.append(Vector2i(center.x + dx, center.y + dy))
    return occupied

func _initialize() -> void:
    var center := Vector2i(0, 0)
    var single: Array[Vector2i] = [center]
    var single_window: Array[Vector2i] = Visibility.visible_window(single, center)
    check(single_window == single, "one existing central fragment stays visible")

    var full: Array[Vector2i] = make_square(center, 1)
    var first: Array[Vector2i] = Visibility.visible_window(full, center)
    check(Visibility.MAX_VISIBLE == 9 and first.size() == 9 and first[0] == center,
        "full 3x3 neighbourhood shows exactly nine including centre")
    check(first == Visibility.visible_window(full, center),
        "same occupancy and centre yield deterministic order")

    var wide: Array[Vector2i] = make_square(center, 2)
    var before: Array[Vector2i] = wide.duplicate()
    var selected: Array[Vector2i] = Visibility.visible_window(wide, center)
    check(wide == before and wide.size() == 25 and selected.size() == 9,
        "render window does not mutate offscreen occupancy or exceed nine")
    check(not Visibility.contains_coordinate(selected, Vector2i(2, 0)),
        "distant fragment stays out of render set but remains in source")

    var reversed: Array[Vector2i] = wide.duplicate()
    reversed.reverse()
    check(Visibility.visible_window(reversed, center) == selected,
        "render output independent of occupancy insertion order")

    wide.append(center)
    wide.append(Vector2i(1, 0))
    check(Visibility.visible_window(wide, center).size() == 9,
        "duplicate occupancy coordinates never duplicate rendered fragments")

    var absent: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
    check(Visibility.visible_window(absent, center).is_empty(),
        "missing centre never fabricates a virtual fragment")

    var shifted_center := Vector2i(-4, 7)
    var shifted: Array[Vector2i] = make_square(shifted_center, 2)
    var shifted_visible: Array[Vector2i] = Visibility.visible_window(shifted, shifted_center)
    check(shifted_visible.size() == 9 and shifted_visible[0] == shifted_center
        and not Visibility.contains_coordinate(shifted_visible, shifted_center + Vector2i(2, 0)),
        "negative and nonzero grid coordinates work without hardcoded origin")

    var empty: Array[Vector2i] = []
    check(Visibility.visible_window(empty, center).is_empty(),
        "empty shelter occupancy yields empty render set")

    print("A3 FRAGMENT VISIBILITY TESTS: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)
