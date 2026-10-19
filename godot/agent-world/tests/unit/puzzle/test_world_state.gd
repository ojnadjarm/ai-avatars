class_name TestWorldState
extends RefCounted
## Unit tests for WorldState (Story 001).
## Covers every acceptance criterion in
## production/epics/agent-puzzle-layer/story-001-world-state.md.
##
## Each sub-test uses a unique world_id so concurrent runs cannot collide.
## Save files are cleaned up at the end of run(), pass or fail.

const SAVES_DIR := "user://saves/"

## Hermetic agent fixture — decouples tests from GameState.agents at runtime
## so they pass regardless of whether the user:// config override is fresh.
## Mirrors the canonical fixtures in res://game_config.json:
##   darksaddler — starting_inventory: ["star_medallion"]
##   luna        — skills: ["astronomy"], starting_inventory: []
##   grok        — neither key present (AC-CB-03 shape)
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
	"null_inv_agent": {
		"display_name": "NullInv",
		"starting_inventory": null,
	},
}

var failure_message: String = ""
var _test_world_ids: Array[String] = []
var _saved_agents: Dictionary = {}


func run() -> bool:
	_install_fixture_agents()
	if not _test_invalid_world_id():
		_restore_agents()
		return false
	if not _test_ac_sl_04_missing_save():
		_restore_agents()
		return false
	if not _test_ac_cb_02_starting_inventory():
		_restore_agents()
		return false
	if not _test_ac_cb_03_no_skills_no_inventory():
		_restore_agents()
		return false
	if not _test_ac_sl_01_state_persists():
		_restore_agents()
		return false
	if not _test_ac_sl_02_schema_version():
		_restore_agents()
		return false
	if not _test_ac_sl_03_world_isolation():
		_restore_agents()
		return false
	if not _test_ac_sl_05_corrupt_json():
		_restore_agents()
		return false
	if not _test_schema_version_mismatch():
		_restore_agents()
		return false
	if not _test_evaluate_predicate():
		_restore_agents()
		return false
	if not _test_fired_puzzles_rebuilt():
		_restore_agents()
		return false
	if not _test_flag_writers_stamped():
		_restore_agents()
		return false
	if not _test_starting_inventory_count_one():
		_restore_agents()
		return false
	if not _test_starting_inventory_null_coerced():
		_restore_agents()
		return false
	if not _test_schema_version_absent():
		_restore_agents()
		return false
	if not _test_take_item_absent_paths():
		_restore_agents()
		return false
	if not _test_evaluate_predicate_malformed():
		_restore_agents()
		return false
	if not _test_get_object_copies():
		_restore_agents()
		return false
	if not _test_unknown_starting_items():
		_restore_agents()
		return false
	_cleanup()
	_restore_agents()
	return true


func _test_unknown_starting_items() -> bool:
	## TD-001 / AC-CB-02 edge-2: starting_inventory entries matching no puzzle
	## rule or prop layer are reported (for a load-time push_warning), while
	## items referenced by give/take effects, take/use_object match targets, or
	## item-gated layers are considered known. Pure static — agent configs are
	## passed in directly, so GameState state never leaks into this test.
	# Arrange — one puzzle covering every known-item position + one item layer.
	var puzzle_list: Array = [{
		"id": "vocab_fixture",
		"actions": [
			{"match": {"verb": "use_object", "target": "star_medallion", "on": "pillar"}},
			{"match": {"verb": "take", "target": "loose_rune"}},
			{"match": {"verb": "go_to", "target": "not_an_item"}},
			{"effect": {"give_item": "granted_item", "take_item": ["spent_item"]}},
		],
	}]
	var props: Array = [{
		"entity_id": "prop_1",
		"layers": [{"gate": {"kind": "item", "id": "gated_item"}, "text": "x"}],
	}]
	var agent_configs: Dictionary = {
		"holder": {"starting_inventory": ["star_medallion", "loose_rune", "granted_item", "spent_item", "gated_item"]},
		"stray": {"starting_inventory": ["mystery_orb", "not_an_item"]},
		"no_inv": {},
	}

	# Act
	var unknown: Array[Dictionary] = WorldState.unknown_starting_items(agent_configs, puzzle_list, props)

	# Assert — every 'holder' item is known; 'stray' reports exactly two:
	# mystery_orb (nowhere) and not_an_item (go_to targets are not items).
	if unknown.size() != 2:
		return _fail("unknown_starting_items: expected 2 unknown entries, got %d (%s)" % [unknown.size(), str(unknown)])
	for entry: Dictionary in unknown:
		if str(entry.get("agent_id")) != "stray":
			return _fail("unknown_starting_items: unexpected agent '%s' flagged" % str(entry.get("agent_id")))
	var flagged: Array[String] = []
	for entry: Dictionary in unknown:
		flagged.append(str(entry.get("item_id")))
	if not ("mystery_orb" in flagged) or not ("not_an_item" in flagged):
		return _fail("unknown_starting_items: expected [mystery_orb, not_an_item], got %s" % str(flagged))
	return true


