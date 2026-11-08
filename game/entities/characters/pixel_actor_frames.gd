extends RefCounted

# ART-01 / CT-88: real 64x64 source pixel-art atlas frames, strictly top-down.
# The source images are original transparent 256x256 PNG sprite sheets:
# four columns = four time frames, four rows = down/left/up/right.
# Runtime scaling does NOT alter atlas pixel dimensions. Nearest filtering
# is enforced at the actor AnimatedSprite2D level, never interpolated.
const SURVIVOR_MOVE: Texture2D = preload("res://game/assets/project/characters/survivor_move_4dir_64.png")
const SURVIVOR_ATTACK: Texture2D = preload("res://game/assets/project/characters/survivor_attack_4dir_64.png")
const ZOMBIE_MOVE: Texture2D = preload("res://game/assets/project/characters/zombie_move_4dir_64.png")
const ZOMBIE_ATTACK: Texture2D = preload("res://game/assets/project/characters/zombie_attack_4dir_64.png")
const SOURCE_FRAME := 64
const DIRECTIONS: Array[String] = ["down", "left", "up", "right"]

static var _survivor: SpriteFrames
static var _zombie: SpriteFrames

static func frames(zombie: bool) -> SpriteFrames:
	if zombie and _zombie != null:
		return _zombie
	if not zombie and _survivor != null:
		return _survivor
	var collection := SpriteFrames.new()
	if collection.has_animation("default"):
		collection.remove_animation("default")
	var travel: Texture2D = ZOMBIE_MOVE if zombie else SURVIVOR_MOVE
	var melee: Texture2D = ZOMBIE_ATTACK if zombie else SURVIVOR_ATTACK
	for row in range(DIRECTIONS.size()):
		var direction: String = DIRECTIONS[row]
		for pose in ["idle", "walk", "attack"]:
			var animation: String = pose + "_" + direction
			collection.add_animation(animation)
			collection.set_animation_loop(animation, pose != "attack")
			collection.set_animation_speed(animation, 26.0 if pose == "attack" else 7.0)
			var atlas: Texture2D = melee if pose == "attack" else travel
			for column in range(1 if pose == "idle" else 4):
				var region := AtlasTexture.new()
				region.atlas = atlas
				region.region = Rect2(column * SOURCE_FRAME, row * SOURCE_FRAME,
					SOURCE_FRAME, SOURCE_FRAME)
				collection.add_frame(animation, region)
	if zombie:
		_zombie = collection
	else:
		_survivor = collection
	return collection

static func direction_name(value: Vector2) -> String:
	if absf(value.x) > absf(value.y):
		return "right" if value.x >= 0 else "left"
	return "down" if value.y >= 0 else "up"

static func valid_source_images() -> bool:
	for sheet in [SURVIVOR_MOVE, SURVIVOR_ATTACK, ZOMBIE_MOVE, ZOMBIE_ATTACK]:
		if sheet == null or sheet.get_size() != Vector2(256, 256):
			return false
		var image: Image = sheet.get_image()
		if image == null or image.get_size() != Vector2i(256, 256):
			return false
		if not image.detect_alpha():
			return false
	return true
