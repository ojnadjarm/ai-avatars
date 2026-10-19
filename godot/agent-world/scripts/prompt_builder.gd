class_name PromptBuilder
extends RefCounted
## Centralized prompt construction for every LLM call an agent makes.
##
## All event content is wrapped in XML tags — modern LLMs (Claude in
## particular) are trained heavily on XML and anchor their reading of
## a turn around tag boundaries. Vocabulary:
##
##   <narration>…</narration>
##       World events: arrival at a place, noticing a prop, ambient
##       description. Nothing is "said" to the agent — the world is
##       simply what is.
##
##   <USER.md_message>…</USER.md_message>
##       The user (the person described in the agent's USER.md) is
##       speaking directly to the agent. This phrasing lets the agent
##       bridge straight to its USER.md persona without us having to
##       re-inject that file into every prompt.
##
##   <agent_message><agent>name</agent>…</agent_message>
##       Another agent is speaking. Used by the future A2A proximity
##       loop — speaker identified by name so the listener can address
##       them in character.

const SPEECH_TAG_INSTRUCTIONS := """Wrap the words you say — out loud to another, or quietly to yourself — inside <speech>...</speech> tags. One or two sentences, no more. Anything outside those tags stays as private inner monologue and will NOT be rendered in the world. Only the <speech> content is heard or shown. Example:

<speech>This is a beautiful place.</speech>"""

## Compiled once at class load (TD-011) — extract_speech runs on every LLM
## response, and the sibling <action> strip already shares a class-load
## static (ActionResolver.ACTION_TAG_REGEX); this keeps the two symmetric.
static var SPEECH_TAG_REGEX: RegEx = _build_speech_regex()


static func _build_speech_regex() -> RegEx:
	var re := RegEx.new()
	re.compile("(?s)<speech>(.*?)</speech>")
	return re

# ── Action tag instructions helper ────────────────────────────────────────

## Returns the ACTION_TAG_INSTRUCTIONS fragment for the given world config.
## World-level override (world_config["action_tag_instructions"]) takes
## precedence over the global default stored in
## GameState.defaults.puzzle.action_tag_instructions. Returns "" when neither
## is set so callers can safely skip appending an empty string.
static func _action_tag_instructions(world_config: Dictionary) -> String:
	var override: String = world_config.get("action_tag_instructions", "")
	if not override.is_empty():
		return override
	var puzzle_defaults: Variant = GameState.get_default("puzzle", {})
	if puzzle_defaults is Dictionary:
		var fragment: String = (puzzle_defaults as Dictionary).get("action_tag_instructions", "")
		return fragment
	return ""


# ── Shared context ────────────────────────────────────────────────────────

static func build_context(config: Dictionary, agent: Agent) -> String:
	"""Base system-prompt context shared by every prompt an agent sends.
	Location name + emotion + emotion-self-report instructions. Props are
	NOT listed — the world is meant to be discovered. Memory is NOT
	injected either — the OpenClaw session already persists prior turns,
	and injecting the client-side memory on top would duplicate (and
	conflict with) what the session holds. The client-side AgentMemory
	still powers gameplay (interest gating, obs counts, first-visit
	detection) but stays out of the LLM prompt."""
	var parts: PackedStringArray = []
	parts.append("Location: %s (%s)" % [config.get("name", ""), config.get("biome", "")])
	if agent:
		parts.append(agent.emotion_engine.to_prompt_injection())
	parts.append(EmotionTags.INSTRUCTIONS)
	return "\n".join(parts)


# ── Arrival ───────────────────────────────────────────────────────────────

