extends RefCounted

# A1-04 / G0 CANDIDATE ONLY. Pure computation; no save/UI/combat mutation.
# The owner approved the existence of a world-level spawn cap, a hidden
# +50% XP anti-lag bonus, 1..3 levels of enemy relief, and a skill every 50
# hero levels. The critical gap and relief amount remain REQUIRED parameters.
const MAX_EXACT_JSON_INT: int = 9007199254740991
const HIDDEN_XP_MULTIPLIER: float = 1.5
const EXTRA_SKILL_INTERVAL: int = 50

static func valid_level(value) -> bool:
	return value is int and value >= 0 and value <= MAX_EXACT_JSON_INT

static func valid_policy(policy) -> bool:
	if not policy is Dictionary:
		return false
	var gap = policy.get("critical_level_gap")
	var reduction = policy.get("enemy_level_reduction")
	return gap is int and gap > 0 and gap <= MAX_EXACT_JSON_INT and reduction is int and reduction >= 1 and reduction <= 3

static func can_spawn(world_level, enemy_level) -> bool:
	return valid_level(world_level) and valid_level(enemy_level) and enemy_level <= world_level

static func extra_skill_slots(hero_level) -> int:
	if not valid_level(hero_level):
		return -1
	return int(hero_level / EXTRA_SKILL_INTERVAL)

static func evaluate(hero_level, world_level, policy) -> Dictionary:
	if not valid_level(hero_level) or not valid_level(world_level) or not valid_policy(policy):
		return {"ok": false, "code": "INVALID_CONFIG"}
	var lag: int = maxi(0, int(world_level) - int(hero_level))
	var active: bool = lag >= int(policy.critical_level_gap)
	return {"ok": true, "active": active,
		"hidden_xp_multiplier": HIDDEN_XP_MULTIPLIER if active else 1.0,
		"enemy_level_reduction": int(policy.enemy_level_reduction) if active else 0,
		"world_level_cap": int(world_level),
		"extra_skill_slots": extra_skill_slots(hero_level)}
