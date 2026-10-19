class_name MeetingOrchestrator
extends RefCounted
## Group-meeting conversation orchestrator — user + N agents.
##
## Spatial gathering is handled upstream by world_loader.call_all_agents_to_player
## + agent.join_meeting. By the time start() is called, every attendee is
## physically held at the meeting circle. This class owns the CONVERSATION
## layer on top: accept user messages, fan them out to every attendee, make
## each agent respond in a randomized order per round, and — critically —
## deliver to each agent only the messages they have NOT yet seen.
##
## Delta-tracking model
## ────────────────────
## The `transcript` is an append-only, chronologically ordered list of
## typed events:
##     {kind: "user",    index, text}                          — user spoke
##     {kind: "speech",  index, speaker_id, speaker_name, text} — agent spoke
##     {kind: "silence", index, speaker_id, speaker_name}       — agent silent
##
## Per attendee we keep `_seen_index[id]` = the last transcript index we
## have already shown that agent (or -1 if they have never been prompted).
## When it is agent X's turn, we slice events `(_seen_index[X], end]`,
## drop anything authored by X itself (their gateway session already has
## their own turns), and hand the remainder to PromptBuilder as a
## chronological `delta_events` list.
##
## Because speaking order is re-shuffled every round, two agents that swap
## positions between rounds will naturally see different slices of the
## transcript — the mapping handles that without any special casing.
##
## Silence is recorded as its own transcript event. The silent agent's
## future deltas filter that event out (never re-receives own); every
## OTHER agent's next delta will include a "{name} stayed silent." line
## so the conversation stays coherent. Silence is invisible in the UI.
##
## End of meeting
## ──────────────
## On end() we fire a single narration prompt per attendee through their
## gateway session telling them the meeting is over and forbidding a
## spoken reply. This is strictly fire-and-forget — the orchestrator does
## not await or render these responses, it only wants the event in each
## agent's session so their next interaction resumes from the right state.

var world_loader: WorldLoader
var attendee_ids: Array[String] = []
var attendee_names: Array[String] = []
var transcript: Array[Dictionary] = []
var active: bool = false
var round_index: int = 0
var _responding_queue: Array[String] = []
var _seen_index: Dictionary = {}           # agent_id -> int (last transcript idx prompted with)
var _prompted_before: Dictionary = {}      # agent_id -> bool (first-vs-continue framing)


func _init(wl: WorldLoader) -> void:
	world_loader = wl


# ── Public ──

func start(ids: Array) -> void:
	attendee_ids.clear()
	attendee_names.clear()
	transcript.clear()
	_responding_queue.clear()
	_seen_index.clear()
	_prompted_before.clear()
	round_index = 0
	for id_any in ids:
		var id: String = str(id_any)
		var agent: Agent = world_loader.find_agent(id)
		if agent == null:
			continue
		attendee_ids.append(id)
		attendee_names.append(agent.display_name)
		_seen_index[id] = -1
		_prompted_before[id] = false
	active = true


func submit_user_message(text: String) -> void:
	if not active:
		return
	if attendee_ids.is_empty():
		return
	var trimmed := text.strip_edges()
	if trimmed == "":
		return
	round_index += 1
	transcript.append({
		"kind": "user",
		"index": transcript.size(),
		"text": trimmed,
	})
	_responding_queue = attendee_ids.duplicate()
	_responding_queue.shuffle()
	_dispatch_next_responder()


func end() -> void:
	if not active:
		return
	# Fire-and-forget closing prompt to each attendee that was actually
	# prompted at least once during this meeting. Agents that joined but
	# never had a turn (meeting dismissed before any round) get nothing,
	# since their session has no meeting context to close. Done BEFORE
	# clearing state so we still have the attendee list and the delta
	# pointers to iterate. Each agent's closing prompt carries their
	# REMAINING delta — everything they had not yet seen at the moment
	# the meeting ended — so no agent is left with a stale view of the
	# last round's exchanges in their session history.
	for id: String in attendee_ids:
		if not bool(_prompted_before.get(id, false)):
			continue
		var agent: Agent = world_loader.find_agent(id)
		if agent == null:
			continue
		var delta_events: Array = _build_delta_for(id)
		var prompt: Dictionary = PromptBuilder.build_meeting_end(
			world_loader.config,
			agent,
			delta_events,
		)
		world_loader.llm.llm_chat(
			GameState.get_agent_gateway(id),
			prompt.system,
			prompt.user,
			GameState.get_agent_session(id),
			"",  # no request_id — we do not want a callback
			GameState.get_agent_model(id),
			id,
		)
	active = false
	attendee_ids.clear()
	attendee_names.clear()
	transcript.clear()
	_responding_queue.clear()
	_seen_index.clear()
	_prompted_before.clear()
	round_index = 0


