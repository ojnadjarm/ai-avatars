class_name ActionResolver
extends RefCounted
## Parses, validates, and executes agent actions from LLM responses.
##
## Owns:
##   - A pre-compiled RegEx for extracting <action> tags (compiled once at
##     class load as a static var, so all instances share one RegEx object).
##   - A reference to the active WorldState, the puzzle list for the current
##     world, and the world-level nothing_happens_text string.
##   - An optional reference to world_loader for call_agent dispatch. When
##     world_loader_ref is null and verb is call_agent, a push_warning is
##     emitted once and the verb is treated as precondition-failed (nothing
##     happens). This is the expected construction during unit tests.
##
## Usage: construct once per world load; call resolve() in the LLM response
## handler. extract_action() is static and may be called freely.

## Canonical verbs per ADR-0001 §4 and TR-puzzle-009.
const VERBS: Array[String] = ["go_to", "take", "use_object", "use_skill", "call_agent"]

## Context-id prefix stamped on call_agent-initiated encounters. R21 path (b)
## keys on this prefix to distinguish deliberate invitations from ambient
## proximity encounters (which carry context_id == "").
const CALL_AGENT_CONTEXT_PREFIX := "puzzle_"

## Pre-compiled regex for the `<action verb="..." target="..." [on="..."]/>`
## shape. Shared across every instance (compiled once at class load) and also
## referenced by `prompt_builder.extract_speech` so the strip pass and the
## parse pass agree on a single literal pattern — drift between them would
## let raw XML leak into the dialogue cloud.
static var ACTION_TAG_REGEX: RegEx = _build_regex()

var _world_state: WorldState
var _world_loader_ref: Object
var _puzzle_list: Array[Dictionary]
var _world_nothing_happens_text: String
var _agents_supplier: Callable = Callable()

## True after the first push_warning for missing world_loader_ref, so we do
## not spam the output panel on every call_agent attempt.
var _warned_no_loader: bool = false
var _warned_no_log: bool = false
var _warned_no_agents: bool = false


# ── Static regex builder ───────────────────────────────────────────────────

static func _build_regex() -> RegEx:
	var re := RegEx.new()
	re.compile("<action\\s+verb=\"([^\"]+)\"\\s+target=\"([^\"]+)\"(?:\\s+on=\"([^\"]+)\")?\\s*/>")
	return re


# ── Construction ──────────────────────────────────────────────────────────

## Construct the resolver for one world session.
##
## world_state        — authoritative WorldState for the current world.
## world_loader_ref   — optional Node reference to the world_loader (needed
##                      for call_agent dispatch via encounter_dispatcher).
##                      Pass null during unit tests; push_warning fires once
##                      on the first call_agent attempt when it is null.
## puzzle_list        — Array of puzzle Dictionaries loaded from the world
##                      JSON. Each entry must have an "actions" Array of
##                      rule Dictionaries.
## world_nothing_happens_text — the world-level fallback narration string
##                      (from the world JSON "nothing_happens_text" field).
##                      Pass "" to skip this tier.
func _init(
		world_state: WorldState,
		world_loader_ref: Object = null,
		puzzle_list: Array[Dictionary] = [],
		world_nothing_happens_text: String = "",
		agents_supplier: Callable = Callable()) -> void:
	_world_state = world_state
	_world_loader_ref = world_loader_ref
	_puzzle_list = puzzle_list
	_world_nothing_happens_text = world_nothing_happens_text
	_agents_supplier = agents_supplier


# ── Public API ────────────────────────────────────────────────────────────

## Extract the first <action> tag from an LLM response string.
##
## Returns a Dictionary with keys "verb", "target", and optionally "on"
## (trimmed of leading/trailing whitespace). Returns {} when no valid
## <action ... /> element is found or when the tag is malformed.
## Only the first element is returned; subsequent elements are silently
## discarded.
static func extract_action(llm_response: String) -> Dictionary:
	var m: RegExMatch = ACTION_TAG_REGEX.search(llm_response)
	if m == null:
		return {}
	var verb: String = m.get_string(1).strip_edges()
	var target: String = m.get_string(2).strip_edges()
	var on_raw: String = m.get_string(3).strip_edges()
	if verb.is_empty() or target.is_empty():
		return {}
	var result: Dictionary = {"verb": verb, "target": target}
	if not on_raw.is_empty():
		result["on"] = on_raw
	return result


