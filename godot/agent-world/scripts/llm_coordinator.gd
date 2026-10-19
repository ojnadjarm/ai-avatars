class_name LLMCoordinator
extends RefCounted
## Owns every LLM request the agents make in-world — arrive/observe/talk
## plus the response handlers that dispatch into the emotion engine,
## narration log, and emotion HUD. Encounters live in EncounterDispatcher.
##
## Holds only a world_loader reference; reads llm, llm_request_queue,
## activity_gate, config, narration_log, dialogue from it.

var world_loader: WorldLoader


func _init(wl: WorldLoader) -> void:
	world_loader = wl


# ── Requests ──

func request_arrive(agent_id: String) -> void:
	var agent: Agent = world_loader.find_agent(agent_id)
	if not agent:
		return
	var cfg: Dictionary = world_loader.config
	var current_world_id: String = cfg.get("id", "")
	var previous_world_id: String = agent.memory.last_world_id
	var previous_world_name: String = agent.memory.last_world_name

	# Same-world re-entry. Skip the arrival prompt entirely — the agent's
	# session already has the context for this world, and a fresh
	# "you have entered X" would just be noise. The agent resumes.
	if previous_world_id != "" and previous_world_id == current_world_id:
		return

	# NB: arrivals do NOT interact with activity_gate — they all fire at
	# world load before any autonomous loop starts, and blocking them
	# would serialize the opening moments of the scene for no benefit.

	var is_new: bool = not agent.memory.visited_locations.has(current_world_id)

	# Per-pair transition override: current world config can declare a
	# transitions map keyed by the source world id, e.g.
	#   "transitions": { "magic_forest": "The sun dips and the forest..." }
	# When present, the line replaces the entire narration.
	var override: String = ""
	if previous_world_id != "":
		var transitions: Dictionary = cfg.get("transitions", {})
		override = transitions.get(previous_world_id, "")

	# Stamp current world BEFORE the prompt goes out so subsequent
	# arrivals (this session or next launch) can compute transitions
	# correctly even if the LLM call itself fails.
	agent.memory.last_world_id = current_world_id
	agent.memory.last_world_name = cfg.get("name", "")
	agent.memory.save_to_disk()

	var p := PromptBuilder.build_arrive(cfg, agent, {
		"is_new": is_new,
		"previous_world_name": previous_world_name,
		"transition_override": override,
	})
	var req_id: String = world_loader.llm_request_queue.register(
		func(text: String) -> void:
			_handle_activity_response(agent_id, text, "arrive", {"entity_name": "a new place — %s" % cfg.get("name", "")})
	)
	_send(agent_id, p, req_id)


func request_observe(agent_id: String, entity_id: String, entity_name: String, entity_desc: String) -> void:
	var agent: Agent = world_loader.find_agent(agent_id)
	if not agent:
		return
	world_loader.activity_gate.trigger()
	# Prop entities get PropLayers-rendered description (base + qualifying
	# layer texts). Non-prop entities (other agents, player) pass through
	# with their caller-supplied description unchanged.
	var desc: String = entity_desc
	if world_loader.world_state != null:
		var prop_cfg: Dictionary = world_loader.find_prop_config(entity_id)
		if not prop_cfg.is_empty():
			desc = PropLayers.render_for_agent(prop_cfg, agent, world_loader.world_state)
	var p := PromptBuilder.build_observe(world_loader.config, agent, entity_name, desc)
	var req_id: String = world_loader.llm_request_queue.register(
		func(text: String) -> void:
			_handle_activity_response(agent_id, text, "observe", {"entity_id": entity_id, "entity_name": entity_name})
	)
	_send(agent_id, p, req_id)


func request_talk(agent_id: String, player_message: String) -> void:
	var agent: Agent = world_loader.find_agent(agent_id)
	var p := PromptBuilder.build_talk(world_loader.config, agent, player_message)
	var req_id: String = world_loader.llm_request_queue.register(
		func(text: String) -> void:
			_handle_talk_response(agent_id, text)
	)
	_send(agent_id, p, req_id)


func request_call(agent_id: String) -> void:
	var agent: Agent = world_loader.find_agent(agent_id)
	if not agent:
		return
	var p := PromptBuilder.build_call(world_loader.config, agent)
	var req_id: String = world_loader.llm_request_queue.register(
		func(text: String) -> void:
			_handle_talk_response(agent_id, text)
	)
	_send(agent_id, p, req_id)


func _send(agent_id: String, p: Dictionary, req_id: String) -> void:
	world_loader.llm.llm_chat(
		GameState.get_agent_gateway(agent_id),
		p.system, p.user,
		GameState.get_agent_session(agent_id),
		req_id,
		GameState.get_agent_model(agent_id),
		agent_id,
	)


# ── Response handlers ──