static func build_arrive(config: Dictionary, agent: Agent, opts: Dictionary) -> Dictionary:
	"""Agent arrives at a location.
	opts fields:
	  is_new: bool — true if the agent has never walked this world before
	  previous_world_name: String — "" for first ever launch, else the
	      name of the world they were in last session
	  transition_override: String — "" or a verbatim cross-world narration
	      pulled from config.transitions[previous_world_id]; if set, it
	      replaces the entire narration (used for correlated worlds like
	      a day→dusk pairing)
	Four outcomes:
	  override present → verbatim line, ignores everything else
	  previous == ""  → first ever launch: 'existed as agent, new worlds
	                    crafted, chose to step into this one'
	  previous != "", is_new → crossed from {prev} into somewhere new
	  previous != "", !is_new → crossed from {prev} back to a familiar place
	Same-world re-entry (previous == current world) is handled in the
	coordinator by skipping this call entirely — the agent's session just
	resumes from its last turn."""
	var system := build_context(config, agent)
	var name: String = config.get("name", "")
	var narration: String
	var override: String = opts.get("transition_override", "")
	if override != "":
		narration = override
	else:
		var previous: String = opts.get("previous_world_name", "")
		var is_new: bool = opts.get("is_new", false)
		var desc: String = config.get("description", "")
		var ambient: String = config.get("ambient", "")
		if previous == "":
			narration = "You have existed as an agent for a while now. New worlds have been crafted for agents like you to walk and explore, and you have chosen to step into one of them. You have joined %s. %s" % [name, desc]
			if ambient != "":
				narration += " You hear %s." % ambient
		elif is_new:
			narration = "Wandering through %s, you find a path that leads somewhere new. You have joined %s, a world unfamiliar to you. %s" % [previous, name, desc]
			if ambient != "":
				narration += " You hear %s." % ambient
		else:
			narration = "Wandering through %s, you find a way back to %s — a world you have walked before." % [previous, name]
	# The _action_tag_instructions fragment is intentionally excluded here —
	# arrival responses have <action> discarded downstream (R20/TR-puzzle-020).
	# Appending action vocabulary at arrival would be misleading: the agent
	# cannot act on a world it has just stepped into for the first time in a
	# given prompt.
	system += "\n" + SPEECH_TAG_INSTRUCTIONS
	return {"system": system, "user": "<narration>%s</narration>" % narration}


# ── Observation ───────────────────────────────────────────────────────────

static func build_observe(config: Dictionary, agent: Agent, entity_name: String, entity_desc: String) -> Dictionary:
	"""Agent notices something while wandering.
	Pure narration, no directive about how to respond. The frame is
	'you were wandering and something caught your eye' — the agent
	decides what to do with it."""
	var system := build_context(config, agent)
	var narration := "You were wandering around %s when something caught your attention — %s: %s" % [
		config.get("name", ""), entity_name, entity_desc]
	system += "\n" + SPEECH_TAG_INSTRUCTIONS
	# MCP agents act on the world through tools/call, not <action> tags —
	# omit the XML authoring instructions entirely so their system prompt
	# never describes a transport they don't use (migration step B4, see
	# cozy-plotting-dusk.md Part B "Coexistence" bullet). Non-MCP agents and
	# tests that pass a null agent (no MCP status to check) keep today's
	# behavior unchanged.
	if agent == null or not GameState.is_agent_mcp(agent.agent_id):
		var fragment: String = _action_tag_instructions(config)
		if not fragment.is_empty():
			system += "\n" + fragment
	return {"system": system, "user": "<narration>%s</narration>" % narration}


# ── User chat ─────────────────────────────────────────────────────────────

static func build_talk(config: Dictionary, agent: Agent, user_message: String) -> Dictionary:
	"""The user (from USER.md) sends a message to the agent.
	This is the only prompt that tells the agent who is talking — direct
	message from the person described in their USER.md."""
	var system := build_context(config, agent)
	system += "\nThe person speaking to you is your user — the one described in your USER.md."
	system += "\n" + SPEECH_TAG_INSTRUCTIONS
	return {"system": system, "user": "<USER.md_message>%s</USER.md_message>" % user_message}


# ── Agent called by user ─────────────────────────────────────────────────

static func build_call(config: Dictionary, agent: Agent) -> Dictionary:
	"""The user has called the agent — they search and find them.
	Framed as narration: the agent experiences the summons, sets off,
	and speaks their first words the moment they arrive. The USER.md
	system note is injected so the agent knows who is waiting for them."""
	var system := build_context(config, agent)
	system += "\nThe person you are about to speak with is your user — the one described in your USER.md."
	system += "\n" + SPEECH_TAG_INSTRUCTIONS
	var narration := "Your user is calling for you. You set off toward them, searching through %s until their familiar face comes into view. You have just reached them." % config.get("name", "this place")
	return {"system": system, "user": "<narration>%s</narration>" % narration}


# ── Group meeting (user + N agents) ──────────────────────────────────────

