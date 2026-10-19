class_name McpProtocol
extends RefCounted
## Transport-independent half of the runtime MCP server (ADR pending, plan
## "Part B — MCP server", cozy-plotting-dusk).
##
## Pure protocol plumbing for a streamable-HTTP JSON-RPC subset:
## `initialize`, `notifications/initialized`, `ping`, `tools/list`,
## `tools/call`. No SSE, no session ids, `Connection: close` per request —
## every request is answered on its own short-lived TCP connection.
##
## This file has ZERO socket/node/autoload dependencies so it is unit
## testable without opening a single port. Anything environment-dependent
## (which agents exist, what the diegetic tool descriptions say) is passed
## in by the caller (the future `mcp_server.gd` autoload) as arguments —
## nothing here reads GameState or Strings.
##
## Responsibilities, in the order they appear below:
##   1. HTTP request framing  — byte accumulator, header/body split,
##      Content-Length, agent_id extraction, method check.
##   2. JSON-RPC dispatch     — parse + route the five supported methods.
##   3. Tool surface          — diegetic name -> canonical verb, tool list,
##      input schemas mirroring ActionResolver/EmotionTags fields.
##   4. HTTP response building — status line + headers + JSON body bytes.


# ── Constants ────────────────────────────────────────────────────────────

## MCP protocol version this server implements. Pinned to a literal because
## there is no Godot-side MCP spec dependency to read it from; if a
## connecting gateway's MCP client negotiates a different version, that is
## a future mcp_server.gd / gateway-config concern, not this file's.
const PROTOCOL_VERSION: String = "2025-06-18"

const SERVER_NAME: String = "ai-avatars-mcp"
const SERVER_VERSION: String = "0.9.0"

## Protocol limit, not a gameplay tunable (see CLAUDE.md "no hardcoded
## values" — that rule targets gameplay tuning, not wire-protocol framing
## limits), so this stays a const rather than a game_config.json default.
## Sized to comfortably hold a tools/call payload (target/on/emotion
## deltas) with headroom; callers may pass a smaller value (tests do, to
## keep fixtures small).
const MAX_BODY_BYTES: int = 65536

## JSON-RPC 2.0 reserved error codes we emit. -32600/-32601/-32700 are the
## spec's own reserved codes; -32602 (Invalid params) is reused here for
## the "unknown tool" case, which is a params-shape failure on tools/call.
const ERROR_PARSE_ERROR: int = -32700
const ERROR_INVALID_REQUEST: int = -32600
const ERROR_METHOD_NOT_FOUND: int = -32601
const ERROR_INVALID_PARAMS: int = -32602

const HTTP_OK: int = 200
const HTTP_ACCEPTED: int = 202
const HTTP_METHOD_NOT_ALLOWED: int = 405
const HTTP_PAYLOAD_TOO_LARGE: int = 413

const HTTP_STATUS_TEXT: Dictionary = {
	200: "OK",
	202: "Accepted",
	404: "Not Found",
	405: "Method Not Allowed",
	413: "Payload Too Large",
}

## Diegetic tool name -> canonical verb. walk_toward/pick_up/use_item_on/
## apply_skill/call_out_to map onto ActionResolver.VERBS; emotion_update is
## its own transport for EmotionTags._apply_block's semantics (no puzzle
## verb — always auto-approved per the plan). Order is the order
## build_tools_list() emits them in.
const TOOL_NAMES: Array[String] = [
	"walk_toward",
	"pick_up",
	"use_item_on",
	"apply_skill",
	"call_out_to",
	"emotion_update",
]

const VERB_MAP: Dictionary = {
	"walk_toward": "go_to",
	"pick_up": "take",
	"use_item_on": "use_object",
	"apply_skill": "use_skill",
	"call_out_to": "call_agent",
	"emotion_update": "emotion_update",
}

## Compiled once at class load and reused by every accumulator scan —
## mirrors the ACTION_TAG_REGEX pattern in action_resolver.gd.
static var _HEADER_TERMINATOR: PackedByteArray = "\r\n\r\n".to_utf8_buffer()


