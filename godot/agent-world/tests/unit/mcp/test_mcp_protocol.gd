class_name TestMcpProtocol
extends RefCounted
## Unit tests for McpProtocol — the transport-independent half of the
## runtime MCP server (plan "Part B — MCP server",
## cozy-plotting-dusk).
##
## McpProtocol is pure static with zero socket/node/autoload dependencies,
## so every fixture here is built in memory: raw request bytes assembled by
## hand, JSON-RPC bodies built with JSON.stringify. No sockets, no scene
## tree, no GameState.

var failure_message: String = ""


func run() -> bool:
	# --- HTTP request framing ---
	if not _test_feed_bytes_header_split_across_three_chunks_completes():
		return false
	if not _test_try_parse_http_request_content_length_honored_trailing_bytes_ignored_and_incomplete_detected():
		return false
	if not _test_extract_agent_id_from_path_returns_id():
		return false
	if not _test_extract_agent_id_x_agent_id_header_overrides_path():
		return false
	if not _test_non_post_method_maps_to_405():
		return false
	if not _test_try_parse_http_request_oversize_body_rejected():
		return false

	# --- JSON-RPC methods ---
	if not _test_build_initialize_response_shape_and_instructions_passthrough():
		return false
	if not _test_handle_jsonrpc_notifications_initialized_returns_202_with_empty_body():
		return false
	if not _test_rpc_envelopes_collapse_float_ids_to_int():
		return false
	if not _test_handle_jsonrpc_ping_returns_empty_result():
		return false
	if not _test_parse_tools_call_happy_path_returns_neutral_dict():
		return false
	if not _test_parse_tools_call_unknown_tool_returns_error():
		return false
	if not _test_handle_jsonrpc_tools_call_populates_neutral_call_dict():
		return false
	if not _test_parse_jsonrpc_malformed_json_returns_parse_error():
		return false
	if not _test_parse_jsonrpc_missing_method_returns_invalid_request():
		return false
	if not _test_handle_jsonrpc_unknown_method_returns_error():
		return false

	# --- Tool surface ---
	if not _test_build_tools_list_contains_all_six_tools_with_schemas():
		return false
	if not _test_verb_for_tool_maps_every_diegetic_name():
		return false

	# --- HTTP response building ---
	if not _test_build_http_response_emits_status_line_content_length_and_connection_close():
		return false

	return true


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


# ── HTTP request framing ─────────────────────────────────────────────────

func _test_feed_bytes_header_split_across_three_chunks_completes() -> bool:
	## A single request arrives across three TCP chunks, with the split
	## points landing mid-header and mid-body — the accumulator must report
	## INCOMPLETE for the first two feeds and COMPLETE (with the right
	## method/path/body) once the last fragment lands.
	# Arrange
	var body_dict: Dictionary = {"jsonrpc": "2.0", "id": 1, "method": "ping", "params": {}}
	var body_text: String = JSON.stringify(body_dict)
	var body_bytes: PackedByteArray = body_text.to_utf8_buffer()
	var header_text: String = "POST /mcp/luna HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % body_bytes.size()
	var header_bytes: PackedByteArray = header_text.to_utf8_buffer()
	var full_bytes: PackedByteArray = header_bytes.duplicate()
	full_bytes.append_array(body_bytes)

	var header_len: int = header_bytes.size()
	var point1: int = header_len / 2
	var point2: int = header_len + (body_bytes.size() / 2)

	var frag1: PackedByteArray = full_bytes.slice(0, point1)
	var frag2: PackedByteArray = full_bytes.slice(point1, point2)
	var frag3: PackedByteArray = full_bytes.slice(point2, full_bytes.size())

	# Act
	var buf: PackedByteArray = PackedByteArray()
	var r1: Dictionary = McpProtocol.feed_bytes(buf, frag1)
	if r1.get("status") != McpProtocol.RequestParseStatus.INCOMPLETE:
		return _fail("3-chunk split: expected INCOMPLETE after fragment 1 (mid-header), got %s" % str(r1.get("status")))
	buf = r1["buffer"] as PackedByteArray

	var r2: Dictionary = McpProtocol.feed_bytes(buf, frag2)
	if r2.get("status") != McpProtocol.RequestParseStatus.INCOMPLETE:
		return _fail("3-chunk split: expected INCOMPLETE after fragment 2 (mid-body), got %s" % str(r2.get("status")))
	buf = r2["buffer"] as PackedByteArray

	var r3: Dictionary = McpProtocol.feed_bytes(buf, frag3)

	# Assert
	if r3.get("status") != McpProtocol.RequestParseStatus.COMPLETE:
		return _fail("3-chunk split: expected COMPLETE after fragment 3, got %s" % str(r3.get("status")))
	if String(r3.get("method")) != "POST":
		return _fail("3-chunk split: method mismatch, got '%s'" % String(r3.get("method")))
	if String(r3.get("path")) != "/mcp/luna":
		return _fail("3-chunk split: path mismatch, got '%s'" % String(r3.get("path")))
	if String(r3.get("body")) != body_text:
		return _fail("3-chunk split: body mismatch, got '%s'" % String(r3.get("body")))
	return true


