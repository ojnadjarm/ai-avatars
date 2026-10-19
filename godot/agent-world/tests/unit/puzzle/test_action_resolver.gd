class_name TestActionResolver
extends RefCounted
## Unit tests for ActionResolver (Story 002).
## Covers every acceptance criterion in
## production/epics/agent-puzzle-layer/story-002-action-resolver.md.
##
## Each sub-test that touches WorldState uses a unique world_id so concurrent
## runs cannot collide. Save files are cleaned up at the end of run().

const SAVES_DIR := "user://saves/"

## Hermetic agent fixture — mirrors test_world_state.gd so both suites use the
## same agent shapes. luna has "astronomy" for use_skill tests.
const FIXTURE_AGENTS: Dictionary = {
	"darksaddler": {
		"display_name": "DarkSaddler",
		"skills": [],
		"starting_inventory": ["star_medallion"],
	},
	"luna": {
		"display_name": "Luna",
		"skills": ["astronomy"],
		"starting_inventory": [],
	},
	"grok": {
		"display_name": "Grok",
	},
}

## Full puzzle defaults block. The user://game_config.json override may shadow
## res://game_config.json and be missing the puzzle block entirely — install
## this hermetically so the resolver's nothing-happens chain resolves correctly
## regardless of the user's on-disk override state.
const FIXTURE_PUZZLE_DEFAULTS: Dictionary = {
	"nothing_happens": {
		"go_to": "Your feet carry you toward it, but the world does not shift.",
		"take": "Your hand closes on nothing that the world would yield.",
		"use_object": "You press it against the thing before you. Nothing stirs.",
		"use_skill": "You bring what you know to bear. The world does not respond.",
		"call_agent": "The name does not carry. No one turns.",
	},
	"nothing_happens_text": "The world holds its shape. Nothing yields.",
}

var failure_message: String = ""
var _test_world_ids: Array[String] = []
var _saved_agents: Dictionary = {}
var _saved_puzzle_defaults: Variant = null
var _had_puzzle_defaults: bool = false


func run() -> bool:
	_install_fixture_agents()
	_install_puzzle_defaults()

	# --- extract_action ---
	if not _test_ac_cb_08_extract_full_tag():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_ac_cb_08_trims_whitespace():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_ac_cb_08_malformed_returns_empty():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_ac_cb_09_first_action_wins():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_absent_on_attribute_no_key():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- nothing-happens fallback chain ---
	if not _test_ac_cb_10a_world_override_returned():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_ac_cb_10b_global_fallback_returned():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_ac_cb_10c_unknown_verb_no_error():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- structural preconditions ---
	if not _test_ac_cb_11_use_object_without_item():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_ac_cb_12_use_skill_without_skill():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_ac_cb_21_valid_preconditions_no_rule():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- effect application ---
	if not _test_ac_cb_13_effect_application_atomic():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- call_agent gate-false path ---
	if not _test_call_agent_gate_false():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- R21 path (b): encounter_complete collaborator credit (AC-FE-07) ---
	if not _test_on_encounter_complete_credits_invited_collaborator():
		_restore_puzzle_defaults()
		_restore_agents()
		return false
	if not _test_on_encounter_complete_ignores_ambient_solved_and_uninvolved():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- require-fail tier-1 (default_fail_narration) ---
	if not _test_require_fail_uses_default_fail_narration():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- call_agent success dispatch ---
	if not _test_call_agent_success_dispatches_encounter():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	# --- take_item effect coverage ---
	if not _test_apply_effects_take_item():
		_restore_puzzle_defaults()
		_restore_agents()
		return false

	_cleanup()
	_restore_puzzle_defaults()
	_restore_agents()
	return true


func _install_fixture_agents() -> void:
	_saved_agents = GameState.agents
	GameState.agents = FIXTURE_AGENTS.duplicate(true)


func _restore_agents() -> void:
	GameState.agents = _saved_agents
	# Always remove any save files this run produced — guarantees cleanup even
	# on failure paths that don't route through _fail().
	_cleanup()


func _install_puzzle_defaults() -> void:
	_had_puzzle_defaults = GameState.defaults.has("puzzle")
	if _had_puzzle_defaults:
		_saved_puzzle_defaults = GameState.defaults["puzzle"]
	GameState.defaults["puzzle"] = FIXTURE_PUZZLE_DEFAULTS.duplicate(true)


