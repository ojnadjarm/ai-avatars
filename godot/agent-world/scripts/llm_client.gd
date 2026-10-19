class_name LLMClient
extends Node
## LLM gateway client — calls Hermes/OpenAI/Anthropic/OpenClaw APIs via HTTP.
## All gateways use standard REST endpoints. No WebSocket, no bridge.

signal llm_response_received(request_id: String, text: String)

## Non-MCP agents (the default) keep today's flat timeout — plenty for a
## completed LLM response and short enough that a hung gateway doesn't hold
## a main-thread request for two minutes.
const CHAT_TIMEOUT_SECONDS: float = 15.0

## MCP agents (GameState.is_agent_mcp) get defaults.mcp.chat_timeout_seconds
## instead (see _chat_timeout_seconds). An MCP agent's turn can involve
## multiple tool round-trips before the gateway's own chat response
## returns — the flat 15s would kill the whole chat turn as
## "[gateway unavailable]" long before a multi-tool-call turn finishes.
const MCP_CHAT_TIMEOUT_SECONDS_FALLBACK: float = 120.0


func llm_chat(gateway_id: String, system_prompt: String, user_message: String, session_id: String = "", request_id: String = "", model_override: String = "", agent_id: String = "") -> void:
	var gw: Dictionary = GameState.get_gateway(gateway_id)
	if gw.is_empty():
		push_warning("[llm] Unknown gateway: %s" % gateway_id)
		llm_response_received.emit(request_id, "[no gateway configured]")
		return

	# Agent-level model overrides gateway default
	if model_override != "":
		gw = gw.duplicate()
		gw["model"] = model_override

	var gw_type: String = gw.get("type", "openai")

	match gw_type:
		"anthropic":
			_anthropic_chat(gw, system_prompt, user_message, request_id, agent_id)
		_:
			# hermes, openai, openclaw — all OpenAI-compatible HTTP
			_http_chat(gw, system_prompt, user_message, session_id, request_id, agent_id)


# ── Per-agent chat timeout ──

## MCP agents get defaults.mcp.chat_timeout_seconds; every other agent (and
## any call with no agent_id — e.g. llm_coordinator's fire-and-forget
## post-resolve echo, which still passes one) keeps CHAT_TIMEOUT_SECONDS
## unchanged. Empty-safe: a missing/non-Dictionary defaults.mcp block falls
## back to MCP_CHAT_TIMEOUT_SECONDS_FALLBACK rather than erroring.
func _chat_timeout_seconds(agent_id: String) -> float:
	if agent_id == "" or not GameState.is_agent_mcp(agent_id):
		return CHAT_TIMEOUT_SECONDS
	var mcp_raw: Variant = GameState.get_default("mcp", {})
	var mcp_cfg: Dictionary = mcp_raw if mcp_raw is Dictionary else {}
	return float(mcp_cfg.get("chat_timeout_seconds", MCP_CHAT_TIMEOUT_SECONDS_FALLBACK))


# ── OpenAI-compatible HTTP (hermes, openai, openclaw) ──

func _http_chat(gw: Dictionary, system_prompt: String, user_message: String, session_id: String, request_id: String, agent_id: String) -> void:
	var endpoint: String = gw.get("endpoint", "")
	if endpoint == "":
		llm_response_received.emit(request_id, "[no endpoint configured]")
		return

	var gw_type: String = gw.get("type", "openai")
	var model: String = gw.get("model", "")
	var api_key: String = gw.get("api_key", "")

	var messages: Array = []
	if system_prompt != "":
		messages.append({"role": "system", "content": system_prompt})
	messages.append({"role": "user", "content": user_message})

	var headers: PackedStringArray = ["Content-Type: application/json"]
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	if session_id != "" and gw_type == "hermes":
		headers.append("X-Hermes-Session-Id: %s" % session_id)

	# OpenClaw: model field must be "openclaw", real model goes in header.
	# Agent selection rides on x-openclaw-agent-id, but for explicit session
	# keys the gateway ALSO requires the `agent:<id>:<main>` prefix — without
	# it the dispatcher can't read the agent id back out of the session key
	# and silently falls through to the default agent.
	var request_model: String = model
	if gw_type == "openclaw":
		if model != "":
			headers.append("x-openclaw-model: %s" % model)
		if agent_id != "":
			headers.append("x-openclaw-agent-id: %s" % agent_id)
		if session_id != "":
			var session_key: String = "agent:%s:%s" % [agent_id, session_id] if agent_id != "" else session_id
			headers.append("x-openclaw-session-key: %s" % session_key)
		request_model = "openclaw"

	var body := JSON.stringify({"model": request_model, "messages": messages})
	var url: String = endpoint.rstrip("/") + "/v1/chat/completions"

	var http := HTTPRequest.new()
	# use_threads=false keeps the request on the main thread (pumped via
	# _process). Godot's default (true) spawns a worker thread per request;
	# if the thread is mid-connect when the user quits, Godot waits for the
	# thread to join before exiting — producing zombie processes that held
	# WSL memory until `wsl --shutdown`. Main-thread HTTP cancels cleanly.
	http.use_threads = false
	# Per-agent timeout — see _chat_timeout_seconds(). Non-MCP agents keep
	# the short 15s default; MCP agents get defaults.mcp.chat_timeout_seconds
	# because their turn can involve multiple tool round-trips before the
	# gateway's own response returns.
	http.timeout = _chat_timeout_seconds(agent_id)
	add_child(http)
	http.request_completed.connect(_on_openai_response.bind(http, request_id))
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		push_warning("[llm] Request error: %d" % err)
		llm_response_received.emit(request_id, "[request failed]")