## Outcome of a single accumulator parse attempt. INCOMPLETE means "keep
## feeding bytes"; COMPLETE means the request dict is ready; ERROR means
## the connection should be closed (malformed request or oversize body).
enum RequestParseStatus { INCOMPLETE, COMPLETE, ERROR }


# ── 1. HTTP request framing ─────────────────────────────────────────────

## Append `chunk` onto `existing_buffer` and attempt to parse a complete
## HTTP request out of the result. Callers (one per TCP connection) keep
## the returned "buffer" and pass it back in as `existing_buffer` on the
## next feed_bytes() call while status is INCOMPLETE.
##
## Returns a Dictionary always containing "status" (RequestParseStatus)
## and "buffer" (PackedByteArray, the grown buffer); on COMPLETE also
## "method"/"path"/"headers"/"body"; on ERROR also "error" (String reason).
static func feed_bytes(existing_buffer: PackedByteArray, chunk: PackedByteArray, max_body_bytes: int = MAX_BODY_BYTES) -> Dictionary:
	var buffer: PackedByteArray = existing_buffer.duplicate()
	buffer.append_array(chunk)
	var result: Dictionary = try_parse_http_request(buffer, max_body_bytes)
	result["buffer"] = buffer
	return result


## Pure (non-mutating) parse attempt over a full buffer. Used by
## feed_bytes() and directly testable on its own — no accumulator state
## needed when a fixture already has every byte in hand.
static func try_parse_http_request(buffer: PackedByteArray, max_body_bytes: int = MAX_BODY_BYTES) -> Dictionary:
	var header_end: int = _find_header_terminator(buffer)
	if header_end == -1:
		# Guard against an unbounded buffer when a client never sends a
		# terminator at all (broken client, or someone flooding the port).
		if buffer.size() > max_body_bytes:
			return {"status": RequestParseStatus.ERROR, "error": "headers exceeded max_body_bytes before a terminator was found"}
		return {"status": RequestParseStatus.INCOMPLETE}

	var header_text: String = buffer.slice(0, header_end).get_string_from_utf8()
	var head: Dictionary = _parse_header_block(header_text)
	if head.is_empty():
		return {"status": RequestParseStatus.ERROR, "error": "malformed request line"}

	var headers: Dictionary = head["headers"] as Dictionary
	var content_length: int = 0
	if headers.has("content-length"):
		var length_text: String = String(headers["content-length"])
		if not length_text.is_valid_int():
			return {"status": RequestParseStatus.ERROR, "error": "invalid Content-Length header"}
		content_length = length_text.to_int()
		if content_length < 0:
			return {"status": RequestParseStatus.ERROR, "error": "invalid Content-Length header"}

	if content_length > max_body_bytes:
		return {"status": RequestParseStatus.ERROR, "error": "body exceeds max_body_bytes"}

	var body_start: int = header_end + _HEADER_TERMINATOR.size()
	var available_body_bytes: int = buffer.size() - body_start
	if available_body_bytes < content_length:
		return {"status": RequestParseStatus.INCOMPLETE}

	# Sliced to exactly content_length — any trailing bytes beyond that
	# (there should never be any, since Connection: close means one
	# request per connection) are silently ignored, not treated as body.
	var body_bytes: PackedByteArray = buffer.slice(body_start, body_start + content_length)
	return {
		"status": RequestParseStatus.COMPLETE,
		"method": String(head["method"]),
		"path": String(head["path"]),
		"headers": headers,
		"body": body_bytes.get_string_from_utf8(),
	}


## True when the method is (case-insensitively) POST. Callers respond
## HTTP_METHOD_NOT_ALLOWED for anything else — this class never builds
## that response itself, since deciding whether to bother reading the
## body first is the caller's (mcp_server.gd's) call.
static func is_post(method: String) -> bool:
	return method.to_upper() == "POST"