func _handle_activity_response(agent_id: String, thought: String, kind: String, ctx: Dictionary) -> void:
	"""Shared handler for arrive + observe. `kind` selects the narration
	phrasing; `ctx` carries any extra fields (entity_id, entity_name) that
	one branch uses and the other ignores.

	Action-resolution step runs AFTER EmotionTags parsing but BEFORE
	extract_speech — extract_speech strips anything outside <speech>, which
	would drop the <action> tag. R20: arrivals discard any <action> without
	entering the resolver (arrival responses are read-only world-entry events).
	"""
	var agent: Agent = world_loader.find_agent(agent_id)
	if not agent:
		return
	thought = EmotionTags.parse_and_apply(thought, agent.emotion_engine)
	# Action resolution step — observe path only per R20.
	if kind == "observe":
		_resolve_action_from_response(agent, thought)
	thought = PromptBuilder.extract_speech(thought)
	var speaker_bb := "[color=%s]%s[/color]" % [UITheme.agent_color_hex(agent_id), agent.display_name]
	if not PromptBuilder.is_silence(thought):
		agent.show_thought(thought)
		var entity_name: String = ctx.get("entity_name", "")
		if kind == "observe" and entity_name != "":
			var entity_bb := "[color=%s]%s[/color]" % [UITheme.TEXT_DIM_HEX, entity_name]
			world_loader.narration_log.add_entry(
				Strings.get_string("world.agent_notices", {"speaker": speaker_bb, "entity": entity_bb, "thought": thought}),
				"thought",
			)
		else:
			world_loader.narration_log.add_entry(
				Strings.get_string("world.agent_says", {"speaker": speaker_bb, "thought": thought}),
				"thought",
			)
	if kind == "observe":
		var entity_id: String = ctx.get("entity_id", "")
		if agent.memory and entity_id != "":
			var is_novel: bool = not agent.memory.has_seen(entity_id)
			agent.memory.add_observation(entity_id)
			agent.memory.save_to_disk()
			if is_novel:
				agent.emotion_engine.process_event("new_topic", {"entity_name": ctx.get("entity_name", "")})
		agent.set_mood(agent.emotion_engine.mood)
		agent.finish_activity()
	else:
		agent.emotion_engine.process_event("new_topic", {"entity_name": ctx.get("entity_name", "")})
		agent.set_mood(agent.emotion_engine.mood)


func _handle_talk_response(agent_id: String, response: String) -> void:
	var agent: Agent = world_loader.find_agent(agent_id)
	var agent_name: String = agent.display_name if agent else agent_id
	if agent:
		response = EmotionTags.parse_and_apply(response, agent.emotion_engine)
		response = PromptBuilder.extract_speech(response)
		agent.emotion_engine.process_event("conversation_turn", {"with": "your user"})
		agent.set_mood(agent.emotion_engine.mood)
	var dialogue: DialogueCloud = world_loader.dialogue
	if dialogue.conversation_history.size() > 0:
		var last = dialogue.conversation_history[dialogue.conversation_history.size() - 1]
		if not last["is_player"] and last["speaker"] == "":
			dialogue.conversation_history.pop_back()
	var mood: String = agent.emotion_engine.mood if agent else UITheme.MOOD_NEUTRAL
	dialogue.set_mood(mood)
	dialogue.show_response(agent_name, response)
	var speaker_bb := "[color=%s]%s[/color]" % [UITheme.agent_color_hex(agent_id), agent_name]
	world_loader.narration_log.add_entry(
		Strings.get_string("world.agent_speaks", {"speaker": speaker_bb, "mood": "[i](%s)[/i]" % mood}),
		"dialogue",
	)


func _resolve_action_from_response(agent: Object, response: String) -> void:
	## R14 action resolution. Parse <action> tag →
	## world_loader.submit_agent_action() → ActionResolver.resolve() runs
	## immediately and synchronously. The post-resolve step
	## (_apply_action_result) then runs: log narration type "action",
	## fire-and-forget narration to the agent's session, queue debounced
	## save. No-op when the response contains no <action> tag.
	##
	## `agent` is typed as Object (not Agent) to mirror ActionResolver.resolve()
	## — both helpers duck-type a single property (`agent.agent_id`), and the
	## broader type lets tests drive the seam with a lightweight stub.
	if world_loader.action_resolver == null:
		return
	# Migration step B4 (cozy-plotting-dusk.md Part B "Coexistence" bullet):
	# an MCP agent's world-actions already ran through
	# world_loader.submit_agent_action() the moment its tools/call arrived
	# (see mcp_server.gd._dispatch_tool_call) — a habit-emitted <action> tag
	# surviving into this agent's chat text (memory/training habit, not
	# something its prompts instruct — prompt_builder omits
	# action_tag_instructions for MCP agents) must be discarded here rather
	# than resolved a second time.
	if GameState.is_agent_mcp(agent.agent_id):
		return
	var action: Dictionary = ActionResolver.extract_action(response)
	if action.is_empty():
		return
	world_loader.submit_agent_action(agent, action, "xml", func(result: Dictionary) -> void:
		_apply_action_result(agent, result)
	)


## Shared post-resolve step for _resolve_action_from_response. `result` is
## always shaped {narration, state_changed}, coming straight from
## ActionResolver.resolve() — actions resolve immediately and
## synchronously, with no approval hold. Mirrors the original v0.8
## direct-resolve post-processing exactly: no-op narration means nothing to
## log/echo (also the v0.7-regression-free path when no puzzle files are
## authored — AC-PERF-03).
func _apply_action_result(agent: Object, result: Dictionary) -> void:
	var narration: String = str(result.get("narration", ""))
	var state_changed: bool = bool(result.get("state_changed", false))
	if not narration.is_empty() and world_loader.narration_log != null:
		# Bare narration, no speaker prefix — "action" entries are
		# second-person world-fact lines ("You reach the pillar."), so a
		# third-person speaker tag would read wrong. Locked contract (TD-010),
		# deliberately unlike the "thought"/"dialogue" entry types.
		world_loader.narration_log.add_entry(narration, "action")
		# Fire-and-forget: route narration back to the agent's session so
		# their next turn includes this world event as context. Empty
		# request_id means no callback — mirrors meeting_orchestrator.end().
		world_loader.llm.llm_chat(
			GameState.get_agent_gateway(agent.agent_id),
			"",  # empty system prompt — session already holds persona
			"<narration>%s</narration>" % narration,
			GameState.get_agent_session(agent.agent_id),
			"",  # no request_id — fire-and-forget
			GameState.get_agent_model(agent.agent_id),
			agent.agent_id,
		)
	if state_changed:
		world_loader.queue_world_state_save(false)