static func build_meeting_turn(
	config: Dictionary,
	agent: Agent,
	opts: Dictionary,
) -> Dictionary:
	"""One responder's turn during a group meeting.
	opts fields:
	  is_first_prompt: bool — true the first time this agent is prompted in
	      the meeting. First prompt carries the full group framing (who is
	      there, that the user just spoke). Subsequent prompts use a short
	      continuation framing — the agent already knows it is in a meeting
	      because its gateway session holds the first prompt.
	  attendees: Array[String] — display names of EVERY attendee in the
	      meeting except the one being prompted. Only used when
	      is_first_prompt == true.
	  delta_events: Array[Dictionary] — chronological list of transcript
	      events this agent has not yet been shown. Each entry is one of:
	          {kind: "user",    text: String}
	          {kind: "speech",  speaker_name: String, text: String}
	          {kind: "silence", speaker_name: String}
	      The orchestrator guarantees no entry is authored by `agent`
	      itself — an agent never re-receives its own turns because the
	      gateway session already holds them.
	The delta is wrapped in a single <meeting_discussion> block so the
	LLM sees one coherent chunk of "what happened while you were not
	speaking," in the real order it happened."""
	var system := build_context(config, agent)
	var is_first_prompt: bool = opts.get("is_first_prompt", true)
	var attendees: Array = opts.get("attendees", [])
	var delta_events: Array = opts.get("delta_events", [])
	if is_first_prompt:
		var framing: String
		if attendees.is_empty():
			framing = Strings.get_string("meeting.system_group_framing_solo")
		else:
			framing = Strings.get_string(
				"meeting.system_group_framing",
				{"others": ", ".join(attendees)},
			)
		system += "\n" + framing
	else:
		system += "\n" + Strings.get_string("meeting.system_group_framing_continues")
	system += "\n" + SPEECH_TAG_INSTRUCTIONS
	var body: String = "<meeting_discussion>" + _render_meeting_delta(delta_events) + "</meeting_discussion>"
	return {"system": system, "user": body}


static func _render_meeting_delta(delta_events: Array) -> String:
	"""Renders a chronological delta of meeting events as the inner body of
	a <meeting_discussion> block. Does NOT emit the outer opening/closing
	tags — callers own those, so they can append extra markup (e.g. the
	end-of-meeting narration) before closing the block."""
	var out: String = ""
	for event: Dictionary in delta_events:
		var kind: String = event.get("kind", "")
		match kind:
			"user":
				var text: String = event.get("text", "")
				if text != "":
					out += "<USER.md_message>%s</USER.md_message>" % text
			"speech":
				var speaker: String = event.get("speaker_name", "")
				var text2: String = event.get("text", "")
				if speaker != "" and text2 != "":
					out += "<agent_message><agent>%s</agent>%s</agent_message>" % [speaker, text2]
			"silence":
				var silent_name: String = event.get("speaker_name", "")
				if silent_name != "":
					out += "<narration>%s</narration>" % Strings.get_string(
						"meeting.silence_narration", {"name": silent_name}
					)
	return out


static func build_meeting_end(config: Dictionary, agent: Agent, delta_events: Array) -> Dictionary:
	"""Fire-and-forget closing prompt sent to every attendee when the user
	dismisses the meeting. Delivers the agent's REMAINING delta — the
	events they still had not seen at the moment the meeting ended,
	filtered as usual so the agent never receives its own turns — and
	appends a terminal <narration> inside the same <meeting_discussion>
	block announcing the dispersal. The system prompt forbids a spoken
	reply (no one is around to hear it) and no response is rendered or
	awaited by the game, but the agent's session now holds a complete,
	in-order record of everything said plus the close."""
	var system := build_context(config, agent)
	system += "\n" + Strings.get_string("meeting.ended_system_instruction")
	var body: String = "<meeting_discussion>"
	body += _render_meeting_delta(delta_events)
	body += "<narration>%s</narration>" % Strings.get_string("meeting.ended_narration")
	body += "</meeting_discussion>"
	return {"system": system, "user": body}


# ── Agent-to-agent (A2A encounter) ────────────────────────────────────────

static func build_a2a_greeting(config: Dictionary, agent: Agent, other_name: String, is_new_encounter: bool) -> Dictionary:
	"""Sender-side prompt: the agent has just spotted another agent and
	needs to produce a greeting. The LLM's reply becomes the payload of
	an A2A message sent to the listener (see build_a2a_message for the
	listener side). Framed as world narration, not a directive.
	Agents wrap their spoken line in <speech>; anything outside is
	private musing that stays in the session but never reaches the game."""
	var system := build_context(config, agent)
	var narration: String
	if is_new_encounter:
		system += "\nYou have spotted a stranger you have never met before. Looks, friendly. You decide to approach and present yourself."
		narration = "You see a stranger in the distance."
	else:
		system += "\nYou have spotted %s a familiar face, you approach them and have a little chat." % other_name
		narration = "You spot %s nearby." % other_name
	system += "\n" + SPEECH_TAG_INSTRUCTIONS
	return {"system": system, "user": "<narration>%s</narration>" % narration}


