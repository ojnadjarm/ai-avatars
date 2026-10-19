class_name TestPropLayers
extends RefCounted
## Unit tests for PropLayers (Story 005).
## Covers every acceptance criterion in
## production/epics/agent-puzzle-layer/story-005-prop-layers.md.
##
## Hermetic fixture pattern: agents are installed via FIXTURE_AGENTS before each
## sub-test and restored afterwards — matches test_world_state.gd scaffolding so
## tests pass regardless of the user:// config override state.
##
## Agent instances are created with Agent.new() off-tree. WorldState instances
## are created with WorldState.load_for() using unique test world IDs, all cleaned
## up in _cleanup().

const SAVES_DIR := "user://saves/"

## Luna has ancient_tongues + astronomy (matching story-005 AC-CB-05 fixture).
## DarkSaddler has star_medallion in starting_inventory.
## No-skill agent has neither skills nor inventory.
const FIXTURE_AGENTS: Dictionary = {
	"luna": {
		"display_name": "Luna",
		"skills": ["ancient_tongues", "astronomy"],
		"starting_inventory": [],
	},
	"darksaddler": {
		"display_name": "DarkSaddler",
		"skills": [],
		"starting_inventory": ["star_medallion"],
	},
	"no_skill_agent": {
		"display_name": "NoSkill",
		"skills": [],
		"starting_inventory": [],
	},
}

var failure_message: String = ""
var _test_world_ids: Array[String] = []
var _test_agents: Array[Agent] = []
var _saved_agents: Dictionary = {}


func run() -> bool:
	_install_fixture_agents()
	if not _test_ac_cb_04_base_only_when_no_gates_pass():
		_restore_agents()
		return false
	if not _test_ac_cb_05_skill_gated_layer_included():
		_restore_agents()
		return false
	if not _test_ac_cb_05_both_skills_both_layers():
		_restore_agents()
		return false
	if not _test_ac_cb_06_item_gated_layer_included():
		_restore_agents()
		return false
	if not _test_ac_cb_06_item_absent_layer_excluded():
		_restore_agents()
		return false
	if not _test_ac_cb_07_flag_gate_absent_then_present():
		_restore_agents()
		return false
	if not _test_ac_cb_07b_item_acquired_mid_session():
		_restore_agents()
		return false
	if not _test_ac_cb_07d_empty_prop_returns_fallback():
		_restore_agents()
		return false
	if not _test_r7c_unknown_gate_kind_evaluates_false():
		_restore_agents()
		return false
	_cleanup()
	_restore_agents()
	return true


# ── Fixtures ──────────────────────────────────────────────────────────────

func _install_fixture_agents() -> void:
	_saved_agents = GameState.agents
	GameState.agents = FIXTURE_AGENTS.duplicate(true)


func _restore_agents() -> void:
	GameState.agents = _saved_agents


## Build an off-tree Agent with the given agent_id set.
## Tracked in _test_agents so _cleanup() can free() them — Agent extends
## CharacterBody2D (Node), which uses manual memory management. Without
## explicit free() the orphan nodes accumulate as ObjectDB leaks on shutdown.
func _make_agent(p_agent_id: String) -> Agent:
	var a: Agent = Agent.new()
	a.agent_id = p_agent_id
	_test_agents.append(a)
	return a


func _world_id(suffix: String) -> String:
	var wid: String = "test_pl_" + suffix
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
	for a: Agent in _test_agents:
		if is_instance_valid(a):
			a.free()
	_test_agents.clear()


# ── Tests ─────────────────────────────────────────────────────────────────