# ── Internals ──

func _dispatch_next_responder() -> void:
	if not active:
		return
	if _responding_queue.is_empty():
		var dialogue: DialogueCloud = world_loader.dialogue
		if dialogue != null and dialogue.has_method("set_meeting_input_enabled"):
			dialogue.set_meeting_input_enabled(true)
		return
	var agent_id: String = _responding_queue.pop_front()
	var agent: Agent = world_loader.find_agent(agent_id)
	if agent == null:
		# Skip vanished agent, keep the round going.
		_dispatch_next_responder()
		return
	var delta_events: Array = _build_delta_for(agent_id)
	var attendees_other: Array = []
	for id: String in attendee_ids:
		if id == agent_id:
			continue
		var other: Agent = world_loader.find_agent(id)
		if other != null:
			attendees_other.append(other.display_name)
	var is_first_prompt: bool = not bool(_prompted_before.get(agent_id, false))
	var prompt: Dictionary = PromptBuilder.build_meeting_turn(
		world_loader.config,
		agent,
		{
			"is_first_prompt": is_first_prompt,
			"attendees": attendees_other,
			"delta_events": delta_events,
		},
	)
	# Bump the seen pointer BEFORE dispatch: once we have shown the agent
	# this slice, nothing in it should ever be replayed — even if the LLM
	# reply arrives much later and new events have been appended in the
	# meantime (which cannot happen today because the round is strictly
	# sequential, but the invariant is cheaper than reasoning about it).
	_seen_index[agent_id] = transcript.size() - 1
	_prompted_before[agent_id] = true
	var req_id: String = world_loader.llm_request_queue.register(
		func(text: String) -> void:
			_on_responder_reply(agent_id, text)
	)
	world_loader.llm.llm_chat(
		GameState.get_agent_gateway(agent_id),
		prompt.system,
		prompt.user,
		GameState.get_agent_session(agent_id),
		req_id,
		GameState.get_agent_model(agent_id),
		agent_id,
	)


func _build_delta_for(agent_id: String) -> Array:
	"""Chronological list of transcript events this agent has not yet been
	shown. Filters out anything authored by the agent itself — their own
	turns already live in their gateway session and re-sending would be
	both wasteful and confusing."""
	var start_idx: int = int(_seen_index.get(agent_id, -1)) + 1
	var out: Array = []
	for i in range(start_idx, transcript.size()):
		var ev: Dictionary = transcript[i]
		var author: String = ev.get("speaker_id", "")
		if author == agent_id:
			continue
		out.append(ev)
	return out


func _on_responder_reply(agent_id: String, raw: String) -> void:
	if not active:
		return
	var agent: Agent = world_loader.find_agent(agent_id)
	var display_name: String = agent.display_name if agent != null else agent_id
	var processed: String = raw
	if agent != null:
		processed = EmotionTags.parse_and_apply(processed, agent.emotion_engine)
	processed = PromptBuilder.extract_speech(processed)
	if PromptBuilder.is_silence(processed):
		# Record the silence as a transcript event so OTHER agents' future
		# deltas can surface a "{name} stayed silent." line. The silent
		# agent itself will filter this entry out of its own future deltas
		# via the author check in _build_delta_for. Silence remains
		# invisible in the dialogue panel and the narration log.
		transcript.append({
			"kind": "silence",
			"index": transcript.size(),
			"speaker_id": agent_id,
			"speaker_name": display_name,
		})
		_dispatch_next_responder()
		return
	if agent != null:
		agent.emotion_engine.process_event("conversation_turn", {"with": "group meeting"})
		agent.set_mood(agent.emotion_engine.mood)
	transcript.append({
		"kind": "speech",
		"index": transcript.size(),
		"speaker_id": agent_id,
		"speaker_name": display_name,
		"text": processed,
	})
	var dialogue: DialogueCloud = world_loader.dialogue
	if dialogue != null and dialogue.has_method("append_meeting_line"):
		dialogue.append_meeting_line(agent_id, display_name, processed, "agent")
	if world_loader.narration_log != null:
		var speaker_bb: String = "[color=%s]%s[/color]" % [
			UITheme.agent_color_hex(agent_id),
			display_name,
		]
		var mood: String = agent.emotion_engine.mood if agent != null else UITheme.MOOD_NEUTRAL
		world_loader.narration_log.add_entry(
			Strings.get_string("world.agent_speaks", {
				"speaker": speaker_bb,
				"mood": "[i](%s)[/i]" % mood,
			}),
			"dialogue",
		)
	_dispatch_next_responder()