func _restore_puzzle_defaults() -> void:
	if _had_puzzle_defaults:
		GameState.defaults["puzzle"] = _saved_puzzle_defaults
	else:
		GameState.defaults.erase("puzzle")


# ── Helpers ───────────────────────────────────────────────────────────────

func _world_id(suffix: String) -> String:
	var wid := "test_ar_" + suffix
	_test_world_ids.append(wid)
	return wid


func _save_path(wid: String) -> String:
	return SAVES_DIR + "world_state_" + wid + ".json"


func _remove_if_exists(wid: String) -> void:
	var path := _save_path(wid)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _fail(msg: String) -> bool:
	failure_message = msg
	_cleanup()
	return false


func _cleanup() -> void:
	for wid: String in _test_world_ids:
		_remove_if_exists(wid)


## Build a minimal Agent-like RefCounted that ActionResolver accepts.
## ActionResolver only reads agent.agent_id and agent.current_state.
func _make_agent(agent_id: String, state: int = Agent.State.IDLE) -> RefCounted:
	var a := RefCounted.new()
	a.set_meta("agent_id", agent_id)
	a.set_meta("current_state", state)
	# Expose the properties via a script that adds them.
	# Since we cannot easily subclass Agent (CharacterBody2D) in a headless
	# unit test, we build a duck-typed object using a locally compiled script.
	var src := """
extends RefCounted
var agent_id: String = \"\"
var current_state: int = 0
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var stub: RefCounted = scr.new()
	stub.set("agent_id", agent_id)
	stub.set("current_state", state)
	return stub


## Build a minimal ActivityGate stub whose can_trigger() returns a fixed value.
func _make_gate_stub(can: bool) -> RefCounted:
	var src: String = """
extends RefCounted
var _can: bool = false
func can_trigger() -> bool:
	return _can
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var gate: RefCounted = scr.new()
	gate.set("_can", can)
	return gate


## Build a minimal world_loader stub for call_agent tests. Exposes:
##   activity_gate  — a gate stub
##   find_agent()  — returns null (no agents available by default)
##   encounter_dispatcher.start() — records calls
func _make_loader_stub(gate_can_trigger: bool) -> RefCounted:
	var gate: RefCounted = _make_gate_stub(gate_can_trigger)
	var src: String = """
extends RefCounted
var activity_gate: RefCounted = null
var _started: bool = false
func find_agent(_id: String) -> Object:
	return null
func can_trigger_activity() -> bool:
	return activity_gate != null and activity_gate.can_trigger()
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var loader: RefCounted = scr.new()
	loader.set("activity_gate", gate)
	return loader


## TD-004 — shared stub factory: minimal target-agent stub ("grok") in the
## given state (0 == IDLE) for call_agent precondition/dispatch tests.
func _make_target_agent_stub(state: int = 0) -> RefCounted:
	var src: String = """
extends RefCounted
var agent_id: String = \"grok\"
var current_state: int = 0
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var stub: RefCounted = scr.new()
	stub.set("current_state", state)
	return stub


## TD-004 — shared stub factory: dispatcher stub recording start() calls
## (3-arg Story 008 signature, context_id captured).
func _make_dispatcher_stub() -> RefCounted:
	var src: String = """
extends RefCounted
var last_sender: String = \"\"
var last_listener: String = \"\"
var last_context_id: String = \"\"
var call_count: int = 0
func start(sender_id: String, listener_id: String, context_id: String = \"\") -> void:
	last_sender = sender_id
	last_listener = listener_id
	last_context_id = context_id
	call_count += 1
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	return scr.new()


## TD-004 — shared stub factory: full loader stub wiring gate + dispatcher +
## find_agent("grok" → target_stub) + both facade methods the resolver
## guards on (request_agent_encounter, can_trigger_activity).
func _make_full_loader_stub(gate_can_trigger: bool, target_stub: RefCounted, dispatcher_stub: RefCounted) -> RefCounted:
	var gate: RefCounted = _make_gate_stub(gate_can_trigger)
	var src: String = """
extends RefCounted
var activity_gate: RefCounted = null
var encounter_dispatcher: RefCounted = null
var _target: RefCounted = null
func find_agent(id: String) -> RefCounted:
	if id == \"grok\":
		return _target
	return null
