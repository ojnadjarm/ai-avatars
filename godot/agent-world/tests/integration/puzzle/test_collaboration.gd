class_name TestCollaboration
extends RefCounted
## Integration tests for Story 004: Collaboration Set & Emotion Events.
##
## Covers: AC-FE-01, AC-FE-02, AC-FE-03, AC-FE-04, AC-FE-05, AC-FE-06, R21b.
##
## DEFERRED (pending v0.8 EncounterDispatcher infrastructure):
##   AC-FE-07 — collaborator membership via call_agent (TR-puzzle-026/027)
##   AC-FE-08 — two-puzzle fixture for multi-world solve ordering
##
## Uses real EmotionEngine instances (not stubs) to verify actual numeric
## deltas and causal-log strings. WorldState typed accessors used throughout;
## no direct field access from outside the puzzle layer.

const SAVES_DIR := "user://saves/"

## Fixture defaults injected into GameState for the duration of the test run.
const FIXTURE_AGENTS: Dictionary = {
	"agent_a": {
		"display_name": "Agent A",
		"skills": [],
		"starting_inventory": [],
	},
	"agent_b": {
		"display_name": "Agent B",
		"skills": [],
		"starting_inventory": [],
	},
	"agent_c": {
		"display_name": "Agent C",
		"skills": [],
		"starting_inventory": [],
	},
}

const FIXTURE_EMOTION_DEFAULTS: Dictionary = {
	"tired_below": 0.3,
	"frustrated_below": 0.3,
	"excited_energy": 0.85,
	"excited_social": 0.6,
	"happy_social": 0.8,
	"happy_patience": 0.6,
	"events": {
		"action_resolved": {
			"energy_delta": 0.04,
			"curiosity_ticks": 2,
		},
		"puzzle_solved": {
			"energy_delta": 0.08,
			"social_battery_delta": 0.06,
			"patience_delta": 0.04,
			"log_cause_contributor": "a thing settled that had not settled before, and you were there when it did",
			"log_cause_witness": "something another did that made the world settle differently",
		},
	},
}

const FIXTURE_PUZZLE_DEFAULTS: Dictionary = {
	"nothing_happens": {
		"go_to": "Your feet carry you, but the world does not shift.",
		"take": "Your hand closes on nothing.",
		"use_object": "Nothing stirs.",
		"use_skill": "The world does not respond.",
		"call_agent": "No one turns.",
	},
	"nothing_happens_text": "The world holds its shape.",
}

const FIXTURE_INTEREST_REFRESH: float = 0.6

var failure_message: String = ""
var _test_world_ids: Array[String] = []
var _saved_agents: Dictionary = {}
var _saved_emotion_defaults: Variant = null
var _had_emotion_defaults: bool = false
var _saved_puzzle_defaults: Variant = null
var _had_puzzle_defaults: bool = false
var _saved_interest_refresh: Variant = null
var _had_interest_refresh: bool = false


func run() -> bool:
	_install_fixtures()

	if not test_collaboration_action_resolved_fires_energy_delta_on_success():
		_restore_fixtures()
		return false
	if not test_collaboration_puzzle_solved_fires_all_deltas_for_contributor():
		_restore_fixtures()
		return false
	if not test_collaboration_puzzle_solved_fires_for_collaborator_in_set():
		_restore_fixtures()
		return false
	if not test_collaboration_bystander_receives_no_emotion_delta():
		_restore_fixtures()
		return false
	if not test_collaboration_puzzle_solved_clamps_at_ceiling():
		_restore_fixtures()
		return false
	if not test_collaboration_layer_interest_refresh_on_new_qualification():
		_restore_fixtures()
		return false
	if not test_collaboration_layer_interest_compound_key_survives_disk_flush():
		_restore_fixtures()
		return false
	if not test_collaboration_two_puzzles_one_cycle_single_puzzle_solved_delta():
		_restore_fixtures()
		return false
	if not test_collaboration_action_resolved_does_not_fire_on_precondition_fail():
		_restore_fixtures()
		return false
	if not test_collaboration_action_resolved_does_not_fire_on_no_match():
		_restore_fixtures()
		return false
	if not test_collaboration_action_resolved_does_not_fire_on_require_fail():
		_restore_fixtures()
		return false
	if not test_collaboration_causal_log_contributor_string_matches():
		_restore_fixtures()
		return false
	if not test_collaboration_causal_log_collaborator_string_matches():
		_restore_fixtures()
		return false
	if not test_collaboration_flag_writer_auto_credit_adds_collaborator():
		_restore_fixtures()
		return false
	if not test_collaboration_flag_writer_auto_credit_walks_or_predicate():
		_restore_fixtures()
		return false
	if not test_collaboration_flag_writer_auto_credit_walks_not_predicate():
		_restore_fixtures()
		return false

	_cleanup()
	_restore_fixtures()
	return true


