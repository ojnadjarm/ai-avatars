class_name LLMRequestQueue
extends RefCounted
## Opaque-id request tracker for LLM calls. Each register() binds a callable
## to a unique id; the LLM client's response signal routes back through
## dispatch(id, text). Lets callers encode their own context into the
## closure at send time instead of parsing anything out of the id string.

var _pending: Dictionary = {}
var _next_id: int = 0


func register(handler: Callable) -> String:
	_next_id += 1
	var req_id := "req:%d" % _next_id
	_pending[req_id] = handler
	return req_id


func dispatch(request_id: String, text: String) -> void:
	var handler: Callable = _pending.get(request_id, Callable())
	_pending.erase(request_id)
	if handler.is_valid():
		handler.call(text)
