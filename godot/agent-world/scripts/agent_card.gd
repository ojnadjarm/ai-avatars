class_name AgentCard
extends RefCounted
## Builds A2A Agent Card dictionaries from game config. The Agent Card is
## the discovery artifact — "who is this agent, where do they live, what
## can they do." In real A2A this lives at /.well-known/agent-card.json;
## in-process it's a dictionary built on demand from GameState.agents.
##
## Spec: https://a2a-protocol.org/latest/specification/#agent-card
##
## When an agent eventually runs as a separate process, the only field
## that changes is `url` — everything else in this file is already
## spec-identical to what an HTTP-hosted card would serve.

const VERSION := "0.1.0"

const DEFAULT_DESCRIPTION := "A wandering agent."

const DEFAULT_SKILL := {
	"id": "chat",
	"name": "Encounter",
	"description": "Talk in character with another agent.",
	"tags": ["chat", "roleplay"],
}


static func for_agent(agent_id: String) -> Dictionary:
	"""Returns the full Agent Card for an agent, or {} if unknown."""
	var cfg: Dictionary = GameState.agents.get(agent_id, {})
	if cfg.is_empty():
		return {}
	return {
		"name": cfg.get("display_name", agent_id),
		"description": cfg.get("description", DEFAULT_DESCRIPTION),
		"url": url_for(agent_id),
		"version": VERSION,
		"capabilities": {"streaming": false},
		"defaultInputModes": ["text"],
		"defaultOutputModes": ["text"],
		"skills": cfg.get("skills", [DEFAULT_SKILL]),
	}


static func url_for(agent_id: String) -> String:
	"""The routing address for an agent. In-process today, HTTP tomorrow —
	the router is the only place that parses this string."""
	return "inproc://" + agent_id


static func has_skill(card: Dictionary, skill_id: String) -> bool:
	"""Does this card advertise a given skill id? Used by callers to
	decide whether they can ask a peer for something specific."""
	var skills: Array = card.get("skills", [])
	for s in skills:
		if s.get("id", "") == skill_id:
			return true
	return false
