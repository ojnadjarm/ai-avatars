class_name TestSolveState
extends RefCounted
## Unit tests for the Story 003 solve-state machine in ActionResolver.
## Covers AC-CB-15, AC-CB-16, AC-CB-17, AC-CB-17c, R24, and session-local
## idempotence. AC-CB-17b is DEFERRED (code path exists, no authored fixture).

const SAVES_DIR := "user://saves/"

const FIXTURE_AGENTS: Dictionary = {
	"luna": {
		"display_name": "Luna",
		"skills": [],
		"starting_inventory": [],
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

const FIXTURE_EMOTION_DEFAULTS: Dictionary = {
	"events": {
		"puzzle_solved": {
			"energy_delta": 0.08,
			"log_cause_contributor": "contrib_cause",
			"log_cause_witness": "witness_cause",
		},
	},
}

var failure_message: String = ""
var _test_world_ids: Array[String] = []
var _saved_agents: Dictionary = {}
var _saved_puzzle_defaults: Variant = null
var _had_puzzle_defaults: bool = false
var _saved_emotion_defaults: Variant = null
var _had_emotion_defaults: bool = false


func run() -> bool:
	_install_fixtures()

	if not _test_solve_state_solve_fires_same_resolve_call():
		_restore_fixtures()
		return false
	if not _test_solve_state_broadcast_delivers_to_every_agent():
		_restore_fixtures()
		return false
	if not _test_solve_state_idempotent_across_reload():
		_restore_fixtures()
		return false
	if not _test_solve_state_solving_to_solved_transition():
		_restore_fixtures()
		return false
	if not _test_solve_state_multi_puzzle_clamp_single_emotion():
		_restore_fixtures()
		return false
	if not _test_solve_state_same_session_re_resolve_no_duplicate_solve():
		_restore_fixtures()
		return false
	if not _test_solve_state_intermediate_transition_sets_solving_and_no_broadcast():
		_restore_fixtures()
		return false

	_cleanup()
	_restore_fixtures()
	return true


# ── Fixture management ────────────────────────────────────────────────────

func _install_fixtures() -> void:
	_saved_agents = GameState.agents
	GameState.agents = FIXTURE_AGENTS.duplicate(true)

	_had_puzzle_defaults = GameState.defaults.has("puzzle")
	if _had_puzzle_defaults:
		_saved_puzzle_defaults = GameState.defaults["puzzle"]
	GameState.defaults["puzzle"] = FIXTURE_PUZZLE_DEFAULTS.duplicate(true)

	_had_emotion_defaults = GameState.defaults.has("emotion")
	if _had_emotion_defaults:
		_saved_emotion_defaults = GameState.defaults["emotion"]
	GameState.defaults["emotion"] = FIXTURE_EMOTION_DEFAULTS.duplicate(true)


func _restore_fixtures() -> void:
	GameState.agents = _saved_agents

	if _had_puzzle_defaults:
		GameState.defaults["puzzle"] = _saved_puzzle_defaults
	else:
		GameState.defaults.erase("puzzle")

	if _had_emotion_defaults:
		GameState.defaults["emotion"] = _saved_emotion_defaults
	else:
		GameState.defaults.erase("emotion")

	# Always remove any save files this run produced — guarantees cleanup even
	# on failure paths that don't route through _fail().
	_cleanup()


# ── Helpers ───────────────────────────────────────────────────────────────

func _world_id(suffix: String) -> String:
	var wid: String = "test_ss_" + suffix
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


## Compile and return an EmotionEngineStub that records process_event calls.
## Signature normalized to 2-arg context dict per Story 004 (TD-005 resolved).
func _make_emotion_engine_stub() -> RefCounted:
	var src: String = """
extends RefCounted
var events: Array = []
func process_event(event: String, context: Dictionary) -> void:
	events.append({"event": event, "context": context})
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	return scr.new()


## Compile and return an AgentStub with agent_id and optional emotion_engine.
func _make_agent_stub(agent_id: String, emotion_engine: RefCounted = null) -> RefCounted:
	var src: String = """
extends RefCounted
var agent_id: String = ""
var current_state: int = 0
var emotion_engine: RefCounted = null
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var stub: RefCounted = scr.new()
	stub.set("agent_id", agent_id)
	stub.set("emotion_engine", emotion_engine)
	return stub


## Build a LoaderStub that owns a narration_log and exposes get_agents().
## Pass the returned stub's Callable(loader, "get_agents") as agents_supplier.
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


## Standard single-agent "take key → unlocks stargate" puzzle config.
func _make_stargate_puzzle(solve_narration: String = "The stargate opens.") -> Dictionary:
	return {
		"id": "stargate",
		"solve": {
			"when": {"flag": {"stargate.unlocked": true}},
			"narration": solve_narration,
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "key"},
				"effect": {"set_flag": {"stargate.unlocked": true}},
				"narration": "You take the key.",
			},
		],
	}


