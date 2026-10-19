class_name WorldState
extends RefCounted
## Authoritative game-side world state for the puzzle layer.
##
## Holds four persisted dictionaries:
##   objects   — prop/object mutable state keyed by prop_id
##   flags     — puzzle-level boolean or numeric flags
##   inventory — agent_id → Array[String] of item_ids
##   puzzles   — puzzle_id → { state: int, collaborators: Array }
##
## Plus two runtime-only dictionaries rebuilt on every load_for():
##   _fired_puzzles — puzzle_id → bool; true once a puzzle reached state 2 (SOLVED)
##   flag_writers   — flag_id   → agent_id; last agent to write the flag
##
## All mutation goes through typed accessors. No caller outside the puzzle
## layer reads or writes the backing Dictionaries directly.
##
## Persists to user://saves/world_state_<world_id>.json with a top-level
## schema_version: 1 key. Missing or corrupt saves return a clean default.
## An invalid world_id zeros out world_id on the returned WorldState, so
## flush() silently no-ops and cannot write to a bad path.

const SAVES_DIR := "user://saves/"
const SCHEMA_VERSION := 1
const WORLD_ID_REGEX := "^[a-z0-9_]+$"

var world_id: String = ""
var objects: Dictionary = {}
var flags: Dictionary = {}
var inventory: Dictionary = {}
var puzzles: Dictionary = {}

var _fired_puzzles: Dictionary = {}
var flag_writers: Dictionary = {}


# ── Factory ───────────────────────────────────────────────────────────────

static func _clean_default(p_world_id: String) -> WorldState:
	var ws := WorldState.new()
	ws.world_id = p_world_id
	_apply_starting_inventory(ws)
	return ws


## Load persisted state for world_id. Returns a clean default (world_id == "")
## when the requested id is invalid. Missing or corrupt files also return a
## clean default, but preserve world_id so a subsequent flush() writes a
## fresh save to the correct path.
static func load_for(p_world_id: String) -> WorldState:
	var re := RegEx.new()
	re.compile(WORLD_ID_REGEX)
	if re.search(p_world_id) == null:
		push_error("[WorldState] Invalid world_id '%s' — must match %s. Returning clean default with no file I/O." % [p_world_id, WORLD_ID_REGEX])
		return _clean_default("")

	var path := SAVES_DIR + "world_state_" + p_world_id + ".json"
	if not FileAccess.file_exists(path):
		return _clean_default(p_world_id)

	var data: Dictionary = GameState.load_json(path, "WorldState")
	if data.is_empty():
		## load_json emitted push_warning since log_label was non-empty.
		return _clean_default(p_world_id)

	if data.get("schema_version", 0) != SCHEMA_VERSION:
		push_warning("[WorldState] schema_version mismatch in '%s' — resetting to clean default." % path)
		return _clean_default(p_world_id)

	var ws := WorldState.new()
	ws.world_id = p_world_id
	_hydrate_from_save(ws, data)
	_apply_starting_inventory(ws)
	return ws


## Populate ws fields from a validated save-file dictionary. Expects schema_version
## to have already been checked by the caller.
static func _hydrate_from_save(ws: WorldState, data: Dictionary) -> void:
	var raw_objects: Variant = data.get("objects", {})
	if raw_objects is Dictionary:
		ws.objects = raw_objects
	var raw_flags: Variant = data.get("flags", {})
	if raw_flags is Dictionary:
		ws.flags = raw_flags
	var raw_inv: Variant = data.get("inventory", {})
	if raw_inv is Dictionary:
		for aid: String in raw_inv:
			var items: Variant = raw_inv[aid]
			var typed: Array[String] = []
			if items is Array:
				for entry: Variant in items:
					typed.append(str(entry))
			ws.inventory[aid] = typed
	var raw_puzzles: Variant = data.get("puzzles", {})
	if raw_puzzles is Dictionary:
		ws.puzzles = raw_puzzles
		for pid: String in ws.puzzles:
			var pdata: Variant = ws.puzzles[pid]
			if pdata is Dictionary:
				ws._fired_puzzles[pid] = int(pdata.get("state", 0)) == 2