func _test_try_parse_http_request_content_length_honored_trailing_bytes_ignored_and_incomplete_detected() -> bool:
	## Content-Length is the sole authority on where the body ends: bytes
	## past it are ignored (there is no pipelining in this subset — every
	## connection is Connection: close), and a body shorter than declared
	## must report INCOMPLETE rather than guessing it is done.
	# Arrange
	var body_dict: Dictionary = {"jsonrpc": "2.0", "id": 2, "method": "ping", "params": {}}
	var body_text: String = JSON.stringify(body_dict)
	var body_bytes: PackedByteArray = body_text.to_utf8_buffer()
	var header_text: String = "POST /mcp/grok HTTP/1.1\r\nContent-Length: %d\r\n\r\n" % body_bytes.size()
	var header_bytes: PackedByteArray = header_text.to_utf8_buffer()

	# Act — full body plus trailing junk beyond Content-Length
	var full_with_trailing: PackedByteArray = header_bytes.duplicate()
	full_with_trailing.append_array(body_bytes)
	full_with_trailing.append_array("EXTRA-JUNK-AFTER-BODY".to_utf8_buffer())
	var complete_result: Dictionary = McpProtocol.try_parse_http_request(full_with_trailing)

	# Assert — COMPLETE, and body stops exactly at Content-Length
	if complete_result.get("status") != McpProtocol.RequestParseStatus.COMPLETE:
		return _fail("content-length: expected COMPLETE with trailing bytes present, got %s" % str(complete_result.get("status")))
	if String(complete_result.get("body")) != body_text:
		return _fail("content-length: body should stop exactly at Content-Length, got '%s'" % String(complete_result.get("body")))

	# Act — only half the declared body has arrived
	var partial: PackedByteArray = header_bytes.duplicate()
	partial.append_array(body_bytes.slice(0, body_bytes.size() / 2))
	var partial_result: Dictionary = McpProtocol.try_parse_http_request(partial)

	# Assert — INCOMPLETE, not COMPLETE or ERROR
	if partial_result.get("status") != McpProtocol.RequestParseStatus.INCOMPLETE:
		return _fail("content-length: expected INCOMPLETE with a partial body, got %s" % str(partial_result.get("status")))
	return true


func _test_extract_agent_id_from_path_returns_id() -> bool:
	# Arrange / Act / Assert
	if McpProtocol.extract_agent_id("/mcp/luna", {}) != "luna":
		return _fail("agent_id: plain path did not resolve to 'luna'")
	if McpProtocol.extract_agent_id("/mcp/darksaddler?x=1", {}) != "darksaddler":
		return _fail("agent_id: a query string should be stripped before extracting the id")
	if McpProtocol.extract_agent_id("/", {}) != "":
		return _fail("agent_id: a path with no agent segment should return ''")
	return true


