class_name AgentMemory
## What the game knows about an agent's history that the LLM session does
## NOT. Deliberately minimal: session memory (OpenClaw/Hermes) is the
## authoritative record of every word said; this class only stores the
## boolean + scalar state the game itself needs to reason about (first
## visit, first meeting, which props have been noticed, how interesting
## each prop still is). Persists to user://saves/.

const SAVES_DIR := "user://saves/"
## Minimum seconds between disk writes per agent. Rapid-fire events
## (observation + emotion delta + peer encounter in the same second)
## used to trigger 3+ sync JSON writes, each stalling the main thread
## 1-3ms on WSL2. We now debounce: a save request within this window
## just marks the memory dirty; the next real save past the window
## flushes. Worst-case loss on crash is DEBOUNCE_SECONDS of state.
const DEBOUNCE_SECONDS := 5.0

var agent_id: String = ""
var seen_entities: Dictionary = {}      # entity_id -> true
var entity_interest: Dictionary = {}    # entity_id -> float (decays on each sighting)
var visited_locations: Dictionary = {}  # location_id -> true
var met_agents: Dictionary = {}         # other_agent_id -> true

var _dirty: bool = false
var _last_save_time: float = -INF

# The last world the agent's session received a prompt for. On arrival
# the coordinator reads this to decide between same-world skip (no
# prompt), cross-world transition (new or familiar), or first-ever
# launch (previous == ""). Stamped on every real arrival.
var last_world_id: String = ""
var last_world_name: String = ""


static func create(id: String) -> AgentMemory:
	var mem := AgentMemory.new()
	mem.agent_id = id
	return mem


# ── Mutation ──────────────────────────────────────────────────────────────

func add_observation(entity_id: String) -> void:
	seen_entities[entity_id] = true
	var current: float = entity_interest.get(entity_id, 1.0)
	entity_interest[entity_id] = current * GameState.get_float("interest_decay", 0.5)


func visit_location(location_id: String) -> void:
	visited_locations[location_id] = true


func mark_met(other_agent_id: String) -> void:
	met_agents[other_agent_id] = true


# ── Queries ───────────────────────────────────────────────────────────────

func has_seen(entity_id: String) -> bool:
	return seen_entities.has(entity_id)


func has_met(other_agent_id: String) -> bool:
	return met_agents.has(other_agent_id)


func get_interest(entity_id: String) -> float:
	return entity_interest.get(entity_id, 1.0)


## Story 004 / F3 — refresh the compound-key interest for a specific layer of
## prop_id when an agent newly qualifies for that layer (Formula 3). The key
## format "layer:<prop_id>:<layer_idx>" separates per-layer decay from the
## bare prop-level interest. Delta from game_config.defaults.interest_refresh_on_new_layer.
func refresh_layer_interest(prop_id: String, layer_idx: int) -> void:
	var key: String = "layer:%s:%d" % [prop_id, layer_idx]
	var current: float = entity_interest.get(key, 0.0)
	entity_interest[key] = minf(current + GameState.get_float("interest_refresh_on_new_layer", 0.6), 1.0)


## Story 004 / F3 / TR-puzzle-028 — return the effective wander-interest for
## prop_id: the maximum of the bare key interest and the highest layer-key
## interest across all layer indices stored for this prop.
## Falls back to get_interest(prop_id) when no layer keys exist for the prop.
func get_prop_interest(prop_id: String) -> float:
	var bare: float = get_interest(prop_id)
	var prefix: String = "layer:%s:" % prop_id
	var best_layer: float = bare
	for key: String in entity_interest:
		if key.begins_with(prefix):
			var val: float = entity_interest.get(key, 0.0)
			if val > best_layer:
				best_layer = val
	return best_layer


# ── Persistence ───────────────────────────────────────────────────────────

func save_to_disk(force: bool = false) -> void:
	_dirty = true
	var now: float = Time.get_ticks_msec() / 1000.0
	if not force and now - _last_save_time < DEBOUNCE_SECONDS:
		return
	_flush_to_disk()


func _flush_to_disk() -> void:
	if not _dirty:
		return
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var path := SAVES_DIR + agent_id + "_memory.json"
	var data := {
		"agent_id": agent_id,
		"seen_entities": seen_entities.keys(),
		"entity_interest": entity_interest,
		"visited_locations": visited_locations.keys(),
		"met_agents": met_agents.keys(),
		"last_world_id": last_world_id,
		"last_world_name": last_world_name,
	}
	GameState.save_json(path, data)
	_last_save_time = Time.get_ticks_msec() / 1000.0
	_dirty = false


static func load_from_disk(id: String) -> AgentMemory:
	var mem := AgentMemory.create(id)
	var path := SAVES_DIR + id + "_memory.json"
	var data := GameState.load_json(path)
	if data.is_empty():
		return mem
	for eid in data.get("seen_entities", []):
		mem.seen_entities[eid] = true
	mem.entity_interest = data.get("entity_interest", {})
	for lid in data.get("visited_locations", []):
		mem.visited_locations[lid] = true
	for mid in data.get("met_agents", []):
		mem.met_agents[mid] = true
	mem.last_world_id = data.get("last_world_id", "")
	mem.last_world_name = data.get("last_world_name", "")
	return mem
