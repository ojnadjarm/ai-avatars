class_name A2ARouter
extends RefCounted
## In-process A2A dispatcher. Takes a JSON-RPC request built with
## A2ATypes, runs the listener's LLM on the sender's behalf, and hands
## back a completed Task through a callback.
##
## Same payload shapes as the wire protocol (Message/Part/Task/JSON-RPC)
## so swapping in real HTTP later is a one-file change: the router's
## dispatch becomes an HTTPRequest.post(target_url, rpc_request).

# Injected by world_loader on construction.
var world_loader: WorldLoader

# In-memory Task store. Keyed by task_id. Lost on game restart — same
# default as a2a-sdk's InMemoryTaskStore. Persistence is a future step.
var _tasks: Dictionary = {}

# Relationship threads. Sorted pair key ("a:b" with a<b) → contextId.
# Two agents keep the same contextId across every encounter they share,
# so the listener's OpenClaw/Hermes session can maintain continuity
# without us re-injecting past dialogue.
var _relationship_contexts: Dictionary = {}


func dispatch(from_agent_id: String, target_url: String, rpc_req: Dictionary, callback: Callable) -> void:
	"""Public entry point. Callback receives a JSON-RPC response dict
	(either {result: Task} or {error: {code, message}})."""
	var rpc_id: String = rpc_req.get("id", "")
	var method: String = rpc_req.get("method", "")
	match method:
		"message/send":
			_handle_message_send(from_agent_id, target_url, rpc_req, callback)
		_:
			callback.call(A2ATypes.rpc_error(rpc_id, -32601, "Method not found: " + method))


# ── message/send ──────────────────────────────────────────────────────────

func _handle_message_send(from_agent_id: String, target_url: String, rpc_req: Dictionary, callback: Callable) -> void:
	var rpc_id: String = rpc_req.get("id", "")
	var params: Dictionary = rpc_req.get("params", {})
	var message: Dictionary = params.get("message", {})

	var to_agent_id := _parse_inproc_url(target_url)
	if to_agent_id == "":
		callback.call(A2ATypes.rpc_error(rpc_id, -32602, "Invalid target URL: " + target_url))
		return

	var listener: Agent = world_loader.find_agent(to_agent_id)
	if not listener:
		callback.call(A2ATypes.rpc_error(rpc_id, -32602, "Target agent not found: " + to_agent_id))
		return

	var ctx_id := _context_for_pair(from_agent_id, to_agent_id)
	var task_id := A2ATypes.new_task_id()

	# Stamp the incoming message with the task+context ids so the full
	# Task history is self-describing.
	var incoming_msg: Dictionary = message.duplicate(true)
	incoming_msg["contextId"] = ctx_id
	incoming_msg["taskId"] = task_id

	var t := A2ATypes.task(task_id, ctx_id, A2ATypes.STATE_WORKING, [incoming_msg], [])
	_tasks[task_id] = t

	var speaker_name := _display_name_for(from_agent_id)
	var incoming_text := _extract_text(message)
	# Game-level "have they met" — separate from the LLM session memory.
	# Drives first-encounter vs return-encounter prompt framing.
	var is_new_encounter: bool = true
	if listener.memory:
		is_new_encounter = not listener.memory.has_met(from_agent_id)
	# Extension metadata — turn pacing flags passed by world_loader via
	# rpc_req.params.meta. A2A allows arbitrary extension fields on
	# params; we use it here to tell the prompt builder whether we're
	# mid-conversation and whether this is the final turn.
	var meta: Dictionary = params.get("meta", {})
	var opts := {
		"is_new_encounter": is_new_encounter,
		"mid_conversation": meta.get("mid_conversation", false),
		"final_turn": meta.get("final_turn", false),
	}
	var prompt := PromptBuilder.build_a2a_message(world_loader.config, listener, speaker_name, incoming_text, opts)

	# Register a callback on world_loader's request queue. When the LLM
	# replies we complete the Task and invoke the A2A callback.
	var llm_req_id: String = world_loader.llm_request_queue.register(
		func(reply_text: String) -> void:
			_complete_task(task_id, reply_text, rpc_id, from_agent_id, to_agent_id, callback)
	)

	world_loader.llm.llm_chat(
		GameState.get_agent_gateway(to_agent_id),
		prompt.system, prompt.user,
		GameState.get_agent_session(to_agent_id),
		llm_req_id,
		GameState.get_agent_model(to_agent_id),
		to_agent_id
	)


func _complete_task(task_id: String, reply_text: String, rpc_id: String, from_agent_id: String, to_agent_id: String, callback: Callable) -> void:
	var t: Dictionary = _tasks.get(task_id, {})
	if t.is_empty():
		callback.call(A2ATypes.rpc_error(rpc_id, -32603, "Task vanished: " + task_id))
		return

	var reply_msg := A2ATypes.message(
		A2ATypes.ROLE_AGENT,
		[A2ATypes.text_part(reply_text)],
		t["contextId"],
		task_id,
	)
	var art := A2ATypes.artifact("art-" + task_id.trim_prefix("task-"), "reply", [A2ATypes.text_part(reply_text)])

	t["history"].append(reply_msg)
	t["artifacts"].append(art)
	t["status"]["state"] = A2ATypes.STATE_COMPLETED

	# Game-level "have they met" — mark the listener as having met the
	# speaker now that the exchange completed successfully. The sender
	# side is marked by the caller (the proximity trigger) since the
	# router doesn't hold a reference to the sender agent.
	var listener: Agent = world_loader.find_agent(to_agent_id)
	if listener and listener.memory:
		listener.memory.mark_met(from_agent_id)
		listener.memory.save_to_disk()

	callback.call(A2ATypes.rpc_result(rpc_id, t))


# ── Helpers ───────────────────────────────────────────────────────────────

func _parse_inproc_url(url: String) -> String:
	const PREFIX := "inproc://"
	if not url.begins_with(PREFIX):
		return ""
	return url.substr(PREFIX.length())


func _context_for_pair(a: String, b: String) -> String:
	var pair_key: String = (a + ":" + b) if a < b else (b + ":" + a)
	if not _relationship_contexts.has(pair_key):
		_relationship_contexts[pair_key] = A2ATypes.new_context_id()
	return _relationship_contexts[pair_key]


func _display_name_for(agent_id: String) -> String:
	var cfg: Dictionary = GameState.agents.get(agent_id, {})
	return cfg.get("display_name", agent_id)


func _extract_text(msg: Dictionary) -> String:
	var parts: Array = msg.get("parts", [])
	var out := ""
	for p: Dictionary in parts:
		if p.get("kind", "") == A2ATypes.PART_TEXT:
			out += p.get("text", "")
	return out