## Resolve an action dict (from extract_action or constructed directly) for
## an agent against the current WorldState and puzzle list.
##
## Returns { "narration": String, "state_changed": bool }. Never throws.
## narration may be "" when call_agent successfully dispatches.
func resolve(agent: Object, action: Dictionary) -> Dictionary:
	var verb: String = str(action.get("verb", "")).strip_edges()
	var target: String = str(action.get("target", "")).strip_edges()
	var on: String = str(action.get("on", "")).strip_edges()

	# Step 1 — Validate verb (case-sensitive, exact match).
	if verb not in VERBS:
		return _nothing_happens(verb, null)

	# Step 2 — Structural preconditions per verb (R10).
	if not _check_preconditions(agent, verb, target, on):
		return _nothing_happens(verb, null)

	# call_agent short-circuit before puzzle scan (R14 adapter).
	if verb == "call_agent":
		return _dispatch_call_agent(agent, target, verb)

	# Step 3 — Scan puzzle list in declaration order for a matching rule.
	var matched_puzzle: Dictionary = {}
	var matched_rule: Dictionary = {}
	for puzzle: Dictionary in _puzzle_list:
		var actions: Variant = puzzle.get("actions", [])
		if not (actions is Array):
			continue
		for rule: Variant in (actions as Array):
			if not (rule is Dictionary):
				continue
			if _rule_matches(rule as Dictionary, verb, target, on):
				matched_puzzle = puzzle
				matched_rule = rule as Dictionary
				break
		if not matched_rule.is_empty():
			break

	# No rule matched.
	if matched_rule.is_empty():
		return _nothing_happens(verb, null)

	# Step 4 — Require predicate check.
	var require: Variant = matched_rule.get("require", null)
	if require != null:
		if not (require is Dictionary) or not _world_state.evaluate_predicate(require as Dictionary):
			var fail_narration: String = str(matched_puzzle.get("default_fail_narration", ""))
			return _nothing_happens(verb, fail_narration if not fail_narration.is_empty() else null)

	var acting_agent_id: String = str(agent.get("agent_id"))

	# Step 5 — Apply effects atomically.
	_apply_effects(acting_agent_id, matched_rule)

	# Steps 5b/5c/6 — post-match bookkeeping + solve scan.
	_post_match_effects(agent, action, acting_agent_id, matched_puzzle)

	# Step 7 — Return success.
	return {"narration": str(matched_rule.get("narration", "")), "state_changed": true}


## Story 004 — post-match bookkeeping extracted from resolve() to keep the
## entry point under the control-manifest complexity/line limits. Runs after
## _apply_effects and before returning narration. Order is load-bearing:
##   5b — collaborator_props append (R21 path a) must precede any solve flip
##        so the acting agent is credited before the broadcast loop runs
##   5c — action_resolved emotion event fires on the acting agent only
##   6  — puzzle solve/intermediate scan, which also fires puzzle_solved
##        on contributor + collaborators (but skips bystanders per R22)
func _post_match_effects(agent: Object, action: Dictionary, acting_agent_id: String, matched_puzzle: Dictionary) -> void:
	var target: String = str(action.get("target", "")).strip_edges()
	var on: String = str(action.get("on", "")).strip_edges()

	# Step 5b — R21 path (a): collaborator_props append.
	var puzzle_id_for_collab: String = str(matched_puzzle.get("id", ""))
	if not puzzle_id_for_collab.is_empty():
		var collab_props: Variant = matched_puzzle.get("collaborator_props", null)
		if collab_props is Array:
			if target in (collab_props as Array) or on in (collab_props as Array):
				_world_state.add_collaborator(puzzle_id_for_collab, acting_agent_id)

	# Step 5c — AC-FE-01: fire action_resolved emotion event on the acting agent.
	# Only fires when a rule matched and effects applied (state_changed == true path).
	# Does NOT fire on precondition fail, no-match, or require fail.
	var acting_engine: Variant = agent.get("emotion_engine")
	if acting_engine != null and (acting_engine is Object) and (acting_engine as Object).has_method("process_event"):
		(acting_engine as Object).call("process_event", "action_resolved", {
			"target_id": target,
		})

	# Step 6 — Scan all puzzles for newly-satisfied solve/intermediate conditions.
	var agents_solved_this_cycle: Dictionary = {}
	_scan_puzzles_for_solve(acting_agent_id, agents_solved_this_cycle)


