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
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(target))
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
	# Keep the last validated primary; never overwrite it with corrupt input.
	if FileAccess.file_exists(path):
		var previous := read_checkpoint()
		if not previous.ok or not validator.call(previous.state):
			DirAccess.remove_absolute(absolute + ".tmp")
			return {"ok": false, "committed": false}
		# Keep the previous backup intact until its replacement has been verified.
		var backup_temporary := absolute + ".bak.tmp"
		if not _stage_backup(absolute, backup_temporary) or DirAccess.rename_absolute(backup_temporary, absolute + ".bak") != OK:
			if FileAccess.file_exists(backup_temporary):
				DirAccess.remove_absolute(backup_temporary)
			DirAccess.remove_absolute(absolute + ".tmp")
			return {"ok": false, "committed": false}
	var error := DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if error != OK:
		DirAccess.remove_absolute(absolute + ".tmp")
		return {"ok": false, "committed": false}
	return {"ok": true, "committed": true, "recover": fault == "after_replace"}

func _stage_backup(source: String, temporary: String) -> bool:
	var expected := FileAccess.get_sha256(source)
	return not expected.is_empty() and DirAccess.copy_absolute(source, temporary) == OK and FileAccess.get_sha256(temporary) == expected

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