## Build and wire a resolver with loader+supplier and return it along with the log.
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


# ── Tests ─────────────────────────────────────────────────────────────────

func _test_solve_state_solve_fires_same_resolve_call() -> bool:
	## AC-CB-15: puzzle transitions to state 2 in the same resolve() call that
	## applies the triggering effect; narration_log gets a "solve" entry.
	# Arrange
	var wid: String = _world_id("ac15")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_stub("luna")
	var agent_b: RefCounted = _make_agent_stub("darksaddler")
	var puzzle: Dictionary = _make_stargate_puzzle()
	var puzzle_list: Array[Dictionary] = [puzzle]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver
	var log: RefCounted = wire[1]

	var acting: RefCounted = _make_agent_stub("luna")

	# Act
	var _result: Dictionary = resolver.resolve(acting, {"verb": "take", "target": "key"})

	# Assert
	if int(ws.puzzles.get("stargate", {}).get("state", -1)) != 2:
		return _fail("AC-CB-15: expected puzzles['stargate']['state'] == 2, got %s" % str(ws.puzzles.get("stargate", {})))
	if not ws._fired_puzzles.get("stargate", false):
		return _fail("AC-CB-15: _fired_puzzles['stargate'] should be true after solve")
	var entries: Array = log.get("entries") as Array
	var solve_entries: int = 0
	for e: Variant in entries:
		if (e as Dictionary).get("type", "") == "solve":
			solve_entries += 1
	if solve_entries < 1:
		return _fail("AC-CB-15: expected >=1 solve entry in narration_log, got %d" % solve_entries)
	return true


func _test_solve_state_broadcast_delivers_to_every_agent() -> bool:
	## AC-CB-16: solve narration delivered to every in-world agent; null entries
	## in the agent list do not crash and still-alive agents receive entries.
	# Arrange
	var wid: String = _world_id("ac16")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_stub("luna")
	var agent_b: RefCounted = _make_agent_stub("darksaddler")
	var agent_c: RefCounted = _make_agent_stub("grok")
	var puzzle: Dictionary = _make_stargate_puzzle("The gate roars open.")
	var puzzle_list: Array[Dictionary] = [puzzle]

	var log_stub: RefCounted = _make_narration_log_stub()
	var loader: RefCounted = _make_loader_stub(log_stub)
	var agent_list: Array = [agent_a, agent_b, agent_c]
	loader.set("agents", agent_list)
	var supplier: Callable = Callable(loader, "get_agents")
	var resolver := ActionResolver.new(ws, loader, puzzle_list, "", supplier)
	var acting: RefCounted = _make_agent_stub("luna")

	# Act
	var _result: Dictionary = resolver.resolve(acting, {"verb": "take", "target": "key"})

	# Assert — exactly 3 solve entries (one per agent), all with identical text.
	var entries: Array = log_stub.get("entries") as Array
	var solve_entries: Array = []
	for e: Variant in entries:
		if (e as Dictionary).get("type", "") == "solve":
			solve_entries.append(e)
	if solve_entries.size() != 3:
		return _fail("AC-CB-16: expected 3 solve entries, got %d" % solve_entries.size())
	var expected_text: String = "The gate roars open."
	for e: Variant in solve_entries:
		if (e as Dictionary).get("text", "") != expected_text:
			return _fail("AC-CB-16: solve entry text mismatch — got '%s'" % (e as Dictionary).get("text", ""))

	# Sub-assertion: null agent in list must not crash; remaining agents still get entries.
	var ws2: WorldState = WorldState.load_for(_world_id("ac16b"))
	var log2: RefCounted = _make_narration_log_stub()
	var loader2: RefCounted = _make_loader_stub(log2)
	# Include a null slot — agents list contains agent_a, null, agent_b.
	var mixed: Array = [agent_a, null, agent_b]
	loader2.set("agents", mixed)
	var supplier2: Callable = Callable(loader2, "get_agents")
	var resolver2 := ActionResolver.new(ws2, loader2, puzzle_list, "", supplier2)
	var _r2: Dictionary = resolver2.resolve(_make_agent_stub("luna"), {"verb": "take", "target": "key"})
	var entries2: Array = log2.get("entries") as Array
	var sc2: int = 0
	for e: Variant in entries2:
		if (e as Dictionary).get("type", "") == "solve":
			sc2 += 1
	# null is skipped; 2 valid agents → 2 solve entries
	if sc2 != 2:
		return _fail("AC-CB-16 sub: expected 2 solve entries with null in list, got %d" % sc2)
	return true