# ── Precondition checker ──────────────────────────────────────────────────

## Per-verb dispatch (TD-003) — each arm delegates to a small helper so new
## verbs add a helper instead of growing this match block toward the 40-line
## limit.
func _check_preconditions(agent: Object, verb: String, target: String, on: String) -> bool:
	match verb:
		"go_to":
			return not target.is_empty()
		"take":
			return _precond_take(agent, target)
		"use_object":
			return _precond_use_object(agent, target, on)
		"use_skill":
			return _precond_use_skill(agent, target, on)
		"call_agent":
			return _precond_call_agent(agent, target)
	return false


func _precond_take(agent: Object, target: String) -> bool:
	if target.is_empty():
		return false
	return not _world_state.agent_has_item(str(agent.get("agent_id")), target)


func _precond_use_object(agent: Object, target: String, on: String) -> bool:
	if target.is_empty() or on.is_empty():
		return false
	return _world_state.agent_has_item(str(agent.get("agent_id")), target)


func _precond_use_skill(agent: Object, target: String, on: String) -> bool:
	if target.is_empty() or on.is_empty():
		return false
	var agent_cfg: Variant = GameState.agents.get(str(agent.get("agent_id")), {})
	var skills: Variant = []
	if agent_cfg is Dictionary:
		skills = (agent_cfg as Dictionary).get("skills", [])
	if not (skills is Array):
		return false
	return target in (skills as Array)


func _precond_call_agent(agent: Object, target: String) -> bool:
	if target.is_empty() or target == str(agent.get("agent_id")):
		return false
	if _world_loader_ref == null:
		if not _warned_no_loader:
			push_warning("[ActionResolver] call_agent precondition: world_loader_ref is null — treating as precondition failure.")
			_warned_no_loader = true
		return false
	# Target must not be busy in a blocking state.
	var target_obj: Object = _world_loader_ref.call("find_agent", target) as Object
	if target_obj == null:
		return false
	var busy_states: Array[int] = [Agent.State.ENCOUNTERING, Agent.State.OBSERVING, Agent.State.TALKING]
	return target_obj.get("current_state") not in busy_states


# ── call_agent adapter ────────────────────────────────────────────────────

func _dispatch_call_agent(agent: Object, target: String, verb: String) -> Dictionary:
	# Defense-in-depth guards. _check_preconditions already rejects when
	# _world_loader_ref is null. Both gate check and dispatch go through
	# world_loader facade methods (TD-002) — the resolver never reaches into
	# activity_gate/encounter_dispatcher properties, so a mid-construction
	# loader answers through the facade's own null handling.
	if _world_loader_ref == null \
			or not _world_loader_ref.has_method("can_trigger_activity") \
			or not _world_loader_ref.has_method("request_agent_encounter"):
		return _nothing_happens(verb, null)
	if not _world_loader_ref.call("can_trigger_activity"):
		return _nothing_happens(verb, null)
	var acting_id: String = str(agent.get("agent_id"))
	# Generate a stable context_id for this puzzle-initiated encounter so the
	# EncounterDispatcher can correlate the encounter_complete signal back to
	# the acting agent and target (TR-puzzle-027). Format uses msec timestamp
	# for uniqueness within a session; not intended to be globally unique.
	var ctx_id: String = CALL_AGENT_CONTEXT_PREFIX + "%s_%s_%d" % [acting_id, target, Time.get_ticks_msec()]
	_world_loader_ref.call("request_agent_encounter", acting_id, target, ctx_id)
	return {"narration": "", "state_changed": false}