func _test_ac_cb_04_base_only_when_no_gates_pass() -> bool:
	## AC-CB-04: agent with no matching skills/items/flags sees only base description.
	# Arrange
	var wid: String = _world_id("cb04")
	_remove_if_exists(wid)
	var prop: Dictionary = {
		"id": "pillar",
		"description": "A stone pillar.",
		"layers": [
			{"gate": {"kind": "skill", "id": "astronomy"}, "text": "A pattern of dots..."},
			{"gate": {"kind": "item", "id": "star_medallion"}, "text": "The medallion resonates."},
			{"gate": {"kind": "flag", "id": "altar.lit"}, "text": "The altar glow intensifies."},
		],
	}
	var agent: Agent = _make_agent("no_skill_agent")
	var ws: WorldState = WorldState.load_for(wid)

	# Act
	var result: String = PropLayers.render_for_agent(prop, agent, ws)

	# Assert
	if result != "A stone pillar.":
		return _fail("AC-CB-04: expected 'A stone pillar.' exactly, got '%s'" % result)

	# Edge: prop with no layers array at all
	var prop_no_layers: Dictionary = {"id": "rock", "description": "A mossy rock."}
	var result2: String = PropLayers.render_for_agent(prop_no_layers, agent, ws)
	if result2 != "A mossy rock.":
		return _fail("AC-CB-04 (no layers key): expected 'A mossy rock.', got '%s'" % result2)

	return true


func _test_ac_cb_05_skill_gated_layer_included() -> bool:
	## AC-CB-05: agent with ancient_tongues sees that layer; without astronomy, that layer absent.
	# Arrange
	var wid: String = _world_id("cb05")
	_remove_if_exists(wid)
	var prop: Dictionary = {
		"id": "pillar",
		"description": "A stone pillar.",
		"layers": [
			{"gate": {"kind": "skill", "id": "ancient_tongues"}, "text": "The carvings spell a warning."},
			{"gate": {"kind": "skill", "id": "astronomy"}, "text": "A pattern of dots mirrors the sky."},
		],
	}
	# luna has ancient_tongues + astronomy; we test with no_skill_agent first, then luna
	var agent_none: Agent = _make_agent("no_skill_agent")
	var agent_luna: Agent = _make_agent("luna")
	var ws: WorldState = WorldState.load_for(wid)

	# Act — agent with no skills
	var result_none: String = PropLayers.render_for_agent(prop, agent_none, ws)

	# Assert — no layers
	if result_none != "A stone pillar.":
		return _fail("AC-CB-05 (no skills): expected base only, got '%s'" % result_none)

	# Act — luna has both skills but we test ancient_tongues presence specifically
	# Temporarily restrict luna to ancient_tongues only to match the story fixture
	var saved_luna: Dictionary = GameState.agents["luna"].duplicate(true)
	(GameState.agents["luna"] as Dictionary)["skills"] = ["ancient_tongues"]
	var result_luna_one: String = PropLayers.render_for_agent(prop, agent_luna, ws)
	GameState.agents["luna"] = saved_luna

	# Assert — ancient_tongues layer present, astronomy layer absent
	var expected_one: String = "A stone pillar.\n\nThe carvings spell a warning."
	if result_luna_one != expected_one:
		return _fail("AC-CB-05 (ancient_tongues only): expected '%s', got '%s'" % [expected_one, result_luna_one])

	# Edge: whitespace-only text must be skipped
	var prop_ws: Dictionary = {
		"id": "pillar2",
		"description": "A stone pillar.",
		"layers": [
			{"gate": {"kind": "skill", "id": "ancient_tongues"}, "text": "   "},
		],
	}
	var result_ws: String = PropLayers.render_for_agent(prop_ws, agent_luna, ws)
	if result_ws != "A stone pillar.":
		return _fail("AC-CB-05 (whitespace text): expected base only (whitespace skipped), got '%s'" % result_ws)

	return true


func _test_ac_cb_05_both_skills_both_layers() -> bool:
	## AC-CB-05 edge: agent with both skills sees both layer texts.
	# Arrange
	var wid: String = _world_id("cb05_both")
	_remove_if_exists(wid)
	var prop: Dictionary = {
		"id": "pillar",
		"description": "A stone pillar.",
		"layers": [
			{"gate": {"kind": "skill", "id": "ancient_tongues"}, "text": "The carvings spell a warning."},
			{"gate": {"kind": "skill", "id": "astronomy"}, "text": "A pattern of dots mirrors the sky."},
		],
	}
	var agent_luna: Agent = _make_agent("luna")  # has ancient_tongues + astronomy
	var ws: WorldState = WorldState.load_for(wid)

	# Act
	var result: String = PropLayers.render_for_agent(prop, agent_luna, ws)

	# Assert
	var expected: String = "A stone pillar.\n\nThe carvings spell a warning.\n\nA pattern of dots mirrors the sky."
	if result != expected:
		return _fail("AC-CB-05 (both skills): expected '%s', got '%s'" % [expected, result])
	return true