## Apply starting_inventory from GameState.agents to agents who don't yet
## have an inventory entry. Dedupes duplicate entries with a push_warning.
## Idempotent — safe to call on both fresh and loaded WorldStates.
static func _apply_starting_inventory(ws: WorldState) -> void:
	var agents: Dictionary = GameState.agents
	for aid: String in agents:
		if ws.inventory.has(aid):
			continue
		var agent_cfg: Variant = agents.get(aid, {})
		if not (agent_cfg is Dictionary):
			continue
		var raw_inv: Variant = (agent_cfg as Dictionary).get("starting_inventory", [])
		if not (raw_inv is Array):
			continue
		var src: Array = raw_inv
		var seen: Dictionary = {}
		var deduped: Array[String] = []
		for entry: Variant in src:
			var item_id: String = str(entry)
			if seen.has(item_id):
				push_warning("[WorldState] Duplicate starting_inventory entry '%s' for agent '%s' — skipping." % [item_id, aid])
				continue
			seen[item_id] = true
			deduped.append(item_id)
		if deduped.size() > 0:
			ws.inventory[aid] = deduped


## TD-001 / GDD AC-CB-02 edge-2 — collect every item id the loaded content can
## reference: give_item/take_item effects, take/use_object match targets, and
## prop-layer item gates. Returns a Dictionary used as a set (id -> true).
static func collect_known_item_ids(puzzle_list: Array, props: Variant) -> Dictionary:
	var known: Dictionary = {}
	for puzzle_variant: Variant in puzzle_list:
		if not (puzzle_variant is Dictionary):
			continue
		var actions: Variant = (puzzle_variant as Dictionary).get("actions", [])
		if not (actions is Array):
			continue
		for rule_variant: Variant in (actions as Array):
			if not (rule_variant is Dictionary):
				continue
			var rule: Dictionary = rule_variant
			var effect: Variant = rule.get("effect", null)
			if effect is Dictionary:
				for eff_key: String in ["give_item", "take_item"]:
					var val: Variant = (effect as Dictionary).get(eff_key, null)
					if val is String:
						known[val] = true
					elif val is Array:
						for item: Variant in (val as Array):
							known[str(item)] = true
			var match_dict: Variant = rule.get("match", null)
			if match_dict is Dictionary:
				var md: Dictionary = match_dict
				if str(md.get("verb", "")) in ["take", "use_object"] and md.has("target"):
					known[str(md["target"])] = true
	if props is Array:
		for prop_variant: Variant in (props as Array):
			if not (prop_variant is Dictionary):
				continue
			var layers: Variant = (prop_variant as Dictionary).get("layers", [])
			if not (layers is Array):
				continue
			for layer_variant: Variant in (layers as Array):
				if not (layer_variant is Dictionary):
					continue
				var gate: Variant = (layer_variant as Dictionary).get("gate", null)
				if gate is Dictionary and str((gate as Dictionary).get("kind", "")) == "item":
					var gate_id: String = str((gate as Dictionary).get("id", ""))
					if not gate_id.is_empty():
						known[gate_id] = true
	return known


## TD-001 — return one {agent_id, item_id} Dictionary per starting_inventory
## entry that matches no known item id in this world's rules and layers.
## Pure and static (agent configs passed in, not read from GameState) so it
## is headless-testable; world_loader push_warns each pair at load time.
static func unknown_starting_items(agent_configs: Dictionary, puzzle_list: Array, props: Variant) -> Array[Dictionary]:
	var known: Dictionary = collect_known_item_ids(puzzle_list, props)
	var result: Array[Dictionary] = []
	for aid: Variant in agent_configs:
		var agent_cfg: Variant = agent_configs[aid]
		if not (agent_cfg is Dictionary):
			continue
		var raw_inv: Variant = (agent_cfg as Dictionary).get("starting_inventory", [])
		if not (raw_inv is Array):
			continue
		for item_variant: Variant in (raw_inv as Array):
			var item_id: String = str(item_variant)
			if not item_id.is_empty() and not known.has(item_id):
				result.append({"agent_id": str(aid), "item_id": item_id})
	return result


# ── Persistence ───────────────────────────────────────────────────────────

## Write current state to disk. No-op when world_id is empty (clean default
## or an invalid id that was zeroed out on load).
func flush() -> void:
	if world_id == "":
		return
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var path := SAVES_DIR + "world_state_" + world_id + ".json"
	var data: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"world_id": world_id,
		"objects": objects,
		"flags": flags,
		"inventory": inventory,
		"puzzles": puzzles,
	}
	GameState.save_json(path, data, "WorldState")


# ── Object accessors ──────────────────────────────────────────────────────

