extends Node
## Autoload singleton — the runtime MCP server. Gateways (Hermes, OpenClaw)
## connect here as MCP clients; each configured agent gets its own URL:
## POST /mcp/<agent_id>.
##
## This is the TCP/dispatch half. All wire-protocol parsing (HTTP framing,
## JSON-RPC, tool schemas) lives in the pure-static McpProtocol — this file
## owns sockets, world binding, and the ActionResolver dispatch. Registered
## in project.godot after GameState/Strings so GameState.defaults is
## already loaded by the time _ready() reads defaults.mcp.
##
## Naming discipline (see plan): this is the RUNTIME MCP server — gateways
## talk to the game. It shares nothing with the GDAI authoring MCP Claude
## uses to build maps in-editor (Part A); different process, different
## protocol, zero shared code.
##
## Lifecycle: survives world changes (it is an autoload, not a scene node).
## world_loader calls bind_world(self) once fully constructed (_ready(),
## after agents are spawned) and unbind_world() on _exit_tree() (quit to
## menu or app quit). With no world bound, every tools/call answers
## immediately with nothing-happens narration — this is what makes "curl
## from the room selector" a safe, well-defined no-op instead of a crash.
##
## Coexistence with the XML path: this file never touches narration_log's
## session-echo mechanism (that lives in llm_coordinator._apply_action_result,
## reached only from the XML observe path). MCP action results are delivered
## INSIDE the held HTTP response — the calling gateway's own MCP client
## receives the narration as the tool's return value, so echoing it back
## into the agent's session as well would show the agent the same event
## twice. See _finish_puzzle_action() below.


# ── Local HTTP status constants ─────────────────────────────────────────
# McpProtocol.HTTP_STATUS_TEXT already carries the reason phrase for 404;
# it just doesn't name a constant for it (mcp_protocol.gd is not to be
# modified per the migration brief). 400 has no entry there at all —
# malformed non-oversize framing is a case McpProtocol's ERROR status
# reports but does not itself assign an HTTP code to (that's an mcp_server
# transport decision, deliberately left to the caller).
const HTTP_NOT_FOUND: int = 404
const HTTP_BAD_REQUEST: int = 400

# ── Config fallbacks ─────────────────────────────────────────────────────
# Every defaults.mcp.* read below falls back to one of these literals so a
# user://game_config.json override saved before this feature shipped (or
# missing individual keys) still produces a safe, in-register server
# instead of an empty instructions string or a silently-disabled feature.
# `enabled` is the one exception that fails CLOSED (see _configured_enabled).

const DEFAULT_PORT: int = 8975
const DEFAULT_MIN_SECONDS_BETWEEN_CALLS: float = 5.0

const DEFAULT_INSTRUCTIONS: String = "This connection lets you act directly on the place you are in, the same as if you reached out yourself. You can walk toward whatever draws your attention, take hold of something you find, press what you carry against what is before you, bring what you know to bear on it, or call out by name to someone nearby. Some of these carry enough weight that the world takes a breath before it answers — wait for it, the answer will come. You may also register how a passing moment has shifted something in you, an honest accounting kept for yourself. None of this replaces speaking — say what you mean, plainly, whenever talking is what you are doing."

const DEFAULT_TOOL_DESCRIPTIONS: Dictionary = {
	"walk_toward": "Move toward a place, a thing, or someone nearby.",
	"pick_up": "Take a thing into your hands.",
	"use_item_on": "Press, fit, or offer a thing you hold against a place, a thing, or someone.",
	"apply_skill": "Bring what you know to bear on a place, a thing, or someone.",
	"call_out_to": "Reach out by name to someone nearby.",
	"emotion_update": "Register how a passing moment has shifted something in you — an honest accounting, not a performance.",
}

const DEFAULT_THROTTLE_NARRATION: String = "You're moving faster than your own hands can follow. Whatever you reached for will still be there when you slow down."
const DEFAULT_EMOTION_UPDATE_NARRATION: String = "You register the shift and let it settle."
const DEFAULT_EMOTION_UPDATE_EMPTY_NARRATION: String = "Nothing in you moves."

