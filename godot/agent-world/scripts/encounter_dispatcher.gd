class_name EncounterDispatcher
extends RefCounted
## Multi-turn A2A encounter flow between two agents. Owns the A2A router.
##
## Flow:
##   1. Sender's LLM generates a greeting (build_a2a_greeting).
##   2. Greeting → router → listener's LLM replies via build_a2a_message.
##   3. _handle_reply either re-dispatches with roles swapped (next turn)
##      or, at the turn cap, fires one silent closing-context delivery
##      to the OTHER agent's session (build_a2a_context_delivery) so both
##      sessions hold the full exchange, then unwinds both agents back to
##      their idle loops.
## Both agents sit in State.ENCOUNTERING for the whole exchange so neither
## wanders off mid-conversation.

## Emitted once when the encounter fully concludes (all turns exhausted, early
## silence, or LLM error). context_id is the stable identifier assigned at
## start() — non-empty only when the encounter was initiated via call_agent
## (puzzle layer); empty for proximity-triggered encounters. Implements TR-puzzle-027.
signal encounter_complete(sender_id: String, listener_id: String, context_id: String)

var world_loader: WorldLoader
var router: A2ARouter
var max_turns: int = 3
## Stable context identifier for the current encounter. Set unconditionally at
## the top of start() before any early-return guards so tests can drive _end()
## directly without going through the LLM round-trip.
var _current_context_id: String = ""


func _init(wl: WorldLoader, turns: int) -> void:
	world_loader = wl
	max_turns = turns
	router = A2ARouter.new()
	router.world_loader = wl


## Extended signature (Story 008 / TR-puzzle-026). context_id defaults to ""
## for existing proximity-triggered call sites. Assignment of _current_context_id
## happens unconditionally BEFORE the sender/listener lookup so that tests can
## call _end() directly after start() without completing the LLM round-trip.
func start(sender_id: String, listener_id: String, context_id: String = "") -> void:
	_current_context_id = context_id
	var sender: Agent = world_loader.find_agent(sender_id)
	var listener: Agent = world_loader.find_agent(listener_id)
	if not sender or not listener:
		return
	# Stamp the global cooldown timer the moment the encounter triggers.
	# No release at the end — the timer drains on its own.
	world_loader.activity_gate.trigger()
	# Freeze the listener for the whole encounter. Sender is already in
	# ENCOUNTERING state from agent._start_encounter before calling us.
	listener.enter_encountering()
	var is_new: bool = not (sender.memory and sender.memory.has_met(listener_id))
	if sender.memory:
		sender.memory.mark_met(listener_id)
		sender.memory.save_to_disk()
	var p := PromptBuilder.build_a2a_greeting(world_loader.config, sender, listener.display_name, is_new)
	var req_id: String = world_loader.llm_request_queue.register(
		func(greeting_text: String) -> void:
			_dispatch_greeting(sender_id, listener_id, greeting_text)
	)
	world_loader.llm.llm_chat(
		GameState.get_agent_gateway(sender_id),
		p.system, p.user,
		GameState.get_agent_session(sender_id),
		req_id,
		GameState.get_agent_model(sender_id),
		sender_id,
	)


func _dispatch_greeting(sender_id: String, listener_id: String, greeting_text: String) -> void:
	var sender: Agent = world_loader.find_agent(sender_id)
	if not sender:
		_end(sender_id, listener_id)
		return
	greeting_text = EmotionTags.parse_and_apply(greeting_text, sender.emotion_engine)
	var spoken := PromptBuilder.extract_speech(greeting_text)
	if PromptBuilder.is_silence(spoken):
		push_warning("[a2a] sender %s produced no speech; aborting encounter" % sender_id)
		_end(sender_id, listener_id)
		return
	_render_speech(sender_id, listener_id, spoken, true)
	_dispatch_turn(sender_id, listener_id, spoken, sender_id, listener_id, 1)


func _dispatch_turn(initiator_id: String, other_id: String, spoken: String, from_id: String, to_id: String, turn: int) -> void:
	# initiator_id = agent who started the encounter (owns finish_activity at end)
	# other_id     = the non-initiator
	# from_id/to_id = current round's sender/receiver; swap each turn
	# turn         = 1-indexed; encounter ends when turn reaches max_turns
	var a2a_msg := A2ATypes.message(A2ATypes.ROLE_USER, [A2ATypes.text_part(spoken)])
	var params := {
		"message": a2a_msg,
		"meta": {
			"mid_conversation": turn > 1,
			"final_turn": turn >= max_turns,
		},
	}
	var rpc_req := A2ATypes.rpc_request("enc-%d" % turn, "message/send", params)
	var target_url := AgentCard.url_for(to_id)
	router.dispatch(
		from_id, target_url, rpc_req,
		func(rpc_response: Dictionary) -> void:
			_handle_reply(initiator_id, other_id, from_id, to_id, rpc_response, turn)
	)