## Returns a defensive copy of the state dict for prop_id, or {} if unknown.
## Callers must use set_object_field() to mutate state — per ADR-0001 §1
## "no caller outside the puzzle layer reads or writes these fields directly."
func get_object(id: String) -> Dictionary:
	var obj: Variant = objects.get(id, null)
	if obj is Dictionary:
		return (obj as Dictionary).duplicate()
	return {}


## Set a single field on a prop's state dict. Creates the entry if absent.
func set_object_field(id: String, key: String, value: Variant) -> void:
	if not objects.has(id):
		objects[id] = {}
	var obj: Dictionary = objects[id]
	obj[key] = value


# ── Flag accessors ────────────────────────────────────────────────────────

## Returns the flag value, or null if not set.
func get_flag(key: String) -> Variant:
	return flags.get(key, null)


## Set a puzzle-level flag. The flag_writers dict is not updated — callers
## that know the acting agent should use set_flag_with_writer() instead.
func set_flag(key: String, value: Variant) -> void:
	flags[key] = value


## Set a puzzle-level flag and record the acting agent. Feeds R21b
## (flag-writer auto-credit) — the resolver stamps every flag write.
func set_flag_with_writer(key: String, value: Variant, agent_id: String) -> void:
	flags[key] = value
	flag_writers[key] = agent_id


# ── Inventory accessors ───────────────────────────────────────────────────

## Give item_id to agent_id. Deduplicates: an agent never holds two copies.
func give_item(agent_id: String, item_id: String) -> void:
	if not inventory.has(agent_id):
		var fresh: Array[String] = []
		inventory[agent_id] = fresh
	var items: Array[String] = inventory[agent_id]
	if not items.has(item_id):
		items.append(item_id)


## Remove item_id from agent_id's inventory. Returns true if the item was
## present and removed, false if the agent did not hold it.
func take_item(agent_id: String, item_id: String) -> bool:
	if not inventory.has(agent_id):
		return false
	var items: Array[String] = inventory[agent_id]
	var idx: int = items.find(item_id)
	if idx == -1:
		return false
	items.remove_at(idx)
	return true


## True when agent_id's inventory contains item_id.
func agent_has_item(agent_id: String, item_id: String) -> bool:
	if not inventory.has(agent_id):
		return false
	return inventory[agent_id].has(item_id)


# ── Puzzle solve-state accessors ──────────────────────────────────────────

## Return the solve state for puzzle_id (0=UNSOLVED, 1=SOLVING, 2=SOLVED).
## Missing entries return 0 per R18. Callers must use this instead of
## indexing `puzzles` directly — per ADR-0001 §1 typed-accessor boundary.
func get_puzzle_state(puzzle_id: String) -> int:
	var pdata: Variant = puzzles.get(puzzle_id, null)
	if not (pdata is Dictionary):
		return 0
	return int((pdata as Dictionary).get("state", 0))


## Set the solve state for puzzle_id. Initializes the puzzle entry with a
## default collaborators array if missing. Does NOT flush — callers flush
## at the right moment (force-flush on solve per R15).
func set_puzzle_state(puzzle_id: String, state: int) -> void:
	if not puzzles.has(puzzle_id):
		puzzles[puzzle_id] = {"state": 0, "collaborators": []}
	var pdata: Variant = puzzles[puzzle_id]
	if not (pdata is Dictionary):
		push_warning("[WorldState] puzzles['%s'] is not a Dictionary — cannot set state." % puzzle_id)
		return
	(pdata as Dictionary)["state"] = state


## Return the R17 idempotence latch for puzzle_id. False when the puzzle
## has never reached SOLVED in the current world-load.
func is_puzzle_fired(puzzle_id: String) -> bool:
	return _fired_puzzles.get(puzzle_id, false)


## Latch the R17 idempotence guard. Called once per puzzle at solve
## broadcast; subsequent solve scans in the same load will skip the puzzle.
func latch_puzzle_fired(puzzle_id: String) -> void:
	_fired_puzzles[puzzle_id] = true


## Story 004 / R22 — return the collaborators array for puzzle_id.
## Initializes the puzzle entry if missing (mirrors set_puzzle_state pattern).
## Callers must NOT index puzzles[] directly — use this accessor.
func get_puzzle_collaborators(puzzle_id: String) -> Array[String]:
	if not puzzles.has(puzzle_id):
		puzzles[puzzle_id] = {"state": 0, "collaborators": []}
	var pdata: Variant = puzzles[puzzle_id]
	if not (pdata is Dictionary):
		return []
	var raw: Variant = (pdata as Dictionary).get("collaborators", [])
	if not (raw is Array):
		return []
	var result: Array[String] = []
	for entry: Variant in raw:
		result.append(str(entry))
	return result