## R21 path (b) — call_agent-invited collaborator membership (AC-FE-07).
## Called (via world_loader) when EncounterDispatcher emits encounter_complete.
## Only encounters whose context_id carries CALL_AGENT_CONTEXT_PREFIX count —
## ambient/proximity encounters (context_id == "") never propagate membership.
## For every unsolved puzzle whose collaborators set already contains the
## caller, the called agent joins the set: cooperation membership is earned by
## deliberate invitation from an agent already involved. The caller's own
## membership comes from path (a) (matched action on collaborator_props) or
## R21b flag-writer credit — a bare call_agent from an uninvolved agent
## identifies no puzzle and adds no one.
## Returns true when any collaborators set changed (caller queues the save).
func on_encounter_complete(sender_id: String, listener_id: String, context_id: String) -> bool:
	if not context_id.begins_with(CALL_AGENT_CONTEXT_PREFIX):
		return false
	if sender_id.is_empty() or listener_id.is_empty() or sender_id == listener_id:
		return false
	var changed: bool = false
	for puzzle: Dictionary in _puzzle_list:
		var puzzle_id: String = str(puzzle.get("id", ""))
		if puzzle_id.is_empty():
			continue
		if _world_state.is_puzzle_fired(puzzle_id) or _world_state.get_puzzle_state(puzzle_id) == 2:
			continue
		var collaborators: Array[String] = _world_state.get_puzzle_collaborators(puzzle_id)
		if sender_id in collaborators and listener_id not in collaborators:
			_world_state.add_collaborator(puzzle_id, listener_id)
			changed = true
	return changed


# ── Rule matching ─────────────────────────────────────────────────────────

## A rule matches when every key declared in rule["match"] equals the
## corresponding value in {verb, target, on}. Keys absent from rule["match"]
## are wildcards. on defaults to "" when absent from the action dict.
##
## Designer note: a rule with an empty match dict ({}) has zero constraints
## and matches EVERY action — that is intentional (supports catch-all rules
## scoped by require/effect) but easy to author by accident. An empty match
## also has no verb/target/on keys, so all three `if md.has(...)` checks skip
## and the function returns true.
func _rule_matches(rule: Dictionary, verb: String, target: String, on: String) -> bool:
	var match_dict: Variant = rule.get("match", null)
	if not (match_dict is Dictionary):
		return false
	var md: Dictionary = match_dict as Dictionary
	if md.has("verb") and str(md["verb"]) != verb:
		return false
	if md.has("target") and str(md["target"]) != target:
		return false
	if md.has("on") and str(md["on"]) != on:
		return false
	return true


# ── Effect applicator ─────────────────────────────────────────────────────

## Apply all effect deltas from a matched rule in the mandated order:
## set_flag → set_object → give_item → take_item. Applied in sequence, not
## atomically — a malformed set_object key emits push_warning and subsequent
## effects still run. No rollback on partial failure; authored rule data is
## assumed valid by the time it reaches this method.
func _apply_effects(agent_id: String, rule: Dictionary) -> void:
	var effect: Variant = rule.get("effect", null)
	if not (effect is Dictionary):
		return
	var eff: Dictionary = effect as Dictionary

	# set_flag — { "flag_key": value, … }
	var set_flag: Variant = eff.get("set_flag", null)
	if set_flag is Dictionary:
		for key: String in (set_flag as Dictionary):
			_world_state.set_flag_with_writer(key, (set_flag as Dictionary)[key], agent_id)

	# set_object — { "prop_id.field": value, … }
	var set_object: Variant = eff.get("set_object", null)
	if set_object is Dictionary:
		for dotted: String in (set_object as Dictionary):
			var parts: PackedStringArray = dotted.split(".", false, 1)
			if parts.size() == 2:
				_world_state.set_object_field(parts[0], parts[1], (set_object as Dictionary)[dotted])
			else:
				push_warning("[ActionResolver] set_object key must be 'prop.field', got: '%s'" % dotted)

	# give_item — String or Array[String]
	var give_item: Variant = eff.get("give_item", null)
	if give_item is String:
		_world_state.give_item(agent_id, give_item as String)
	elif give_item is Array:
		for item_id: Variant in (give_item as Array):
			_world_state.give_item(agent_id, str(item_id))

	# take_item — String or Array[String]
	var take_item_val: Variant = eff.get("take_item", null)
	if take_item_val is String:
		_world_state.take_item(agent_id, take_item_val as String)
	elif take_item_val is Array:
		for item_id: Variant in (take_item_val as Array):
			_world_state.take_item(agent_id, str(item_id))