func _test_extract_agent_id_x_agent_id_header_overrides_path() -> bool:
	# Arrange
	var headers_with_override: Dictionary = {"x-agent-id": "grok"}
	var headers_blank_override: Dictionary = {"x-agent-id": "   "}

	# Act / Assert
	if McpProtocol.extract_agent_id("/mcp/luna", headers_with_override) != "grok":
		return _fail("agent_id override: a non-empty x-agent-id header should win over the path")
	if McpProtocol.extract_agent_id("/mcp/luna", headers_blank_override) != "luna":
		return _fail("agent_id override: a blank x-agent-id header should fall back to the path")
	return true


func _test_non_post_method_maps_to_405() -> bool:
	# Arrange / Act / Assert
	if not McpProtocol.is_post("POST"):
		return _fail("405: is_post('POST') should be true")
	if not McpProtocol.is_post("post"):
		return _fail("405: is_post should be case-insensitive")
	if McpProtocol.is_post("GET"):
		return _fail("405: is_post('GET') should be false")

	var response: PackedByteArray = McpProtocol.build_http_response(McpProtocol.HTTP_METHOD_NOT_ALLOWED, null)
	var response_text: String = response.get_string_from_utf8()
	if not response_text.begins_with("HTTP/1.1 405 Method Not Allowed\r\n"):
		return _fail("405: status line mismatch, got '%s'" % response_text.split("\r\n")[0])
	return true


func _test_try_parse_http_request_oversize_body_rejected() -> bool:
	## Both an oversize declared Content-Length and an unterminated flood
	## of bytes (no \r\n\r\n ever arrives) must ERROR once past
	## max_body_bytes, rather than growing the buffer forever.
	# Arrange
	var small_max: int = 16
	var oversized_body_bytes: PackedByteArray = "x".repeat(64).to_utf8_buffer()
	var header_text: String = "POST /mcp/luna HTTP/1.1\r\nContent-Length: %d\r\n\r\n" % oversized_body_bytes.size()
	var buffer: PackedByteArray = header_text.to_utf8_buffer()
	buffer.append_array(oversized_body_bytes)

	# Act
	var result: Dictionary = McpProtocol.try_parse_http_request(buffer, small_max)

	# Assert
	if result.get("status") != McpProtocol.RequestParseStatus.ERROR:
		return _fail("oversize: declared Content-Length above max_body_bytes should ERROR, got %s" % str(result.get("status")))

	# Act — header-less flood, never terminated
	var flood: PackedByteArray = "x".repeat(small_max * 4).to_utf8_buffer()
	var flood_result: Dictionary = McpProtocol.try_parse_http_request(flood, small_max)

	# Assert
	if flood_result.get("status") != McpProtocol.RequestParseStatus.ERROR:
		return _fail("oversize: an unterminated flood past max_body_bytes should ERROR, got %s" % str(flood_result.get("status")))
	return true


# ── JSON-RPC methods ─────────────────────────────────────────────────────

func _test_build_initialize_response_shape_and_instructions_passthrough() -> bool:
	# Arrange
	var instructions_text: String = "You may act upon this world through six gestures."

	# Act
	var response: Dictionary = McpProtocol.build_initialize_response(42, instructions_text)

	# Assert
	if response.get("jsonrpc") != "2.0":
		return _fail("initialize: jsonrpc field mismatch")
	if response.get("id") != 42:
		return _fail("initialize: id should pass through unchanged")
	var result_raw: Variant = response.get("result")
	if not (result_raw is Dictionary):
		return _fail("initialize: result should be a Dictionary")
	var result: Dictionary = result_raw as Dictionary
	if result.get("instructions") != instructions_text:
		return _fail("initialize: instructions did not pass through verbatim")
	if result.get("protocolVersion") != McpProtocol.PROTOCOL_VERSION:
		return _fail("initialize: protocolVersion mismatch")
	if not (result.get("serverInfo") is Dictionary):
		return _fail("initialize: serverInfo should be a Dictionary")
	if not (result.get("capabilities") is Dictionary):
		return _fail("initialize: capabilities should be a Dictionary")
	return true