## Story 004 / R21 — append agent_id to the collaborators array for puzzle_id.
## Deduplicates: agent_id is only appended when not already present.
## Initializes the puzzle entry if missing (mirrors set_puzzle_state pattern).
func add_collaborator(puzzle_id: String, agent_id: String) -> void:
	if not puzzles.has(puzzle_id):
		puzzles[puzzle_id] = {"state": 0, "collaborators": []}
	var pdata: Variant = puzzles[puzzle_id]
	if not (pdata is Dictionary):
		push_warning("[WorldState] puzzles['%s'] is not a Dictionary — cannot add collaborator." % puzzle_id)
		return
	var raw: Variant = (pdata as Dictionary).get("collaborators", null)
	if raw == null:
		(pdata as Dictionary)["collaborators"] = []
		raw = (pdata as Dictionary)["collaborators"]
	if not (raw is Array):
		push_warning("[WorldState] puzzles['%s'].collaborators is not an Array — cannot add collaborator." % puzzle_id)
		return
	if not (raw as Array).has(agent_id):
		(raw as Array).append(agent_id)


## Story 004 / R21b — return the agent_id of the last writer of flag_id,
## or "" if the flag was never written with set_flag_with_writer().
func get_flag_writer(flag_id: String) -> String:
	return str(flag_writers.get(flag_id, ""))


# ── Predicate evaluation ──────────────────────────────────────────────────

## Evaluate a puzzle predicate Dictionary against current state. Supported
## forms for v1:
##
##   { "flag": { "key": value, … } }        — all listed flags match
##   { "object": { "id.field": value, … } } — all listed object fields match
##   { "and": [ pred, … ] }                  — all sub-predicates true (empty → true)
##   { "or":  [ pred, … ] }                  — at least one sub-predicate true (empty → false)
##   { "not": pred }                          — sub-predicate false
##
## Empty or unrecognised predicates return false and emit a push_warning.
## Per ADR-0001 this is "nothing happens", not an error — the resolver
## treats a false predicate as a no-match and narrates accordingly.
func evaluate_predicate(pred: Dictionary) -> bool:
	if pred.is_empty():
		return false
	if pred.has("and"):
		return _eval_and(pred["and"])
	if pred.has("or"):
		return _eval_or(pred["or"])
	if pred.has("not"):
		return _eval_not(pred["not"])
	if pred.has("flag"):
		return _eval_flag(pred["flag"])
	if pred.has("object"):
		return _eval_object(pred["object"])
	push_warning("[WorldState] Unknown predicate keys: %s" % str(pred.keys()))
	return false


func _eval_and(sub: Variant) -> bool:
	if not (sub is Array):
		push_warning("[WorldState] 'and' value must be an Array.")
		return false
	for item: Variant in sub:
		if not (item is Dictionary):
			push_warning("[WorldState] 'and' element is not a Dictionary.")
			return false
		if not evaluate_predicate(item):
			return false
	return true


func _eval_or(sub: Variant) -> bool:
	if not (sub is Array):
		push_warning("[WorldState] 'or' value must be an Array.")
		return false
	for item: Variant in sub:
		if not (item is Dictionary):
			push_warning("[WorldState] 'or' element is not a Dictionary.")
			continue
		if evaluate_predicate(item):
			return true
	return false


func _eval_not(sub: Variant) -> bool:
	if not (sub is Dictionary):
		push_warning("[WorldState] 'not' value must be a Dictionary.")
		return false
	return not evaluate_predicate(sub)


func _eval_flag(checks: Variant) -> bool:
	if not (checks is Dictionary):
		push_warning("[WorldState] 'flag' value must be a Dictionary.")
		return false
	for key: String in checks:
		if get_flag(key) != checks[key]:
			return false
	return true


func _eval_object(checks: Variant) -> bool:
	if not (checks is Dictionary):
		push_warning("[WorldState] 'object' value must be a Dictionary.")
		return false
	for dotted: String in checks:
		var parts: PackedStringArray = dotted.split(".", false, 1)
		if parts.size() != 2:
			push_warning("[WorldState] 'object' key must be 'prop_id.field', got: %s" % dotted)
			return false
		var obj: Dictionary = get_object(parts[0])
		if obj.get(parts[1], null) != checks[dotted]:
			return false
	return true