func _test_solve_state_idempotent_across_reload() -> bool:
	## AC-CB-17: after flush+reload, _fired_puzzles is rebuilt from state==2,
	## and a second resolve with the same action produces zero new "solve" entries.
	# Arrange — session 1: solve the puzzle and flush.
	var wid: String = _world_id("ac17")
	_remove_if_exists(wid)
	var ws1: WorldState = WorldState.load_for(wid)
	var agent_a: RefCounted = _make_agent_stub("luna")
	var puzzle: Dictionary = _make_stargate_puzzle("Stargate opens.")
	var puzzle_list: Array[Dictionary] = [puzzle]
	var wire1: Array = _make_wired_resolver(ws1, [agent_a], puzzle_list)
	var resolver1: ActionResolver = wire1[0] as ActionResolver
	var _r1: Dictionary = resolver1.resolve(_make_agent_stub("luna"), {"verb": "take", "target": "key"})
	# ws.flush() is called inside _handle_solve, but flush again to be explicit.
	ws1.flush()

	# Session 2: reload from disk.
	var ws2: WorldState = WorldState.load_for(wid)
	if not ws2._fired_puzzles.get("stargate", false):
		return _fail("AC-CB-17: after reload _fired_puzzles['stargate'] should be true (rebuilt from state==2)")

	var log2: RefCounted = _make_narration_log_stub()
	var loader2: RefCounted = _make_loader_stub(log2)
	loader2.set("agents", [_make_agent_stub("luna")])
	var supplier2: Callable = Callable(loader2, "get_agents")
	var resolver2 := ActionResolver.new(ws2, loader2, puzzle_list, "", supplier2)

	# Act — same triggering action in session 2.
	# Note: the flag stargate.unlocked is persisted so take precondition differs.
	# Directly set the flag to simulate re-trigger without the take precondition block.
	# The "take" precondition (agent must NOT already have key) passes because inventory
	# is clean after reload. The rule sets the flag again, but _fired_puzzles gates the solve.
	var _r2: Dictionary = resolver2.resolve(_make_agent_stub("luna"), {"verb": "take", "target": "key"})

	# Assert — state stays 2, no new solve entries.
	if int(ws2.puzzles.get("stargate", {}).get("state", -1)) != 2:
		return _fail("AC-CB-17: state should remain 2 after second resolve")
	var entries2: Array = log2.get("entries") as Array
	var sc2: int = 0
	for e: Variant in entries2:
		if (e as Dictionary).get("type", "") == "solve":
			sc2 += 1
	if sc2 != 0:
		return _fail("AC-CB-17: expected 0 new solve entries in session 2, got %d" % sc2)
	return true


