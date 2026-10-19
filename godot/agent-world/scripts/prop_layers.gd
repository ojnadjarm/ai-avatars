class_name PropLayers
extends RefCounted
## Layered observation assembly for the puzzle layer (Story 005).
##
## Single static entry point:
##   render_for_agent(prop, agent, world_state) -> String
##
## Assembles the base prop description plus any layer texts whose gates
## pass for this agent in this world state. Result is joined with "\n\n".
## Pure — no state, no signals, no side effects.
##
## Gate kinds:
##   "skill" — agent.has_skill(id)
##   "item"  — world_state.agent_has_item(agent_id, id)
##   "flag"  — world_state.get_flag(id) evaluates truthy
##   other   — evaluates false; push_warning emitted at WorldState.load_for()
##             time (not here at render time — per ADR-0001).
##
## Gate metadata (kind, id) never appears in the rendered output.
## Empty or whitespace-only layer text is skipped silently.
## When all parts are absent (empty base, no qualifying layers),
## returns defaults.puzzle.empty_prop_fallback — never an empty string.


## Assemble the layered observation text for agent observing prop in world_state.
## prop       — Dictionary with optional "description" and "layers" keys.
## agent      — Agent node (must expose agent_id: String and has_skill(id) -> bool).
## world_state — WorldState for the current world.
static func render_for_agent(prop: Dictionary, agent: Agent, world_state: WorldState) -> String:
	var parts: PackedStringArray = PackedStringArray()

	var base: String = prop.get("description", "").strip_edges()
	if not base.is_empty():
		parts.append(base)

	var layers: Array = prop.get("layers", [])
	for layer: Variant in layers:
		if not (layer is Dictionary):
			continue
		var layer_dict: Dictionary = layer
		if _evaluate_gate(layer_dict.get("gate", {}), agent, world_state):
			var text: String = layer_dict.get("text", "").strip_edges()
			if not text.is_empty():
				parts.append(text)

	if parts.is_empty():
		return _empty_prop_fallback()
	return "\n\n".join(parts)


## Evaluate a single gate dict against agent and world_state.
## Returns false for unknown gate kinds — push_warning was already emitted
## at WorldState.load_for() time (Story 006 integration point).
static func _evaluate_gate(gate: Dictionary, agent: Agent, world_state: WorldState) -> bool:
	var kind: String = gate.get("kind", "")
	var id: String = gate.get("id", "")
	match kind:
		"skill":
			return agent.has_skill(id)
		"item":
			return world_state.agent_has_item(agent.agent_id, id)
		"flag":
			var flag_val: Variant = world_state.get_flag(id)
			return flag_val != null and bool(flag_val)
		_:
			return false


## Read defaults.puzzle.empty_prop_fallback from config.
## Traverses the nested dict the same way ActionResolver._get_puzzle_default does.
## The literal below is an absolute last resort for a missing config key —
## the production value lives in game_config.json → defaults.puzzle.empty_prop_fallback.
static func _empty_prop_fallback() -> String:
	var puzzle_cfg: Variant = GameState.get_default("puzzle", {})
	if puzzle_cfg is Dictionary:
		var fallback: Variant = (puzzle_cfg as Dictionary).get("empty_prop_fallback", "")
		if fallback is String and not (fallback as String).is_empty():
			return fallback as String
	return "It is here, present and unremarkable."