## Ultimate fallback narration when even defaults.puzzle.nothing_happens_text
## is missing (a user:// override predating the puzzle layer entirely).
## Mirrors the literal shipped in game_config.json so a missing key degrades
## to the same prose an intact config would show, not empty text.
const DEFAULT_NOTHING_HAPPENS_TEXT: String = "The world holds its shape. Nothing yields."


# ── State ────────────────────────────────────────────────────────────────

var _server: TCPServer = TCPServer.new()
var _listening: bool = false
var _port: int = DEFAULT_PORT

## Set by world_loader.bind_world()/unbind_world(). Null means "no world
## loaded" — every tools/call short-circuits to nothing-happens narration.
var _world_loader: WorldLoader = null

## One entry per TCP connection currently being read (not yet a complete
## request). {"peer": StreamPeerTCP, "buffer": PackedByteArray}.
var _connections: Array[Dictionary] = []

## Per-agent throttle clock (migration step B3 — defaults.mcp.
## min_seconds_between_calls). Time.get_ticks_msec() at the last call that
## was ALLOWED through; a missing key means "never called yet".
var _last_call_msec: Dictionary[String, int] = {}


# ── Virtual methods ──────────────────────────────────────────────────────

func _ready() -> void:
	if not _configured_enabled():
		set_process(false)
		return
	_port = _configured_port()
	var err: int = _server.listen(_port, "127.0.0.1")
	if err != OK:
		push_error("[mcp_server] Failed to listen on 127.0.0.1:%d — error %d. MCP server disabled for this session." % [_port, err])
		set_process(false)
		return
	_listening = true
	print("[mcp_server] Listening on 127.0.0.1:%d" % _port)


func _process(_delta: float) -> void:
	# Cheap when idle by construction: is_connection_available() is O(1) and
	# _connections is an empty array with nothing spawned yet, so the loop
	# below is a no-op until a client actually connects.
	_accept_new_connections()
	_poll_active_connections()


func _exit_tree() -> void:
	if _listening:
		_server.stop()
	for conn: Dictionary in _connections:
		_disconnect_peer(conn.get("peer"))


# ── World binding (public — called by world_loader) ─────────────────────

func bind_world(world: WorldLoader) -> void:
	_world_loader = world


func unbind_world() -> void:
	_world_loader = null


# ── Connection lifecycle ─────────────────────────────────────────────────

func _accept_new_connections() -> void:
	if not _listening:
		return
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if peer == null:
			continue
		_connections.append({"peer": peer, "buffer": PackedByteArray()})


func _poll_active_connections() -> void:
	if _connections.is_empty():
		return
	var still_active: Array[Dictionary] = []
	for conn: Dictionary in _connections:
		var peer: StreamPeerTCP = conn.get("peer") as StreamPeerTCP
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue  # dropped before completing a request — discard silently
		var available: int = peer.get_available_bytes()
		if available <= 0:
			still_active.append(conn)
			continue
		var read_result: Array = peer.get_partial_data(available)
		if int(read_result[0]) != OK:
			continue  # read error — drop the connection
		var chunk: PackedByteArray = read_result[1]
		var parsed: Dictionary = McpProtocol.feed_bytes(conn["buffer"] as PackedByteArray, chunk, McpProtocol.MAX_BODY_BYTES)
		var status: int = int(parsed.get("status", McpProtocol.RequestParseStatus.ERROR))
		if status == McpProtocol.RequestParseStatus.INCOMPLETE:
			conn["buffer"] = parsed["buffer"]
			still_active.append(conn)
			continue
		if status == McpProtocol.RequestParseStatus.ERROR:
			_send_and_close(peer, _status_for_parse_error(str(parsed.get("error", ""))), null)
			continue
		_handle_request(peer, parsed)
	_connections = still_active


static func _disconnect_peer(peer_variant: Variant) -> void:
	var peer: StreamPeerTCP = peer_variant as StreamPeerTCP
	if peer != null and is_instance_valid(peer):
		peer.disconnect_from_host()


# ── Request routing ──────────────────────────────────────────────────────