func _install_fixture_agents() -> void:
	_saved_agents = GameState.agents
	GameState.agents = FIXTURE_AGENTS.duplicate(true)


func _restore_agents() -> void:
	GameState.agents = _saved_agents
	# Always remove any save files this run produced — guarantees cleanup even
	# on failure paths that don't route through _fail().
	_cleanup()


# ── Helpers ───────────────────────────────────────────────────────────────

func _world_id(suffix: String) -> String:
	var wid := "test_ws_" + suffix
	_test_world_ids.append(wid)
	return wid


func _save_path(wid: String) -> String:
	return SAVES_DIR + "world_state_" + wid + ".json"


func _write_raw(wid: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var f := FileAccess.open(_save_path(wid), FileAccess.WRITE)
	if f:
		f.store_string(content)


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


# ── Tests ─────────────────────────────────────────────────────────────────

func _test_invalid_world_id() -> bool:
	## Invalid world_id → clean default with world_id == "", no file I/O.
	var ws: WorldState = WorldState.load_for("bad id!")
	if ws.world_id != "":
		return _fail("invalid world_id: expected world_id == '', got '%s'" % ws.world_id)
	if not ws.objects.is_empty():
		return _fail("invalid world_id: objects not empty on clean default")
	if not ws.flags.is_empty():
		return _fail("invalid world_id: flags not empty on clean default")
	## flush() must silently no-op on a zeroed world_id
	ws.flush()
	return true


func _test_ac_sl_04_missing_save() -> bool:
	## AC-SL-04: missing save → clean dicts, starting_inventory applied.
	var wid := _world_id("sl04")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	if not ws.objects.is_empty():
		return _fail("AC-SL-04: objects not empty on missing save")
	if not ws.flags.is_empty():
		return _fail("AC-SL-04: flags not empty on missing save")
	if ws.world_id != wid:
		return _fail("AC-SL-04: world_id not preserved on missing save")
	if not ws.agent_has_item("darksaddler", "star_medallion"):
		return _fail("AC-SL-04: starting_inventory not applied for darksaddler")
	return true


func _test_ac_cb_02_starting_inventory() -> bool:
	## AC-CB-02: starting_inventory present and persisted after flush.
	var wid := _world_id("cb02")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	if not ws.agent_has_item("darksaddler", "star_medallion"):
		return _fail("AC-CB-02: darksaddler missing star_medallion after load")
	ws.flush()

	## Parse the written file directly and confirm the inventory shape.
	var f := FileAccess.open(_save_path(wid), FileAccess.READ)
	if not f:
		return _fail("AC-CB-02: could not reopen save file")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return _fail("AC-CB-02: saved file is not a JSON object")
	var inv_raw: Variant = (parsed as Dictionary).get("inventory", {})
	if not (inv_raw is Dictionary):
		return _fail("AC-CB-02: inventory missing from save")
	var ds_items: Variant = (inv_raw as Dictionary).get("darksaddler", [])
	if not (ds_items is Array) or not (ds_items as Array).has("star_medallion"):
		return _fail("AC-CB-02: save file does not contain star_medallion for darksaddler")

	## Reload and confirm persistence through the accessor path.
	var ws2: WorldState = WorldState.load_for(wid)
	if not ws2.agent_has_item("darksaddler", "star_medallion"):
		return _fail("AC-CB-02: star_medallion missing after flush + reload")
	return true


func _test_ac_cb_03_no_skills_no_inventory() -> bool:
	## AC-CB-03: grok config has neither skills nor starting_inventory.
	var wid := _world_id("cb03")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	if ws.agent_has_item("grok", "anything"):
		return _fail("AC-CB-03: grok should not have 'anything'")
	if ws.agent_has_item("grok", "star_medallion"):
		return _fail("AC-CB-03: grok should not have star_medallion")
	return true


func _test_ac_sl_01_state_persists() -> bool:
	## AC-SL-01: flags and object fields survive flush + reload.
	var wid := _world_id("sl01")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	ws.set_flag("door.open", true)
	ws.set_object_field("chest", "open", true)
	ws.set_object_field("chest", "contents", "rune")
	ws.flush()

	var ws2: WorldState = WorldState.load_for(wid)
	if ws2.get_flag("door.open") != true:
		return _fail("AC-SL-01: door.open flag not persisted")
	var chest: Dictionary = ws2.get_object("chest")
	if chest.get("open") != true:
		return _fail("AC-SL-01: chest.open field not persisted")
	if chest.get("contents") != "rune":
		return _fail("AC-SL-01: chest.contents field not persisted")
	return true


func _test_ac_sl_02_schema_version() -> bool:
	## AC-SL-02: schema_version == 1 in every written file.
	var wid := _world_id("sl02")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	ws.flush()

	var f := FileAccess.open(_save_path(wid), FileAccess.READ)
	if not f:
		return _fail("AC-SL-02: could not open save file after flush")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return _fail("AC-SL-02: saved file is not valid JSON")
	var schema: Variant = (parsed as Dictionary).get("schema_version", null)
	if schema != 1:
		return _fail("AC-SL-02: schema_version is %s, expected 1" % str(schema))

	## Second save after a state change — schema_version still 1.
	ws.set_flag("something", true)
	ws.flush()
	f = FileAccess.open(_save_path(wid), FileAccess.READ)
	parsed = JSON.parse_string(f.get_as_text())
	if (parsed as Dictionary).get("schema_version", null) != 1:
		return _fail("AC-SL-02: schema_version drifted on second save")
	return true


func _test_ac_sl_03_world_isolation() -> bool:
	## AC-SL-03: item in world A must not appear in world B.
	var wid_a := _world_id("sl03a")
	var wid_b := _world_id("sl03b")
	_remove_if_exists(wid_a)
	_remove_if_exists(wid_b)

	var ws_a: WorldState = WorldState.load_for(wid_a)
	ws_a.give_item("luna", "star_medallion")
	ws_a.flush()

	var ws_b: WorldState = WorldState.load_for(wid_b)
	if ws_b.agent_has_item("luna", "star_medallion"):
		return _fail("AC-SL-03: star_medallion leaked from world A into world B")

	var ws_a2: WorldState = WorldState.load_for(wid_a)
	if not ws_a2.agent_has_item("luna", "star_medallion"):
		return _fail("AC-SL-03: star_medallion missing from world A after reload")
	return true


func _test_ac_sl_05_corrupt_json() -> bool:
	## AC-SL-05: corrupt JSON → clean default, starting_inventory applied.
	var wid := _world_id("sl05")
	_write_raw(wid, '{"schema_version": 1, "objects": {TRUNCATED')

	var ws: WorldState = WorldState.load_for(wid)
	if not ws.objects.is_empty():
		return _fail("AC-SL-05: objects not empty after corrupt load")
	if not ws.flags.is_empty():
		return _fail("AC-SL-05: flags not empty after corrupt load")
	if not ws.agent_has_item("darksaddler", "star_medallion"):
		return _fail("AC-SL-05: starting_inventory not applied after corrupt load")

	## Empty file → same clean-init path.
	var wid_empty := _world_id("sl05_empty")
	_write_raw(wid_empty, "")
	var ws_empty: WorldState = WorldState.load_for(wid_empty)
	if not ws_empty.objects.is_empty() or not ws_empty.flags.is_empty():
		return _fail("AC-SL-05: empty file did not produce clean default")
	return true


func _test_schema_version_mismatch() -> bool:
	## schema_version != 1 → push_warning + clean default.
	var wid := _world_id("schmismatch")
	_write_raw(wid, '{"schema_version": 99, "objects": {"should":"ignore"}, "flags": {"x":true}, "inventory": {}, "puzzles": {}}')

	var ws: WorldState = WorldState.load_for(wid)
	if not ws.objects.is_empty():
		return _fail("schema_version mismatch: objects not empty")
	if not ws.flags.is_empty():
		return _fail("schema_version mismatch: flags not empty")
	## starting_inventory still applied on clean default
	if not ws.agent_has_item("darksaddler", "star_medallion"):
		return _fail("schema_version mismatch: starting_inventory not applied on clean default")
	return true


func _test_evaluate_predicate() -> bool:
	## evaluate_predicate: AND/OR/NOT + equality over flags and objects.
	var wid := _world_id("pred")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	ws.set_flag("door.open", true)
	ws.set_flag("altar.lit", false)
	ws.set_object_field("chest", "contents", "rune")

	if not ws.evaluate_predicate({"flag": {"door.open": true}}):
		return _fail("predicate: flag match failed")
	if ws.evaluate_predicate({"flag": {"door.open": false}}):
		return _fail("predicate: flag mismatch returned true")
	if not ws.evaluate_predicate({"object": {"chest.contents": "rune"}}):
		return _fail("predicate: object match failed")
	if not ws.evaluate_predicate({"and": [{"flag": {"door.open": true}}, {"object": {"chest.contents": "rune"}}]}):
		return _fail("predicate: AND failed")
	if ws.evaluate_predicate({"and": [{"flag": {"door.open": true}}, {"flag": {"altar.lit": true}}]}):
		return _fail("predicate: AND returned true for mixed")
	if not ws.evaluate_predicate({"or": [{"flag": {"altar.lit": true}}, {"flag": {"door.open": true}}]}):
		return _fail("predicate: OR failed")
	if not ws.evaluate_predicate({"not": {"flag": {"altar.lit": true}}}):
		return _fail("predicate: NOT failed")
	if ws.evaluate_predicate({}):
		return _fail("predicate: empty predicate returned true")
	return true


func _test_fired_puzzles_rebuilt() -> bool:
	## _fired_puzzles rebuilt from loaded puzzles dict on load_for.
	var wid := _world_id("fired")
	var payload := '{"schema_version": 1, "objects": {}, "flags": {}, "inventory": {}, "puzzles": {"stargate": {"state": 2, "collaborators": ["luna","darksaddler"]}, "unlit": {"state": 0, "collaborators": []}}}'
	_write_raw(wid, payload)

	var ws: WorldState = WorldState.load_for(wid)
	if ws._fired_puzzles.get("stargate", false) != true:
		return _fail("_fired_puzzles: stargate (state=2) not marked fired")
	if ws._fired_puzzles.get("unlit", false) != false:
		return _fail("_fired_puzzles: unlit (state=0) marked fired")
	return true


func _test_flag_writers_stamped() -> bool:
	## set_flag_with_writer stamps flag_writers; set_flag does not.
	var wid := _world_id("writers")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	ws.set_flag("plain", true)
	ws.set_flag_with_writer("credited", true, "luna")

	if ws.flag_writers.has("plain"):
		return _fail("flag_writers: plain set_flag should not stamp")
	if ws.flag_writers.get("credited", "") != "luna":
		return _fail("flag_writers: credited flag not stamped with 'luna'")

	## flag_writers is runtime-only — cleared on reload.
	ws.flush()
	var ws2: WorldState = WorldState.load_for(wid)
	if ws2.flag_writers.has("credited"):
		return _fail("flag_writers: should be cleared on reload (runtime-only)")
	return true


func _test_starting_inventory_count_one() -> bool:
	## starting_inventory dedup: darksaddler's star_medallion appears exactly once.
	var wid := _world_id("count")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	var items: Variant = ws.inventory.get("darksaddler", [])
	if not (items is Array):
		return _fail("starting_inventory count: inventory shape wrong")
	var count: int = 0
	for entry: Variant in (items as Array):
		if str(entry) == "star_medallion":
			count += 1
	if count != 1:
		return _fail("starting_inventory count: expected 1, got %d" % count)
	return true


func _test_starting_inventory_null_coerced() -> bool:
	## AC-CB-03 edge: starting_inventory: null → no crash, agent has no items.
	var wid := _world_id("null_inv")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	if ws.agent_has_item("null_inv_agent", "anything"):
		return _fail("starting_inventory: null should yield no items")
	## Flush + reload round-trip must still work with a null-inventory agent in config.
	ws.flush()
	var ws2: WorldState = WorldState.load_for(wid)
	if ws2.agent_has_item("null_inv_agent", "anything"):
		return _fail("starting_inventory: null should yield no items after reload")
	return true


func _test_schema_version_absent() -> bool:
	## AC-SL-05 edge: schema_version key entirely absent → clean default.
	var wid := _world_id("schabsent")
	_write_raw(wid, '{"objects": {"x": {"f": 1}}, "flags": {"y": true}, "inventory": {}}')

	var ws: WorldState = WorldState.load_for(wid)
	if not ws.objects.is_empty():
		return _fail("schema_version absent: objects leaked from bad save")
	if not ws.flags.is_empty():
		return _fail("schema_version absent: flags leaked from bad save")
	if not ws.agent_has_item("darksaddler", "star_medallion"):
		return _fail("schema_version absent: starting_inventory not applied on clean default")
	return true


func _test_take_item_absent_paths() -> bool:
	## take_item must return false for agents with no inventory entry AND
	## for agents who have an entry but don't hold the item.
	var wid := _world_id("take_absent")
	_remove_if_exists(wid)

	var ws: WorldState = WorldState.load_for(wid)
	if ws.take_item("nonexistent_agent", "anything") != false:
		return _fail("take_item: agent-absent should return false")

	## luna has an empty inventory from fixture — has an entry via give_item, then try taking a different item.
	ws.give_item("luna", "known_item")
	if ws.take_item("luna", "unheld_item") != false:
		return _fail("take_item: agent-has-inventory-but-no-item should return false")
	## Verify known_item is still there after the failed take.
	if not ws.agent_has_item("luna", "known_item"):
		return _fail("take_item: failed take must not mutate inventory")

	## give_item dedup — adding the same item twice stays at count 1.
	ws.give_item("luna", "known_item")
	var items: Array = ws.inventory["luna"] as Array
	if items.size() != 1:
		return _fail("give_item: dedup failed, got %d entries" % items.size())
	return true


func _test_evaluate_predicate_malformed() -> bool:
	## evaluate_predicate: malformed input guard paths all return false safely.
	var wid := _world_id("pred_bad")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)

	## and / or: non-Array
	if ws.evaluate_predicate({"and": "not-an-array"}) != false:
		return _fail("malformed: and=string should be false")
	if ws.evaluate_predicate({"or": "not-an-array"}) != false:
		return _fail("malformed: or=string should be false")

	## and / or: non-Dict elements
	if ws.evaluate_predicate({"and": [42]}) != false:
		return _fail("malformed: and element not Dict should be false")
	if ws.evaluate_predicate({"or": [42]}) != false:
		return _fail("malformed: or element not Dict should be false")

	## Empty and / or — vacuous truth semantics (and=true, or=false).
	if ws.evaluate_predicate({"and": []}) != true:
		return _fail("empty and: vacuous-true expected")
	if ws.evaluate_predicate({"or": []}) != false:
		return _fail("empty or: false expected")

	## not: non-Dict
	if ws.evaluate_predicate({"not": "not-a-dict"}) != false:
		return _fail("malformed: not=string should be false")

	## flag / object: non-Dict
	if ws.evaluate_predicate({"flag": "not-a-dict"}) != false:
		return _fail("malformed: flag=string should be false")
	if ws.evaluate_predicate({"object": "not-a-dict"}) != false:
		return _fail("malformed: object=string should be false")

	## object: key missing dot separator
	if ws.evaluate_predicate({"object": {"no_dot_here": 1}}) != false:
		return _fail("malformed: object key without dot should be false")

	## Unknown top-level predicate key
	if ws.evaluate_predicate({"whatever_key": true}) != false:
		return _fail("malformed: unknown key should be false")

	## Predicate referencing a nonexistent flag (should be false, not crash).
	if ws.evaluate_predicate({"flag": {"never_written": true}}) != false:
		return _fail("malformed: nonexistent flag should be false")

	## get_object on unknown prop returns {} — predicate against it is false.
	if ws.evaluate_predicate({"object": {"ghost.field": "value"}}) != false:
		return _fail("malformed: unknown prop should be false")
	return true


func _test_get_object_copies() -> bool:
	## get_object must return a defensive copy — mutating the returned dict
	## must NOT mutate the backing state (ADR-0001 §1 boundary rule).
	var wid := _world_id("copy")
	_remove_if_exists(wid)
	var ws: WorldState = WorldState.load_for(wid)
	ws.set_object_field("chest", "open", false)

	var leased: Dictionary = ws.get_object("chest")
	leased["open"] = true  # try to mutate through the returned reference

	var actual: Dictionary = ws.get_object("chest")
	if actual.get("open") != false:
		return _fail("get_object: returned reference was mutable — backing state leaked")
	return true
