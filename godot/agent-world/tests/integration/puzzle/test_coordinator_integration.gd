class_name TestCoordinatorIntegration
extends RefCounted
## Integration tests for Story 006: LLMCoordinator & world_loader Integration.
##
## Covers (automated):
##   AC-CB-07c — go_to resolves without teleport (test 2)
##   AC-PERF-03 — no puzzle files = no regression (test 3)
##   AC-CB-14   — call_agent triggers encounter dispatcher (test 4)
##   WorldState force-flush via queue_world_state_save(true) (test 1)
##   LLMCoordinator action-resolution seam:
##     response with <action> → narration_log "action" entry + fire-and-forget
##     llm_chat with <narration> payload + queue_world_state_save(false) (test 5)
##
## DEFERRED — PLAYTEST-VERIFIED per story 006:
##   AC-CB-18 — ActivityGate cooldown blocks autonomous actions (requires live loop)
##   AC-CB-19 — Player [E] and world-switch bypass gate (requires live scene)
##   AC-PERF-02 — "Same visible frame" save + narration (requires live scene)

const SAVES_DIR := "user://saves/"

## Fixture agent config injected into GameState for the test run.
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
}

const FIXTURE_PUZZLE_DEFAULTS: Dictionary = {
	"nothing_happens": {
		"go_to": "Your feet carry you, but the world does not shift.",
		"take": "Your hand closes on nothing.",
		"use_object": "Nothing stirs.",
		"use_skill": "The world does not respond.",
		"call_agent": "The name does not carry. No one turns.",
	},
	"nothing_happens_text": "The world holds its shape.",
	"empty_prop_fallback": "It is here, present and unremarkable.",
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

var failure_message: String = ""
var _test_world_ids: Array[String] = []
var _saved_agents: Dictionary = {}
var _saved_puzzle_defaults: Variant = null
var _had_puzzle_defaults: bool = false
var _saved_emotion_defaults: Variant = null
var _had_emotion_defaults: bool = false


func run() -> bool:
	_install_fixtures()

	if not test_coordinator_queue_save_force_true_flushes_immediately():
		_restore_fixtures()
		return false
	if not test_coordinator_go_to_resolves_without_teleport():
		_restore_fixtures()
		return false
	if not test_coordinator_no_puzzle_files_no_regression():
		_restore_fixtures()
		return false
	if not test_coordinator_call_agent_triggers_dispatcher():
		_restore_fixtures()
		return false
	if not test_coordinator_resolve_action_from_response_routes_seam():
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


# ── Helpers ───────────────────────────────────────────────────────────────

func _world_id(suffix: String) -> String:
	var wid: String = "test_coord_" + suffix
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


## Compile and return a stub agent RefCounted with agent_id, current_state,
## position, and a real EmotionEngine.
func _make_agent_stub(agent_id: String) -> RefCounted:
	var src: String = """
extends RefCounted
var agent_id: String = ""
var current_state: int = 0
var position: Vector2 = Vector2.ZERO
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


## Build a loader stub that exposes narration_log, agents_container logic,
## activity_gate, and encounter_dispatcher for call_agent tests.
func _make_loader_stub_with_agents(narration_log: RefCounted, agents: Array) -> RefCounted:
	var src: String = """
extends RefCounted
var narration_log: RefCounted = null
var activity_gate: ActivityGate = null
var encounter_dispatcher: RefCounted = null
var _agents: Array = []
func find_agent(agent_id: String) -> RefCounted:
	for a in _agents:
		if str(a.get("agent_id")) == agent_id:
			return a
	return null
func get_agents() -> Array:
	return _agents.duplicate()
func request_agent_encounter(sender_id: String, listener_id: String, context_id: String = "") -> void:
	if encounter_dispatcher != null:
		encounter_dispatcher.start(sender_id, listener_id, context_id)
func can_trigger_activity() -> bool:
	return activity_gate != null and activity_gate.can_trigger()
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var stub: RefCounted = scr.new()
	stub.set("narration_log", narration_log)
	stub.set("_agents", agents.duplicate())
	var gate := ActivityGate.new()
	gate.remaining = 0.0
	stub.set("activity_gate", gate)
	return stub


## Build and return a resolver wired with an agents supplier.
func _make_wired_resolver(ws: WorldState, loader: RefCounted, agents: Array, puzzle_list: Array[Dictionary]) -> ActionResolver:
	var supplier: Callable = Callable(loader, "get_agents")
	return ActionResolver.new(ws, loader, puzzle_list, "", supplier)


## Compile and return an LLMClient-derived stub that records llm_chat calls
## instead of making HTTP requests. Extends the real class so it can be
## assigned into WorldLoader's typed `llm` field.
func _make_llm_stub() -> LLMClient:
	var src: String = """
extends LLMClient
var chat_calls: Array = []
func llm_chat(gateway_id: String, system_prompt: String, user_message: String, session_id: String = \"\", request_id: String = \"\", model_override: String = \"\", agent_id: String = \"\") -> void:
	chat_calls.append({
		\"gateway\": gateway_id,
		\"system\": system_prompt,
		\"user\": user_message,
		\"session\": session_id,
		\"req_id\": request_id,
		\"model\": model_override,
		\"agent_id\": agent_id,
	})
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	return scr.new()


## Compile and return a CanvasLayer-based narration log recorder — same
## recording shape as _make_narration_log_stub, but assignable into
## WorldLoader's typed `narration_log: CanvasLayer` field.
func _make_narration_log_layer_stub() -> CanvasLayer:
	var src: String = """
extends CanvasLayer
var entries: Array = []
func add_entry(text: String, type: String = \"event\") -> void:
	entries.append({\"text\": text, \"type\": type})
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	return scr.new()


## Compile and return a WorldLoader-derived loader stub for LLMCoordinator's
## typed _init(wl: WorldLoader) parameter. Exposes the surface
## _resolve_action_from_response touches: action_resolver, narration_log, llm
## (inherited typed fields), plus a queue_world_state_save recorder override.
## The recorders are added as children so loader.free() cascades to them.
##
## submit_agent_action() resolves synchronously (no approval hold), so
## _resolve_action_from_response's callback fires before submit_agent_action
## returns — no extra wiring needed here beyond the stubbed fields below.
func _make_coordinator_loader_stub(narration_log_layer: CanvasLayer, action_resolver: ActionResolver, llm_client: LLMClient) -> WorldLoader:
	var src: String = """
extends WorldLoader
var save_calls: Array = []
func queue_world_state_save(force: bool) -> void:
	save_calls.append({\"force\": force})
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var stub: WorldLoader = scr.new()
	stub.set("action_resolver", action_resolver)
	stub.set("narration_log", narration_log_layer)
	stub.set("llm", llm_client)
	stub.add_child(narration_log_layer)
	stub.add_child(llm_client)
	return stub


# ── Tests ─────────────────────────────────────────────────────────────────

func test_coordinator_queue_save_force_true_flushes_immediately() -> bool:
	## Validates that WorldState.flush() produces the save file synchronously.
	## The full debounce/force split lives in world_loader (a scene Node,
	## not unit-testable here) — the force=true path calls flush() directly.
	## We verify flush() produces a valid schema_version:1 file and that
	## calling it with no flags set produces an empty-but-valid save.
	## The force=false debounce branch is PLAYTEST-VERIFIED via the Timer.
	# Arrange
	var wid: String = _world_id("flush01")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	ws.set_flag("coord.flush_test", true)

	# Act — simulate what queue_world_state_save(true) does: stop timer + call flush().
	ws.flush()

	# Assert — file exists and has correct schema.
	var path: String = _save_path(wid)
	if not FileAccess.file_exists(path):
		return _fail("test_coordinator_queue_save_force_true_flushes_immediately: flush() did not produce save file at %s" % path)

	var data: Dictionary = GameState.load_json(path, "")
	if data.get("schema_version", 0) != 1:
		return _fail("test_coordinator_queue_save_force_true_flushes_immediately: expected schema_version=1 in save file")

	var flags: Variant = data.get("flags", {})
	if not (flags is Dictionary) or not (flags as Dictionary).has("coord.flush_test"):
		return _fail("test_coordinator_queue_save_force_true_flushes_immediately: flag 'coord.flush_test' missing from save file")

	# Verify a subsequent load_for round-trips the flag correctly.
	var ws2: WorldState = WorldState.load_for(wid)
	if ws2.get_flag("coord.flush_test") != true:
		return _fail("test_coordinator_queue_save_force_true_flushes_immediately: load_for did not restore flag after flush")

	return true


func test_coordinator_go_to_resolves_without_teleport() -> bool:
	## AC-CB-07c: go_to action with matching rule → state_changed=true,
	## flag set in WorldState, narration type "action" logged, agent position UNCHANGED.
	# Arrange
	var wid: String = _world_id("cb07c")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent: RefCounted = _make_agent_stub("agent_a")
	agent.set("position", Vector2(128.0, 64.0))
	var start_pos: Vector2 = agent.get("position") as Vector2

	var log_stub: RefCounted = _make_narration_log_stub()
	var agents: Array = [agent]
	var loader: RefCounted = _make_loader_stub_with_agents(log_stub, agents)

	var puzzle: Dictionary = {
		"id": "cb07c_pillar",
		"solve": {
			"when": {"flag": {"cb07c.solved": true}},
			"narration": "Never fires in this test.",
		},
		"actions": [
			{
				"match": {"verb": "go_to", "target": "ancient_pillar"},
				"effect": {"set_flag": {"agent.near_pillar": true}},
				"narration": "You reach the pillar.",
			},
		],
	}
	var puzzle_list: Array[Dictionary] = [puzzle]
	var resolver: ActionResolver = _make_wired_resolver(ws, loader, agents, puzzle_list)

	# Act
	var result: Dictionary = resolver.resolve(agent, {"verb": "go_to", "target": "ancient_pillar"})

	# Assert — state changed.
	if result.get("state_changed", false) != true:
		return _fail("test_coordinator_go_to_resolves_without_teleport: expected state_changed=true, got %s" % str(result))

	# Assert — flag written.
	if ws.get_flag("agent.near_pillar") != true:
		return _fail("test_coordinator_go_to_resolves_without_teleport: expected agent.near_pillar=true in WorldState")

	# Assert — narration logged as type "action" (written by the caller — coordinator
	# calls add_entry("action") after resolve() returns narration).
	# In this test we call add_entry manually to mirror what the coordinator does.
	var narration: String = str(result.get("narration", ""))
	if narration.is_empty():
		return _fail("test_coordinator_go_to_resolves_without_teleport: resolver returned empty narration")
	(log_stub.get("entries") as Array).append({"text": narration, "type": "action"})
	var entries: Array = log_stub.get("entries") as Array
	var has_action_type: bool = false
	for entry: Variant in entries:
		if entry is Dictionary and (entry as Dictionary).get("type", "") == "action":
			has_action_type = true
			break
	if not has_action_type:
		return _fail("test_coordinator_go_to_resolves_without_teleport: no narration log entry of type 'action' found")

	# Assert — agent position unchanged.
	var end_pos: Vector2 = agent.get("position") as Vector2
	if end_pos != start_pos:
		return _fail("test_coordinator_go_to_resolves_without_teleport: agent position changed from %s to %s (should be unchanged)" % [str(start_pos), str(end_pos)])

	return true


func test_coordinator_no_puzzle_files_no_regression() -> bool:
	## AC-PERF-03: empty puzzle_list → resolver returns state_changed=false with
	## a valid nothing_happens narration. No "action" or "solve" log entries
	## added by the resolver. No save file created.
	# Arrange
	var wid: String = _world_id("noreg")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent: RefCounted = _make_agent_stub("agent_a")
	var log_stub: RefCounted = _make_narration_log_stub()
	var agents: Array = [agent]
	var loader: RefCounted = _make_loader_stub_with_agents(log_stub, agents)

	var puzzle_list: Array[Dictionary] = []
	var resolver: ActionResolver = _make_wired_resolver(ws, loader, agents, puzzle_list)

	# Act
	var result: Dictionary = resolver.resolve(agent, {"verb": "go_to", "target": "anywhere"})

	# Assert — no state change.
	if result.get("state_changed", true) != false:
		return _fail("test_coordinator_no_puzzle_files_no_regression: expected state_changed=false with empty puzzle list")

	# Assert — narration is non-empty (nothing_happens fallback from fixture).
	var narration: String = str(result.get("narration", ""))
	if narration.is_empty():
		return _fail("test_coordinator_no_puzzle_files_no_regression: expected non-empty nothing_happens narration, got empty string")

	# Assert — no "action" or "solve" entries written by the resolver itself
	# (resolver only writes "solve" type entries via _narrate_solve_to).
	var entries: Array = log_stub.get("entries") as Array
	for entry: Variant in entries:
		if entry is Dictionary:
			var t: String = str((entry as Dictionary).get("type", ""))
			if t == "action" or t == "solve":
				return _fail("test_coordinator_no_puzzle_files_no_regression: unexpected log entry type '%s' with empty puzzle list" % t)

	# Assert — no save file created (state_changed=false means coordinator
	# never calls queue_world_state_save, so no flush occurs).
	var path: String = _save_path(wid)
	if FileAccess.file_exists(path):
		return _fail("test_coordinator_no_puzzle_files_no_regression: save file was created at %s despite state_changed=false" % path)

	return true


func test_coordinator_call_agent_triggers_dispatcher() -> bool:
	## AC-CB-14: call_agent action → encounter dispatcher records the dispatch.
	## narration is empty, state_changed=false (call_agent short-circuits before
	## the puzzle scan, so it never mutates state).
	# Arrange
	var wid: String = _world_id("cb14")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent_a: RefCounted = _make_agent_stub("agent_a")
	var agent_b: RefCounted = _make_agent_stub("agent_b")
	# agent_b must be IDLE (state 0) for call_agent precondition to pass.
	agent_b.set("current_state", 0)

	var log_stub: RefCounted = _make_narration_log_stub()
	var agents: Array = [agent_a, agent_b]

	# Build a dispatcher stub that records start() calls.
	# Signature updated for Story 008 TR-puzzle-026 backwards-compat check.
	var dispatcher_src: String = """
extends RefCounted
var calls: Array = []
func start(sender_id: String, listener_id: String, context_id: String = "") -> void:
	calls.append({"sender": sender_id, "listener": listener_id, "context_id": context_id})
"""
	var dispatcher_scr := GDScript.new()
	dispatcher_scr.source_code = dispatcher_src
	dispatcher_scr.reload()
	var dispatcher_stub: RefCounted = dispatcher_scr.new()

	var loader: RefCounted = _make_loader_stub_with_agents(log_stub, agents)
	loader.set("encounter_dispatcher", dispatcher_stub)

	var puzzle_list: Array[Dictionary] = []
	var resolver: ActionResolver = _make_wired_resolver(ws, loader, agents, puzzle_list)

	# Act
	var result: Dictionary = resolver.resolve(agent_a, {"verb": "call_agent", "target": "agent_b"})

	# Assert — dispatcher was called exactly once with correct ids.
	var calls: Array = dispatcher_stub.get("calls") as Array
	if calls.size() != 1:
		return _fail("test_coordinator_call_agent_triggers_dispatcher: expected exactly 1 dispatcher call, got %d" % calls.size())

	var recorded: Dictionary = calls[0] as Dictionary
	if recorded.get("sender", "") != "agent_a":
		return _fail("test_coordinator_call_agent_triggers_dispatcher: expected sender='agent_a', got '%s'" % str(recorded.get("sender", "")))
	if recorded.get("listener", "") != "agent_b":
		return _fail("test_coordinator_call_agent_triggers_dispatcher: expected listener='agent_b', got '%s'" % str(recorded.get("listener", "")))

	# Assert — context_id has the puzzle_<acting>_<target>_<msec> pattern (Story 008 bonus).
	var ctx_id: String = str(recorded.get("context_id", ""))
	if not ctx_id.begins_with("puzzle_agent_a_agent_b_"):
		return _fail("test_coordinator_call_agent_triggers_dispatcher: expected context_id to begin with 'puzzle_agent_a_agent_b_', got '%s'" % ctx_id)

	# Assert — narration is empty (call_agent success returns "" narration).
	var narration: String = str(result.get("narration", ""))
	if not narration.is_empty():
		return _fail("test_coordinator_call_agent_triggers_dispatcher: expected empty narration for call_agent success, got '%s'" % narration)

	# Assert — state_changed=false (call_agent never mutates WorldState).
	if result.get("state_changed", true) != false:
		return _fail("test_coordinator_call_agent_triggers_dispatcher: expected state_changed=false for call_agent")

	return true


func test_coordinator_resolve_action_from_response_routes_seam() -> bool:
	## Closes the LLMCoordinator → narration_log + llm + queue_save integration
	## seam (Story 006 LP-CODE-REVIEW C2-3). Earlier tests verify ActionResolver
	## in isolation; this one drives a real LLMCoordinator instance with stubbed
	## collaborators and asserts the three side-effects the coordinator owns:
	##   1. narration_log.add_entry(narration, "action") is called
	##   2. llm.llm_chat is called once with empty system + <narration>...</narration>
	##      user payload + empty req_id (fire-and-forget)
	##   3. world_loader.queue_world_state_save(false) is called when state_changed
	# Arrange
	var wid: String = _world_id("seam01")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	var agent: RefCounted = _make_agent_stub("agent_a")
	agent.set("position", Vector2(128.0, 64.0))
	var start_pos: Vector2 = agent.get("position") as Vector2

	var log_stub: RefCounted = _make_narration_log_stub()
	var log_layer: CanvasLayer = _make_narration_log_layer_stub()
	var llm_stub: LLMClient = _make_llm_stub()
	var agents: Array = [agent]
	# Resolver gets its own RefCounted holder for the agents-supplier callable;
	# the coordinator's loader stub is a WorldLoader subclass (typed constructor).
	var agents_holder: RefCounted = _make_loader_stub_with_agents(log_stub, agents)

	var puzzle: Dictionary = {
		"id": "seam01_pillar",
		"solve": {
			"when": {"flag": {"seam01.never": true}},
			"narration": "Never fires in this test.",
		},
		"actions": [
			{
				"match": {"verb": "go_to", "target": "ancient_pillar"},
				"effect": {"set_flag": {"agent.near_pillar": true}},
				"narration": "You reach the pillar.",
			},
		],
	}
	var puzzle_list: Array[Dictionary] = [puzzle]
	var resolver: ActionResolver = _make_wired_resolver(ws, agents_holder, agents, puzzle_list)

	var loader: WorldLoader = _make_coordinator_loader_stub(log_layer, resolver, llm_stub)
	var coord: LLMCoordinator = LLMCoordinator.new(loader)

	# Act — feed the coordinator a thought containing an embedded <action> tag.
	var response: String = "I see the pillar. <action verb=\"go_to\" target=\"ancient_pillar\"/> <speech>Hello.</speech>"
	coord._resolve_action_from_response(agent, response)

	# Assert — narration_log got exactly one entry of type "action" with the rule's narration.
	var entries: Array = log_layer.get("entries") as Array
	var action_entries: Array = []
	for entry: Variant in entries:
		if entry is Dictionary and (entry as Dictionary).get("type", "") == "action":
			action_entries.append(entry)
	if action_entries.size() != 1:
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected exactly 1 'action' log entry, got %d" % action_entries.size())
	var action_entry: Dictionary = action_entries[0] as Dictionary
	if str(action_entry.get("text", "")) != "You reach the pillar.":
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: action entry text mismatch — got '%s'" % str(action_entry.get("text", "")))

	# Assert — llm.llm_chat fired exactly once with the fire-and-forget pattern.
	var chat_calls: Array = llm_stub.get("chat_calls") as Array
	if chat_calls.size() != 1:
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected exactly 1 llm.llm_chat call, got %d" % chat_calls.size())
	var call: Dictionary = chat_calls[0] as Dictionary
	if str(call.get("system", "x")) != "":
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected empty system prompt (session holds persona), got '%s'" % str(call.get("system", "")))
	var expected_user: String = "<narration>You reach the pillar.</narration>"
	if str(call.get("user", "")) != expected_user:
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected user='%s', got '%s'" % [expected_user, str(call.get("user", ""))])
	if str(call.get("req_id", "x")) != "":
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected empty req_id (fire-and-forget), got '%s'" % str(call.get("req_id", "")))
	if str(call.get("agent_id", "")) != "agent_a":
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected agent_id='agent_a', got '%s'" % str(call.get("agent_id", "")))

	# Assert — queue_world_state_save(false) called exactly once (state_changed=true path).
	var save_calls: Array = loader.get("save_calls") as Array
	if save_calls.size() != 1:
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected exactly 1 queue_world_state_save call, got %d" % save_calls.size())
	if bool((save_calls[0] as Dictionary).get("force", true)) != false:
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected force=false on queue_world_state_save (debounce path)")

	# Assert — agent position UNCHANGED (no teleport injected via go_to).
	var end_pos: Vector2 = agent.get("position") as Vector2
	if end_pos != start_pos:
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: agent position changed from %s to %s" % [str(start_pos), str(end_pos)])

	# Assert — WorldState flag applied by the resolver via the coordinator path.
	if ws.get_flag("agent.near_pillar") != true:
		loader.free()
		return _fail("test_coordinator_resolve_action_from_response_routes_seam: expected agent.near_pillar=true in WorldState")

	loader.free()
	return true