func _handle_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	var method: String = str(parsed.get("method", ""))
	if not McpProtocol.is_post(method):
		_send_and_close(peer, McpProtocol.HTTP_METHOD_NOT_ALLOWED, null)
		return

	var path: String = str(parsed.get("path", ""))
	var headers_raw: Variant = parsed.get("headers", {})
	var headers: Dictionary = headers_raw as Dictionary if headers_raw is Dictionary else {}
	var agent_id: String = McpProtocol.extract_agent_id(path, headers)
	if agent_id == "" or not GameState.agents.has(agent_id):
		_send_and_close(peer, HTTP_NOT_FOUND, McpProtocol.rpc_error(null, McpProtocol.ERROR_INVALID_REQUEST, "Unknown agent: %s" % agent_id))
		return

	var body_text: String = str(parsed.get("body", ""))
	var outcome: Dictionary = McpProtocol.handle_jsonrpc(body_text, _instructions_text(), _tool_descriptions())
	var call_raw: Variant = outcome.get("call")
	if call_raw != null:
		_dispatch_tool_call(peer, agent_id, call_raw as Dictionary)
		return
	_send_and_close(peer, int(outcome.get("http_status", McpProtocol.HTTP_OK)), outcome.get("body"))


static func _status_for_parse_error(reason: String) -> int:
	if reason.contains("max_body_bytes"):
		return McpProtocol.HTTP_PAYLOAD_TOO_LARGE
	return HTTP_BAD_REQUEST


func _send_and_close(peer: StreamPeerTCP, status: int, body: Variant) -> void:
	peer.put_data(McpProtocol.build_http_response(status, body))
	peer.disconnect_from_host()


# ── tools/call dispatch ──────────────────────────────────────────────────

## `call` is McpProtocol's neutral dispatch dict: {tool_name, verb,
## arguments, request_id} — request_id here is the JSON-RPC message id
## (kept as `jsonrpc_id` below to avoid confusing it with other ids).
func _dispatch_tool_call(peer: StreamPeerTCP, agent_id: String, call: Dictionary) -> void:
	var verb: String = str(call.get("verb", ""))
	var jsonrpc_id: Variant = call.get("request_id")
	var arguments_raw: Variant = call.get("arguments", {})
	var arguments: Dictionary = arguments_raw as Dictionary if arguments_raw is Dictionary else {}

	# Plan "Coexistence" bullet — no world bound, e.g. a curl from the room
	# selector: never touch a resolver that doesn't exist, just answer
	# nothing-happens (fourth-wall safe, same fallback chain the puzzle
	# layer uses).
	if _world_loader == null or not is_instance_valid(_world_loader):
		_finish_tool_call(peer, jsonrpc_id, _nothing_happens_text(verb))
		return

	var agent: Agent = _world_loader.find_agent(agent_id)
	if agent == null:
		# Configured but not currently spawned in this world (or spawn is
		# still mid-flight) — same nothing-happens answer, now via the bound
		# world's own nothing_happens_text tier (tier 2) when it has one.
		_finish_tool_call(peer, jsonrpc_id, _nothing_happens_text(verb))
		return

	if not _consume_throttle(agent_id):
		_finish_tool_call(peer, jsonrpc_id, _throttle_narration())
		return

	if verb == "emotion_update":
		_finish_tool_call(peer, jsonrpc_id, _apply_emotion_update(agent, arguments))
		return

	var action: Dictionary = {"verb": verb, "target": str(arguments.get("target", ""))}
	var on_value: String = str(arguments.get("on", ""))
	if not on_value.is_empty():
		action["on"] = on_value
	_submit_puzzle_action(peer, jsonrpc_id, agent, action)


## Routes through the SAME choke point the XML path uses
## (world_loader.submit_agent_action → ActionResolver), so puzzle semantics
## are identical on both transports. submit_agent_action() resolves
## synchronously — the callback fires before this function returns — so the
## result is captured and the HTTP response is answered in-line.
func _submit_puzzle_action(peer: StreamPeerTCP, jsonrpc_id: Variant, agent: Agent, action: Dictionary) -> void:
	_world_loader.submit_agent_action(agent, action, "mcp", func(result: Dictionary) -> void:
		_finish_puzzle_action(peer, jsonrpc_id, result)
	)