func _test_solve_state_solving_to_solved_transition() -> bool:
	## AC-CB-17c: a puzzle at state==1 (SOLVING) does NOT rebuild _fired_puzzles,
	## and a subsequent action that satisfies solve.when produces state==2 + SOLVED
	## narration (no SOLVING narration on the 1→2 path).
	# Arrange: manually set state=1 and flush.
	var wid: String = _world_id("ac17c")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	ws.puzzles["stargate"] = {"state": 1, "collaborators": []}
	ws.flush()

	# Reload: state==1 means _fired_puzzles["stargate"] must be FALSE.
	var ws2: WorldState = WorldState.load_for(wid)
	if ws2._fired_puzzles.get("stargate", true) != false:
		return _fail("AC-CB-17c: state==1 should NOT set _fired_puzzles; expected false, got true")

	var puzzle: Dictionary = {
		"id": "stargate",
		"intermediate_when": {"flag": {"staged": true}},
		"solving_narration": "SOLVING",
		"solve": {
			"when": {"flag": {"stargate.unlocked": true}},
			"narration": "SOLVED",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "key"},
				"effect": {"set_flag": {"stargate.unlocked": true}},
				"narration": "You take the key.",
			},
		],
	}
	var puzzle_list: Array[Dictionary] = [puzzle]
	var agent_a: RefCounted = _make_agent_stub("luna")
	var agent_b: RefCounted = _make_agent_stub("darksaddler")
	var wire: Array = _make_wired_resolver(ws2, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver
	var log: RefCounted = wire[1]

	# Act: action sets stargate.unlocked → satisfies solve.when directly from state==1.
	var _r: Dictionary = resolver.resolve(_make_agent_stub("luna"), {"verb": "take", "target": "key"})

	# Assert: state == 2, N "SOLVED" entries (one per agent), zero "SOLVING" entries.
	if int(ws2.puzzles.get("stargate", {}).get("state", -1)) != 2:
		return _fail("AC-CB-17c: expected state==2, got %s" % str(ws2.puzzles.get("stargate", {})))
	var entries: Array = log.get("entries") as Array
	var solved_count: int = 0
	var solving_count: int = 0
	for e: Variant in entries:
		var ed: Dictionary = e as Dictionary
		if ed.get("type", "") == "solve":
			if ed.get("text", "") == "SOLVED":
				solved_count += 1
			elif ed.get("text", "") == "SOLVING":
				solving_count += 1
	if solved_count != 2:
		return _fail("AC-CB-17c: expected 2 SOLVED entries (one per agent), got %d" % solved_count)
	if solving_count != 0:
		return _fail("AC-CB-17c: expected 0 SOLVING entries on 1→2 path, got %d" % solving_count)
	return true


func _test_solve_state_multi_puzzle_clamp_single_emotion() -> bool:
	## R24: when two puzzles both solve in one resolve() call, each agent receives
	## exactly one emotion event (not two), and narration_log gets 2*N entries.
	## Story 004: darksaddler pre-seeded as collaborator so it qualifies for the
	## emotion event (bystanders are filtered at _apply_puzzle_solved_emotion).
	# Arrange
	var wid: String = _world_id("r24")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# Pre-seed darksaddler as a collaborator on both puzzles so it receives the
	# emotion event (Story 004 contributor/collaborator split). Without this,
	# darksaddler is a bystander and correctly receives 0 events — but the R24
	# clamp test needs darksaddler eligible to verify "1 not 2" across 2 puzzles.
	ws.add_collaborator("p1", "darksaddler")
	ws.add_collaborator("p2", "darksaddler")

	var ee_a: RefCounted = _make_emotion_engine_stub()
	var ee_b: RefCounted = _make_emotion_engine_stub()
	var agent_a: RefCounted = _make_agent_stub("luna", ee_a)
	var agent_b: RefCounted = _make_agent_stub("darksaddler", ee_b)

	# Both puzzles share the same solve.when flag so one action fires both.
	var puzzle_p1: Dictionary = {
		"id": "p1",
		"solve": {
			"when": {"flag": {"shared": true}},
			"narration": "P1 solved.",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "trigger"},
				"effect": {"set_flag": {"shared": true}},
				"narration": "Trigger taken.",
			},
		],
	}
	var puzzle_p2: Dictionary = {
		"id": "p2",
		"solve": {
			"when": {"flag": {"shared": true}},
			"narration": "P2 solved.",
		},
		"actions": [],
	}
	var puzzle_list: Array[Dictionary] = [puzzle_p1, puzzle_p2]
	var wire: Array = _make_wired_resolver(ws, [agent_a, agent_b], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver
	var log: RefCounted = wire[1]

	# Act
	var _r: Dictionary = resolver.resolve(_make_agent_stub("luna"), {"verb": "take", "target": "trigger"})

	# Assert — 4 solve entries total (2 puzzles × 2 agents).
	var entries: Array = log.get("entries") as Array
	var sc: int = 0
	for e: Variant in entries:
		if (e as Dictionary).get("type", "") == "solve":
			sc += 1
	if sc != 4:
		return _fail("R24: expected 4 solve entries (2 puzzles × 2 agents), got %d" % sc)

	# Assert — each agent received exactly one emotion event (R24 clamp).
	# agent_a (luna) = contributor; agent_b (darksaddler) = collaborator.
	var events_a: Array = ee_a.get("events") as Array
	var events_b: Array = ee_b.get("events") as Array
	if events_a.size() != 1:
		return _fail("R24: agent_a (luna) should have exactly 1 emotion event, got %d" % events_a.size())
	if events_b.size() != 1:
		return _fail("R24: agent_b (darksaddler) should have exactly 1 emotion event, got %d" % events_b.size())
	if (events_a[0] as Dictionary).get("event", "") != "puzzle_solved":
		return _fail("R24: agent_a event should be 'puzzle_solved', got '%s'" % (events_a[0] as Dictionary).get("event", ""))
	if (events_b[0] as Dictionary).get("event", "") != "puzzle_solved":
		return _fail("R24: agent_b event should be 'puzzle_solved', got '%s'" % (events_b[0] as Dictionary).get("event", ""))
	# Verify context dict shape (Story 004 normalization — was .cause/.delta).
	var ctx_a: Dictionary = (events_a[0] as Dictionary).get("context", {}) as Dictionary
	var ctx_b: Dictionary = (events_b[0] as Dictionary).get("context", {}) as Dictionary
	if not ctx_a.has("is_contributor"):
		return _fail("R24: agent_a event context missing 'is_contributor' key")
	if not ctx_b.has("is_contributor"):
		return _fail("R24: agent_b event context missing 'is_contributor' key")
	return true


func _test_solve_state_same_session_re_resolve_no_duplicate_solve() -> bool:
	## Session-local idempotence: a second resolve in the same session must not
	## add more "solve" entries to narration_log.
	# Arrange
	var wid: String = _world_id("sessidem")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	var agent_a: RefCounted = _make_agent_stub("luna")
	var puzzle: Dictionary = _make_stargate_puzzle("Gate opens.")
	var puzzle_list: Array[Dictionary] = [puzzle]
	var wire: Array = _make_wired_resolver(ws, [agent_a], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver
	var log: RefCounted = wire[1]

	# Act — first resolve (solves the puzzle).
	var _r1: Dictionary = resolver.resolve(_make_agent_stub("luna"), {"verb": "take", "target": "key"})
	var entries_after_first: Array = (log.get("entries") as Array).duplicate()
	var sc1: int = 0
	for e: Variant in entries_after_first:
		if (e as Dictionary).get("type", "") == "solve":
			sc1 += 1

	# Act — second resolve with same action (flag already set; take precondition:
	# agent must NOT have the key, so we use a fresh acting stub each time).
	# The flag stargate.unlocked is now set, so the rule effect is a no-op but
	# _fired_puzzles["stargate"] gates the solve scan.
	var _r2: Dictionary = resolver.resolve(_make_agent_stub("luna"), {"verb": "take", "target": "key"})
	var entries_after_second: Array = log.get("entries") as Array
	var sc2: int = 0
	for e: Variant in entries_after_second:
		if (e as Dictionary).get("type", "") == "solve":
			sc2 += 1

	# Assert — solve count must not grow.
	if sc2 != sc1:
		return _fail("session-idem: solve entry count grew from %d to %d on second resolve" % [sc1, sc2])
	return true


func _test_solve_state_intermediate_transition_sets_solving_and_no_broadcast() -> bool:
	## AC-CB-17c intermediate path: action satisfying intermediate_when sets state=1,
	## delivers solving_narration to acting agent only. A second action satisfying
	## solve.when → state=2, SOLVED narration broadcast, zero additional SOLVING entries.
	# Arrange
	var wid: String = _world_id("inter")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_luna: RefCounted = _make_agent_stub("luna")
	var agent_dark: RefCounted = _make_agent_stub("darksaddler")

	var puzzle: Dictionary = {
		"id": "stargate",
		"intermediate_when": {"flag": {"staged": true}},
		"solving_narration": "SOLVING",
		"solve": {
			"when": {"flag": {"final": true}},
			"narration": "SOLVED",
		},
		"actions": [
			{
				"match": {"verb": "take", "target": "stage_key"},
				"effect": {"set_flag": {"staged": true}},
				"narration": "Stage done.",
			},
			{
				"match": {"verb": "take", "target": "final_key"},
				"effect": {"set_flag": {"final": true}},
				"narration": "Final done.",
			},
		],
	}
	var puzzle_list: Array[Dictionary] = [puzzle]
	var wire: Array = _make_wired_resolver(ws, [agent_luna, agent_dark], puzzle_list)
	var resolver: ActionResolver = wire[0] as ActionResolver
	var log: RefCounted = wire[1]

	# Act — first action triggers intermediate_when (staged = true).
	var _r1: Dictionary = resolver.resolve(agent_luna, {"verb": "take", "target": "stage_key"})

	# Assert intermediate state.
	if int(ws.puzzles.get("stargate", {}).get("state", -1)) != 1:
		return _fail("inter: expected state==1 after intermediate action, got %s" % str(ws.puzzles.get("stargate", {})))
	if ws._fired_puzzles.get("stargate", false) != false:
		return _fail("inter: _fired_puzzles must remain false after intermediate (only SOLVED latches it)")
	var entries_mid: Array = log.get("entries") as Array
	var solving_mid: int = 0
	var solved_mid: int = 0
	for e: Variant in entries_mid:
		var ed: Dictionary = e as Dictionary
		if ed.get("type", "") == "solve":
			if ed.get("text", "") == "SOLVING":
				solving_mid += 1
			elif ed.get("text", "") == "SOLVED":
				solved_mid += 1
	if solving_mid != 1:
		return _fail("inter: expected exactly 1 SOLVING entry (acting agent only), got %d" % solving_mid)
	if solved_mid != 0:
		return _fail("inter: expected 0 SOLVED entries after intermediate, got %d" % solved_mid)

	# Act — second action triggers solve.when (final = true).
	var _r2: Dictionary = resolver.resolve(agent_luna, {"verb": "take", "target": "final_key"})

	# Assert final state.
	if int(ws.puzzles.get("stargate", {}).get("state", -1)) != 2:
		return _fail("inter: expected state==2 after solve action, got %s" % str(ws.puzzles.get("stargate", {})))
	var entries_final: Array = log.get("entries") as Array
	var solving_final: int = 0
	var solved_final: int = 0
	for e: Variant in entries_final:
		var ed: Dictionary = e as Dictionary
		if ed.get("type", "") == "solve":
			if ed.get("text", "") == "SOLVING":
				solving_final += 1
			elif ed.get("text", "") == "SOLVED":
				solved_final += 1
	# 2 agents in world → 2 SOLVED entries; SOLVING count must not grow beyond 1.
	if solved_final != 2:
		return _fail("inter: expected 2 SOLVED entries (one per agent), got %d" % solved_final)
	if solving_final != 1:
		return _fail("inter: SOLVING count should remain 1 (no new SOLVING on 1→2 path), got %d" % solving_final)
	return true