func _test_handle_jsonrpc_notifications_initialized_returns_202_with_empty_body() -> bool:
	# Arrange
	var body_text: String = JSON.stringify({"jsonrpc": "2.0", "method": "notifications/initialized"})

	# Act
	var outcome: Dictionary = McpProtocol.handle_jsonrpc(body_text)

	# Assert
	if int(outcome.get("http_status", -1)) != McpProtocol.HTTP_ACCEPTED:
		return _fail("notifications/initialized: expected HTTP 202, got %s" % str(outcome.get("http_status")))
	if outcome.get("body") != null:
		return _fail("notifications/initialized: expected a null (empty) body")
	return true


func _test_rpc_envelopes_collapse_float_ids_to_int() -> bool:
	## Regression: Godot's JSON.parse_string turns every wire number into a
	## float, so an integer request id re-serialized verbatim as "0.0" — the
	## official MCP SDK's pydantic models reject that (JSON-RPC ids must be
	## int/string/null). Feed a RAW body string so the id takes the real
	## wire path through the float conversion.
	# Arrange
	var raw_body: String = '{"jsonrpc":"2.0","id":0,"method":"ping"}'

	# Act
	var outcome: Dictionary = McpProtocol.handle_jsonrpc(raw_body)
	var body: Dictionary = outcome.get("body") as Dictionary

	# Assert — the echoed id is a true int and serializes without a decimal
	if typeof(body.get("id")) != TYPE_INT:
		return _fail("float id: expected TYPE_INT id, got type %d (%s)" % [typeof(body.get("id")), str(body.get("id"))])
	if not JSON.stringify(body).contains('"id":0'):
		return _fail("float id: serialized body lost the integer id: %s" % JSON.stringify(body))
	if JSON.stringify(body).contains("0.0"):
		return _fail("float id: serialized body still carries a float id: %s" % JSON.stringify(body))

	# Assert — error envelopes go through the same canonicalization
	var err_body: Dictionary = McpProtocol.rpc_error(7.0, McpProtocol.ERROR_METHOD_NOT_FOUND, "x")
	if typeof(err_body.get("id")) != TYPE_INT:
		return _fail("float id: rpc_error id not canonicalized, got %s" % str(err_body.get("id")))

	# Assert — string ids pass through untouched
	var str_body: Dictionary = McpProtocol.rpc_result("abc-1", {})
	if str_body.get("id") != "abc-1":
		return _fail("float id: string id should pass through, got %s" % str(str_body.get("id")))
	return true


func _test_handle_jsonrpc_ping_returns_empty_result() -> bool:
	# Arrange
	var body_text: String = JSON.stringify({"jsonrpc": "2.0", "id": 9, "method": "ping"})

	# Act
	var outcome: Dictionary = McpProtocol.handle_jsonrpc(body_text)

	# Assert
	if int(outcome.get("http_status", -1)) != McpProtocol.HTTP_OK:
		return _fail("ping: expected HTTP 200, got %s" % str(outcome.get("http_status")))
	var body_raw: Variant = outcome.get("body")
	if not (body_raw is Dictionary):
		return _fail("ping: expected a JSON-RPC body Dictionary")
	var body: Dictionary = body_raw as Dictionary
	if body.get("id") != 9:
		return _fail("ping: response id should match the request")
	var result_raw: Variant = body.get("result")
	if not (result_raw is Dictionary) or not (result_raw as Dictionary).is_empty():
		return _fail("ping: result should be an empty Dictionary")
	return true