## Post-resolve step for an MCP-sourced action — the MCP counterpart to
## llm_coordinator._apply_action_result(), deliberately NOT that function.
## It keeps the narration_log entry (sidebar visibility) and the
## debounced world-state save, but drops the fire-and-forget session echo:
## the calling gateway's own MCP client receives `narration` as this
## tool call's result the moment _finish_tool_call() below writes the HTTP
## response, so the agent already has the event. Echoing it into the
## session as well (as the XML path does, because an XML agent has no
## other way to learn what happened) would show it to the agent twice.
func _finish_puzzle_action(peer: StreamPeerTCP, jsonrpc_id: Variant, result: Dictionary) -> void:
	var narration: String = str(result.get("narration", ""))
	if not narration.is_empty() and _world_loader != null and is_instance_valid(_world_loader) and _world_loader.narration_log != null:
		_world_loader.narration_log.add_entry(narration, "action")
	if bool(result.get("state_changed", false)) and _world_loader != null and is_instance_valid(_world_loader):
		_world_loader.queue_world_state_save(false)
	_finish_tool_call(peer, jsonrpc_id, narration)


func _finish_tool_call(peer: StreamPeerTCP, jsonrpc_id: Variant, narration: String) -> void:
	if peer == null or not is_instance_valid(peer):
		return
	var result_body: Dictionary = McpProtocol.rpc_result(jsonrpc_id, {
		"content": [{"type": "text", "text": narration}],
		"isError": false,
	})
	_send_and_close(peer, McpProtocol.HTTP_OK, result_body)


# ── emotion_update (always resolves immediately, no puzzle rule match) ──

## Mirrors EmotionTags._apply_block's semantics exactly: same clamp calls,
## same log_cause, same "all-zero deltas is a silent no-op" rule. Differs
## in one respect — EmotionTags runs inside a bigger observe/talk response
## where the caller refreshes the mood aura afterward regardless; a
## standalone emotion_update tools/call has no such caller, so this
## refreshes it directly via agent.set_mood() before returning.
func _apply_emotion_update(agent: Agent, arguments: Dictionary) -> String:
	var engine: EmotionEngine = agent.emotion_engine
	if engine == null:
		return _emotion_update_empty_narration()

	var energy_delta: float = clampf(float(arguments.get("energy", 0.0)), -1.0, 1.0)
	var patience_delta: float = clampf(float(arguments.get("patience", 0.0)), -1.0, 1.0)
	var social_delta: float = clampf(float(arguments.get("social_battery", 0.0)), -1.0, 1.0)
	var any_delta: bool = energy_delta != 0.0 or patience_delta != 0.0 or social_delta != 0.0
	if not any_delta:
		return _emotion_update_empty_narration()

	var reason: String = str(arguments.get("reason", "")).strip_edges()
	if reason.is_empty():
		reason = "unspecified"

	engine.energy = clampf(engine.energy + energy_delta, 0.0, 1.0)
	engine.patience = clampf(engine.patience + patience_delta, 0.0, 1.0)
	engine.social_battery = clampf(engine.social_battery + social_delta, 0.0, 1.0)
	engine.log_cause(reason)
	agent.set_mood(engine.mood)
	return _emotion_update_narration()


# ── Per-agent throttle (defaults.mcp.min_seconds_between_calls) ─────────

## Returns true and records `agent_id`'s call time when enough real time has
## passed since its last ALLOWED call; false (and does NOT update the
## clock) when the agent is calling too soon — mirrors ActivityGate.trigger()
## only being called on the actions that actually proceed, not on rejected
## attempts.
func _consume_throttle(agent_id: String) -> bool:
	var min_seconds: float = _min_seconds_between_calls()
	if min_seconds <= 0.0:
		return true
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_call_msec.get(agent_id, -1))
	if last_msec >= 0 and (now_msec - last_msec) < int(min_seconds * 1000.0):
		return false
	_last_call_msec[agent_id] = now_msec
	return true


# ── Nothing-happens fallback (no world bound / agent not spawned) ───────

