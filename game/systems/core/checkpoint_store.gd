extends RefCounted

const JsonNumbers = preload("res://game/state/json_numbers.gd")

# JSON checkpoint storage; schema validation is supplied by the active session.
var path: String
var fault: String = "" # Test seam; never exposed to player commands.

func _init(save_path: String = "user://saves/core-bootstrap.json") -> void:
	path = save_path

func read_checkpoint(source: String = "") -> Dictionary:
	var target := path if source.is_empty() else source
	if not FileAccess.file_exists(target):
		return {"ok": false, "code": "NOT_FOUND"}
	# Invalid JSON is an expected recovery case: use the error-returning
	# parser instead of parse_string(), which logs a Godot ERROR for damaged
	# player files even though this function correctly rejects the data.
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(target)) != OK:
		return {"ok": false, "code": "INVALID_STATE"}
	var parsed = parser.data
	if not parsed is Dictionary:
		return {"ok": false, "code": "INVALID_STATE"}
	return {"ok": true, "state": JsonNumbers.normalize_numbers(parsed)}

func write_checkpoint(state: Dictionary, validator: Callable) -> Dictionary:
	if fault == "before_replace" or not validator.call(state):
		return {"ok": false, "committed": false}
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return {"ok": false, "committed": false}
	if not _stage_checkpoint(state):
		return {"ok": false, "committed": false}
	# Preserve both durable files on every failure before primary replacement.
	# Copy the previous primary into a verified temporary backup, but DO NOT
	# publish it as .bak until the new primary has actually committed.
	var had_primary := FileAccess.file_exists(path)
	var backup_temporary := absolute + ".bak.tmp"
	if had_primary:
		var previous := read_checkpoint()
		if not previous.ok or not validator.call(previous.state):
			DirAccess.remove_absolute(absolute + ".tmp")
			return {"ok": false, "committed": false}
		if not _stage_backup(absolute, backup_temporary):
			if FileAccess.file_exists(backup_temporary):
				DirAccess.remove_absolute(backup_temporary)
			DirAccess.remove_absolute(absolute + ".tmp")
			return {"ok": false, "committed": false}
	var error := _replace_primary(absolute + ".tmp", absolute)
	if error != OK:
		DirAccess.remove_absolute(absolute + ".tmp")
		if had_primary and FileAccess.file_exists(backup_temporary):
			DirAccess.remove_absolute(backup_temporary)
		return {"ok": false, "committed": false}
	# Primary commit is now durable. If backup promotion fails, reporting
	# an uncommitted action would allow an already-persisted receipt/reward to
	# be retried against stale in-memory state. Keep the older valid .bak and
	# report success; the next successful save can refresh the backup.
	var backup_updated := true
	if had_primary:
		backup_updated = _replace_backup(backup_temporary, absolute + ".bak") == OK
		if not backup_updated and FileAccess.file_exists(backup_temporary):
			DirAccess.remove_absolute(backup_temporary)
	return {"ok": true, "committed": true, "recover": fault == "after_replace", "backup_updated": backup_updated}

func _stage_backup(source: String, temporary: String) -> bool:
	var expected := FileAccess.get_sha256(source)
	return not expected.is_empty() and DirAccess.copy_absolute(source, temporary) == OK and FileAccess.get_sha256(temporary) == expected

# Seams for deterministic filesystem error injection in isolated tests.
func _replace_primary(temporary: String, target: String) -> int:
	return DirAccess.rename_absolute(temporary, target)

func _replace_backup(temporary: String, target: String) -> int:
	return DirAccess.rename_absolute(temporary, target)

# Invoked only after user-selected backup has passed complete session validation.
func restore_checkpoint(state: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if not _stage_checkpoint(state):
		return false
	var archive := ""
	if FileAccess.file_exists(path):
		var prefix := absolute + ".rejected"
		archive = prefix
		var index := 1
		while FileAccess.file_exists(archive) or DirAccess.dir_exists_absolute(archive):
			archive = "%s.%d" % [prefix, index]
			index += 1
		if DirAccess.copy_absolute(absolute, archive) != OK:
			DirAccess.remove_absolute(absolute + ".tmp")
			return false
	if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		DirAccess.remove_absolute(absolute + ".tmp")
		if not archive.is_empty():
			DirAccess.remove_absolute(archive)
		return false
	return true

func _stage_checkpoint(state: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var serialized := JSON.stringify(state, "", true, true).to_utf8_buffer()
	file.store_buffer(serialized)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(temporary) != serialized:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	return true