func request_agent_encounter(sender_id: String, listener_id: String, context_id: String = \"\") -> void:
	if encounter_dispatcher != null:
		encounter_dispatcher.start(sender_id, listener_id, context_id)
func can_trigger_activity() -> bool:
	return activity_gate != null and activity_gate.can_trigger()
"""
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	var loader: RefCounted = scr.new()
	loader.set("activity_gate", gate)
	loader.set("encounter_dispatcher", dispatcher_stub)
	loader.set("_target", target_stub)
	return loader


# ── Tests: extract_action ─────────────────────────────────────────────────

func _test_ac_cb_08_extract_full_tag() -> bool:
	## AC-CB-08: full tag parses all three attributes correctly.
	# Arrange
	var input := "<action verb=\"use_object\" target=\"star_medallion\" on=\"ancient_pillar\"/>"

	# Act
	var result: Dictionary = ActionResolver.extract_action(input)

	# Assert
	if result.get("verb", "") != "use_object":
		return _fail("AC-CB-08: verb expected 'use_object', got '%s'" % result.get("verb", ""))
	if result.get("target", "") != "star_medallion":
		return _fail("AC-CB-08: target expected 'star_medallion', got '%s'" % result.get("target", ""))
	if result.get("on", "") != "ancient_pillar":
		return _fail("AC-CB-08: on expected 'ancient_pillar', got '%s'" % result.get("on", ""))
	return true


func _test_ac_cb_08_trims_whitespace() -> bool:
	## Attributes with extra internal whitespace are trimmed.
	# Arrange
	var input := "<action verb=\"  go_to  \" target=\"  pillar  \"/>"

	# Act
	var result: Dictionary = ActionResolver.extract_action(input)

	# Assert
	if result.get("verb", "") != "go_to":
		return _fail("trim: verb expected 'go_to', got '%s'" % result.get("verb", ""))
	if result.get("target", "") != "pillar":
		return _fail("trim: target expected 'pillar', got '%s'" % result.get("target", ""))
	return true


func _test_ac_cb_08_malformed_returns_empty() -> bool:
	## Malformed tags (unclosed, missing attributes) return {}.
	# Arrange / Act / Assert
	if not ActionResolver.extract_action("").is_empty():
		return _fail("malformed: empty string should return {}")
	if not ActionResolver.extract_action("no action here").is_empty():
		return _fail("malformed: no tag should return {}")
	if not ActionResolver.extract_action("<action verb=\"go_to\"/>").is_empty():
		return _fail("malformed: missing target should return {}")
	if not ActionResolver.extract_action("<action target=\"x\"/>").is_empty():
		return _fail("malformed: missing verb should return {}")
	# Unclosed tag
	if not ActionResolver.extract_action("<action verb=\"go_to\" target=\"x\"").is_empty():
		return _fail("malformed: unclosed tag should return {}")
	return true


func _test_ac_cb_09_first_action_wins() -> bool:
	## AC-CB-09: only the first <action> element is returned.
	# Arrange
	var input := "<action verb=\"go_to\" target=\"pillar\"/> ... <action verb=\"take\" target=\"coin\"/>"

	# Act
	var result: Dictionary = ActionResolver.extract_action(input)

	# Assert
	if result.get("verb", "") != "go_to":
		return _fail("AC-CB-09: expected first verb 'go_to', got '%s'" % result.get("verb", ""))
	if result.get("target", "") != "pillar":
		return _fail("AC-CB-09: expected first target 'pillar', got '%s'" % result.get("target", ""))
	return true


func _test_absent_on_attribute_no_key() -> bool:
	## When the `on` attribute is absent the returned dict has no "on" key.
	# Arrange
	var input := "<action verb=\"go_to\" target=\"pillar\"/>"

	# Act
	var result: Dictionary = ActionResolver.extract_action(input)

	# Assert
	if result.has("on"):
		return _fail("absent on: dict should not have 'on' key, got: %s" % str(result))
	return true


# ── Tests: nothing-happens fallback chain ─────────────────────────────────

func _test_ac_cb_10a_world_override_returned() -> bool:
	## AC-CB-10a: unknown verb returns world-level nothing_happens_text when set.
	# Arrange
	var wid := _world_id("10a")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	var world_text := "The world ignores you."
	var resolver := ActionResolver.new(ws, null, [], world_text)
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "summon", "target": "dragon"}

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert
	if result.get("narration", "") != world_text:
		return _fail("AC-CB-10a: expected world override narration '%s', got '%s'" % [world_text, result.get("narration", "")])
	if result.get("state_changed", true) != false:
		return _fail("AC-CB-10a: state_changed should be false")
	return true


func _test_ac_cb_10b_global_fallback_returned() -> bool:
	## AC-CB-10b: unknown verb, no world override → global defaults.puzzle.nothing_happens_text.
	## Install a temporary puzzle.nothing_happens_text default; the user:// config
	## override may shadow res://game_config.json so we cannot rely on the shipped value.
	# Arrange
	var expected: String = "The world holds its shape. Nothing yields."
	var puzzle_defaults: Dictionary = GameState.defaults.get("puzzle", {}) as Dictionary
	var saved_text: Variant = puzzle_defaults.get("nothing_happens_text", null)
	puzzle_defaults["nothing_happens_text"] = expected
	GameState.defaults["puzzle"] = puzzle_defaults

	var wid := _world_id("10b")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	var resolver := ActionResolver.new(ws, null, [], "")
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "summon", "target": "dragon"}

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Restore before asserting so a failure cannot leak state to later tests.
	if saved_text == null:
		puzzle_defaults.erase("nothing_happens_text")
	else:
		puzzle_defaults["nothing_happens_text"] = saved_text

	# Assert
	if result.get("narration", "") != expected:
		return _fail("AC-CB-10b: expected global fallback '%s', got '%s'" % [expected, result.get("narration", "")])
	if result.get("state_changed", true) != false:
		return _fail("AC-CB-10b: state_changed should be false")
	return true


func _test_ac_cb_10c_unknown_verb_no_error() -> bool:
	## AC-CB-10c: unknown verb produces no push_error, no exception.
	## We verify this indirectly: if the call returns without crashing and
	## returns a valid dict, the requirement is satisfied. The test harness
	## would surface any unhandled exception as a script error.
	# Arrange
	var wid := _world_id("10c")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	var resolver := ActionResolver.new(ws, null, [], "")
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "summon", "target": "dragon"}

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert — just confirm it returned a sane dict
	if not result.has("narration"):
		return _fail("AC-CB-10c: result missing 'narration' key")
	if not result.has("state_changed"):
		return _fail("AC-CB-10c: result missing 'state_changed' key")
	return true


# ── Tests: structural preconditions ───────────────────────────────────────

func _test_ac_cb_11_use_object_without_item() -> bool:
	## AC-CB-11: use_object when agent lacks the item → state_changed == false,
	## WorldState unmodified.
	# Arrange
	var wid := _world_id("11")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	# luna has no items in fixture (starting_inventory: [])
	var resolver := ActionResolver.new(ws, null, [], "")
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "use_object", "target": "missing_key", "on": "door"}

	var flag_count_before: int = ws.flags.size()
	var inv_count_before: int = ws.inventory.size()
	var obj_count_before: int = ws.objects.size()

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert
	if result.get("state_changed", true) != false:
		return _fail("AC-CB-11: state_changed should be false when item missing")
	if ws.flags.size() != flag_count_before:
		return _fail("AC-CB-11: flags count changed after precondition failure")
	if ws.objects.size() != obj_count_before:
		return _fail("AC-CB-11: objects count changed after precondition failure")
	return true


func _test_ac_cb_12_use_skill_without_skill() -> bool:
	## AC-CB-12: use_skill when agent lacks the skill → state_changed == false.
	# Arrange
	var wid := _world_id("12")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	# darksaddler has skills: [] in fixture
	var resolver := ActionResolver.new(ws, null, [], "")
	var agent: RefCounted = _make_agent("darksaddler")
	var action: Dictionary = {"verb": "use_skill", "target": "astronomy", "on": "ancient_pillar"}

	var flag_count_before: int = ws.flags.size()
	var obj_count_before: int = ws.objects.size()

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert
	if result.get("state_changed", true) != false:
		return _fail("AC-CB-12: state_changed should be false when skill missing")
	if ws.flags.size() != flag_count_before:
		return _fail("AC-CB-12: flags changed after skill precondition failure")
	if ws.objects.size() != obj_count_before:
		return _fail("AC-CB-12: objects changed after skill precondition failure")
	return true


func _test_ac_cb_21_valid_preconditions_no_rule() -> bool:
	## AC-CB-21: agent has required skill, syntactically valid action, no
	## matching puzzle rule → state_changed == false, per-verb narration returned.
	# Arrange
	var wid := _world_id("21")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	# luna has astronomy skill in fixture
	var resolver := ActionResolver.new(ws, null, [], "")
	var agent: RefCounted = _make_agent("luna")
	# use_skill with target=astronomy, on=unrelated_pillar — preconditions pass
	# but empty puzzle_list means no rule matches.
	var action: Dictionary = {"verb": "use_skill", "target": "astronomy", "on": "unrelated_pillar"}

	var flag_count_before: int = ws.flags.size()
	var obj_count_before: int = ws.objects.size()

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert
	if result.get("state_changed", true) != false:
		return _fail("AC-CB-21: state_changed should be false with no matching rule")
	var narration: String = result.get("narration", "")
	if narration.is_empty():
		return _fail("AC-CB-21: narration should be non-empty (per-verb nothing-happens)")
	if ws.flags.size() != flag_count_before:
		return _fail("AC-CB-21: flags changed with no matching rule")
	if ws.objects.size() != obj_count_before:
		return _fail("AC-CB-21: objects changed with no matching rule")
	return true


# ── Tests: effect application ─────────────────────────────────────────────

func _test_ac_cb_13_effect_application_atomic() -> bool:
	## AC-CB-13: all declared state deltas applied when rule matches and
	## require predicate is satisfied.
	# Arrange
	var wid := _world_id("13")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	# luna has astronomy skill in fixture

	# Pre-seed the required flag so the predicate passes.
	ws.set_flag("pillar.approach_permitted", true)

	# Build an in-memory puzzle with one rule.
	var puzzle: Dictionary = {
		"puzzle_id": "test_puzzle",
		"default_fail_narration": "The carvings do not respond.",
		"actions": [
			{
				"match": {
					"verb": "use_skill",
					"target": "astronomy",
					"on": "ancient_pillar",
				},
				"require": {
					"flag": {"pillar.approach_permitted": true},
				},
				"effect": {
					"set_flag": {"pillar.prayer_read": true},
					"set_object": {"ancient_pillar.illuminated": true},
					"give_item": "star_chart",
				},
				"narration": "The carvings illuminate briefly, then fade.",
			},
		],
	}
	var puzzle_list: Array[Dictionary] = [puzzle]
	var resolver := ActionResolver.new(ws, null, puzzle_list, "")
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "use_skill", "target": "astronomy", "on": "ancient_pillar"}

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert — result shape
	if result.get("state_changed", false) != true:
		return _fail("AC-CB-13: state_changed should be true")
	if result.get("narration", "") != "The carvings illuminate briefly, then fade.":
		return _fail("AC-CB-13: narration mismatch, got '%s'" % result.get("narration", ""))

	# Assert — set_flag applied
	if ws.get_flag("pillar.prayer_read") != true:
		return _fail("AC-CB-13: set_flag pillar.prayer_read not applied")
	# set_flag_with_writer must stamp the agent
	if ws.flag_writers.get("pillar.prayer_read", "") != "luna":
		return _fail("AC-CB-13: flag_writers not stamped for luna")

	# Assert — set_object applied
	var pillar_obj: Dictionary = ws.get_object("ancient_pillar")
	if pillar_obj.get("illuminated", false) != true:
		return _fail("AC-CB-13: set_object ancient_pillar.illuminated not applied")

	# Assert — give_item applied
	if not ws.agent_has_item("luna", "star_chart"):
		return _fail("AC-CB-13: give_item star_chart not applied")

	return true


# ── Tests: call_agent gate-false path ─────────────────────────────────────

func _test_call_agent_gate_false() -> bool:
	## call_agent: when the loader's can_trigger_activity() facade returns
	## false, nothing-happens narration is returned and state_changed is false.
	# Arrange — gate locked; idle target so preconditions pass and the gate
	# branch is the actual failure cause (TD-004 shared stub factories).
	var wid := _world_id("cagf")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	var dispatcher_stub: RefCounted = _make_dispatcher_stub()
	var loader_stub: RefCounted = _make_full_loader_stub(false, _make_target_agent_stub(), dispatcher_stub)

	var resolver := ActionResolver.new(ws, loader_stub, [], "")
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "call_agent", "target": "grok"}

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert
	if result.get("state_changed", true) != false:
		return _fail("call_agent gate-false: state_changed should be false")
	var narration: String = result.get("narration", "")
	if narration.is_empty():
		return _fail("call_agent gate-false: narration should be non-empty nothing-happens")
	if int(dispatcher_stub.get("call_count")) != 0:
		return _fail("call_agent gate-false: dispatcher must not be called when the gate is locked")
	return true


# ── Tests: require-fail → default_fail_narration (nothing-happens tier 1) ────

func _test_require_fail_uses_default_fail_narration() -> bool:
	## When a rule matches but its require predicate returns false, the
	## puzzle's default_fail_narration is returned as the narration (tier 1
	## of the nothing-happens chain), with state_changed == false and no
	## WorldState mutation.
	# Arrange
	var wid := _world_id("require_fail")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	# Do NOT pre-seed the required flag — predicate will fail.

	var puzzle: Dictionary = {
		"puzzle_id": "test_puzzle",
		"default_fail_narration": "The carvings hold their silence.",
		"actions": [
			{
				"match": {
					"verb": "use_skill",
					"target": "astronomy",
					"on": "ancient_pillar",
				},
				"require": {
					"flag": {"pillar.approach_permitted": true},
				},
				"effect": {
					"set_flag": {"pillar.prayer_read": true},
				},
				"narration": "The carvings illuminate briefly, then fade.",
			},
		],
	}
	var puzzle_list: Array[Dictionary] = [puzzle]
	var resolver := ActionResolver.new(ws, null, puzzle_list, "")
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "use_skill", "target": "astronomy", "on": "ancient_pillar"}

	var flag_count_before: int = ws.flags.size()

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert
	if result.get("state_changed", true) != false:
		return _fail("require-fail: state_changed should be false")
	if result.get("narration", "") != "The carvings hold their silence.":
		return _fail("require-fail: expected default_fail_narration, got '%s'" % result.get("narration", ""))
	# WorldState must not have been mutated.
	if ws.flags.size() != flag_count_before:
		return _fail("require-fail: flags dict was mutated (size changed)")
	if ws.get_flag("pillar.prayer_read") != null:
		return _fail("require-fail: pillar.prayer_read was written despite require failure")
	return true


# ── Tests: call_agent success dispatch ────────────────────────────────────

func _test_call_agent_success_dispatches_encounter() -> bool:
	## call_agent: when activity_gate.can_trigger() returns true and the
	## target agent is idle, encounter_dispatcher.start is called with the
	## correct sender/listener and resolve returns {"", false}.
	# Arrange
	var wid := _world_id("cas")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# TD-004 shared stub factories: open gate, idle target, recording
	# dispatcher behind the request_agent_encounter facade (Story 008 routing).
	var dispatcher_stub: RefCounted = _make_dispatcher_stub()
	var loader_stub: RefCounted = _make_full_loader_stub(true, _make_target_agent_stub(), dispatcher_stub)

	var resolver := ActionResolver.new(ws, loader_stub, [], "")
	var agent: RefCounted = _make_agent("luna")
	var action: Dictionary = {"verb": "call_agent", "target": "grok"}

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert — result shape
	if result.get("state_changed", true) != false:
		return _fail("call_agent success: state_changed should be false")
	if result.get("narration", "NOT_EMPTY") != "":
		return _fail("call_agent success: narration should be empty string (encounter owns narration)")
	# Assert — dispatcher was called with correct args
	if int(dispatcher_stub.get("call_count")) != 1:
		return _fail("call_agent success: dispatcher.start should be called exactly once")
	if str(dispatcher_stub.get("last_sender")) != "luna":
		return _fail("call_agent success: sender should be 'luna', got '%s'" % dispatcher_stub.get("last_sender"))
	if str(dispatcher_stub.get("last_listener")) != "grok":
		return _fail("call_agent success: listener should be 'grok', got '%s'" % dispatcher_stub.get("last_listener"))
	if not str(dispatcher_stub.get("last_context_id")).begins_with(ActionResolver.CALL_AGENT_CONTEXT_PREFIX):
		return _fail("call_agent success: context_id should carry the puzzle prefix, got '%s'" % dispatcher_stub.get("last_context_id"))
	return true


# ── Tests: R21 path (b) — encounter_complete collaborator credit ──────────

func _test_on_encounter_complete_credits_invited_collaborator() -> bool:
	## AC-FE-07 / R21 path (b): a completed call_agent encounter (context_id
	## carries CALL_AGENT_CONTEXT_PREFIX) adds the invited listener to every
	## unsolved puzzle whose collaborators already contain the caller — and
	## only those.
	# Arrange — caller "luna" involved in inv_puzzle only.
	var wid := _world_id("fe07")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	var puzzles: Array[Dictionary] = [
		{"id": "inv_puzzle", "actions": []},
		{"id": "other_puzzle", "actions": []},
	]
	ws.add_collaborator("inv_puzzle", "luna")
	var resolver := ActionResolver.new(ws, null, puzzles, "")

	# Act
	var ctx: String = ActionResolver.CALL_AGENT_CONTEXT_PREFIX + "luna_grok_1"
	var changed: bool = resolver.on_encounter_complete("luna", "grok", ctx)

	# Assert
	if not changed:
		return _fail("AC-FE-07: on_encounter_complete should report a change")
	if not ws.get_puzzle_collaborators("inv_puzzle").has("grok"):
		return _fail("AC-FE-07: invited listener should join inv_puzzle collaborators")
	if ws.get_puzzle_collaborators("other_puzzle").has("grok"):
		return _fail("AC-FE-07: listener must NOT join a puzzle the caller is not involved in")
	return true


func _test_on_encounter_complete_ignores_ambient_solved_and_uninvolved() -> bool:
	## AC-FE-07 negative space: ambient encounters (context_id == ""), solved
	## puzzles, and callers not already in a collaborators set never add
	## membership.
	# Arrange — luna collaborator on a puzzle that is already SOLVED.
	var wid := _world_id("fe07n")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	var puzzles: Array[Dictionary] = [
		{"id": "p_solved", "actions": []},
		{"id": "p_open", "actions": []},
	]
	ws.add_collaborator("p_solved", "luna")
	ws.set_puzzle_state("p_solved", 2)
	ws.latch_puzzle_fired("p_solved")
	var resolver := ActionResolver.new(ws, null, puzzles, "")
	var ctx: String = ActionResolver.CALL_AGENT_CONTEXT_PREFIX + "x_y_2"

	# Act + Assert — ambient/proximity encounter: no membership propagation.
	if resolver.on_encounter_complete("luna", "grok", ""):
		return _fail("AC-FE-07: ambient encounter (empty context_id) must not change collaborators")
	# Act + Assert — solved puzzle: skipped even with the caller in its set.
	if resolver.on_encounter_complete("luna", "grok", ctx):
		return _fail("AC-FE-07: solved puzzle must not accept new collaborators")
	if ws.get_puzzle_collaborators("p_solved").has("grok"):
		return _fail("AC-FE-07: listener leaked into a solved puzzle's collaborators")
	# Act + Assert — caller uninvolved anywhere: nothing to join.
	if resolver.on_encounter_complete("darksaddler", "grok", ctx):
		return _fail("AC-FE-07: uninvolved caller must not create membership")
	return true


# ── Tests: take_item effect coverage ──────────────────────────────────────

func _test_apply_effects_take_item() -> bool:
	## AC-CB-13 coverage extension: take_item effect removes the item from
	## the acting agent's inventory when the rule matches.
	# Arrange
	var wid := _world_id("take_item")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	# darksaddler starts with star_medallion (fixture) — verify precondition.
	if not ws.agent_has_item("darksaddler", "star_medallion"):
		return _fail("take_item: fixture precondition — darksaddler must start with star_medallion")

	var puzzle: Dictionary = {
		"puzzle_id": "test_take",
		"actions": [
			{
				"match": {
					"verb": "use_object",
					"target": "star_medallion",
					"on": "altar",
				},
				"effect": {
					"take_item": "star_medallion",
					"set_flag": {"altar.offering_made": true},
				},
				"narration": "The medallion settles into the hollow and will not come free.",
			},
		],
	}
	var puzzle_list: Array[Dictionary] = [puzzle]
	var resolver := ActionResolver.new(ws, null, puzzle_list, "")
	var agent: RefCounted = _make_agent("darksaddler")
	var action: Dictionary = {"verb": "use_object", "target": "star_medallion", "on": "altar"}

	# Act
	var result: Dictionary = resolver.resolve(agent, action)

	# Assert — result shape
	if result.get("state_changed", false) != true:
		return _fail("take_item: state_changed should be true")
	# Assert — item removed from inventory
	if ws.agent_has_item("darksaddler", "star_medallion"):
		return _fail("take_item: star_medallion should have been removed from darksaddler")
	# Assert — sibling effect still applied
	if ws.get_flag("altar.offering_made") != true:
		return _fail("take_item: sibling set_flag altar.offering_made not applied")
	return true