func _test_ac_cb_06_item_gated_layer_included() -> bool:
	## AC-CB-06: agent holding star_medallion in WorldState sees the item-gated layer.
	# Arrange
	var wid: String = _world_id("cb06_held")
	_remove_if_exists(wid)
	var prop: Dictionary = {
		"id": "altar",
		"description": "An ancient altar.",
		"layers": [
			{"gate": {"kind": "item", "id": "star_medallion"}, "text": "The medallion resonates with the altar."},
		],
	}
	var agent_luna: Agent = _make_agent("luna")
	var ws: WorldState = WorldState.load_for(wid)
	ws.give_item("luna", "star_medallion")

	# Act
	var result: String = PropLayers.render_for_agent(prop, agent_luna, ws)

	# Assert
	var expected: String = "An ancient altar.\n\nThe medallion resonates with the altar."
	if result != expected:
		return _fail("AC-CB-06 (held): expected '%s', got '%s'" % [expected, result])
	return true


func _test_ac_cb_06_item_absent_layer_excluded() -> bool:
	## AC-CB-06 edge: agent NOT holding item sees only base description.
	## Also covers the wrong-world edge from the story's QA block: an item given
	## to luna in world A must not satisfy an item gate evaluated against world B's
	## WorldState — inventory is per-world, not per-agent-globally.
	# Arrange
	var wid: String = _world_id("cb06_absent")
	var wid_other: String = _world_id("cb06_other_world")
	_remove_if_exists(wid)
	_remove_if_exists(wid_other)
	var prop: Dictionary = {
		"id": "altar",
		"description": "An ancient altar.",
		"layers": [
			{"gate": {"kind": "item", "id": "star_medallion"}, "text": "The medallion resonates with the altar."},
		],
	}
	var agent_luna: Agent = _make_agent("luna")  # starting_inventory is [] in fixture
	var ws: WorldState = WorldState.load_for(wid)
	# luna has no star_medallion in this world (starting_inventory is empty)

	# Act
	var result: String = PropLayers.render_for_agent(prop, agent_luna, ws)

	# Assert
	if result != "An ancient altar.":
		return _fail("AC-CB-06 (absent): expected 'An ancient altar.', got '%s'" % result)

	# Edge — wrong-world: give the item in a DIFFERENT world's WorldState, then
	# observe back in the original world. The gate must still fail.
	var ws_other: WorldState = WorldState.load_for(wid_other)
	ws_other.give_item("luna", "star_medallion")
	var result_wrong_world: String = PropLayers.render_for_agent(prop, agent_luna, ws)
	if result_wrong_world != "An ancient altar.":
		return _fail("AC-CB-06 (wrong-world): item in world B leaked into world A render — got '%s'" % result_wrong_world)
	return true


