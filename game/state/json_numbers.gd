extends RefCounted

# Godot JSON decodes all numbers as floats. Restore exact integral values within
# JSON's safe range before DTO validation; fractional remainders stay floats.
static func normalize_numbers(value):
	if value is float and is_finite(value) and value == floor(value) and abs(value) <= 9007199254740991:
		return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = normalize_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(normalize_numbers(entry))
		return result
	return value