func _test_parse_tools_call_happy_path_returns_neutral_dict() -> bool:
	# Arrange
	var params: Dictionary = {"name": "pick_up", "arguments": {"target": "star_medallion"}}

	# Act
	var outcome: Dictionary = McpProtocol.parse_tools_call("req-1", params)

	# Assert
	if not bool(outcome.get("ok", false)):
		return _fail("tools/call: expected ok == true for a known tool")
	var call_raw: Variant = outcome.get("call")
	if not (call_raw is Dictionary):
		return _fail("tools/call: expected a 'call' Dictionary")
	var call: Dictionary = call_raw as Dictionary
	if String(call.get("tool_name")) != "pick_up":
		return _fail("tools/call: tool_name mismatch, got '%s'" % String(call.get("tool_name")))
	if String(call.get("verb")) != "take":
		return _fail("tools/call: verb mismatch, got '%s'" % String(call.get("verb")))
	if call.get("request_id") != "req-1":
		return _fail("tools/call: request_id should pass through unchanged")
	var arguments_raw: Variant = call.get("arguments")
	if not (arguments_raw is Dictionary):
		return _fail("tools/call: arguments should be a Dictionary")
	if String((arguments_raw as Dictionary).get("target")) != "star_medallion":
		return _fail("tools/call: arguments.target mismatch")
	return true


func _test_parse_tools_call_unknown_tool_returns_error() -> bool:
	# Arrange
	var params: Dictionary = {"name": "teleport", "arguments": {}}

	# Act
	var outcome: Dictionary = McpProtocol.parse_tools_call(7, params)

	# Assert
	if bool(outcome.get("ok", true)):
		return _fail("tools/call: expected ok == false for an unknown tool")
	var error_raw: Variant = outcome.get("error")
	if not (error_raw is Dictionary):
		return _fail("tools/call: expected an 'error' Dictionary")
	var error: Dictionary = error_raw as Dictionary
	if error.get("id") != 7:
		return _fail("tools/call: error envelope id should match the request id")
	var error_obj_raw: Variant = error.get("error")
	if not (error_obj_raw is Dictionary):
		return _fail("tools/call: error envelope missing nested 'error' object")
	if int((error_obj_raw as Dictionary).get("code", 0)) != McpProtocol.ERROR_INVALID_PARAMS:
		return _fail("tools/call: unknown tool should use ERROR_INVALID_PARAMS")
	return true


func _test_handle_jsonrpc_tools_call_populates_neutral_call_dict() -> bool:
	## End-to-end through handle_jsonrpc: a successful tools/call must leave
	## "body" null (the caller writes the HTTP response itself once
	## ActionResolver has run) and populate "call" with the neutral dispatch
	## dict.
	# Arrange
	var body_text: String = JSON.stringify({
		"jsonrpc": "2.0",
		"id": 11,
		"method": "tools/call",
		"params": {"name": "walk_toward", "arguments": {"target": "runestone_portal"}},
	})

	# Act
	var outcome: Dictionary = McpProtocol.handle_jsonrpc(body_text)

	# Assert
	if outcome.get("body") != null:
		return _fail("handle_jsonrpc: a successful tools/call should leave body null")
	var call_raw: Variant = outcome.get("call")
	if not (call_raw is Dictionary):
		return _fail("handle_jsonrpc: expected a 'call' Dictionary for a successful tools/call")
	var call: Dictionary = call_raw as Dictionary
	if String(call.get("verb")) != "go_to":
		return _fail("handle_jsonrpc: tools/call verb mapping mismatch, got '%s'" % String(call.get("verb")))
	return true


func _test_parse_jsonrpc_malformed_json_returns_parse_error() -> bool:
	# Arrange / Act
	print("EXPECTED ERROR (muted): Parse JSON failed, malformed JSON-RPC")
	Engine.print_error_messages = false
	var outcome: Dictionary = McpProtocol.parse_jsonrpc("{this is not json")
	Engine.print_error_messages = true

	# Assert
	if bool(outcome.get("ok", true)):
		return _fail("parse_jsonrpc: malformed JSON should not report ok == true")
	var error_raw: Variant = outcome.get("error")
	if not (error_raw is Dictionary):
		return _fail("parse_jsonrpc: expected an 'error' envelope")
	var error_obj_raw: Variant = (error_raw as Dictionary).get("error")
	if not (error_obj_raw is Dictionary):
		return _fail("parse_jsonrpc: error envelope missing nested 'error' object")
	if int((error_obj_raw as Dictionary).get("code", 0)) != McpProtocol.ERROR_PARSE_ERROR:
		return _fail("parse_jsonrpc: malformed JSON should use ERROR_PARSE_ERROR (-32700)")
	return true