## Requests are `POST /mcp/<agent_id>`. An `x-agent-id` header, when
## present and non-empty, overrides whatever the path says. Returns "" when
## neither source yields an id — the caller decides how to fail that.
static func extract_agent_id(path: String, headers: Dictionary) -> String:
	var override_raw: Variant = headers.get("x-agent-id")
	if override_raw != null:
		var override_value: String = String(override_raw).strip_edges()
		if not override_value.is_empty():
			return override_value

	var clean_path: String = path
	var query_index: int = clean_path.find("?")
	if query_index != -1:
		clean_path = clean_path.substr(0, query_index)

	var segments: PackedStringArray = clean_path.split("/", false)
	if segments.size() >= 2 and segments[0] == "mcp":
		return segments[1]
	return ""


# ── 2. JSON-RPC dispatch ────────────────────────────────────────────────

## Parse a raw JSON-RPC request body. Returns either
## {"ok": true, "id": Variant, "method": String, "params": Dictionary}
## or {"ok": false, "error": <jsonrpc error envelope>} when the body is not
## valid JSON, not a JSON object, or is missing a non-empty "method".
static func parse_jsonrpc(body_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "error": rpc_error(null, ERROR_PARSE_ERROR, "Parse error")}

	var msg: Dictionary = parsed as Dictionary
	var method_raw: Variant = msg.get("method")
	if not (method_raw is String) or String(method_raw).is_empty():
		return {"ok": false, "error": rpc_error(msg.get("id"), ERROR_INVALID_REQUEST, "Invalid Request: missing method")}

	var params_raw: Variant = msg.get("params", {})
	var params: Dictionary = params_raw as Dictionary if params_raw is Dictionary else {}
	return {"ok": true, "id": msg.get("id"), "method": String(method_raw), "params": params}


## Single entry point from a raw JSON-RPC body to "what should the HTTP
## response be". Returns a Dictionary with:
##   "http_status": int    — 200 for every JSON-RPC result/error envelope,
##                            202 for the notifications/initialized ack.
##   "body": Dictionary or null — the JSON-RPC envelope to serialize as the
##                            HTTP body, or null for the 202 ack and for a
##                            successfully parsed tools/call (see "call").
##   "call": Dictionary or null — populated only when method == "tools/call"
##                            parsed successfully: {tool_name, verb,
##                            arguments, request_id}. The caller
##                            (mcp_server.gd) dispatches this through
##                            ActionResolver and is responsible for
##                            eventually writing the HTTP response itself —
##                            this class never blocks or holds connection
##                            state.
##
## instructions        — fourth-wall-safe diegetic capability framing for
##                        initialize.result.instructions. Building that
##                        string is the caller's job (see class doc comment).
## tool_descriptions    — diegetic tool name -> description string, passed
##                        straight through to build_tools_list().
static func handle_jsonrpc(body_text: String, instructions: String = "", tool_descriptions: Dictionary = {}) -> Dictionary:
	var parsed: Dictionary = parse_jsonrpc(body_text)
	if not bool(parsed.get("ok", false)):
		return {"http_status": HTTP_OK, "body": parsed.get("error"), "call": null}

	var request_id: Variant = parsed.get("id")
	var method: String = String(parsed.get("method"))
	var params: Dictionary = parsed.get("params") as Dictionary

	match method:
		"initialize":
			return {"http_status": HTTP_OK, "body": build_initialize_response(request_id, instructions), "call": null}
		"notifications/initialized":
			return {"http_status": HTTP_ACCEPTED, "body": null, "call": null}
		"ping":
			return {"http_status": HTTP_OK, "body": build_ping_response(request_id), "call": null}
		"tools/list":
			return {"http_status": HTTP_OK, "body": build_tools_list_response(request_id, tool_descriptions), "call": null}
		"tools/call":
			var outcome: Dictionary = parse_tools_call(request_id, params)
			if bool(outcome.get("ok", false)):
				return {"http_status": HTTP_OK, "body": null, "call": outcome.get("call")}
			return {"http_status": HTTP_OK, "body": outcome.get("error"), "call": null}
		_:
			return {"http_status": HTTP_OK, "body": rpc_error(request_id, ERROR_METHOD_NOT_FOUND, "Method not found: %s" % method), "call": null}