# ── Puzzle solve scan ─────────────────────────────────────────────────────

## Scan all puzzles in declaration order after effects are applied. Handles
## both SOLVED (state 0|1 → 2) and SOLVING (state 0 → 1) transitions.
## cycle_dict is per-resolve() call and enforces the R24 one-emotion-per-agent
## clamp across multiple puzzles that fire in the same action.
func _scan_puzzles_for_solve(acting_agent_id: String, cycle_dict: Dictionary) -> void:
	for puzzle: Dictionary in _puzzle_list:
		var puzzle_id: String = str(puzzle.get("id", ""))
		if puzzle_id.is_empty():
			push_warning("[ActionResolver] Puzzle missing 'id' field — skipping solve scan entry.")
			continue

		# R17 idempotence: never re-fire a solved puzzle.
		if _world_state.is_puzzle_fired(puzzle_id):
			continue

		var state: int = _world_state.get_puzzle_state(puzzle_id)

		# Check SOLVED condition first (any state → 2).
		var solve: Variant = puzzle.get("solve", {})
		var solve_when: Variant = null
		if solve is Dictionary:
			solve_when = (solve as Dictionary).get("when", null)
		if solve_when is Dictionary and _world_state.evaluate_predicate(solve_when as Dictionary):
			_handle_solve(puzzle, puzzle_id, acting_agent_id, cycle_dict)
			continue

		# Check SOLVING intermediate transition (0 → 1 only).
		if state == 0:
			var intermediate_when: Variant = puzzle.get("intermediate_when", null)
			if intermediate_when is Dictionary and _world_state.evaluate_predicate(intermediate_when as Dictionary):
				_handle_intermediate(puzzle, puzzle_id, acting_agent_id)


## Transition a puzzle to SOLVED (state 2), latch idempotence, flush, and
## broadcast solve narration + emotion event to contributor + collaborators only.
## Bystanders (neither contributor nor collaborator) receive narration only.
func _handle_solve(puzzle: Dictionary, puzzle_id: String, acting_agent_id: String, cycle_dict: Dictionary) -> void:
	# R21b: auto-credit flag-writers as collaborators before the broadcast loop.
	_credit_flag_writers(puzzle, puzzle_id, acting_agent_id)

	_world_state.set_puzzle_state(puzzle_id, 2)
	_world_state.latch_puzzle_fired(puzzle_id)
	_world_state.flush()

	var solve_dict: Variant = puzzle.get("solve", {})
	var solve_narration: String = ""
	if solve_dict is Dictionary:
		solve_narration = str((solve_dict as Dictionary).get("narration", ""))
	if solve_narration.is_empty():
		push_warning("[ActionResolver] Puzzle '%s' solved but solve.narration is empty." % puzzle_id)

	var world_agents: Array[Object] = _get_world_agents()
	for agent_obj: Object in world_agents:
		if agent_obj == null:
			continue
		if not is_instance_valid(agent_obj):
			continue
		_narrate_solve_to(agent_obj, solve_narration)
		_apply_puzzle_solved_emotion(agent_obj, acting_agent_id, puzzle_id, cycle_dict)