func _test_parse_jsonrpc_missing_method_returns_invalid_request() -> bool:
	# Arrange
	var body_text: String = JSON.stringify({"jsonrpc": "2.0", "id": 3})

	# Act
	var outcome: Dictionary = McpProtocol.parse_jsonrpc(body_text)

	# Assert
	if bool(outcome.get("ok", true)):
		return _fail("parse_jsonrpc: a body with no 'method' should not report ok == true")
	var error_obj_raw: Variant = (outcome.get("error") as Dictionary).get("error")
	if not (error_obj_raw is Dictionary):
		return _fail("parse_jsonrpc: error envelope missing nested 'error' object")
	if int((error_obj_raw as Dictionary).get("code", 0)) != McpProtocol.ERROR_INVALID_REQUEST:
		return _fail("parse_jsonrpc: missing method should use ERROR_INVALID_REQUEST (-32600)")
	return true


func _test_handle_jsonrpc_unknown_method_returns_error() -> bool:
	# Arrange
	var body_text: String = JSON.stringify({"jsonrpc": "2.0", "id": 5, "method": "tools/frobnicate", "params": {}})

	# Act
	var outcome: Dictionary = McpProtocol.handle_jsonrpc(body_text)

	# Assert
	if int(outcome.get("http_status", -1)) != McpProtocol.HTTP_OK:
		return _fail("handle_jsonrpc: unknown method should still answer HTTP 200 with a JSON-RPC error envelope")
	var body_raw: Variant = outcome.get("body")
	if not (body_raw is Dictionary):
		return _fail("handle_jsonrpc: expected a body envelope for an unknown method")
	var error_obj_raw: Variant = (body_raw as Dictionary).get("error")
	if not (error_obj_raw is Dictionary):
		return _fail("handle_jsonrpc: unknown method body should contain an 'error' object")
	if int((error_obj_raw as Dictionary).get("code", 0)) != McpProtocol.ERROR_METHOD_NOT_FOUND:
		return _fail("handle_jsonrpc: unknown method should use ERROR_METHOD_NOT_FOUND (-32601)")
	if outcome.get("call") != null:
		return _fail("handle_jsonrpc: unknown method should not populate 'call'")
	return true


# ── Tool surface ─────────────────────────────────────────────────────────

func _test_build_tools_list_contains_all_six_tools_with_schemas() -> bool:
	# Arrange
	var descriptions: Dictionary = {"walk_toward": "You may walk toward what you see."}

	# Act
	var tools: Array[Dictionary] = McpProtocol.build_tools_list(descriptions)

	# Assert — exactly the 6 expected tools, each with a usable schema
	if tools.size() != McpProtocol.TOOL_NAMES.size():
		return _fail("tools/list: expected %d tools, got %d" % [McpProtocol.TOOL_NAMES.size(), tools.size()])

	var names_seen: Dictionary = {}
	for tool: Dictionary in tools:
		var name: String = String(tool.get("name"))
		names_seen[name] = true
		var schema_raw: Variant = tool.get("inputSchema")
		if not (schema_raw is Dictionary):
			return _fail("tools/list: tool '%s' missing an inputSchema Dictionary" % name)
		var schema: Dictionary = schema_raw as Dictionary
		if String(schema.get("type", "")) != "object":
			return _fail("tools/list: tool '%s' schema type should be 'object'" % name)
		if not (schema.get("properties") is Dictionary):
			return _fail("tools/list: tool '%s' schema missing 'properties'" % name)

	for expected_name: String in McpProtocol.TOOL_NAMES:
		if not names_seen.has(expected_name):
			return _fail("tools/list: missing expected tool '%s'" % expected_name)

	# Assert — caller-supplied descriptions pass through; missing ones default to ""
	for tool: Dictionary in tools:
		var name: String = String(tool.get("name"))
		if name == "walk_toward" and String(tool.get("description")) != "You may walk toward what you see.":
			return _fail("tools/list: walk_toward description was not passed through")
		if name == "pick_up" and String(tool.get("description")) != "":
			return _fail("tools/list: pick_up description should default to '' when not supplied")

	return true