static func build_initialize_response(request_id: Variant, instructions: String) -> Dictionary:
	return rpc_result(request_id, {
		"protocolVersion": PROTOCOL_VERSION,
		"capabilities": {"tools": {}},
		"serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
		"instructions": instructions,
	})


static func build_ping_response(request_id: Variant) -> Dictionary:
	return rpc_result(request_id, {})


static func build_tools_list_response(request_id: Variant, descriptions: Dictionary = {}) -> Dictionary:
	return rpc_result(request_id, {"tools": build_tools_list(descriptions)})


## Parses a tools/call params dict into a neutral dispatch shape (see
## handle_jsonrpc doc comment). Returns {"ok": true, "call": {...}} or
## {"ok": false, "error": <jsonrpc error envelope>} when "name" does not
## match a known tool.
static func parse_tools_call(request_id: Variant, params: Dictionary) -> Dictionary:
	var tool_name: String = String(params.get("name", ""))
	if not VERB_MAP.has(tool_name):
		return {"ok": false, "error": rpc_error(request_id, ERROR_INVALID_PARAMS, "Unknown tool: %s" % tool_name)}

	var arguments_raw: Variant = params.get("arguments", {})
	var arguments: Dictionary = arguments_raw as Dictionary if arguments_raw is Dictionary else {}
	var call: Dictionary = {
		"tool_name": tool_name,
		"verb": verb_for_tool(tool_name),
		"arguments": arguments,
		"request_id": request_id,
	}
	return {"ok": true, "call": call}


static func rpc_result(request_id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": _canonical_id(request_id), "result": result}


static func rpc_error(request_id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": _canonical_id(request_id), "error": {"code": code, "message": message}}


## JSON-RPC ids must be an integer, a string, or null — never a float.
## Godot's JSON.parse_string turns every JSON number into a float, so an
## id parsed off the wire as 0 arrives here as 0.0 and would be
## re-serialized as "0.0", which strict clients (the official MCP SDK's
## pydantic models) reject. Whole-valued floats collapse back to int;
## anything else passes through untouched.
static func _canonical_id(request_id: Variant) -> Variant:
	if request_id is float:
		var as_float: float = request_id
		if as_float == floorf(as_float):
			return int(as_float)
	return request_id


# ── 3. Tool surface ─────────────────────────────────────────────────────

## Canonical verb for a diegetic tool name, or "" when unknown.
static func verb_for_tool(tool_name: String) -> String:
	return String(VERB_MAP.get(tool_name, ""))


## Builds the tools/list array: all 6 tools, in TOOL_NAMES order, each with
## an inputSchema mirroring what ActionResolver.resolve()/EmotionTags
## actually read off the action dict.
##
## descriptions — diegetic tool name -> caller-supplied description string,
## reused verbatim from defaults.puzzle.action_tag_instructions phrasing
## upstream (see plan). Missing entries default to "" — this class never
## invents agent-facing prose of its own.
static func build_tools_list(descriptions: Dictionary = {}) -> Array[Dictionary]:
	var tools: Array[Dictionary] = []
	for tool_name: String in TOOL_NAMES:
		var verb: String = verb_for_tool(tool_name)
		tools.append({
			"name": tool_name,
			"description": String(descriptions.get(tool_name, "")),
			"inputSchema": _schema_for_verb(verb),
		})
	return tools


## go_to/take/call_agent take "target" only; use_object/use_skill also take
## "on" (ActionResolver._check_preconditions rejects both verbs when either
## is empty); emotion_update takes the three EmotionTags deltas + reason.
static func _schema_for_verb(verb: String) -> Dictionary:
	match verb:
		"go_to":
			return _target_schema("The place, thing, or agent to move toward.")
		"take":
			return _target_schema("The thing to take into your hands.")
		"call_agent":
			return _target_schema("The agent to call out to, by name.")
		"use_object":
			return _target_and_on_schema(
				"The item you are holding and pressing into use.",
				"The place, thing, or agent to use it on.")
		"use_skill":
			return _target_and_on_schema(
				"The skill you are bringing to bear.",
				"The place, thing, or agent to use it on.")
		"emotion_update":
			return _emotion_update_schema()
		_:
			return {}


static func _target_schema(target_description: String) -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"target": {"type": "string", "description": target_description},
		},
		"required": ["target"],
	}