func _test_ac_cb_07_flag_gate_absent_then_present() -> bool:
	## AC-CB-07: flag absent → layer excluded; flag set true → layer included on re-observe.
	# Arrange
	var wid: String = _world_id("cb07")
	_remove_if_exists(wid)
	var prop: Dictionary = {
		"id": "brazier",
		"description": "A cold brazier.",
		"layers": [
			{"gate": {"kind": "flag", "id": "altar.lit"}, "text": "Flames reveal carved runes."},
		],
	}
	var agent: Agent = _make_agent("no_skill_agent")
	var ws: WorldState = WorldState.load_for(wid)

	# Act — flag absent
	var result_absent: String = PropLayers.render_for_agent(prop, agent, ws)

	# Assert — layer not present
	if result_absent != "A cold brazier.":
		return _fail("AC-CB-07 (flag absent): expected 'A cold brazier.', got '%s'" % result_absent)

	# Act — set flag true, re-observe
	ws.set_flag("altar.lit", true)
	var result_lit: String = PropLayers.render_for_agent(prop, agent, ws)

	# Assert — layer now present
	var expected_lit: String = "A cold brazier.\n\nFlames reveal carved runes."
	if result_lit != expected_lit:
		return _fail("AC-CB-07 (flag set): expected '%s', got '%s'" % [expected_lit, result_lit])

	# Edge: flag set to 0 (falsy) → layer absent
	ws.set_flag("altar.lit", 0)
	var result_zero: String = PropLayers.render_for_agent(prop, agent, ws)
	if result_zero != "A cold brazier.":
		return _fail("AC-CB-07 (flag=0): expected base only, got '%s'" % result_zero)

	# Edge: flag set to 1 (truthy) → layer present
	ws.set_flag("altar.lit", 1)
	var result_one: String = PropLayers.render_for_agent(prop, agent, ws)
	if result_one != expected_lit:
		return _fail("AC-CB-07 (flag=1): expected layer present, got '%s'" % result_one)

	return true


func _test_ac_cb_07b_item_acquired_mid_session() -> bool:
	## AC-CB-07b: first observation without item → base only; after give_item + flush,
	## second observation shows item-gated layer. Save file contains item.
	# Arrange
	var wid: String = _world_id("cb07b")
	_remove_if_exists(wid)
	var prop: Dictionary = {
		"id": "altar",
		"description": "An ancient altar.",
		"layers": [
			{"gate": {"kind": "item", "id": "star_medallion"}, "text": "The medallion resonates with the altar."},
		],
	}
	var agent_luna: Agent = _make_agent("luna")
	var ws: WorldState = WorldState.load_for(wid)

	# Act — first observation (luna has no star_medallion yet)
	var result_before: String = PropLayers.render_for_agent(prop, agent_luna, ws)

	# Assert — base description only
	if result_before != "An ancient altar.":
		return _fail("AC-CB-07b (before acquire): expected base only, got '%s'" % result_before)

	# Act — acquire item, flush, verify save file
	ws.give_item("luna", "star_medallion")
	ws.flush()

	var f: FileAccess = FileAccess.open(_save_path(wid), FileAccess.READ)
	if not f:
		return _fail("AC-CB-07b: save file not found after flush")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return _fail("AC-CB-07b: save file is not a JSON object")
	var inv_raw: Variant = (parsed as Dictionary).get("inventory", {})
	if not (inv_raw is Dictionary):
		return _fail("AC-CB-07b: inventory missing from save")
	var luna_items: Variant = (inv_raw as Dictionary).get("luna", [])
	if not (luna_items is Array) or not (luna_items as Array).has("star_medallion"):
		return _fail("AC-CB-07b: save file does not contain star_medallion for luna")

	# Act — second observation (same ws, item already given)
	var result_after: String = PropLayers.render_for_agent(prop, agent_luna, ws)

	# Assert — item-gated layer now present
	var expected_after: String = "An ancient altar.\n\nThe medallion resonates with the altar."
	if result_after != expected_after:
		return _fail("AC-CB-07b (after acquire): expected '%s', got '%s'" % [expected_after, result_after])

	# Item-scoping is agent-level not prop-level: each prop's layers[] is independent,
	# so cross-prop bleed is structurally impossible. World-scoping is covered by
	# _test_ac_cb_06_item_absent_layer_excluded (item in another world does not satisfy
	# a gate evaluated against this WorldState).
	return true