# ── Fixture management ────────────────────────────────────────────────────

func _install_fixtures() -> void:
	_saved_agents = GameState.agents
	GameState.agents = FIXTURE_AGENTS.duplicate(true)

	_had_emotion_defaults = GameState.defaults.has("emotion")
	if _had_emotion_defaults:
		_saved_emotion_defaults = GameState.defaults["emotion"]
	GameState.defaults["emotion"] = FIXTURE_EMOTION_DEFAULTS.duplicate(true)

	_had_puzzle_defaults = GameState.defaults.has("puzzle")
	if _had_puzzle_defaults:
		_saved_puzzle_defaults = GameState.defaults["puzzle"]
	GameState.defaults["puzzle"] = FIXTURE_PUZZLE_DEFAULTS.duplicate(true)

	_had_interest_refresh = GameState.defaults.has("interest_refresh_on_new_layer")
	if _had_interest_refresh:
		_saved_interest_refresh = GameState.defaults["interest_refresh_on_new_layer"]
	GameState.defaults["interest_refresh_on_new_layer"] = FIXTURE_INTEREST_REFRESH


func _restore_fixtures() -> void:
	GameState.agents = _saved_agents

	if _had_emotion_defaults:
		GameState.defaults["emotion"] = _saved_emotion_defaults
	else:
		GameState.defaults.erase("emotion")

	if _had_puzzle_defaults:
		GameState.defaults["puzzle"] = _saved_puzzle_defaults
	else:
		GameState.defaults.erase("puzzle")

	if _had_interest_refresh:
		GameState.defaults["interest_refresh_on_new_layer"] = _saved_interest_refresh
	else:
		GameState.defaults.erase("interest_refresh_on_new_layer")

	# Always remove any save files this run produced — guarantees cleanup even
	# on failure paths that don't route through _fail().
	_cleanup()


# ── Helpers ───────────────────────────────────────────────────────────────

func _world_id(suffix: String) -> String:
	var wid: String = "test_co_" + suffix
	_test_world_ids.append(wid)
	return wid


func _save_path(wid: String) -> String:
	return SAVES_DIR + "world_state_" + wid + ".json"


func _remove_if_exists(wid: String) -> void:
	var path: String = _save_path(wid)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _fail(msg: String) -> bool:
	failure_message = msg
	_cleanup()
	return false


func _cleanup() -> void:
	for wid: String in _test_world_ids:
		_remove_if_exists(wid)


func _approx(a: float, b: float, tol: float = 0.001) -> bool:
	return absf(a - b) <= tol


## Create a stub-shaped RefCounted with agent_id and a real EmotionEngine.
## The emotion_engine is a real EmotionEngine instance so deltas and causal
## log entries are exercised end-to-end without mocking.
func _make_agent_with_real_emotion_engine(agent_id: String) -> RefCounted:
	var src: String = """
extends RefCounted
var agent_id: String = ""
var current_state: int = 0
var emotion_engine: EmotionEngine = null
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var stub: RefCounted = scr.new()
	stub.set("agent_id", agent_id)
	var engine := EmotionEngine.new()
	stub.set("emotion_engine", engine)
	return stub


## Return the EmotionEngine from a stub agent.
func _engine(agent: RefCounted) -> EmotionEngine:
	return agent.get("emotion_engine") as EmotionEngine


## Compile and return a NarrationLogStub that records add_entry calls.
func _make_narration_log_stub() -> RefCounted:
	var src: String = """
extends RefCounted
var entries: Array = []
func add_entry(text: String, type: String) -> void:
	entries.append({"text": text, "type": type})
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	return scr.new()


