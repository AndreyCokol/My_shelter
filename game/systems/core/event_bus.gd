extends RefCounted

# Delivery dedup is only a bounded in-memory convenience. Persistent receipts in
# CoreSession, not this cache, ensure one-time domain changes across reloads.
const MAX_RECENT_EVENT_IDS := 4096

var _subscriptions: Dictionary = {}
var _seen: Dictionary = {}
var _seen_order: Array[String] = []
var _seen_offset: int = 0
var _serial: int = 0
var _dispatching: bool = false

# Stable bound owner methods are recommended; repeat registration is idempotent.
func subscribe(owner: Object, callback: Callable, event_types: Array = []) -> int:
	if not is_instance_valid(owner) or not callback.is_valid() or callback.get_object() != owner:
		return 0
	var types: Array = []
	for type in event_types:
		if not (type is String or type is StringName) or str(type).is_empty():
			return 0
		if not str(type) in types:
			types.append(str(type))
	types.sort()
	_prune()
	for token in _subscriptions:
		var sub: Dictionary = _subscriptions[token]
		if sub.owner.get_ref() == owner and sub.callback == callback and sub.types == types:
			return token
	_serial += 1
	_subscriptions[_serial] = {"owner": weakref(owner), "callback": callback, "types": types}
	return _serial

func unsubscribe(token: int) -> void:
	_subscriptions.erase(token)

func unsubscribe_owner(owner: Object) -> void:
	for token in _subscriptions.keys():
		if _subscriptions[token].owner.get_ref() == owner:
			_subscriptions.erase(token)

func subscription_count() -> int:
	_prune()
	return _subscriptions.size()

# CoreSession is the publisher. Subscribers cannot recursively publish facts.
func publish_after_commit(event: Dictionary) -> bool:
	if _dispatching or not valid_event(event) or _seen.has(event.event_id):
		return false
	_seen[event.event_id] = true
	_seen_order.append(event.event_id)
	if _seen_order.size() - _seen_offset > MAX_RECENT_EVENT_IDS:
		_seen.erase(_seen_order[_seen_offset])
		_seen_offset += 1
		# Periodic compaction bounds array memory without O(window) work per event.
		if _seen_offset >= MAX_RECENT_EVENT_IDS:
			_seen_order = _seen_order.slice(_seen_offset)
			_seen_offset = 0
	_dispatching = true
	_prune()
	# Fixed delivery list: new subscriptions start with the next event.
	for token in _subscriptions.keys():
		if not _subscriptions.has(token):
			continue
		var sub: Dictionary = _subscriptions[token]
		if not _alive(sub):
			_subscriptions.erase(token)
			continue
		if sub.types.is_empty() or event.event_type in sub.types:
			var delivery := event.duplicate(true)
			delivery.event_type = str(delivery.event_type)
			sub.callback.call(delivery)
	_dispatching = false
	return true

# Loading invalidates transient delivery history, but keeps live UI subscriptions.
# State/receipts, not this in-memory set, guarantee domain idempotency.
func reset_history() -> void:
	_seen.clear()
	_seen_order.clear()
	_seen_offset = 0

func _prune() -> void:
	for token in _subscriptions.keys():
		if not _alive(_subscriptions[token]):
			_subscriptions.erase(token)

static func _alive(sub: Dictionary) -> bool:
	var owner = sub.owner.get_ref()
	return is_instance_valid(owner) and sub.callback.is_valid() and not (owner is Node and owner.is_queued_for_deletion())

static func valid_event(event: Dictionary) -> bool:
	if not (event.get("event_type") is String or event.get("event_type") is StringName) or str(event.event_type).is_empty():
		return false
	for key in ["event_id", "action_id"]:
		if not event.get(key) is String or event[key].is_empty():
			return false
	for key in ["game_minute", "state_revision"]:
		var number = event.get(key)
		if not (number is int or number is float) or not is_finite(number) or number != floor(number) or number < 0 or number > 9007199254740991:
			return false
	return event.get("payload") is Dictionary