static func _target_and_on_schema(target_description: String, on_description: String) -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"target": {"type": "string", "description": target_description},
			"on": {"type": "string", "description": on_description},
		},
		"required": ["target", "on"],
	}


## No "required" list: EmotionTags._apply_block treats a block with every
## delta at 0.0 as a silent no-op rather than a hard error, so nothing here
## is a mechanical precondition — "reason" is a convention, not a
## requirement, the same way the tag-based path only writes it when at
## least one delta is present.
static func _emotion_update_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"energy": {"type": "number", "minimum": -1.0, "maximum": 1.0, "description": "Delta to apply to energy, in [-1.0, 1.0]. Optional."},
			"patience": {"type": "number", "minimum": -1.0, "maximum": 1.0, "description": "Delta to apply to patience, in [-1.0, 1.0]. Optional."},
			"social_battery": {"type": "number", "minimum": -1.0, "maximum": 1.0, "description": "Delta to apply to social_battery, in [-1.0, 1.0]. Optional."},
			"reason": {"type": "string", "description": "Short plain reason for the shift. Convention: include this whenever any delta above is non-zero."},
		},
	}


# ── 4. HTTP response building ───────────────────────────────────────────

## Builds full raw HTTP/1.1 response bytes: status line, Content-Type,
## Content-Length, Connection: close, blank line, JSON body. Pass
## body_dict = null for an empty-body response (the notifications/
## initialized 202 ack, or a bare status like 405/413).
static func build_http_response(status_code: int, body_dict: Variant) -> PackedByteArray:
	var body_text: String = ""
	if body_dict != null:
		body_text = JSON.stringify(body_dict)
	var body_bytes: PackedByteArray = body_text.to_utf8_buffer()

	var status_text: String = String(HTTP_STATUS_TEXT.get(status_code, "Unknown"))
	var header_lines: PackedStringArray = PackedStringArray([
		"HTTP/1.1 %d %s" % [status_code, status_text],
		"Content-Type: application/json",
		"Content-Length: %d" % body_bytes.size(),
		"Connection: close",
		"",
		"",
	])
	var response: PackedByteArray = "\r\n".join(header_lines).to_utf8_buffer()
	response.append_array(body_bytes)
	return response


# ── Private helpers ──────────────────────────────────────────────────────

## Byte-level scan for the first "\r\n\r\n" in buffer. Deliberately not
## implemented via get_string_from_utf8().find(...) on the whole buffer —
## a partially-arrived body can split a multi-byte UTF-8 character, and we
## don't want that anywhere near the search for a pure-ASCII terminator.
static func _find_header_terminator(buffer: PackedByteArray) -> int:
	var needle_size: int = _HEADER_TERMINATOR.size()
	var limit: int = buffer.size() - needle_size
	for i: int in range(limit + 1):
		var found: bool = true
		for j: int in range(needle_size):
			if buffer[i + j] != _HEADER_TERMINATOR[j]:
				found = false
				break
		if found:
			return i
	return -1


## Parses the request line + header lines (everything before the \r\n\r\n
## terminator). Returns {} when the request line has fewer than 2
## space-separated tokens (no usable method/path). Header keys are
## lower-cased so callers never have to case-fold themselves.
static func _parse_header_block(header_text: String) -> Dictionary:
	var lines: PackedStringArray = header_text.split("\r\n")
	if lines.is_empty():
		return {}

	var request_parts: PackedStringArray = lines[0].split(" ", false)
	if request_parts.size() < 2:
		return {}

	var headers: Dictionary = {}
	for i: int in range(1, lines.size()):
		var line: String = lines[i]
		if line.strip_edges().is_empty():
			continue
		var colon_index: int = line.find(":")
		if colon_index == -1:
			continue
		var key: String = line.substr(0, colon_index).strip_edges().to_lower()
		var value: String = line.substr(colon_index + 1).strip_edges()
		headers[key] = value

	return {
		"method": request_parts[0],
		"path": request_parts[1],
		"headers": headers,
	}