func _on_openai_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, request_id: String) -> void:
	if is_instance_valid(http):
		http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[llm] Connection failed (result=%d)" % result)
		llm_response_received.emit(request_id, "[gateway unavailable]")
		return

	if code != 200:
		var err_text := body.get_string_from_utf8()
		push_warning("[llm] HTTP %d: %s" % [code, err_text.substr(0, 200)])
		llm_response_received.emit(request_id, "[error: HTTP %d]" % code)
		return

	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data or not data is Dictionary:
		llm_response_received.emit(request_id, "[invalid response]")
		return

	var choices: Array = data.get("choices", [])
	if choices.is_empty():
		llm_response_received.emit(request_id, "[no response]")
		return

	var message: Dictionary = choices[0].get("message", {})
	var content: String = message.get("content", "").strip_edges()
	if content == "":
		content = "[no response]"

	llm_response_received.emit(request_id, content)


# ── Anthropic API (direct) ──

func _anthropic_chat(gw: Dictionary, system_prompt: String, user_message: String, request_id: String, agent_id: String = "") -> void:
	var endpoint: String = gw.get("endpoint", "https://api.anthropic.com")
	var api_key: String = gw.get("api_key", "")
	var model: String = gw.get("model", "claude-haiku-4-5-20251001")

	if api_key == "":
		llm_response_received.emit(request_id, "[no API key configured]")
		return

	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"x-api-key: %s" % api_key,
		"anthropic-version: 2023-06-01",
	]

	var body_dict: Dictionary = {
		"model": model,
		"max_tokens": 1024,
		"messages": [{"role": "user", "content": user_message}],
	}
	if system_prompt != "":
		body_dict["system"] = system_prompt

	var url: String = endpoint.rstrip("/") + "/v1/messages"

	var http := HTTPRequest.new()
	# use_threads=false keeps the request on the main thread (pumped via
	# _process). Godot's default (true) spawns a worker thread per request;
	# if the thread is mid-connect when the user quits, Godot waits for the
	# thread to join before exiting — producing zombie processes that held
	# WSL memory until `wsl --shutdown`. Main-thread HTTP cancels cleanly.
	http.use_threads = false
	# Per-agent timeout — see _chat_timeout_seconds(). Non-MCP agents keep
	# the short 15s default; MCP agents get defaults.mcp.chat_timeout_seconds
	# because their turn can involve multiple tool round-trips before the
	# gateway's own response returns.
	http.timeout = _chat_timeout_seconds(agent_id)
	add_child(http)
	http.request_completed.connect(_on_anthropic_response.bind(http, request_id))
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body_dict))
	if err != OK:
		http.queue_free()
		push_warning("[llm] Anthropic request error: %d" % err)
		llm_response_received.emit(request_id, "[request failed]")


func _on_anthropic_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, request_id: String) -> void:
	if is_instance_valid(http):
		http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[llm] Anthropic connection failed (result=%d)" % result)
		llm_response_received.emit(request_id, "[gateway unavailable]")
		return

	if code != 200:
		var err_text := body.get_string_from_utf8()
		push_warning("[llm] Anthropic HTTP %d: %s" % [code, err_text.substr(0, 200)])
		llm_response_received.emit(request_id, "[error: HTTP %d]" % code)
		return

	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data or not data is Dictionary:
		llm_response_received.emit(request_id, "[invalid response]")
		return

	var content_arr: Array = data.get("content", [])
	if content_arr.is_empty():
		llm_response_received.emit(request_id, "[no response]")
		return

	var content: String = ""
	for block in content_arr:
		var block_dict: Dictionary = block
		if block_dict.get("type", "") == "text":
			content += block_dict.get("text", "")

	content = content.strip_edges()
	if content == "":
		content = "[no response]"

	llm_response_received.emit(request_id, content)
