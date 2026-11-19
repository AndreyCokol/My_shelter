extends RefCounted

# A1/G0 CANDIDATE ONLY. Pure metadata validator, not yet wired into game
# rules, inventory, serialization, UI, or the current ruleset.
# The four tokens represent EXACTLY the four approved classes; they are not
# extra player-facing categories or new loot sources.
const SHELTER_OBJECT := "shelter_object"
const MATERIAL := "material"
const NON_SYSTEM := "non_system"
const SYSTEM_EQUIPMENT := "system_equipment"
const CATEGORIES := [SHELTER_OBJECT, MATERIAL, NON_SYSTEM, SYSTEM_EQUIPMENT]

static func categories() -> Array:
	return CATEGORIES.duplicate()

static func valid_category(value) -> bool:
	return value is String and CATEGORIES.has(value)

static func valid_metadata(value) -> bool:
	if not value is Dictionary:
		return false
	var category = value.get("category")
	if not valid_category(category):
		return false
	var is_equipment = value.get("is_equipment", false)
	if not is_equipment is bool:
		return false
	# A building, material or shelter object is never classified as
	# equipment, even when it has useful gameplay functionality.
	if category in [SHELTER_OBJECT, MATERIAL] and is_equipment:
		return false
	if category != SYSTEM_EQUIPMENT:
		# Rarity and quality belong to system EQUIPMENT only.
		return not value.has("rarity") and not value.has("quality_percent")
	if not is_equipment:
		return false
	var rarity = value.get("rarity")
	if not rarity is String or rarity.strip_edges().is_empty():
		return false
	# Quality only has meaning in the same record as its rarity.
	# No unapproved rarity tiers, item weights or migration defaults here.
	var quality = value.get("quality_percent")
	if not (quality is int or quality is float):
		return false
	return is_finite(float(quality)) and quality >= 0 and quality <= 100
