extends RefCounted

# Internal G1a schema, intentionally separate from the full campaign schema.
var path: String
var fault: String = "" # Test seam; never exposed to player commands.

func _init(save_path: String = "user://saves/core-bootstrap.json") -> void:
	path = save_path

func read_checkpoint(source: String = "") -> Dictionary:
	var target := path if source.is_empty() else source
	if not FileAccess.file_exists(target):
		return {"ok": false, "code": "NOT_FOUND"}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(target))
	if not parsed is Dictionary:
		return {"ok": false, "code": "INVALID_STATE"}
	return {"ok": true, "state": normalize_numbers(parsed)}

func write_checkpoint(state: Dictionary, validator: Callable) -> Dictionary:
	if fault == "before_replace":
		return {"ok": false, "committed": false}
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return {"ok": false, "committed": false}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "committed": false}
	file.store_string(JSON.stringify(state))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not read_checkpoint(path + ".tmp").ok:
		return {"ok": false, "committed": false}
	# Keep the last validated primary; never overwrite it with corrupt input.
	if FileAccess.file_exists(path):
		var previous := read_checkpoint()
		if not previous.ok or not validator.call(previous.state):
			return {"ok": false, "committed": false}
		if DirAccess.copy_absolute(absolute, absolute + ".bak") != OK:
			return {"ok": false, "committed": false}
	var error := DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if error != OK:
		return {"ok": false, "committed": false}
	return {"ok": true, "committed": true, "recover": fault == "after_replace"}

# Invoked only after user-selected backup has passed complete session validation.
func restore_checkpoint(state: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or not read_checkpoint(path + ".tmp").ok:
		return false
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(absolute, absolute + ".rejected") != OK:
			return false
	return DirAccess.rename_absolute(absolute + ".tmp", absolute) == OK

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