func _test_ac_cb_07d_empty_prop_returns_fallback() -> bool:
	## AC-CB-07d: empty description + empty layers → fallback string (non-empty).
	# Arrange
	var wid: String = _world_id("cb07d")
	_remove_if_exists(wid)
	var agent: Agent = _make_agent("no_skill_agent")
	var ws: WorldState = WorldState.load_for(wid)

	# Resolve the expected fallback from config the same way PropLayers does —
	# nested under defaults.puzzle, not a top-level dotted key. The hardcoded
	# sentinel is the absolute-last-resort PropLayers uses when config is absent.
	var puzzle_cfg: Variant = GameState.get_default("puzzle", {})
	var expected_fallback: String = "It is here, present and unremarkable."
	if puzzle_cfg is Dictionary:
		var raw: Variant = (puzzle_cfg as Dictionary).get("empty_prop_fallback", "")
		if raw is String and not (raw as String).is_empty():
			expected_fallback = raw

	# Act — empty description, empty layers array
	var prop_empty: Dictionary = {"id": "rock", "description": "", "layers": []}
	var result_empty: String = PropLayers.render_for_agent(prop_empty, agent, ws)

	# Assert — fallback equals the resolved config value (not just non-empty)
	if result_empty != expected_fallback:
		return _fail("AC-CB-07d (empty desc): expected fallback '%s', got '%s'" % [expected_fallback, result_empty])

	# Edge: description is whitespace-only → treated as empty → fallback fires
	var prop_ws: Dictionary = {"id": "rock2", "description": "   ", "layers": []}
	var result_ws: String = PropLayers.render_for_agent(prop_ws, agent, ws)
	if result_ws.is_empty():
		return _fail("AC-CB-07d (whitespace desc): fallback must not be empty string")
	if result_ws != result_empty:
		return _fail("AC-CB-07d (whitespace desc): must equal same fallback as empty desc, got '%s'" % result_ws)

	# Edge: layers present but all have empty text → fallback fires
	var prop_empty_text: Dictionary = {
		"id": "rock3",
		"description": "",
		"layers": [
			{"gate": {"kind": "skill", "id": "ancient_tongues"}, "text": ""},
			{"gate": {"kind": "skill", "id": "astronomy"}, "text": "  "},
		],
	}
	# Use luna so both skill gates pass — but text is empty, so no parts added
	var agent_luna: Agent = _make_agent("luna")
	var result_blank_text: String = PropLayers.render_for_agent(prop_empty_text, agent_luna, ws)
	if result_blank_text.is_empty():
		return _fail("AC-CB-07d (blank layer text): fallback must not be empty")
	if result_blank_text != result_empty:
		return _fail("AC-CB-07d (blank layer text): must equal fallback, got '%s'" % result_blank_text)

	# Edge: prop dict missing "description" key entirely → treated as empty → fallback fires
	var prop_no_key: Dictionary = {"id": "rock4", "layers": []}
	var result_no_key: String = PropLayers.render_for_agent(prop_no_key, agent, ws)
	if result_no_key.is_empty():
		return _fail("AC-CB-07d (no description key): fallback must not be empty")
	if result_no_key != result_empty:
		return _fail("AC-CB-07d (no description key): must equal fallback, got '%s'" % result_no_key)

	return true


func _test_r7c_unknown_gate_kind_evaluates_false() -> bool:
	## R7c: unknown gate kind evaluates false at render time; no crash.
	## push_warning at load_for() time is Story 006's integration point — not tested here.
	# Arrange
	var wid: String = _world_id("r7c")
	_remove_if_exists(wid)
	var prop: Dictionary = {
		"id": "pillar",
		"description": "A stone pillar.",
		"layers": [
			{"gate": {"kind": "enchantment", "id": "some_spell"}, "text": "Magic text."},
			{"gate": {"kind": "reputation", "id": "elder_trust"}, "text": "Elder text."},
			{"gate": {}, "text": "No-kind text."},
		],
	}
	var agent: Agent = _make_agent("luna")  # fully skilled — all known gates would pass
	var ws: WorldState = WorldState.load_for(wid)

	# Act
	var result: String = PropLayers.render_for_agent(prop, agent, ws)

	# Assert — all unknown gates evaluate false, only base description appears
	if result != "A stone pillar.":
		return _fail("R7c: expected base only for unknown gate kinds, got '%s'" % result)
	return true
