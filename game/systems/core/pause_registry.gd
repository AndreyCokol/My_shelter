extends RefCounted

var _tokens: Dictionary = {}
var _serial: int = 0

func acquire_pause(reason: String) -> int:
	_serial += 1
	_tokens[_serial] = reason
	return _serial

func release_pause(token: int) -> void:
	_tokens.erase(token)

func is_paused() -> bool:
	return not _tokens.is_empty()
