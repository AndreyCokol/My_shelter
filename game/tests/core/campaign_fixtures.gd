extends RefCounted

static func rules() -> Dictionary:
	# Technical fixtures, not accepted product balance or literary content.
	return {"version": "test-v1", "minutes_per_real_second": 1.0, "discovery_xp": 5,
		"items": {"seed.basic": {}, "tool.basic": {}},
		"containers": [{"id": "player", "capacity_units": 20}, {"id": "storage", "capacity_units": 100}],
		"scenes": {"shelter": ["default"], "outside": ["default"]},
		"offers": {"seed": {"type_id": "seed.basic", "quantity": 2, "price": 3}},
		"parcels": {"starter": {"type_id": "seed.basic", "quantity": 3, "coins": 10, "eligible": true}},
		"rewards": {"first": {"type_id": "tool.basic", "quantity": 1, "hero_xp": 7, "eligible": true}, "locked": {"type_id": "tool.basic", "quantity": 1, "eligible": false}}}