## Instance variant — prefers the bound world's own nothing_happens_text
## (tier 2 of ActionResolver's four-tier chain) before falling back to the
## config-driven per-verb/global tiers below. Tier 1 (a matched puzzle
## rule's own default_fail_narration) never applies here: reaching this
## helper at all means no puzzle rule was ever consulted (no world, or no
## agent to act through).
func _nothing_happens_text(verb: String) -> String:
	if _world_loader != null and is_instance_valid(_world_loader):
		var world_text: String = str(_world_loader.config.get("nothing_happens_text", ""))
		if not world_text.is_empty():
			return world_text
	return _fallback_nothing_happens_text(verb)


## Static tiers 3/4 of ActionResolver._nothing_happens, reimplemented here
## because that method is a private instance method on ActionResolver (takes
## no world_state, not reusable statically) and this migration's brief
## excludes touching action_resolver.gd. See the final report's "gaps"
## section — a shared static NothingHappens helper both classes could call
## is a reasonable follow-up refactor.
static func _fallback_nothing_happens_text(verb: String) -> String:
	var puzzle_defaults: Variant = GameState.get_default("puzzle", {})
	var cfg: Dictionary = puzzle_defaults if puzzle_defaults is Dictionary else {}
	var nothing_happens: Variant = cfg.get("nothing_happens", {})
	if nothing_happens is Dictionary:
		var per_verb: String = str((nothing_happens as Dictionary).get(verb, ""))
		if not per_verb.is_empty():
			return per_verb
	var global_text: String = str(cfg.get("nothing_happens_text", ""))
	if not global_text.is_empty():
		return global_text
	return DEFAULT_NOTHING_HAPPENS_TEXT


# ── Config accessors ──────────────────────────────────────────────────────
# `user://game_config.json` silently shadows res:// — every read below
# falls back to a literal default when defaults.mcp (or the specific key)
# is absent, so an override saved before this feature shipped still works.

static func _mcp_defaults() -> Dictionary:
	var raw: Variant = GameState.get_default("mcp", {})
	if raw is Dictionary:
		return raw
	return {}


## Fails CLOSED by design (see plan Part B "Coexistence" bullet): a
## user://game_config.json override saved before this feature shipped has
## no "enabled" key at all, and the safe behavior for an old override is
## "the MCP server does not start", not "starts listening unexpectedly".
static func _configured_enabled() -> bool:
	return bool(_mcp_defaults().get("enabled", false))


static func _configured_port() -> int:
	return int(_mcp_defaults().get("port", DEFAULT_PORT))


static func _min_seconds_between_calls() -> float:
	return float(_mcp_defaults().get("min_seconds_between_calls", DEFAULT_MIN_SECONDS_BETWEEN_CALLS))


static func _instructions_text() -> String:
	var text: String = str(_mcp_defaults().get("instructions", ""))
	return text if not text.is_empty() else DEFAULT_INSTRUCTIONS


## Per-key fallback (not just whole-block): an override that customizes a
## few tools but not all six still gets in-register descriptions for the
## ones it omitted, instead of blank strings on the tools/list response.
static func _tool_descriptions() -> Dictionary:
	var raw: Variant = _mcp_defaults().get("tool_descriptions", {})
	var configured: Dictionary = raw if raw is Dictionary else {}
	var merged: Dictionary = DEFAULT_TOOL_DESCRIPTIONS.duplicate()
	for key: String in configured:
		merged[key] = configured[key]
	return merged


static func _throttle_narration() -> String:
	var text: String = str(_mcp_defaults().get("throttle_narration", ""))
	return text if not text.is_empty() else DEFAULT_THROTTLE_NARRATION


static func _emotion_update_narration() -> String:
	var text: String = str(_mcp_defaults().get("emotion_update_narration", ""))
	return text if not text.is_empty() else DEFAULT_EMOTION_UPDATE_NARRATION


static func _emotion_update_empty_narration() -> String:
	var text: String = str(_mcp_defaults().get("emotion_update_empty_narration", ""))
	return text if not text.is_empty() else DEFAULT_EMOTION_UPDATE_EMPTY_NARRATION