func _handle_reply(initiator_id: String, other_id: String, prev_from_id: String, prev_to_id: String, rpc_response: Dictionary, turn: int) -> void:
	var listener: Agent = world_loader.find_agent(prev_to_id)
	if rpc_response.has("error"):
		push_warning("[a2a] turn %d failed: %s" % [turn, str(rpc_response["error"])])
		_end(initiator_id, other_id)
		return
	var t: Dictionary = rpc_response.get("result", {})
	var artifacts: Array = t.get("artifacts", [])
	var reply_text := ""
	if not artifacts.is_empty():
		var parts: Array = artifacts[0].get("parts", [])
		if not parts.is_empty():
			reply_text = parts[0].get("text", "")
	if listener and listener.emotion_engine:
		reply_text = EmotionTags.parse_and_apply(reply_text, listener.emotion_engine)
	var spoken := PromptBuilder.extract_speech(reply_text)
	if PromptBuilder.is_silence(spoken):
		push_warning("[a2a] turn %d: %s produced no speech; ending encounter" % [turn, prev_to_id])
		_end(initiator_id, other_id)
		return
	_render_speech(prev_to_id, prev_from_id, spoken, false)
	if turn >= max_turns:
		# Final spoken turn done. The speaker's session already holds this
		# line (it was generated there), but the listener's session doesn't
		# — they only received it through the router callback as a
		# rendered narration beat. Fire one silent LLM round-trip against
		# the listener so their history records the closing line, with a
		# strict "do not reply" instruction so nothing new is rendered.
		_deliver_closing_context(initiator_id, other_id, prev_to_id, prev_from_id, spoken)
		return
	_dispatch_turn(initiator_id, other_id, spoken, prev_to_id, prev_from_id, turn + 1)


func _deliver_closing_context(initiator_id: String, other_id: String, speaker_id: String, receiver_id: String, closing_text: String) -> void:
	# speaker_id just produced the final spoken line of the encounter.
	# receiver_id is the other participant — they heard it rendered in
	# the world but their LLM session has no record of it yet. One last
	# LLM round-trip against receiver_id lands the closing line in their
	# session, then _end unfreezes both agents. The reply is intentionally
	# discarded (see build_a2a_context_delivery — the prompt tells the
	# agent to reply NO_REPLY).
	var receiver: Agent = world_loader.find_agent(receiver_id)
	if not receiver:
		_end(initiator_id, other_id)
		return
	var speaker: Agent = world_loader.find_agent(speaker_id)
	var speaker_name: String = speaker.display_name if speaker else speaker_id
	var p := PromptBuilder.build_a2a_context_delivery(world_loader.config, receiver, speaker_name, closing_text)
	var req_id: String = world_loader.llm_request_queue.register(
		func(_discarded_reply: String) -> void:
			_end(initiator_id, other_id)
	)
	world_loader.llm.llm_chat(
		GameState.get_agent_gateway(receiver_id),
		p.system, p.user,
		GameState.get_agent_session(receiver_id),
		req_id,
		GameState.get_agent_model(receiver_id),
		receiver_id,
	)


## Single exit point for every encounter outcome. Emits encounter_complete
## exactly once with the stable context_id captured at start(), then resets
## _current_context_id so a subsequent encounter starts clean.
func _end(initiator_id: String, other_id: String) -> void:
	var initiator: Agent = world_loader.find_agent(initiator_id)
	var other: Agent = world_loader.find_agent(other_id)
	if initiator:
		initiator.finish_activity()
	if other:
		other.mark_encounter_ended()
	encounter_complete.emit(initiator_id, other_id, _current_context_id)
	_current_context_id = ""


func _render_speech(speaker_id: String, other_id: String, text: String, is_greeting: bool) -> void:
	if PromptBuilder.is_silence(text):
		return
	var speaker: Agent = world_loader.find_agent(speaker_id)
	var speaker_name: String = speaker.display_name if speaker else speaker_id
	var other: Agent = world_loader.find_agent(other_id)
	var other_name: String = other.display_name if other else other_id
	if speaker:
		speaker.show_thought(text)
	var speaker_bb := "[color=%s]%s[/color]" % [UITheme.agent_color_hex(speaker_id), speaker_name]
	var other_bb := "[color=%s]%s[/color]" % [UITheme.agent_color_hex(other_id), other_name]
	var verb: String = Strings.get_string("a2a.greets" if is_greeting else "a2a.answers")
	world_loader.narration_log.add_entry(
		Strings.get_string("a2a.turn_line", {"speaker": speaker_bb, "verb": verb, "listener": other_bb, "text": text}),
		"dialogue"
	)