func _test_verb_for_tool_maps_every_diegetic_name() -> bool:
	# Arrange
	var expected: Dictionary = {
		"walk_toward": "go_to",
		"pick_up": "take",
		"use_item_on": "use_object",
		"apply_skill": "use_skill",
		"call_out_to": "call_agent",
		"emotion_update": "emotion_update",
	}

	# Act / Assert
	for tool_name: String in expected.keys():
		var expected_verb: String = String(expected[tool_name])
		var actual_verb: String = McpProtocol.verb_for_tool(tool_name)
		if actual_verb != expected_verb:
			return _fail("verb map: %s should map to %s, got '%s'" % [tool_name, expected_verb, actual_verb])
	if McpProtocol.verb_for_tool("nonexistent_tool") != "":
		return _fail("verb map: an unknown tool name should map to ''")
	return true


# ── HTTP response building ───────────────────────────────────────────────

func _test_build_http_response_emits_status_line_content_length_and_connection_close() -> bool:
	# Arrange
	var body_dict: Dictionary = {"jsonrpc": "2.0", "id": 1, "result": {}}

	# Act
	var response: PackedByteArray = McpProtocol.build_http_response(McpProtocol.HTTP_OK, body_dict)
	var response_text: String = response.get_string_from_utf8()
	var sections: PackedStringArray = response_text.split("\r\n\r\n", false)

	# Assert — headers/body split, status line, required headers
	if sections.size() < 2:
		return _fail("response builder: expected a blank line separating headers from body")
	var header_lines: PackedStringArray = sections[0].split("\r\n")
	var body_text: String = sections[1]

	if header_lines[0] != "HTTP/1.1 200 OK":
		return _fail("response builder: status line mismatch, got '%s'" % header_lines[0])

	var found_content_type: bool = false
	var found_content_length: bool = false
	var found_connection_close: bool = false
	var declared_length: int = -1
	for line: String in header_lines:
		if line.begins_with("Content-Type:"):
			found_content_type = true
		if line.begins_with("Content-Length:"):
			found_content_length = true
			declared_length = line.substr("Content-Length:".length()).strip_edges().to_int()
		if line == "Connection: close":
			found_connection_close = true

	if not found_content_type:
		return _fail("response builder: missing Content-Type header")
	if not found_content_length:
		return _fail("response builder: missing Content-Length header")
	if not found_connection_close:
		return _fail("response builder: missing Connection: close header")
	if declared_length != body_text.to_utf8_buffer().size():
		return _fail("response builder: declared Content-Length (%d) does not match actual body size (%d)" % [declared_length, body_text.to_utf8_buffer().size()])

	var reparsed: Variant = JSON.parse_string(body_text)
	if not (reparsed is Dictionary):
		return _fail("response builder: body did not round-trip as valid JSON")

	# Assert — empty-body form (e.g. the 202 ack) yields Content-Length: 0, no body bytes
	var empty_response: PackedByteArray = McpProtocol.build_http_response(McpProtocol.HTTP_ACCEPTED, null)
	var empty_text: String = empty_response.get_string_from_utf8()
	if not empty_text.begins_with("HTTP/1.1 202 Accepted\r\n"):
		return _fail("response builder: 202 status line mismatch")
	if not empty_text.ends_with("Connection: close\r\n\r\n"):
		return _fail("response builder: empty-body response should end right after the blank line")

	return true
