extends RefCounted

# A3 fragment render selection only. This is NOT a persisted fragment model.
# Candidate helper for the owner-approved 3x3 maximum display window.
# No mutation of occupancy, economy, save state, GameClock, NPCs or scenes.
const MAX_VISIBLE := 9

# Return a stable centre-first listing of existing fragments within distance 1
# on BOTH world-grid axes. An absent centre is an invalid view and renders none.
# Diagonal visibility does not imply diagonal traversal or connectivity.
static func visible_window(occupied: Array[Vector2i], center: Vector2i) -> Array[Vector2i]:
    var membership: Dictionary = {}
    for cell in occupied:
        membership[cell] = true
    var result: Array[Vector2i] = []
    if not membership.has(center):
        return result
    result.append(center)
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            if dx == 0 and dy == 0:
                continue
            # GDScript int is 64-bit; validate before narrowing to Vector2i.
            var nx: int = int(center.x) + dx
            var ny: int = int(center.y) + dy
            if nx < -2147483648 or nx > 2147483647 or ny < -2147483648 or ny > 2147483647:
                continue
            var neighbor := Vector2i(nx, ny)
            if membership.has(neighbor):
                result.append(neighbor)
    return result

static func contains_coordinate(window: Array[Vector2i], coordinate: Vector2i) -> bool:
    return coordinate in window