## Transition a puzzle to SOLVING (state 0 → 1). Does NOT latch _fired_puzzles.
## Delivers solving_narration to the acting agent only (not broadcast).
func _handle_intermediate(puzzle: Dictionary, puzzle_id: String, acting_agent_id: String) -> void:
	_world_state.set_puzzle_state(puzzle_id, 1)
	_world_state.flush()

	var solving_narration: String = str(puzzle.get("solving_narration", ""))
	if solving_narration.is_empty():
		return
	var acting_agent: Object = _find_agent_in_world(acting_agent_id)
	if acting_agent == null:
		return
	_narrate_solve_to(acting_agent, solving_narration)


## Write one narration_log entry of type "solve". Silent when narration is
## empty or when narration_log is unavailable (warns once).
func _narrate_solve_to(agent_obj: Object, narration: String) -> void:
	if narration.is_empty():
		return
	if _world_loader_ref == null or _world_loader_ref.get("narration_log") == null:
		if not _warned_no_log:
			push_warning("[ActionResolver] narration_log unavailable — solve narration suppressed.")
			_warned_no_log = true
		return
	# TODO(Story-006): replace with LLMCoordinator.narrate_to_all once wired.
	_world_loader_ref.narration_log.add_entry(narration, "solve")


## Story 004 / R22 — fire a puzzle_solved emotion event to agent_obj for
## contributors and collaborators only. Bystanders return early (no event).
## Enforces R24: each agent receives at most one emotion event per resolve()
## cycle via cycle_dict. Signature normalized to 2-arg context dict (TD-005).
func _apply_puzzle_solved_emotion(agent_obj: Object, acting_agent_id: String, puzzle_id: String, cycle_dict: Dictionary) -> void:
	var agent_id: String = str(agent_obj.get("agent_id"))
	if cycle_dict.has(agent_id):
		return

	# R22: determine role — contributor, collaborator, or bystander.
	var is_contributor: bool = (agent_id == acting_agent_id)
	var collaborators: Array[String] = _world_state.get_puzzle_collaborators(puzzle_id)
	var is_collaborator: bool = collaborators.has(agent_id)

	# Bystanders receive narration (already sent by _narrate_solve_to) but no emotion event.
	if not is_contributor and not is_collaborator:
		return

	cycle_dict[agent_id] = true

	var engine: Variant = agent_obj.get("emotion_engine")
	if engine == null:
		return
	if not (engine is Object) or not (engine as Object).has_method("process_event"):
		return

	(engine as Object).call("process_event", "puzzle_solved", {
		"acting_agent_id": acting_agent_id,
		"is_contributor": is_contributor,
	})


## Return all in-world agents. Sources checked in priority order:
##   1. _agents_supplier Callable (test-injectable, avoids Node dependencies)
##   2. _world_loader_ref.agents_container children
##   3. Empty array with a one-time warning.
func _get_world_agents() -> Array[Object]:
	var result: Array[Object] = []
	if _agents_supplier.is_valid():
		var raw: Variant = _agents_supplier.call()
		if raw is Array:
			for entry: Variant in (raw as Array):
				if entry != null:
					result.append(entry as Object)
		elif raw != null and not _warned_no_agents:
			push_warning("[ActionResolver] agents_supplier returned a non-Array value — solve broadcast suppressed.")
			_warned_no_agents = true
		return result
	if _world_loader_ref != null and _world_loader_ref.get("agents_container") != null:
		var container: Object = _world_loader_ref.get("agents_container") as Object
		if container.has_method("get_children"):
			for child: Variant in container.call("get_children"):
				if child != null:
					result.append(child as Object)
		return result
	if not _warned_no_agents:
		push_warning("[ActionResolver] No agents source available — solve broadcast suppressed.")
		_warned_no_agents = true
	return result