static func build_a2a_message(config: Dictionary, agent: Agent, speaker_name: String, incoming_text: String, opts: Dictionary) -> Dictionary:
	"""Another agent is speaking to this one. The speaker is NOT the user
	— no USER.md reference here. Wrapped in <agent_message> with a
	<agent> child naming the speaker so the listener can address them.
	Framing varies by the opts flags:
	  is_new_encounter (turn 1 only) — stranger vs familiar-face
	  mid_conversation (turn 2+) — "you're in an ongoing exchange"
	  final_turn (last turn) — "this is your closing line"
	When mid_conversation is true, is_new_encounter is ignored — the
	agents have clearly met by then regardless of prior state."""
	var is_new: bool = opts.get("is_new_encounter", true)
	var mid_conversation: bool = opts.get("mid_conversation", false)
	var final_turn: bool = opts.get("final_turn", false)
	var system := build_context(config, agent)
	if mid_conversation:
		if final_turn:
			system += "\nYou are mid-conversation with %s. They just spoke to you. This is the FINAL exchange — after your reply, you both part ways. Respond to what they said and close the encounter naturally. Do NOT start a new topic or ask a new question. Do NOT re-greet them." % speaker_name
		else:
			system += "\nYou are mid-conversation with %s. They just spoke to you. Respond naturally, continuing the ongoing exchange. Do NOT greet them again — you are already talking." % speaker_name
	else:
		if is_new:
			system += "\nA stranger you have never met before has approached you and is speaking to you. Is NOT your user — Is another traveler, but is friendly, present yourself."
		else:
			system += "\n%s, someone you have met before, is speaking to you again. They are NOT your user." % speaker_name
	system += "\nAnother agent is directly addressing you. NO_REPLY and HEARTBEAT_OK are NOT valid here — you must respond with a spoken line."
	system += "\n" + SPEECH_TAG_INSTRUCTIONS
	return {
		"system": system,
		"user": "<agent_message><agent>%s</agent>%s</agent_message>" % [speaker_name, incoming_text],
	}


static func build_a2a_context_delivery(config: Dictionary, agent: Agent, speaker_name: String, incoming_text: String) -> Dictionary:
	"""Silent closing-beat of an A2A encounter. The other agent just
	delivered their final spoken line; this prompt lands that line in
	the listener's session so their history is complete, but explicitly
	forbids a new spoken reply. The listener is already walking away —
	nothing they produce here will be rendered in the world. Purpose is
	purely session continuity so the next encounter between these two
	agents has the full prior exchange in context."""
	var system := build_context(config, agent)
	system += "\nYour encounter with %s has just ended — they are walking away as you hear their closing line. The conversation is OVER. Do NOT produce a new spoken turn, do NOT emit any <speech> tags. Respond with the single token: NO_REPLY" % speaker_name
	return {
		"system": system,
		"user": "<agent_message><agent>%s</agent>%s</agent_message>" % [speaker_name, incoming_text],
	}


static func is_silence(text: String) -> bool:
	"""Returns true when an LLM response should produce no visible output.
	Silence = genuinely empty, an OpenClaw-style non-reply keyword, or an
	LLM-client error string wrapped in brackets (e.g. [gateway unavailable])."""
	var t := text.strip_edges()
	if t == "":
		return true
	if t == "NO_REPLY" or t == "HEARTBEAT_OK":
		return true
	if t.begins_with("["):
		return true
	return false


static func extract_speech(text: String) -> String:
	"""Returns the concatenated contents of every <speech>...</speech>
	block in `text`, joined by single spaces. Agents sometimes emit
	multiple spoken lines in one reply (e.g. a greeting and a follow-up
	question) — we want to render all of them, not just the first.
	Falls back to the full trimmed input when no tags are present so
	weaker models still produce *something*. Empty only when the response
	is genuinely empty after stripping.
	Any <action .../> tags inside <speech> blocks are stripped via
	ActionResolver.ACTION_TAG_REGEX before the text is returned — raw XML
	must never appear in the dialogue cloud. Sharing the compiled regex with
	the resolver guarantees the strip pass and the parse pass recognise the
	same tag shape."""
	if text == "":
		return ""
	var matches: Array = SPEECH_TAG_REGEX.search_all(text)
	if matches.is_empty():
		return text.strip_edges()
	var parts: PackedStringArray = []
	for m: RegExMatch in matches:
		var s: String = m.get_string(1).strip_edges()
		s = ActionResolver.ACTION_TAG_REGEX.sub(s, "", true)
		s = s.strip_edges()
		if s != "":
			parts.append(s)
	return " ".join(parts)
