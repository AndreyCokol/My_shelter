extends RefCounted

# P0 combat loadout is derived solely from persisted campaign state and the
# current rules catalog. A view cannot equip/forge a weapon by editing UI state.
# Existing schema-v4 saves without equipped_weapon_instance_id are unarmed.
static func profile(state: Dictionary, rules: Dictionary) -> Dictionary:
	var balance: Dictionary = rules.get("combat", {})
	var unarmed: Dictionary = balance.get("unarmed", {"damage": 25, "reach": 64.0, "cooldown": 0.45})
	var chosen: Dictionary = unarmed
	var equipped_id: String = str(state.player.get("equipped_weapon_instance_id", ""))
	var active_type := ""
	if not equipped_id.is_empty():
		var weapons: Dictionary = balance.get("weapons", {})
		for item in state.inventory.items:
			if item.get("instance_id") != equipped_id or item.get("container_id") != "player" or int(item.get("quantity", 0)) <= 0:
				continue
			if weapons.has(item.type_id):
				chosen = weapons[item.type_id]
				active_type = item.type_id
			break
	var experience: int = maxi(0, int(state.player.get("xp", 0)))
	var step: int = maxi(1, int(balance.get("xp_per_bonus", 10)))
	var cap: int = maxi(0, int(balance.get("max_bonus", 5)))
	var bonus: int = mini(cap, experience / step)
	return {"weapon_type_id": active_type, "weapon_instance_id": equipped_id if not active_type.is_empty() else "",
		"damage": int(chosen.damage) + bonus, "reach": float(chosen.reach),
		"cooldown": float(chosen.cooldown), "experience_bonus": bonus}

static func valid_catalog(rules: Dictionary) -> bool:
	if not rules.get("combat") is Dictionary:
		return false
	var combat: Dictionary = rules.combat
	if not combat.get("unarmed") is Dictionary or not combat.get("weapons") is Dictionary:
		return false
	for field in ["xp_per_bonus", "max_bonus"]:
		if not combat.get(field) is int or combat[field] < (1 if field == "xp_per_bonus" else 0) or combat[field] > 100:
			return false
	if not valid_profile(combat.unarmed):
		return false
	for type_id in combat.weapons:
		if not rules.items.has(type_id) or not valid_profile(combat.weapons[type_id]):
			return false
	return true

static func valid_profile(value) -> bool:
	if not value is Dictionary:
		return false
	if not value.get("damage") is int or value.damage <= 0 or value.damage > 1000:
		return false
	for field in ["reach", "cooldown"]:
		var number = value.get(field)
		if not (number is float or number is int) or not is_finite(float(number)) or number <= 0:
			return false
	return value.reach <= 250 and value.cooldown <= 10.0

# The authoritative item must be a specific owned bag instance, not any stack
# of the same type in storage. Empty string means the safe unarmed state.
static func valid_equipment(state: Dictionary, rules: Dictionary) -> bool:
	var id = state.player.get("equipped_weapon_instance_id", "")
	if not id is String:
		return false
	if id.is_empty():
		return true
	var weapons: Dictionary = rules.get("combat", {}).get("weapons", {})
	for item in state.inventory.items:
		if item.get("instance_id") == id:
			return item.get("container_id") == "player" and weapons.has(item.get("type_id")) and int(item.get("quantity", 0)) > 0
	return false