## Compile and return a LoaderStub that owns a narration_log.
func _make_loader_stub(narration_log: RefCounted) -> RefCounted:
	var src: String = """
extends RefCounted
var narration_log: RefCounted = null
var agents: Array = []
func get_agents() -> Array:
	return agents.duplicate()
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var stub: RefCounted = scr.new()
	stub.set("narration_log", narration_log)
	return stub


## Build and wire a resolver with a loader supplier. Returns [resolver, log_stub].
func _make_wired_resolver(ws: WorldState, agents: Array, puzzle_list: Array[Dictionary]) -> Array:
	var log_stub: RefCounted = _make_narration_log_stub()
	var loader: RefCounted = _make_loader_stub(log_stub)
	for a: RefCounted in agents:
		var existing: Array = loader.get("agents") as Array
		existing.append(a)
		loader.set("agents", existing)
	var supplier: Callable = Callable(loader, "get_agents")
	var resolver := ActionResolver.new(ws, loader, puzzle_list, "", supplier)
	return [resolver, log_stub]


## Simple single-action puzzle: take "trigger" → sets flag → solve fires.
func _make_simple_puzzle(puzzle_id: String, solve_narration: String = "The world shifts.") -> Dictionary:
	return {
		"id": puzzle_id,
		"solve": {
			"when": {"flag": {puzzle_id + ".done": true}},
			"narration": solve_narration,
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"effect": {"set_flag": {puzzle_id + ".done": true}},
				"narration": "You take the trigger.",
			},
		],
	}


## Puzzle whose action fires but solve.when is never reachable from it — used
## to isolate action_resolved delta testing without puzzle_solved interference.
func _make_action_only_puzzle(puzzle_id: String) -> Dictionary:
	return {
		"id": puzzle_id,
		"solve": {
			"when": {"flag": {puzzle_id + ".unreachable": true}},
			"narration": "Never fires.",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"effect": {"set_flag": {puzzle_id + ".done": true}},
				"narration": "You take the trigger.",
			},
		],
	}


## Simple fail puzzle: require predicate that is never satisfied.
func _make_require_fail_puzzle(puzzle_id: String) -> Dictionary:
	return {
		"id": puzzle_id,
		"solve": {
			"when": {"flag": {puzzle_id + ".done": true}},
			"narration": "Solved.",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"require": {"flag": {puzzle_id + ".prereq": true}},
				"effect": {"set_flag": {puzzle_id + ".done": true}},
				"narration": "You take the trigger.",
			},
		],
	}


# ── Tests ─────────────────────────────────────────────────────────────────

func test_collaboration_action_resolved_fires_energy_delta_on_success() -> bool:
	## AC-FE-01: valid action with matching rule → action_resolved fires →
	## energy increases by energy_delta. Edge case: ceiling clamp at 1.0.
	# Arrange
	var wid: String = _world_id("fe01")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine: EmotionEngine = _engine(agent)

	# Use action-only puzzle — isolates action_resolved delta from puzzle_solved.
	var puzzle_list: Array[Dictionary] = [_make_action_only_puzzle("fe01")]
	var wire: Array = _make_wired_resolver(ws, [agent], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Sub-case 1: baseline energy 0.62 → expected 0.66.
	engine.energy = 0.62

	# Act
	var _result: Dictionary = resolver.resolve(agent, {"verb": "take", "target": "trigger"})

	# Assert
	if not _approx(engine.energy, 0.66):
		return _fail("AC-FE-01: expected energy 0.66, got %.4f" % engine.energy)
	# action_resolved also resets _fresh_curiosity_ticks (observable via mood getter).
	# With energy ~0.66 and default ticks=2 from fixture, mood should be 'curious'.
	if engine.mood != "curious":
		return _fail("AC-FE-01: expected mood 'curious' after action_resolved, got '%s'" % engine.mood)

	# Sub-case 2: ceiling clamp — energy 0.97 + 0.04 must clamp to 1.0.
	var wid2: String = _world_id("fe01b")
	_remove_if_exists(wid2)
	var ws2: WorldState = WorldState.load_for(wid2)
	var agent2: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine2: EmotionEngine = _engine(agent2)
	engine2.energy = 0.97
	var puzzle_list2: Array[Dictionary] = [_make_action_only_puzzle("fe01b")]
	var wire2: Array = _make_wired_resolver(ws2, [agent2], puzzle_list2)
	var resolver2: ActionResolver = wire2[0] as ActionResolver
	var _r2: Dictionary = resolver2.resolve(agent2, {"verb": "take", "target": "trigger"})
	if not _approx(engine2.energy, 1.0):
		return _fail("AC-FE-01 ceiling: expected energy 1.0, got %.4f" % engine2.energy)

	return true


func test_collaboration_puzzle_solved_fires_all_deltas_for_contributor() -> bool:
	## AC-FE-02 contributor: contributor receives energy+0.08, social_battery+0.06,
	## patience+0.04 deltas when puzzle solve fires.
	# Arrange
	var wid: String = _world_id("fe02a")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine_a: EmotionEngine = _engine(agent_a)
	engine_a.energy = 0.58
	engine_a.social_battery = 0.44
	engine_a.patience = 0.52

	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe02a")]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — agent_a is the contributor (acting agent).
	var _r: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert — contributor fires BOTH action_resolved (+0.04 energy) AND puzzle_solved
	# (+0.08 energy, +0.06 social_battery, +0.04 patience). social_battery and patience
	# only accumulate from puzzle_solved since action_resolved only touches energy.
	if not _approx(engine_a.energy, 0.70):
		return _fail("AC-FE-02a energy: expected 0.70, got %.4f" % engine_a.energy)
	if not _approx(engine_a.social_battery, 0.50):
		return _fail("AC-FE-02a social_battery: expected 0.50, got %.4f" % engine_a.social_battery)
	if not _approx(engine_a.patience, 0.56):
		return _fail("AC-FE-02a patience: expected 0.56, got %.4f" % engine_a.patience)

	return true


func test_collaboration_puzzle_solved_fires_for_collaborator_in_set() -> bool:
	## AC-FE-02 collaborator: collaborator in WorldState.puzzles[id].collaborators
	## receives identical deltas as the contributor.
	# Arrange
	var wid: String = _world_id("fe02b")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# Pre-seed agent_b as collaborator before resolve.
	ws.add_collaborator("fe02b", "agent_b")

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var agent_b: RefCounted = _make_agent_with_real_emotion_engine("agent_b")
	var engine_a: EmotionEngine = _engine(agent_a)
	var engine_b: EmotionEngine = _engine(agent_b)
	engine_a.energy = 0.5
	engine_a.social_battery = 0.5
	engine_a.patience = 0.5
	engine_b.energy = 0.5
	engine_b.social_battery = 0.5
	engine_b.patience = 0.5

	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe02b")]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — agent_a is contributor; agent_b is collaborator.
	var _r: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert agent_b (collaborator) received puzzle_solved deltas.
	# agent_b receives no action_resolved event (not the acting agent).
	if not _approx(engine_b.energy, 0.58):
		return _fail("AC-FE-02b collaborator energy: expected 0.58, got %.4f" % engine_b.energy)
	if not _approx(engine_b.social_battery, 0.56):
		return _fail("AC-FE-02b collaborator social_battery: expected 0.56, got %.4f" % engine_b.social_battery)
	if not _approx(engine_b.patience, 0.54):
		return _fail("AC-FE-02b collaborator patience: expected 0.54, got %.4f" % engine_b.patience)

	return true


func test_collaboration_bystander_receives_no_emotion_delta() -> bool:
	## AC-FE-02 bystander: agent_c not in collaborators and not contributor →
	## all bars unchanged after solve fires.
	# Arrange
	var wid: String = _world_id("fe02c")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var agent_c: RefCounted = _make_agent_with_real_emotion_engine("agent_c")
	var engine_c: EmotionEngine = _engine(agent_c)
	# Record starting values explicitly.
	engine_c.energy = 0.58
	engine_c.social_battery = 0.44
	engine_c.patience = 0.52

	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe02c")]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_c], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — agent_a is contributor; agent_c is bystander (not in collaborators).
	var _r: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert agent_c bars are unchanged (direct bar assertion, not log inspection).
	if not _approx(engine_c.energy, 0.58):
		return _fail("AC-FE-02c bystander energy should be unchanged 0.58, got %.4f" % engine_c.energy)
	if not _approx(engine_c.social_battery, 0.44):
		return _fail("AC-FE-02c bystander social_battery should be unchanged 0.44, got %.4f" % engine_c.social_battery)
	if not _approx(engine_c.patience, 0.52):
		return _fail("AC-FE-02c bystander patience should be unchanged 0.52, got %.4f" % engine_c.patience)

	return true


func test_collaboration_puzzle_solved_clamps_at_ceiling() -> bool:
	## AC-FE-03: social_battery = 0.98 → after puzzle_solved fires with delta
	## 0.06, social_battery == 1.0 (not 1.04).
	# Arrange
	var wid: String = _world_id("fe03")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine_a: EmotionEngine = _engine(agent_a)
	engine_a.energy = 0.98
	engine_a.social_battery = 0.98
	engine_a.patience = 0.98

	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe03")]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act
	var _r: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert — each bar clamped independently at 1.0.
	if not _approx(engine_a.social_battery, 1.0):
		return _fail("AC-FE-03: social_battery should clamp to 1.0, got %.4f" % engine_a.social_battery)
	if not _approx(engine_a.energy, 1.0):
		return _fail("AC-FE-03: energy should clamp to 1.0, got %.4f" % engine_a.energy)
	if not _approx(engine_a.patience, 1.0):
		return _fail("AC-FE-03: patience should clamp to 1.0, got %.4f" % engine_a.patience)

	return true


func test_collaboration_layer_interest_refresh_on_new_qualification() -> bool:
	## AC-FE-04: refresh_layer_interest adds the config delta to the existing
	## compound-key value, clamped to 1.0. Three sub-cases:
	##   1. existing = 0.3 → result = 0.9
	##   2. key absent  → result = 0.6
	##   3. existing = 0.8 → result = 1.0 (ceiling)
	# Arrange
	var mem := AgentMemory.create("agent_a")

	# Sub-case 1: existing 0.3 + 0.6 = 0.9.
	mem.entity_interest["layer:ancient_pillar:1"] = 0.3

	# Act
	mem.refresh_layer_interest("ancient_pillar", 1)

	# Assert
	var val1: float = mem.entity_interest.get("layer:ancient_pillar:1", -1.0) as float
	if not _approx(val1, 0.9):
		return _fail("AC-FE-04 sub1: expected 0.9, got %.4f" % val1)

	# Sub-case 2: key absent → 0.0 + 0.6 = 0.6.
	var mem2 := AgentMemory.create("agent_a")
	mem2.refresh_layer_interest("ancient_pillar", 2)
	var val2: float = mem2.entity_interest.get("layer:ancient_pillar:2", -1.0) as float
	if not _approx(val2, 0.6):
		return _fail("AC-FE-04 sub2: expected 0.6 (absent key), got %.4f" % val2)

	# Sub-case 3: existing 0.8 + 0.6 = clamp to 1.0.
	var mem3 := AgentMemory.create("agent_a")
	mem3.entity_interest["layer:ancient_pillar:3"] = 0.8
	mem3.refresh_layer_interest("ancient_pillar", 3)
	var val3: float = mem3.entity_interest.get("layer:ancient_pillar:3", -1.0) as float
	if not _approx(val3, 1.0):
		return _fail("AC-FE-04 sub3: expected 1.0 (ceiling), got %.4f" % val3)

	return true


func test_collaboration_layer_interest_compound_key_survives_disk_flush() -> bool:
	## TD-008 / AC-FE-04 persistence half: the compound "layer:<prop>:<n>" key
	## written by refresh_layer_interest survives a forced save_to_disk and a
	## fresh load_from_disk. Asserts the reloaded value equals the in-memory
	## value (not a literal) so the test is immune to config-delta changes.
	var flush_agent_id: String = "td008_flush_agent"
	var save_path: String = "user://saves/" + flush_agent_id + "_memory.json"

	# Arrange — fresh memory, one layer-interest refresh.
	var mem := AgentMemory.create(flush_agent_id)
	mem.refresh_layer_interest("ancient_pillar", 1)
	var in_memory_val: float = mem.entity_interest.get("layer:ancient_pillar:1", -1.0) as float
	if in_memory_val < 0.0:
		return _fail("TD-008: compound key missing in memory before flush")

	# Act — force flush past the debounce, then reload from disk.
	mem.save_to_disk(true)
	var reloaded: AgentMemory = AgentMemory.load_from_disk(flush_agent_id)
	var reloaded_val: float = reloaded.entity_interest.get("layer:ancient_pillar:1", -1.0) as float

	# Cleanup before asserting so a failure never leaves the save behind.
	DirAccess.remove_absolute(save_path)

	# Assert
	if not _approx(reloaded_val, in_memory_val):
		return _fail("TD-008: expected reloaded compound key %.4f, got %.4f" % [in_memory_val, reloaded_val])
	return true


func test_collaboration_two_puzzles_one_cycle_single_puzzle_solved_delta() -> bool:
	## AC-FE-08 / R24 with a REAL EmotionEngine: two puzzles whose solve.when
	## both flip on one shared flag write must both solve in the same resolve()
	## cycle, but the contributor's energy rises by exactly one
	## puzzle_solved.energy_delta — 0.58 + 0.04 (action_resolved) + 0.08
	## (puzzle_solved, once) = 0.70, not 0.78.
	# Arrange — p1 carries the action; p2 solves off the same flag.
	var wid: String = _world_id("fe08")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine_a: EmotionEngine = _engine(agent_a)
	engine_a.energy = 0.58

	var puzzle_p1: Dictionary = {
		"id": "fe08_p1",
		"solve": {
			"when": {"flag": {"fe08.shared": true}},
			"narration": "The first thing settles.",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"effect": {"set_flag": {"fe08.shared": true}},
				"narration": "You take the trigger.",
			},
		],
	}
	var puzzle_p2: Dictionary = {
		"id": "fe08_p2",
		"solve": {
			"when": {"flag": {"fe08.shared": true}},
			"narration": "The second thing settles.",
		},
		"actions": [],
	}
	var puzzle_list: Array[Dictionary] = [puzzle_p1, puzzle_p2]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — one action flips both solve predicates in a single cycle.
	var _r: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert — both puzzles actually solved (the clamp claim is meaningful).
	if ws.get_puzzle_state("fe08_p1") != 2:
		return _fail("AC-FE-08: fe08_p1 should be SOLVED (state 2), got %d" % ws.get_puzzle_state("fe08_p1"))
	if ws.get_puzzle_state("fe08_p2") != 2:
		return _fail("AC-FE-08: fe08_p2 should be SOLVED (state 2), got %d" % ws.get_puzzle_state("fe08_p2"))

	# Assert — exactly one puzzle_solved delta on the contributor.
	if not _approx(engine_a.energy, 0.70):
		return _fail("AC-FE-08: expected energy 0.70 (one puzzle_solved delta, not two), got %.4f" % engine_a.energy)

	return true


func test_collaboration_action_resolved_does_not_fire_on_precondition_fail() -> bool:
	## AC-FE-05: action fails precondition (take item agent already holds) →
	## action_resolved does NOT fire → energy unchanged.
	# Arrange
	var wid: String = _world_id("fe05a")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# Give agent_a the item so 'take' precondition fails (can't take what you have).
	ws.give_item("agent_a", "trigger")

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine_a: EmotionEngine = _engine(agent_a)
	engine_a.energy = 0.62
	var starting_energy: float = engine_a.energy

	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe05a")]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — take fails because agent already holds "trigger".
	var result: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert — precondition failed, state_changed should be false.
	if result.get("state_changed", true) != false:
		return _fail("AC-FE-05 precondition: expected state_changed=false")
	# Energy must not have changed.
	if not _approx(engine_a.energy, starting_energy):
		return _fail("AC-FE-05 precondition: energy should be unchanged %.4f, got %.4f" % [starting_energy, engine_a.energy])

	return true


func test_collaboration_action_resolved_does_not_fire_on_no_match() -> bool:
	## AC-FE-05 no-match path: verb is valid but no puzzle rule matches →
	## action_resolved does NOT fire → energy unchanged.
	# Arrange
	var wid: String = _world_id("fe05b")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine_a: EmotionEngine = _engine(agent_a)
	engine_a.energy = 0.62
	var starting_energy: float = engine_a.energy

	# Puzzle that matches "take trigger" only — not "take other_thing".
	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe05b")]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — "take other_thing" matches no rule in the puzzle.
	var result: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "other_thing"})

	# Assert
	if result.get("state_changed", true) != false:
		return _fail("AC-FE-05 no-match: expected state_changed=false")
	if not _approx(engine_a.energy, starting_energy):
		return _fail("AC-FE-05 no-match: energy should be unchanged %.4f, got %.4f" % [starting_energy, engine_a.energy])

	return true


func test_collaboration_action_resolved_does_not_fire_on_require_fail() -> bool:
	## AC-FE-05 require-fail path: rule matches verb+target but require predicate
	## is unsatisfied → ActionResolver returns nothing_happens before Step 5 →
	## action_resolved does NOT fire → energy unchanged.
	# Arrange
	var wid: String = _world_id("fe05c")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine_a: EmotionEngine = _engine(agent_a)
	engine_a.energy = 0.62
	var starting_energy: float = engine_a.energy

	# Puzzle requires fe05c.prereq=true before take triggers; never set → require fails.
	var puzzle_list: Array[Dictionary] = [_make_require_fail_puzzle("fe05c")]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — rule matches but require predicate is false.
	var result: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert — state_changed=false, energy unchanged (no action_resolved fire).
	if result.get("state_changed", true) != false:
		return _fail("AC-FE-05 require-fail: expected state_changed=false")
	if not _approx(engine_a.energy, starting_energy):
		return _fail("AC-FE-05 require-fail: energy should be unchanged %.4f, got %.4f" % [starting_energy, engine_a.energy])

	return true


func test_collaboration_causal_log_contributor_string_matches() -> bool:
	## AC-FE-06 contributor: after solve, contributor's causal log last entry
	## equals the log_cause_contributor string from config.
	# Arrange
	var wid: String = _world_id("fe06a")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var engine_a: EmotionEngine = _engine(agent_a)

	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe06a")]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act
	var _r: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert — last causal log entry is the contributor string.
	var causes: Array = engine_a.recent_causes(10)
	if causes.is_empty():
		return _fail("AC-FE-06 contributor: causal log is empty")
	var last_cause: String = str(causes[causes.size() - 1])
	var expected: String = "a thing settled that had not settled before, and you were there when it did"
	if last_cause != expected:
		return _fail("AC-FE-06 contributor: expected '%s', got '%s'" % [expected, last_cause])

	return true


func test_collaboration_causal_log_collaborator_string_matches() -> bool:
	## AC-FE-06 collaborator/witness: after solve, collaborator's causal log
	## last entry equals the log_cause_witness string from config.
	# Arrange
	var wid: String = _world_id("fe06b")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# Pre-seed agent_b as collaborator.
	ws.add_collaborator("fe06b", "agent_b")

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var agent_b: RefCounted = _make_agent_with_real_emotion_engine("agent_b")
	var engine_b: EmotionEngine = _engine(agent_b)

	var puzzle_list: Array[Dictionary] = [_make_simple_puzzle("fe06b")]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — agent_a is contributor; agent_b is collaborator.
	var _r: Dictionary = resolver.resolve(agent_a, {"verb": "take", "target": "trigger"})

	# Assert — agent_b's last cause is the witness string.
	var causes: Array = engine_b.recent_causes(10)
	if causes.is_empty():
		return _fail("AC-FE-06 collaborator: causal log is empty")
	var last_cause: String = str(causes[causes.size() - 1])
	var expected: String = "something another did that made the world settle differently"
	if last_cause != expected:
		return _fail("AC-FE-06 collaborator: expected '%s', got '%s'" % [expected, last_cause])

	return true


func test_collaboration_flag_writer_auto_credit_adds_collaborator() -> bool:
	## R21b: agent_a sets a flag via set_flag_with_writer that appears in
	## solve.when. agent_b's action flips solve.when to true. After solve:
	## agent_a is in collaborators (flag_writer auto-credit) and receives
	## the collaborator emotion event.
	# Arrange
	var wid: String = _world_id("r21b")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# agent_a writes a flag as if it had previously taken an action.
	ws.set_flag_with_writer("prereq.lit", true, "agent_a")

	# Puzzle requires prereq.lit AND the take-trigger action to solve.
	var puzzle: Dictionary = {
		"id": "r21b_puzzle",
		"solve": {
			"when": {"and": [
				{"flag": {"prereq.lit": true}},
				{"flag": {"r21b_puzzle.done": true}},
			]},
			"narration": "The world settles.",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"effect": {"set_flag": {"r21b_puzzle.done": true}},
				"narration": "You take the trigger.",
			},
		],
	}

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var agent_b: RefCounted = _make_agent_with_real_emotion_engine("agent_b")
	var engine_a: EmotionEngine = _engine(agent_a)
	engine_a.energy = 0.5
	engine_a.social_battery = 0.5
	engine_a.patience = 0.5

	var puzzle_list: Array[Dictionary] = [puzzle]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — agent_b triggers the solve (contributor).
	var _r: Dictionary = resolver.resolve(agent_b, {"verb": "take", "target": "trigger"})

	# Assert — agent_a should be in collaborators (R21b auto-credit).
	var collaborators: Array[String] = ws.get_puzzle_collaborators("r21b_puzzle")
	if not collaborators.has("agent_a"):
		return _fail("R21b: expected agent_a in collaborators via flag_writer auto-credit, got %s" % str(collaborators))

	# Assert — agent_a received the collaborator emotion event (not bystander).
	# energy: 0.5 + 0.08 (puzzle_solved collaborator) = 0.58
	if not _approx(engine_a.energy, 0.58):
		return _fail("R21b: agent_a (flag_writer collaborator) energy should be 0.58, got %.4f" % engine_a.energy)

	return true


func test_collaboration_flag_writer_auto_credit_walks_or_predicate() -> bool:
	## R21b OR-branch: solve.when wraps the flag check in an OR. The flag-writer
	## walker must recurse into the OR array and find the flag id; otherwise
	## the writer is silently dropped from collaborators.
	# Arrange
	var wid: String = _world_id("r21b_or")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# agent_a writes the flag that will satisfy the OR.
	ws.set_flag_with_writer("prereq_a.lit", true, "agent_a")

	# Puzzle solves when EITHER prereq is lit. agent_a's write satisfies the
	# first branch from the start; agent_b's action just needs to trigger the
	# solve scan via _post_match_effects.
	var puzzle: Dictionary = {
		"id": "r21b_or_puzzle",
		"solve": {
			"when": {"or": [
				{"flag": {"prereq_a.lit": true}},
				{"flag": {"prereq_b.lit": true}},
			]},
			"narration": "The world settles via either path.",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"effect": {"set_flag": {"r21b_or_puzzle.touched": true}},
				"narration": "You take the trigger.",
			},
		],
	}

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var agent_b: RefCounted = _make_agent_with_real_emotion_engine("agent_b")

	var puzzle_list: Array[Dictionary] = [puzzle]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — agent_b triggers the solve scan (contributor).
	var _r: Dictionary = resolver.resolve(agent_b, {"verb": "take", "target": "trigger"})

	# Assert — agent_a should be credited because the OR-branch walker
	# extracted prereq_a.lit from the nested predicate.
	var collaborators: Array[String] = ws.get_puzzle_collaborators("r21b_or_puzzle")
	if not collaborators.has("agent_a"):
		return _fail("R21b OR: expected agent_a in collaborators via OR-branch flag-writer walk, got %s" % str(collaborators))

	return true


func test_collaboration_flag_writer_auto_credit_walks_not_predicate() -> bool:
	## R21b NOT-branch: solve.when wraps the flag check in a NOT. The flag-writer
	## walker must recurse into the NOT sub-predicate and find the flag id;
	## otherwise the writer is silently dropped from collaborators.
	# Arrange
	var wid: String = _world_id("r21b_not")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# agent_a explicitly writes dark.lit=false; the NOT predicate evaluates true
	# (since dark.lit != true), so the puzzle is solvable from the moment
	# agent_b's action triggers the solve scan.
	ws.set_flag_with_writer("dark.lit", false, "agent_a")

	var puzzle: Dictionary = {
		"id": "r21b_not_puzzle",
		"solve": {
			"when": {"not": {"flag": {"dark.lit": true}}},
			"narration": "Where the dark was, settling.",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"effect": {"set_flag": {"r21b_not_puzzle.touched": true}},
				"narration": "You take the trigger.",
			},
		],
	}

	var agent_a: RefCounted = _make_agent_with_real_emotion_engine("agent_a")
	var agent_b: RefCounted = _make_agent_with_real_emotion_engine("agent_b")

	var puzzle_list: Array[Dictionary] = [puzzle]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver

	# Act — agent_b triggers the solve scan (contributor).
	var _r: Dictionary = resolver.resolve(agent_b, {"verb": "take", "target": "trigger"})

	# Assert — agent_a should be credited because the NOT-branch walker
	# recursed into the inner flag clause and found dark.lit.
	var collaborators: Array[String] = ws.get_puzzle_collaborators("r21b_not_puzzle")
	if not collaborators.has("agent_a"):
		return _fail("R21b NOT: expected agent_a in collaborators via NOT-branch flag-writer walk, got %s" % str(collaborators))

	return true