## Story 004 / R21b — before the solve broadcast loop, walk the solve.when
## predicate to find every flag referenced, then look up who last wrote each
## flag. If the writer is non-empty, is not the acting agent (already the
## contributor), and is not already in collaborators — append them.
func _credit_flag_writers(puzzle: Dictionary, puzzle_id: String, acting_agent_id: String) -> void:
	var solve_dict: Variant = puzzle.get("solve", {})
	if not (solve_dict is Dictionary):
		return
	var when_pred: Variant = (solve_dict as Dictionary).get("when", null)
	if not (when_pred is Dictionary):
		return
	var flag_ids: Array[String] = _extract_flag_ids_from_predicate(when_pred as Dictionary)
	for flag_id: String in flag_ids:
		var writer: String = _world_state.get_flag_writer(flag_id)
		if writer.is_empty():
			continue
		if writer == acting_agent_id:
			continue
		# add_collaborator dedupes internally.
		_world_state.add_collaborator(puzzle_id, writer)


## Recursively collect every flag key referenced in a predicate dict.
## Handles nested and/or/not composition per the ADR-0001 predicate grammar.
func _extract_flag_ids_from_predicate(pred: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if pred.has("flag"):
		var flag_checks: Variant = pred["flag"]
		if flag_checks is Dictionary:
			for key: String in (flag_checks as Dictionary):
				result.append(key)
	if pred.has("and"):
		var sub: Variant = pred["and"]
		if sub is Array:
			for item: Variant in (sub as Array):
				if item is Dictionary:
					result.append_array(_extract_flag_ids_from_predicate(item as Dictionary))
	if pred.has("or"):
		var sub: Variant = pred["or"]
		if sub is Array:
			for item: Variant in (sub as Array):
				if item is Dictionary:
					result.append_array(_extract_flag_ids_from_predicate(item as Dictionary))
	if pred.has("not"):
		var sub: Variant = pred["not"]
		if sub is Dictionary:
			result.append_array(_extract_flag_ids_from_predicate(sub as Dictionary))
	return result


## Linear scan over world agents; returns first whose agent_id matches, or null.
func _find_agent_in_world(agent_id: String) -> Object:
	for agent_obj: Object in _get_world_agents():
		if agent_obj == null:
			continue
		if str(agent_obj.get("agent_id")) == agent_id:
			return agent_obj
	return null


# ── Nothing-happens fallback chain ────────────────────────────────────────

## Return a nothing-happens result following the four-tier fallback chain:
##   1. override_narration (non-null, non-empty) — e.g. puzzle default_fail_narration
##   2. _world_nothing_happens_text (non-empty)
##   3. defaults.puzzle.nothing_happens.<verb>
##   4. defaults.puzzle.nothing_happens_text — push_warning if empty
func _nothing_happens(verb: String, override_narration: Variant) -> Dictionary:
	# Tier 1 — per-puzzle default_fail_narration (only when a rule matched but require failed).
	if override_narration != null and str(override_narration) != "":
		return {"narration": str(override_narration), "state_changed": false}

	# Tier 2 — world-level override.
	if not _world_nothing_happens_text.is_empty():
		return {"narration": _world_nothing_happens_text, "state_changed": false}

	# Tier 3 — per-verb config default.
	var per_verb: String = _get_puzzle_default("nothing_happens." + verb)
	if not per_verb.is_empty():
		return {"narration": per_verb, "state_changed": false}

	# Tier 4 — global config default.
	var global_text: String = _get_puzzle_default("nothing_happens_text")
	if global_text.is_empty():
		push_warning("[ActionResolver] defaults.puzzle.nothing_happens_text is empty — no fallback narration available.")
	return {"narration": global_text, "state_changed": false}


## Traverse the defaults.puzzle nested dict using a dot-separated path.
## Returns "" when any segment is missing or not a Dictionary.
## Example: _get_puzzle_default("nothing_happens.use_skill")
func _get_puzzle_default(dotted_path: String) -> String:
	var puzzle_defaults: Variant = GameState.get_default("puzzle", {})
	if not (puzzle_defaults is Dictionary):
		return ""
	var node: Variant = puzzle_defaults as Dictionary
	for segment: String in dotted_path.split("."):
		if not (node is Dictionary):
			return ""
		node = (node as Dictionary).get(segment, null)
		if node == null:
			return ""
	if node is String:
		return node as String
	return ""
