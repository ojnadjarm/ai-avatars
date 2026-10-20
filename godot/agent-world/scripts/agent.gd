class_name Agent
extends CharacterBody2D

@export var agent_id: String = ""
@export var display_name: String = ""
@export var interactions: bool = true
@export var wandering: bool = true

# Behavior tuning — populated from game_config.defaults in _ready.
# @export defaults exist only as a fallback if a config key is missing.
var move_speed: float = 100.0
var observe_radius: float = 300.0
var encounter_radius: float = 220.0
var idle_decay_interval: float = 2.5
var wander_pause_range: Vector2 = Vector2(0.5, 2.0)

# Ambient wander brain (AgentWander) — owns destination selection, walk
# texture (speed jitter, sway, change of mind), and dwell/look-around
# behavior. This node keeps the layers below it: planner, execution,
# recovery. _walk_is_wander tags the active walk so texture and arrival
# dwell only apply to wander walks — summon/meeting walks stay crisp.
var wander_brain: AgentWander = AgentWander.new()
var _walk_is_wander: bool = false

# Movement feel — acceleration-limited SPEED (magnitude only) plus a
# two-radius arrival profile (slow radius with a speed floor, then the
# existing 6px arrival snap). Direction is deliberately NOT smoothed:
# smoothing the velocity vector gives the agent a turning radius
# (v²/accel ≈ 11px at cruise) larger than the 6px arrival tolerance,
# and the agent orbits its waypoint forever — observed live as growing
# paths, phantom wedge escapes, and an agent that never dwells. Speed
# ramps give the ease-in/ease-out; path curvature comes from the wander
# sway instead. Loaded from defaults in _load_defaults().
var _accel: float = 450.0
var _arrival_slow_radius: float = 60.0
var _arrival_speed_floor: float = 0.3
var _smoothed_speed: float = 0.0

enum State { IDLE, WALKING, OBSERVING, TALKING, ENCOUNTERING }

## Emitted once when the agent reaches the player after being called via
## summon_to — world_loader uses this to open the chat at the right moment.
signal call_arrived
var current_state: int = State.IDLE

var target_position: Vector2 = Vector2.ZERO
var has_target: bool = false
var stuck_timer: float = 0.0
var last_position: Vector2 = Vector2.ZERO
var idle_timer: float = 0.0
var idle_decay_accumulator: float = 0.0
var facing: String = "down"
var current_mood: String = "neutral"

# Edge-tracked proximity sets. Keyed by entity id, present while currently
# in range. Used to enforce "one roll per approach" for both prop
# observation and agent encounters: a roll happens on the frame an entity
# enters range, never again until it leaves and re-enters.
var _peer_in_proximity: Dictionary = {}
var _prop_in_range: Dictionary = {}

# Emotion engine (client-side, initialized from baseline)
var emotion_engine: EmotionEngine = EmotionEngine.new()

# Memory (client-side, persists to user://saves/)
var memory: AgentMemory = null

# Mood visuals
var mood_aura: Sprite2D
var _idle_tween: Tween
var _aura_tween: Tween
# Cached once to avoid per-call CircleShape2D/PhysicsShapeQueryParameters2D
# allocation in _segment_is_clear. Godot physics shapes are RID-backed server
# resources; churning them per frame leaks into the physics server pool and
# persists even after process exit under WSL2.
var _cast_shape: CircleShape2D = null
var _cast_query: PhysicsShapeQueryParameters2D = null
# Reusable exclusion buffer — refilled in-place each call instead of allocating
# a fresh Array[RID]. LOS checks fire dozens of times per Theta* plan; the old
# per-call allocation was the dominant source of per-frame object churn.
var _excl_buf: Array[RID] = []

# RVO avoidance — dynamic agent-vs-agent via NavigationAgent2D. The
# navigation mesh is NOT used; only the avoidance half of the node. Each
# physics frame we feed the agent a desired velocity, then apply the safe
# velocity the solver returned on the *previous* frame to move_and_slide().
# This 1-frame lag is negligible (16ms at 60Hz) and keeps movement robust
# even if the velocity_computed signal is late or never fires on a frame.
var nav_agent: NavigationAgent2D
var _safe_velocity: Vector2 = Vector2.ZERO

# Cached room data (built once on _ready). Bounds are always overwritten
# by _cache_room_data from the world_loader's room_bounds.
var _cached_props: Array = []
var _room_min: Vector2 = Vector2.ZERO
var _room_max: Vector2 = Vector2.ZERO
var _player_camera: Camera2D = null

# Pathfinding grid — built once on spawn via physics shape queries.
# Walls are static, so the grid is built once and never refreshed.
# _nav_grid is a dict of Vector2i → true for every walkable cell;
# the search operates directly on this dict instead of going through
# Godot's AStar2D. We dropped AStar2D during the walking-algorithm
# refactor because Theta* needs its own search that interleaves
# line-of-sight checks with node expansion — that requirement is not
# something AStar2D exposes.
var _nav_grid: Dictionary = {}
## Walkable cells whose centre is blocked but an offset point inside the cell is clear (narrow decks): Vector2i → Vector2.
var _cell_anchor: Dictionary = {}
var _grid_origin: Vector2 = Vector2.ZERO
var _grid_cell_size: float = 40.0
var _grid_cols: int = 0
var _grid_rows: int = 0

# Flow field for meeting mode. Built once on join_meeting via BFS
# from the anchor's cell through the walkable grid, stored as
# {Vector2i: distance_in_cells}. Every walkable cell reachable from
# the anchor has an entry; unreachable cells are absent. Agents
# consult the field when Theta* can't produce a path (usually
# because peers disconnect the grid locally) — reading the gradient
# at the current cell gives a guaranteed non-zero, obstacle-aware
# direction that naturally curves around walls. Flow fields are the
# textbook solution for many-agents-to-one-point convergence, and
# they replace the straight-line "seek anchor" fallback that was
# producing the "still looks like straight lines" bug.
var _flow_field: Dictionary = {}
var _flow_field_source_cell: Vector2i = Vector2i(-999, -999)

# Current path the agent is executing. _path_points is the smoothed
# waypoint list in world space; _path_index is the next one to reach.
# _goal_position keeps the original request so the supervisor can
# replan from the current pose rather than the stale waypoint.
var _path_points: Array[Vector2] = []
var _path_index: int = 0
var _goal_position: Vector2 = Vector2.ZERO
var _has_goal: bool = false

# Movement supervisor — watches per-frame distance-to-waypoint. When
# progress stalls for _stall_threshold seconds we replan from here;
# after _MAX_REPLANS consecutive failures we drop back to IDLE. The
# counters reset whenever the agent advances a waypoint, so crossing
# even one counts as real progress.
var _stall_timer: float = 0.0
var _stall_last_distance: float = INF
var _stall_threshold: float = 0.6
var _replan_attempts: int = 0
const _MAX_REPLANS: int = 3

# Hard throttle on Theta* invocations. When the player blocks an agent's
# path, stall-recovery and idle-wander otherwise fire Theta* 5-10× per
# second per agent — with 3 agents on a 1452-cell grid that burns FPS
# catastrophically. This throttle guarantees at most ~5 plans/sec/agent.
# When throttled, callers keep the existing path (or no path if none).
#
# The per-agent phase offset (added in _load_defaults from the id hash)
# prevents all three agents from ticking their plan windows in lockstep
# — without it, multiple agents can replan on the same physics frame,
# producing a visible single-frame stutter even though each individual
# plan is under budget.
var _last_plan_time: float = -1000.0
var _plan_phase_offset: float = 0.0
const _MIN_PLAN_INTERVAL: float = 0.2

# Reusable Theta* scratch state — cleared at the start of each plan
# instead of allocated. Without this, every plan creates 4 Dictionaries
# + 2 Arrays that become garbage immediately, producing the 400+ object
# allocations per replan storm that showed up as the FPS cliff.
# Parallel arrays for the heap (one float, one Vector2i) avoid the
# sub-array allocation of [f, cell] pair tuples.
var _theta_g: Dictionary = {}
var _theta_parent: Dictionary = {}
var _theta_closed: Dictionary = {}
var _theta_open_f: Array[float] = []
var _theta_open_cell: Array[Vector2i] = []

# Summon / follow mode — set by world_loader when the player "calls"
# a single agent. _summon_target is a live Node2D we chase; every
# tick we replan toward its current position if it has drifted from
# where we last aimed, and stop when we're within _summon_stop_distance.
# _summon_replan_cooldown throttles failed replans so unreachable
# targets don't cause a replan storm. Mutually exclusive with meeting.
var _summon_target: Node2D = null
var _summon_stop_distance: float = 180.0
var _summon_last_plan_pos: Vector2 = Vector2.ZERO
var _summon_replan_cooldown: float = 0.0
# Base replan throttle (seconds) shared by summon + meeting follow loops.
# Loaded from defaults.agent_replan_cooldown in _load_defaults().
var _replan_cooldown_base: float = 0.3

# Meeting mode — zone-based. Instead of a pre-assigned landing
# point, the agent is told "be within _meeting_radius of the
# anchor on any walkable, uncrowded spot." The agent picks its
# own landing dynamically via _pick_meeting_landing, which prefers
# the agent's current position if it already qualifies (so an
# agent that's already near the user doesn't march off to hit a
# stale precomputed slot). While _meeting_anchor is non-null the
# agent refuses to wander, observe props, or initiate encounters.
var _meeting_anchor: Node2D = null
var _meeting_radius: float = 220.0
var _meeting_held: bool = false
var _meeting_replan_cooldown: float = 0.0
# Consecutive plan failures to a picked landing. Drives the retry
# backoff in _meeting_backoff_for_fails(); reset on any successful
# plan or arrival. There is no ceiling that drops the agent out
# of the meeting — the agent stays committed indefinitely and just
# retries less aggressively when blocked.
var _meeting_fail_count: int = 0

# Planning override — when true, _is_peer_stationary treats EVERY
# peer as a blocker, forcing the planner to curve around every
# agent regardless of state. Flipped on briefly during stall
# recovery in meeting mode so a second replan can thread a path
# around peers the first attempt couldn't dodge.
var _plan_strict_blockers: bool = false

# Queued meeting — set by queue_meeting() when call_all fires while
# the agent is in a social state. Consumed by _consume_pending_meeting
# from the three exit hooks (finish_activity / stop_talking /
# mark_encounter_ended), so a busy agent auto-joins the meeting as
# soon as its current activity completes.
var _meeting_pending_anchor: Node2D = null
var _meeting_pending_radius: float = 0.0

# Proactive peer-stuck detection for free walking. When two agents
# wedge together, RVO can't find safe velocity and the stall
# supervisor needs 0.4-0.6s to notice. This check fires earlier (at
# stuck_timer > 0.15) whenever a peer is inside crowding range, and
# splices a short escape waypoint in front of the current one.
# 0.5s cooldown prevents thrashing. Disabled in meeting mode — held
# peers are intentional there.
var _peer_peel_cooldown: float = 0.0
const _PEER_PEEL_RESET: float = 0.5
const _PEER_PEEL_STUCK_TIME: float = 0.15

# Wedge recovery — persistent stuck detector that survives _walk_to()
# resets. When the agent has stayed inside _WEDGE_PIN_RADIUS of
# _wedge_anchor for _WEDGE_DETECT_TIME while WALKING with a goal, we
# attempt LOCAL tactical recovery only:
#   1. Waypoint-skip — if the segment from here to path[i+1] is clear,
#      advance past the wedged waypoint. Cuts corner-clip diagonals.
#   2. Perpendicular nudge — step ~1 body width sideways and re-approach
#      from a fresh angle.
# If both fail we bail and arm a cooldown so the higher-level driver
# (summon target moving, peers shifting) can change the situation
# organically. We never send the agent more than 1 body width from
# its wedge spot — Theta* already finds the right global path; this
# layer only unsticks local body-collision wedges.
var _wedge_anchor: Vector2 = Vector2.INF
var _wedge_anchor_timer: float = 0.0
var _wedge_escape_cooldown: float = 0.0
const _WEDGE_DETECT_TIME: float = 1.5
const _WEDGE_PIN_RADIUS_MULT: float = 1.0
const _WEDGE_PROGRESS_RADIUS_MULT: float = 2.0
const _WEDGE_NUDGE_DIST_MULT: float = 1.0
const _WEDGE_ESCAPE_COOLDOWN: float = 3.0

# Injected by world_loader before the agent is added to the tree.
var world_loader: WorldLoader
var player: CharacterBody2D
var props_container: Node2D
var display_height: float = 140.0

# Thoughts the agent has had that the player hasn't seen yet. Drained when
# the player opens a chat with this agent — that's the "here's what I
# noticed while you were away" scrollback.
var _unread_thoughts: Array = []
var _thought_bubble: ThoughtBubble
var _mood_popup: Label
var _mood_popup_tween: Tween


func _ready() -> void:
	_load_defaults()
	wander_brain.setup(self)
	if interactions or wandering:
		call_deferred("_cache_room_data")
	_create_mood_aura()
	_create_thought_bubble()
	_create_mood_popup()
	_setup_navigation()
	emotion_engine.mood_changed.connect(_on_mood_changed)


func _exit_tree() -> void:
	# Godot tweens are owned by the SceneTree, not the node that created them.
	# Looping tweens (the mood-idle bounce) run forever unless killed — if the
	# agent is freed without explicit kill, the tween keeps firing property
	# sets against a freed reference, consuming scheduler time every frame
	# across the entire session. Same for the aura tween.
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null
	if _aura_tween and _aura_tween.is_valid():
		_aura_tween.kill()
	_aura_tween = null
	if _mood_popup_tween and _mood_popup_tween.is_valid():
		_mood_popup_tween.kill()
	_mood_popup_tween = null
	_cached_props.clear()
	_peer_in_proximity.clear()
	_prop_in_range.clear()
	_nav_grid.clear()
	_cell_anchor.clear()
	_flow_field.clear()
	_excl_buf.clear()
	_theta_g.clear()
	_theta_parent.clear()
	_theta_closed.clear()
	_theta_open_f.clear()
	_theta_open_cell.clear()
	# Debounced saves may have queued state not yet written — flush before
	# the agent (and its memory) is destroyed so nothing is lost on shutdown
	# or world transition.
	if memory and not WorldBuilder.offline:
		memory._flush_to_disk()


func _load_defaults() -> void:
	# Stagger the replan window per agent so 3 agents that all want to
	# replan in the same time slice land on different physics frames.
	# Offset in [0, _MIN_PLAN_INTERVAL) derived from the id hash.
	_plan_phase_offset = float(absi(agent_id.hash()) % 100) / 100.0 * _MIN_PLAN_INTERVAL
	move_speed = WorldBuilder.walk_speed(get_node_or_null("CharSprite") as AnimatedSprite2D, GameState.get_float("agent_move_speed", move_speed))
	observe_radius = GameState.get_float("observe_radius", observe_radius)
	encounter_radius = GameState.get_float("encounter_radius", encounter_radius)
	idle_decay_interval = GameState.get_float("idle_decay_interval", idle_decay_interval)
	_replan_cooldown_base = GameState.get_float("agent_replan_cooldown", _replan_cooldown_base)
	wander_pause_range = GameState.get_range("wander_pause_range", wander_pause_range)
	_accel = GameState.get_float("agent_acceleration", _accel)
	_arrival_slow_radius = GameState.get_float("arrival_slow_radius", _arrival_slow_radius)
	_arrival_speed_floor = GameState.get_float("arrival_speed_floor", _arrival_speed_floor)


func _setup_navigation() -> void:
	# RVO2 avoidance only — no baked NavigationRegion2D. We feed the agent
	# a desired velocity each physics frame; the velocity_computed signal
	# writes back a safe_velocity we apply next frame.
	#
	# Radius must fully encompass the feet circle (FOOT_RADIUS in
	# agent_spawner), otherwise the solver plans for a smaller body than
	# physics enforces and agents jam mid-step. 2x gives a 6px buffer.
	nav_agent = NavigationAgent2D.new()
	nav_agent.avoidance_enabled = true
	nav_agent.radius = WorldBuilder.FOOT_RADIUS * 2.0
	nav_agent.max_speed = move_speed * 1.5
	nav_agent.neighbor_distance = 200.0
	nav_agent.max_neighbors = 8
	nav_agent.time_horizon_agents = 1.5
	# Hash-based priority jitter in [0.5, 1.0] — keeps every agent in an
	# "active" priority band while still giving them unique tie-breakers so
	# the RVO solver can't deadlock on perfectly symmetric head-on approaches.
	nav_agent.avoidance_priority = 0.5 + float(absi(agent_id.hash()) % 100) / 200.0
	nav_agent.velocity_computed.connect(_on_nav_velocity_computed)
	add_child(nav_agent)


func _create_thought_bubble() -> void:
	_thought_bubble = ThoughtBubble.new()
	_thought_bubble.position = Vector2(0, -display_height * 0.55)
	add_child(_thought_bubble)


func _create_mood_popup() -> void:
	# Emoji label that briefly appears above the vessel's head when the derived
	# mood transitions. Sits slightly higher than the thought bubble so the two
	# never overlap.
	_mood_popup = Label.new()
	_mood_popup.add_theme_font_override("font", UITheme.emoji_font())
	_mood_popup.add_theme_font_size_override("font_size", 16)
	_mood_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mood_popup.position = Vector2(-8, roundf(-display_height * 0.8) - 28)
	_mood_popup.size = Vector2(16, 16)
	_mood_popup.pivot_offset = Vector2(8, 8)
	_mood_popup.modulate.a = 0.0
	_mood_popup.z_as_relative = false
	_mood_popup.z_index = 18
	add_child(_mood_popup)


func _on_mood_changed(new_mood: String) -> void:
	if not _mood_popup:
		return
	var emoji: String = UITheme.MOOD_EMOJI.get(new_mood, "")
	if emoji == "":
		return
	_mood_popup.text = emoji
	if _mood_popup_tween and _mood_popup_tween.is_valid():
		_mood_popup_tween.kill()
	_mood_popup.scale = Vector2(0.5, 0.5)
	_mood_popup.modulate.a = 0.0
	_mood_popup_tween = create_tween().set_parallel(true)
	_mood_popup_tween.tween_property(_mood_popup, "modulate:a", 1.0, 0.15)
	_mood_popup_tween.tween_property(_mood_popup, "scale", Vector2(1.2, 1.2), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_mood_popup_tween.chain().tween_property(_mood_popup, "scale", Vector2(1.0, 1.0), 0.1)
	_mood_popup_tween.chain().tween_interval(1.5)
	_mood_popup_tween.chain().tween_property(_mood_popup, "modulate:a", 0.0, 0.4)


func show_thought(thought: String) -> void:
	if _thought_bubble:
		_thought_bubble.blink()
	_unread_thoughts.append(thought)


func drain_unread_thoughts() -> Array:
	var out := _unread_thoughts.duplicate()
	_unread_thoughts.clear()
	return out


func start_talking() -> void:
	current_state = State.TALKING


func stop_talking() -> void:
	if current_state == State.TALKING:
		current_state = State.IDLE
		_consume_pending_meeting()


func finish_activity() -> void:
	# Called after an action (observation or encounter) finishes for the
	# initiator. Drops state back to IDLE and seeds a short pause before
	# the next wander target. The global ActivityGate is the only thing
	# that limits new actions.
	if current_state == State.OBSERVING or current_state == State.ENCOUNTERING:
		current_state = State.IDLE
	idle_timer = randf_range(1.0, 3.0)
	_consume_pending_meeting()


func enter_encountering() -> void:
	# Called on the NON-INITIATOR when the dispatcher starts a multi-turn
	# encounter. Freezes them in place so they can't wander off mid
	# conversation.
	velocity = Vector2.ZERO
	has_target = false
	current_state = State.ENCOUNTERING


func mark_encounter_ended() -> void:
	# Called on the NON-INITIATOR when the full encounter completes. Drops
	# their ENCOUNTERING state back to IDLE with a short pause.
	if current_state == State.ENCOUNTERING:
		current_state = State.IDLE
		idle_timer = randf_range(1.0, 3.0)
	_consume_pending_meeting()


func _cache_room_data() -> void:
	if world_loader and world_loader.room_bounds.size != Vector2.ZERO:
		var bounds: Rect2 = world_loader.room_bounds
		var inset := 20.0
		_room_min = bounds.position + Vector2(inset, inset)
		_room_max = bounds.end - Vector2(inset, inset)
	if props_container:
		for child in props_container.get_children():
			if child is Area2D and "prop_id" in child and child.prop_id != "":
				_cached_props.append(child)
	print("[agent:%s] %d props cached" % [display_name, _cached_props.size()])
	_build_nav_grid()


func _update_label_scale() -> void:
	# Keep the name label readable regardless of camera zoom by counter-scaling it.
	var label := get_node_or_null("NameLabel") as Label
	if not label:
		return
	if not is_instance_valid(_player_camera) and player:
		_player_camera = player.get_node_or_null("Camera2D") as Camera2D
	if not _player_camera:
		return
	var zoom: float = _player_camera.zoom.x
	if zoom <= 0.0:
		return
	# Exactly 1/zoom: the label then draws at the integer stretch factor, so pixel fonts stay crisp.
	var s: float = 1.0 / zoom
	label.scale = Vector2(s, s)


func _create_mood_aura() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, UITheme.MOOD_AURA_GRADIENT_INNER)
	gradient.set_color(1, UITheme.MOOD_AURA_GRADIENT_OUTER)
	gradient.set_offset(1, 1.0)
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = gradient
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(0.5, 0.0)
	grad_tex.width = 64
	grad_tex.height = 64
	mood_aura = Sprite2D.new()
	mood_aura.name = "MoodAura"
	mood_aura.texture = grad_tex
	mood_aura.z_index = -1
	mood_aura.modulate = UITheme.MOOD_AURA_HIDDEN
	add_child(mood_aura)


func set_mood(mood: String) -> void:
	current_mood = mood
	_update_aura(mood)
	_start_idle_tween(mood)


func _update_aura(mood: String) -> void:
	if not mood_aura:
		return
	var color: Color = _mood_aura_color(mood)
	if _aura_tween and _aura_tween.is_valid():
		_aura_tween.kill()
	_aura_tween = create_tween()
	_aura_tween.tween_property(mood_aura, "modulate", color, 0.5)


static func _mood_speed_multiplier(mood: String) -> float:
	var cfg: Variant = GameState.get_default("mood_speed", {})
	if cfg is Dictionary:
		return float(cfg.get(mood, 1.0))
	return 1.0


static func _mood_aura_color(mood: String) -> Color:
	var cfg: Variant = GameState.get_default("mood_aura", {})
	if cfg is Dictionary and cfg.has(mood):
		var rgba: Array = cfg[mood]
		if rgba.size() == 4:
			return Color(rgba[0], rgba[1], rgba[2], rgba[3])
	return UITheme.MOOD_AURA_HIDDEN


func _start_idle_tween(mood: String) -> void:
	if _idle_tween:
		_idle_tween.kill()
		_idle_tween = null
	var sprite := get_node_or_null("CharSprite")
	if not sprite:
		return
	sprite.position = Vector2.ZERO
	match mood:
		"happy":
			_idle_tween = create_tween().set_loops()
			_idle_tween.tween_property(sprite, "position:y", -2.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
			_idle_tween.tween_property(sprite, "position:y", 0.0, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		"frustrated":
			_idle_tween = create_tween().set_loops()
			_idle_tween.tween_property(sprite, "position:x", 1.0, 0.08)
			_idle_tween.tween_property(sprite, "position:x", -1.0, 0.08)
			_idle_tween.tween_property(sprite, "position:x", 0.0, 0.08)
			_idle_tween.tween_interval(2.0)
		"curious":
			_idle_tween = create_tween().set_loops()
			_idle_tween.tween_property(sprite, "position:x", 1.5, 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			_idle_tween.tween_property(sprite, "position:x", 0.0, 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			_idle_tween.tween_interval(1.5)
		"excited":
			_idle_tween = create_tween().set_loops()
			_idle_tween.tween_property(sprite, "position:y", -3.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			_idle_tween.tween_property(sprite, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
			_idle_tween.tween_interval(0.3)


func _physics_process(delta: float) -> void:
	_update_label_scale()

	var desired_velocity := Vector2.ZERO

	# Static mode — no movement, no AI, just handle talking.
	if not interactions and not wandering:
		_apply_movement(desired_velocity)
		if current_state != State.TALKING:
			_play_anim("idle")
		return

	# Meeting > summon > state machine. Meeting mode and summon mode
	# are mutually exclusive. Both tick before the state machine so an
	# active follow/replan can retarget the current path on this same
	# frame when the player moves.
	if _meeting_anchor != null:
		_tick_meeting(delta)
	elif _summon_target != null:
		_tick_summon(delta)

	match current_state:
		State.WALKING:
			# Change-of-mind ticks first — it may drop the target, and
			# the no-target branch below handles the fallout this frame.
			if _walk_is_wander:
				wander_brain.tick_walk(delta)
			if not has_target:
				_finish_walk_idle()
			else:
				var distance := global_position.distance_to(target_position)
				if distance < 6.0 and not _advance_waypoint():
					has_target = false
					_has_goal = false
					_path_points.clear()
					_finish_walk_idle()
					_play_anim("idle")
				else:
					distance = global_position.distance_to(target_position)
					var direction := (target_position - global_position).normalized()
					var speed: float = move_speed * _mood_speed_multiplier(current_mood)
					if _walk_is_wander:
						# Wander texture: per-walk cruise jitter + slow
						# noise surge, and a simplex heading sway that
						# bows the path. Sway damps to zero across the
						# arrival slow radius so landings stay clean.
						speed *= wander_brain.speed_scale()
						var sway_damp: float = 1.0
						if _path_index >= _path_points.size() - 1:
							sway_damp = clampf(distance / _arrival_slow_radius, 0.0, 1.0)
						direction = direction.rotated(wander_brain.sway_angle() * sway_damp)
					# Two-radius arrival: ramp down across the slow
					# radius toward the final goal only — mid-path
					# corners shouldn't dawdle at every turn. The floor
					# keeps the last stretch from crawling.
					if _path_index >= _path_points.size() - 1 and distance < _arrival_slow_radius:
						speed *= maxf(distance / _arrival_slow_radius, _arrival_speed_floor)
					desired_velocity = direction * speed
					_update_facing(direction)
					_play_anim("walk")
					_tick_supervisor(delta, distance)
					# Proactive peer peel, free walking only. Meeting
					# mode relies on RVO + distinct slots; held agents
					# are intentional crowders and must not be peeled.
					if _meeting_anchor == null:
						_peer_peel_cooldown -= delta
						if _peer_peel_cooldown <= 0.0:
							_check_peer_crowding()
			# Wander/observe/encounter rolls are autonomous behavior;
			# during a meeting the agent is explicitly held so those
			# rolls must not fire.
			if interactions and _meeting_anchor == null:
				_check_nearby_props()
				_check_nearby_agents()

		State.IDLE:
			_play_anim("idle")
			if interactions and _meeting_anchor == null:
				idle_decay_accumulator += delta
				if idle_decay_accumulator >= idle_decay_interval:
					emotion_engine.process_event("idle", {"turns": 1})
					idle_decay_accumulator = 0.0
				_check_nearby_props()
				_check_nearby_agents()
			if wandering and _meeting_anchor == null and _summon_target == null:
				wander_brain.tick_dwell(delta)
			idle_timer -= delta
			if idle_timer <= 0.0 and wandering and _meeting_anchor == null:
				wander_brain.start_wander()

		State.OBSERVING, State.TALKING, State.ENCOUNTERING:
			_play_anim("idle")

	_apply_movement(desired_velocity)


func _apply_movement(desired: Vector2) -> void:
	# Acceleration-limited SPEED: the commanded speed ramps toward the
	# desired magnitude at _accel px/s² (ease-in from rest, ease-out
	# into the arrival ramp) while the direction is taken verbatim —
	# exact-direction convergence is what guarantees waypoints are
	# actually reached (see the note on _smoothed_speed). Stops stay
	# instant — a zero desired clears everything so talk freezes and
	# arrival snaps never drift. The smoothed command (not the raw
	# desired) is handed to the nav agent for this frame's RVO pass; we
	# then move using whatever safe velocity the solver returned on the
	# previous frame.
	if desired == Vector2.ZERO:
		_smoothed_speed = 0.0
		nav_agent.velocity = Vector2.ZERO
		velocity = Vector2.ZERO
	else:
		_smoothed_speed = move_toward(
			_smoothed_speed, desired.length(), _accel * get_physics_process_delta_time()
		)
		var commanded: Vector2 = desired.normalized() * _smoothed_speed
		nav_agent.velocity = commanded
		velocity = _safe_velocity if _safe_velocity != Vector2.ZERO else commanded
	move_and_slide()
	if current_state == State.WALKING:
		# Fast position-based stall check — fires when physics has us
		# wedged and velocity collapsed to zero. _tick_supervisor covers
		# the slower "distance-to-waypoint isn't shrinking" case; both
		# route through _handle_stall which replans the path.
		if global_position.distance_to(last_position) < 0.5:
			stuck_timer += get_physics_process_delta_time()
			# Was 0.4s — raised to 1.0s to stop racing with the distance
			# supervisor (_stall_threshold = 0.6s). Two detectors at ~0.5s
			# were firing Theta* back-to-back when the player stood near
			# an agent mid-walk.
			if stuck_timer > 1.0:
				stuck_timer = 0.0
				_handle_stall()
		else:
			stuck_timer = 0.0
		_tick_wedge_tracker(get_physics_process_delta_time())
	last_position = global_position


func _nearest_crowding_peer() -> Agent:
	# Returns the closest peer within ~1.1 * collision-shape width, or
	# null. Used by _handle_stall to distinguish physical-contact
	# stalls (where replanning alone can't help) from geometry stalls.
	var crowd_radius: float = display_height * 1.1
	var best: Agent = null
	var best_dist: float = crowd_radius
	if not world_loader or not world_loader.agents_container:
		return null
	for other: Node in world_loader.agents_container.get_children():
		if other == self or not is_instance_valid(other) or not (other is Agent):
			continue
		var peer: Agent = other
		var d: float = global_position.distance_to(peer.global_position)
		if d < best_dist:
			best_dist = d
			best = peer
	return best


func _peel_direction(crowder: Agent) -> Vector2:
	# Direction to sidestep a crowding peer. The raw "away from
	# crowder" vector flips to 180° when the crowder is in front of
	# our heading, producing a visible backward jog mid-walk. We
	# strip the backward component against the current heading so
	# the nudge always moves laterally or forward. Returns ZERO when
	# the crowder is already behind us (no peel needed).
	var away: Vector2 = (global_position - crowder.global_position).normalized()
	if away == Vector2.ZERO:
		return Vector2.ZERO
	var heading: Vector2 = Vector2.ZERO
	if has_target:
		heading = (target_position - global_position).normalized()
	if heading == Vector2.ZERO and velocity.length() > 1.0:
		heading = velocity.normalized()
	if heading == Vector2.ZERO:
		return away
	var along: float = away.dot(heading)
	if along >= 0.0:
		return Vector2.ZERO
	var tangential: Vector2 = away - heading * along
	if tangential.length_squared() < 0.01:
		var side: float = 1.0 if randf() > 0.5 else -1.0
		tangential = Vector2(-heading.y, heading.x) * side
	return tangential.normalized()


func _segment_is_clear(a: Vector2, b: Vector2) -> bool:
	# Shape-cast a circle of agent radius along the segment. A thin
	# raycast would happily pass through gaps narrower than the
	# agent's body, so path smoothing would shortcut into walls the
	# body can't physically traverse. cast_motion returns
	# [safe_fraction, unsafe_fraction]; 1.0 means the full sweep is
	# clear. Other agents are excluded — RVO handles dynamic
	# separation while we walk.
	if a.distance_squared_to(b) < 1.0:
		return true
	var space := get_world_2d().direct_space_state
	if _cast_shape == null:
		_cast_shape = CircleShape2D.new()
		_cast_query = PhysicsShapeQueryParameters2D.new()
		_cast_query.shape = _cast_shape
		_cast_query.collide_with_bodies = true
		_cast_query.collide_with_areas = false
	_cast_shape.radius = WorldBuilder.FOOT_RADIUS
	_cast_query.transform = Transform2D(0.0, a)
	_cast_query.motion = b - a
	_cast_query.exclude = _dynamic_body_exclusions()
	var result: PackedFloat32Array = space.cast_motion(_cast_query)
	if result.size() < 2:
		return false
	return result[0] >= 0.999


func _dynamic_body_exclusions() -> Array[RID]:
	_excl_buf.clear()
	_excl_buf.append(get_rid())
	if world_loader and world_loader.agents_container:
		for other: Node in world_loader.agents_container.get_children():
			if other != self and other is CharacterBody2D:
				_excl_buf.append((other as CharacterBody2D).get_rid())
	if player:
		_excl_buf.append(player.get_rid())
	return _excl_buf


func _on_nav_velocity_computed(safe_velocity: Vector2) -> void:
	_safe_velocity = safe_velocity


func _check_nearby_props() -> void:
	# One observation roll per "approach" — when a prop transitions into
	# observe range. Probability == current interest. Interest halves on
	# each successful observation; below 10% the prop is ignored entirely.
	for prop in _cached_props:
		if not is_instance_valid(prop):
			continue
		var pid: String = prop.prop_id
		var in_range: bool = global_position.distance_to(prop.global_position) < observe_radius
		if not in_range:
			_prop_in_range.erase(pid)
			continue
		if _prop_in_range.has(pid):
			continue
		var interest: float = memory.get_interest(pid)
		if interest < 0.1:
			continue
		if not world_loader.activity_gate.can_trigger():
			continue
		_prop_in_range[pid] = true
		if randf() < interest:
			_observe_prop(prop)
			return


func _check_nearby_agents() -> void:
	# One encounter roll per "approach" — when a peer transitions into
	# encounter range. Flat 25% probability. Only the lexicographically
	# lower agent_id rolls per pair so the joint chance stays at 25%
	# instead of compounding when both agents check on the same frame.
	if not world_loader.agents_container:
		return
	for other in world_loader.agents_container.get_children():
		if other == self or not is_instance_valid(other) or not (other is Agent):
			continue
		var peer: Agent = other
		var pid: String = peer.agent_id
		var in_range: bool = global_position.distance_to(peer.global_position) < encounter_radius
		if not in_range:
			_peer_in_proximity.erase(pid)
			continue
		if _peer_in_proximity.has(pid):
			continue
		if agent_id >= pid:
			continue
		if peer.current_state != State.IDLE and peer.current_state != State.WALKING:
			continue
		if not peer.interactions:
			continue
		if not world_loader.activity_gate.can_trigger():
			continue
		_peer_in_proximity[pid] = true
		if randf() < 0.25:
			_start_encounter(peer)
			return


func _start_encounter(other: Agent) -> void:
	velocity = Vector2.ZERO
	has_target = false
	current_state = State.ENCOUNTERING
	print("[agent:%s] Encountering %s" % [display_name, other.display_name])
	if world_loader:
		world_loader.request_agent_encounter(agent_id, other.agent_id)


func _observe_prop(prop: Area2D) -> void:
	velocity = Vector2.ZERO
	has_target = false
	current_state = State.OBSERVING
	var current_interest: float = memory.get_interest(prop.prop_id)
	print("[agent:%s] Observing %s (%.0f%%)" % [display_name, prop.prop_name, current_interest * 100])
	var desc: String = prop.prop_description if "prop_description" in prop else ""
	if world_loader:
		world_loader.request_agent_observe(agent_id, prop.prop_id, prop.prop_name, desc)


func _finish_walk_idle() -> void:
	# Shared landing for every walk that ends inside the WALKING branch.
	# Wander walks hand dwell control to the brain (heavy-tailed dwell,
	# POI facing, look-around glances); everything else keeps the flat
	# configured pause.
	current_state = State.IDLE
	if _walk_is_wander:
		_walk_is_wander = false
		wander_brain.on_walk_finished()
	else:
		idle_timer = randf_range(wander_pause_range.x, wander_pause_range.y)


func begin_wander_walk(dest: Vector2) -> bool:
	# Entry point used by AgentWander. Routes through the same planner
	# as every other walk, then tags the walk so texture (speed jitter,
	# sway, change of mind) applies and completion hands dwell control
	# back to the brain. Returns false when no path could be planned.
	_walk_to(dest)
	_walk_is_wander = has_target
	return _walk_is_wander


func cancel_wander_walk() -> void:
	# Mid-walk change of mind — drop the path and goal; the WALKING
	# branch notices the missing target on this same frame and lands in
	# _finish_walk_idle with the generic short pause (the wander flag is
	# cleared here, so no arrival dwell/recency stamp fires — the agent
	# never actually arrived anywhere).
	if not _walk_is_wander:
		return
	_walk_is_wander = false
	_path_points.clear()
	_path_index = 0
	has_target = false
	_has_goal = false


func face_toward(point: Vector2) -> void:
	# Pure body language: turn to face a world point while idle. Used by
	# the wander brain for POI facing on arrival and dwell glances.
	var dir: Vector2 = point - global_position
	if dir.length_squared() < 1.0:
		return
	_update_facing(dir.normalized())
	_play_anim("idle")


func is_wanderable_point(p: Vector2) -> bool:
	# A valid wander destination: inside the (inset) room rect AND on a
	# walkable nav-grid cell. Ring samples around POIs are rejected, not
	# clamped — a clamped ring point would hug the bounds edge.
	if p.x < _room_min.x or p.x > _room_max.x or p.y < _room_min.y or p.y > _room_max.y:
		return false
	return _is_walkable_point(p)


func clamp_to_room(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, _room_min.x, _room_max.x),
		clampf(p.y, _room_min.y, _room_max.y),
	)


func _walk_to(pos: Vector2) -> void:
	# Public entry point for both wandering and external commands (the
	# player or another agent calling this one). Records the goal,
	# resets the replan counter, and hands off to the pathfinder. The
	# caller never has to care about obstacles — if the direct line is
	# blocked, the path will route around it. Every walk starts untagged;
	# begin_wander_walk re-tags it right after, so a summon or meeting
	# walk issued mid-wander silently drops the wander texture.
	_walk_is_wander = false
	_goal_position = pos
	_has_goal = true
	_replan_attempts = 0
	_plan_path_to(pos)


func summon_to(target: Node2D, stop_distance: float = 0.0) -> void:
	# Begin follow-mode toward a live Node2D (typically the player).
	# Refuses to interrupt an active social state or an active meeting
	# — the caller can retry later. stop_distance <= 0 means "use the
	# default body-width proximity".
	if target == null or not is_instance_valid(target):
		return
	if _meeting_anchor != null:
		return
	if is_socially_busy():
		return
	_summon_target = target
	_summon_stop_distance = stop_distance if stop_distance > 0.0 else maxf(150.0, display_height * 1.3)
	_summon_last_plan_pos = target.global_position
	_summon_replan_cooldown = 0.0
	_walk_to(target.global_position)


func _tick_summon(delta: float) -> void:
	# Per-frame follow loop. Cheap: just a distance check + an optional
	# throttled replan. The heavy lifting (pathfinding around obstacles)
	# happens inside _walk_to. Replans are gated by _summon_replan_cooldown
	# so an unreachable target can't trigger a replan every frame.
	if not is_instance_valid(_summon_target):
		_summon_target = null
		return
	var target_pos: Vector2 = _summon_target.global_position
	var d: float = global_position.distance_to(target_pos)
	if d <= _summon_stop_distance:
		_stop_and_face(target_pos)
		_summon_target = null
		call_arrived.emit()
		return
	_summon_replan_cooldown -= delta
	if _summon_replan_cooldown > 0.0:
		return
	# Replan if the target drifted from our last plan point, or if
	# we've fallen back to IDLE (path finished short, or the last
	# attempt aborted on unreachable geometry).
	var drifted: bool = target_pos.distance_to(_summon_last_plan_pos) > 30.0
	var idle_but_away: bool = current_state == State.IDLE and d > _summon_stop_distance + 50.0
	if drifted or idle_but_away:
		_summon_last_plan_pos = target_pos
		_summon_replan_cooldown = _replan_cooldown_base
		_walk_to(target_pos)


func _stop_and_face(face_target: Vector2) -> void:
	# Arrival stop: drop the path, zero velocity, turn to face the
	# target, and hand back to IDLE so the player can immediately
	# press [E] to talk.
	_path_points.clear()
	_path_index = 0
	has_target = false
	_has_goal = false
	_replan_attempts = 0
	velocity = Vector2.ZERO
	current_state = State.IDLE
	idle_timer = randf_range(0.5, 1.2)
	var dir: Vector2 = (face_target - global_position).normalized()
	if dir != Vector2.ZERO:
		_update_facing(dir)
	_play_anim("idle")


func is_socially_busy() -> bool:
	return (
		current_state == State.TALKING
		or current_state == State.ENCOUNTERING
		or current_state == State.OBSERVING
	)


func is_meeting_held() -> bool:
	return _meeting_held


## Return true if this agent has skill_id listed in GameState.agents[agent_id].skills.
## Pure read — does not mutate state. Safe to call off-tree (test context).
func has_skill(skill_id: String) -> bool:
	var agent_cfg: Variant = GameState.agents.get(agent_id, null)
	if not (agent_cfg is Dictionary):
		return false
	var skills: Variant = (agent_cfg as Dictionary).get("skills", [])
	if not (skills is Array):
		return false
	return (skills as Array).has(skill_id)


## Return true if the puzzle layer's WorldState records item_id in this agent's
## inventory. Delegates to WorldState.agent_has_item — live read, not cached.
## Returns false when world_loader is null (test context or pre-spawn).
## Implements Story 008 / TR-puzzle-028.
func has_item(item_id: String) -> bool:
	var ws: WorldState = world_loader.world_state if world_loader else null
	if ws == null:
		return false
	return ws.agent_has_item(agent_id, item_id)


## Return the effective wander-interest for prop_id: the maximum of the bare
## entity_interest key and the highest "layer:<prop_id>:<n>" compound key in
## memory.entity_interest. Returns 0.0 when no key exists (story 008 semantics
## differ from memory.get_interest which defaults to 1.0).
## Implements Story 008 / TR-puzzle-028. Not yet called from production code —
## this helper is infrastructure for future Formula 3 wander-weight work.
func _get_prop_interest(prop_id: String) -> float:
	if memory == null:
		return 0.0
	return compute_prop_interest(memory.entity_interest, prop_id)


## Pure interest-max logic, static so headless tests can drive it directly
## without instantiating a CharacterBody2D (TD-014a — replaces the verbatim
## mirror that lived in test_agent_dispatcher_extensions).
static func compute_prop_interest(entity_interest: Dictionary, prop_id: String) -> float:
	var best: float = entity_interest.get(prop_id, 0.0)
	for key: String in entity_interest:
		if key.begins_with("layer:" + prop_id + ":"):
			best = maxf(best, entity_interest[key])
	return best


func join_meeting(anchor: Node2D, radius: float) -> void:
	# Enters meeting mode. `radius` is the max acceptable distance
	# from the anchor — any walkable, uncrowded point inside that
	# zone is a valid landing. The agent picks its own landing via
	# _pick_and_walk_to_landing; if it's already standing at a
	# qualifying spot, it holds in place without moving at all.
	# Refuses if the agent is already in a social state — caller
	# should use queue_meeting in that case. Overrides any previous
	# meeting assignment and cancels any pending queue.
	if anchor == null or not is_instance_valid(anchor):
		return
	if is_socially_busy():
		return
	_summon_target = null  # exclusive with follow-mode summon
	_meeting_anchor = anchor
	_meeting_radius = maxf(80.0, radius)
	_meeting_held = false
	_meeting_fail_count = 0
	_meeting_replan_cooldown = 0.0
	_meeting_pending_anchor = null
	# Build the flow field from the anchor cell once on join. The
	# gradient is what lets _plan_path_to produce a waypoint even
	# when Theta* can't thread a clean route through the blocker
	# mask — without this, agents could end up frozen on failed
	# plans, which was the exact bug reported against the straight-
	# line seek fallback.
	var anchor_cell: Vector2i = _nearest_walkable_cell(anchor.global_position)
	_build_flow_field(anchor_cell)
	_pick_and_walk_to_landing()


func queue_meeting(anchor: Node2D, radius: float) -> void:
	# Stores a meeting assignment for an agent that's currently in a
	# social state. Consumed automatically by _consume_pending_meeting()
	# the moment the agent transitions out of TALKING / ENCOUNTERING /
	# OBSERVING (see finish_activity / stop_talking / mark_encounter_ended).
	if anchor == null or not is_instance_valid(anchor):
		return
	_meeting_pending_anchor = anchor
	_meeting_pending_radius = radius


func _consume_pending_meeting() -> void:
	# Called from the three social-state exit hooks. If a meeting was
	# queued while the agent was busy, this fires the real join_meeting
	# now that the agent is free. Safe to call unconditionally — no-op
	# when there's no pending assignment.
	if _meeting_pending_anchor == null:
		return
	var anchor: Node2D = _meeting_pending_anchor
	var radius: float = _meeting_pending_radius
	_meeting_pending_anchor = null
	if is_instance_valid(anchor):
		join_meeting(anchor, radius)


func leave_meeting() -> void:
	# Drops the agent out of meeting mode. Position and path are kept
	# as-is — a held agent stays IDLE and will wander after the next
	# idle_timer tick; an arriving agent finishes whatever path it
	# was on. Also cancels any pending queue so end_meeting fully
	# clears meeting intent. Normal behavior (wander, observe,
	# encounters) resumes on the next physics frame.
	if _meeting_anchor == null and _meeting_pending_anchor == null:
		return
	_meeting_anchor = null
	_meeting_pending_anchor = null
	_meeting_held = false
	_meeting_fail_count = 0
	_meeting_replan_cooldown = 0.0
	_flow_field.clear()
	_flow_field_source_cell = Vector2i(-999, -999)


func _is_walkable_point(p: Vector2) -> bool:
	# True if the given world point sits on a walkable nav-grid cell.
	# Used by proactive peel and stall recovery to refuse nudges
	# that would push the agent into geometry. Agents without a
	# built grid (static mode) conservatively report true so the
	# checks don't deadlock.
	if _nav_grid.is_empty():
		return true
	var cell: Vector2i = _world_to_cell(p)
	return _nav_grid.has(cell)


func _tick_meeting(delta: float) -> void:
	# Zone-based meeting loop. No pre-assigned slots — the agent
	# evaluates every frame whether its CURRENT spot is good enough,
	# and only walks somewhere else when it genuinely needs to.
	#
	# 1. Anchor freed → leave meeting.
	# 2. Held state → watch for anchor drifting out of zone.
	# 3. Not held + in zone + walkable + uncrowded → HALT AND HOLD.
	#    This is the fix for "agent marches past the user to reach
	#    a stale precomputed slot". Whatever the agent is currently
	#    doing — walking, idling, finishing an old path — if it
	#    finds itself in a valid landing, it stops there.
	# 4. Not held + (outside zone OR current spot unusable) → pick
	#    a new landing via _pick_and_walk_to_landing and start a
	#    fresh plan.
	# 5. Plan failure scales the retry cooldown via
	#    _meeting_backoff_for_fails; the agent never abandons.
	if not is_instance_valid(_meeting_anchor):
		leave_meeting()
		return
	_meeting_replan_cooldown -= delta
	var anchor_pos: Vector2 = _meeting_anchor.global_position
	var to_anchor: float = global_position.distance_to(anchor_pos)

	var max_radius: float = _meeting_max_radius()

	if _meeting_held:
		# Held: only repick when the anchor has drifted past the
		# MAX radius. Inside max but outside min is "good enough"
		# — agents shouldn't shuffle just because the player took
		# a step that pushed them from 0.95·min to 1.05·min.
		if to_anchor > max_radius and _meeting_replan_cooldown <= 0.0:
			_meeting_held = false
			_meeting_replan_cooldown = _replan_cooldown_base
			_pick_and_walk_to_landing()
			if _meeting_held:
				# _pick_and_walk_to_landing already settled us in a
				# new spot (landing was current position).
				return
			if not _has_goal:
				_meeting_fail_count += 1
				_meeting_replan_cooldown = _meeting_backoff_for_fails()
			else:
				_meeting_fail_count = 0
		return

	# Early-arrival fast path. Two-tier acceptance:
	#   • MIN zone (to_anchor ≤ _meeting_radius): always accept,
	#     that's the ideal landing ring.
	#   • MAX zone (to_anchor ≤ max_radius, which is min * 1.3):
	#     accept ONLY after the agent has failed to reach the min
	#     zone a few times. This is the "try for min but settle
	#     for max if you can't get there" rule — agents still
	#     prefer the tight ring, but won't burn cycles on an
	#     unreachable spot when they're already close enough.
	var in_min_zone: bool = to_anchor <= _meeting_radius
	var in_max_zone: bool = to_anchor <= max_radius
	if in_min_zone or (in_max_zone and _meeting_fail_count >= 3):
		if _is_walkable_point(global_position) and not _is_position_crowded(global_position):
			_meeting_held = true
			_meeting_fail_count = 0
			_stop_and_face(anchor_pos)
			return

	# Not in zone, or current position is unusable (crowded / on
	# an unwalkable cell somehow). Pick a new landing and walk.
	# "Outside" is computed against MIN — the replan target is
	# the tight ring; the max-zone acceptance above is only a
	# fallback once we've given up trying to hit min.
	if _meeting_replan_cooldown <= 0.0:
		var outside: bool = to_anchor > _meeting_radius
		var idle: bool = current_state == State.IDLE
		if outside or idle:
			_meeting_replan_cooldown = _replan_cooldown_base
			_pick_and_walk_to_landing()
			if _meeting_held:
				return
			if not _has_goal:
				_meeting_fail_count += 1
				_meeting_replan_cooldown = _meeting_backoff_for_fails()
			else:
				_meeting_fail_count = 0


func _meeting_max_radius() -> float:
	# Two-tier acceptance zone. Agents prefer landings inside
	# _meeting_radius (min) — that's where _pick_meeting_landing
	# samples its rings. But if a peer/wall combo makes the min
	# zone unreachable, an agent that's already within this max
	# radius will stop there instead of burning cycles on an
	# impossible plan. 1.3× gives the "min + 30%" tolerance Oscar
	# asked for; tight enough that the circle still looks like a
	# circle, loose enough that cramped corners don't trap agents.
	return _meeting_radius * 1.3


func _meeting_backoff_for_fails() -> float:
	# Retry cadence grows with consecutive plan failures — 0.25s
	# for the first failure, clamped to 0.8s so the seek fallback
	# can take a step and then get re-planned quickly from a
	# cleaner position. Reset on any successful plan or arrival.
	return clampf(0.25 + 0.2 * float(_meeting_fail_count), 0.25, 0.8)


func _meeting_try_accept_current(crowder: Agent) -> bool:
	# Meeting-mode bailout: if we're stuck AND either we're already
	# close enough to the anchor OR the peer we're wedged against
	# is itself held / parked near the anchor, accept our current
	# spot as a valid landing and go held right here. This is the
	# "agent stuck next to another agent who already made it" fix —
	# instead of thrashing on replans we just stop and turn toward
	# the meeting. Returns true when we've committed to the hold
	# (caller should early-return), false when the bailout doesn't
	# apply and normal recovery should continue.
	if _meeting_anchor == null or not is_instance_valid(_meeting_anchor):
		return false
	var anchor_pos: Vector2 = _meeting_anchor.global_position
	var slack: float = _meeting_max_radius()
	var in_zone: bool = global_position.distance_to(anchor_pos) <= slack
	var crowder_parked: bool = false
	if crowder != null and is_instance_valid(crowder):
		if crowder._meeting_held and crowder._meeting_anchor == _meeting_anchor:
			crowder_parked = true
		elif crowder.global_position.distance_to(anchor_pos) <= slack:
			crowder_parked = true
	if not (in_zone or crowder_parked):
		return false
	if not _is_walkable_point(global_position):
		return false
	_meeting_held = true
	_meeting_fail_count = 0
	_stop_and_face(anchor_pos)
	return true


func _pick_and_walk_to_landing() -> void:
	# Picks a landing via _pick_meeting_landing and either walks to
	# it or — if the picked landing is our current position — marks
	# us held in place without moving at all. Used by both
	# join_meeting (initial placement) and _tick_meeting (replans).
	if not is_instance_valid(_meeting_anchor):
		return
	var anchor_pos: Vector2 = _meeting_anchor.global_position
	var landing: Vector2 = _pick_meeting_landing(anchor_pos)
	if landing.distance_squared_to(global_position) < 4.0:
		_meeting_held = true
		_meeting_fail_count = 0
		_stop_and_face(anchor_pos)
		return
	_walk_to(landing)
	if not _has_goal:
		push_warning(
			"[agent:%s] meeting: plan to landing %s failed"
			% [display_name, str(landing)]
		)


func _pick_meeting_landing(anchor_pos: Vector2) -> Vector2:
	# Returns the best landing point for this agent relative to the
	# meeting anchor. Strategy:
	#
	#   Fast path — if the agent is already inside the meeting zone
	#   at a walkable, uncrowded spot, return the current position.
	#   This is the single most important piece of the fix: an
	#   agent that walked near the user (for any reason) just stops
	#   there instead of marching off to a pre-computed slot.
	#
	#   Sampling — otherwise sweep rings at 0.85 / 0.65 / 0.45 /
	#   0.25 of the zone radius, 32 angles per ring. Reject
	#   unwalkable cells and crowded positions. Score surviving
	#   candidates by (travel_distance + peer_spread_penalty) and
	#   keep the lowest. This naturally produces:
	#     - near-optimal travel (closest spot wins on travel term)
	#     - spread around the anchor (spread term penalizes
	#       clustering near already-held peers)
	#
	#   Fallback — if no candidate survives, return current
	#   position if we're at least in zone, otherwise return the
	#   anchor itself and let the planner sort it out.
	if global_position.distance_to(anchor_pos) <= _meeting_radius:
		if _is_walkable_point(global_position) and not _is_position_crowded(global_position):
			return global_position
	# 3 rings × 8 angles = 24 candidates (was 4×16=64). Each candidate
	# runs a physics shape LOS cast, so halving the count directly
	# halves the landing-pick cost — by far the hottest physics code
	# in meeting mode.
	var rings: Array[float] = [
		_meeting_radius * 0.85,
		_meeting_radius * 0.55,
		_meeting_radius * 0.3,
	]
	var sample_count: int = 8
	var best: Vector2 = anchor_pos
	var best_score: float = INF
	for r: float in rings:
		for k in range(sample_count):
			var angle: float = TAU * float(k) / float(sample_count)
			var candidate: Vector2 = anchor_pos + Vector2(cos(angle), sin(angle)) * r
			if not _is_walkable_point(candidate):
				continue
			if _is_position_crowded(candidate):
				continue
			var travel: float = global_position.distance_to(candidate)
			var spread: float = _peer_spread_penalty(candidate)
			var score: float = travel + spread
			# Strongly prefer candidates we can actually see from
			# where we are. Without this, the planner happily picks
			# a "closer" point on the far side of a wall and then
			# A* produces a long curve around — or fails outright.
			# The LOS check costs one shape sweep per candidate,
			# which is why sample_count was halved to 16.
			if not _segment_is_clear(global_position, candidate):
				score += 400.0
			if score < best_score:
				best_score = score
				best = candidate
	if best_score == INF:
		# No sampled candidate survived. Last-ditch fallback.
		if global_position.distance_to(anchor_pos) <= _meeting_radius:
			return global_position
		return anchor_pos
	return best


func _is_position_crowded(pos: Vector2) -> bool:
	# True if a meeting peer's claimed slot would conflict with `pos`.
	# Held peers reserve their current position; walking peers headed
	# to the same anchor reserve their planned landing (the last point
	# in their active path). Reserving the planned landing — not the
	# walking peer's current position — prevents two joining agents
	# from racing to the same slot (which left the second arrival
	# stuck) without re-introducing the deadlock that ignoring walking
	# peers entirely was meant to avoid.
	var min_sep: float = display_height * 0.9
	if world_loader == null or world_loader.agents_container == null:
		return false
	for other: Node in world_loader.agents_container.get_children():
		if other == self or not is_instance_valid(other) or not (other is Agent):
			continue
		var peer: Agent = other
		if peer._meeting_anchor != _meeting_anchor:
			continue
		var claim_pos: Vector2
		if peer._meeting_held:
			claim_pos = peer.global_position
		elif not peer._path_points.is_empty():
			claim_pos = peer._path_points[peer._path_points.size() - 1]
		else:
			continue
		if pos.distance_to(claim_pos) < min_sep:
			return true
	return false


func _peer_spread_penalty(pos: Vector2) -> float:
	# Soft score penalty for landings near peers' claimed slots.
	# Encourages natural spread around the anchor as tie-breaker
	# when multiple candidates are otherwise equivalent on travel
	# distance. Mirrors _is_position_crowded: held peers count from
	# their current position, walking peers count from the endpoint
	# of their active path.
	var penalty: float = 0.0
	var influence: float = display_height * 2.0
	if world_loader == null or world_loader.agents_container == null:
		return 0.0
	for other: Node in world_loader.agents_container.get_children():
		if other == self or not is_instance_valid(other) or not (other is Agent):
			continue
		var peer: Agent = other
		if peer._meeting_anchor != _meeting_anchor:
			continue
		var claim_pos: Vector2
		if peer._meeting_held:
			claim_pos = peer.global_position
		elif not peer._path_points.is_empty():
			claim_pos = peer._path_points[peer._path_points.size() - 1]
		else:
			continue
		var d: float = pos.distance_to(claim_pos)
		if d < influence:
			penalty += (influence - d) * 0.5
	return penalty


func _check_peer_crowding() -> void:
	# Fast-path peer-stuck recovery. Only fires when we've been
	# near-stationary long enough (_PEER_PEEL_STUCK_TIME) for it to
	# count as real wedging, not normal velocity variation. If a
	# crowding peer is present, splice a short escape waypoint away
	# from them in front of the current one so the agent peels out
	# before the slower stall supervisor would kick in.
	if stuck_timer < _PEER_PEEL_STUCK_TIME:
		return
	var crowder: Agent = _nearest_crowding_peer()
	if crowder == null:
		return
	# Meeting bailout first — if we're crowded near the anchor or
	# against a parked peer, just stop here and declare ourselves
	# held. Skipping this would peel us away from a perfectly fine
	# landing spot only to replan right back into the same wedge.
	if _meeting_anchor != null and _meeting_try_accept_current(crowder):
		return
	var away: Vector2 = _peel_direction(crowder)
	if away == Vector2.ZERO:
		return
	var nudge: Vector2 = global_position + away * (display_height * 1.2)
	nudge.x = clampf(nudge.x, _room_min.x, _room_max.x)
	nudge.y = clampf(nudge.y, _room_min.y, _room_max.y)
	# Walkability + body-clearance checks. Without them the peel can
	# slam the agent directly into a wall when the peer happens to
	# be between us and an obstacle. Failing here leaves the stall
	# supervisor to take the next swing with a full replan.
	if not _is_walkable_point(nudge):
		return
	if not _segment_is_clear(global_position, nudge):
		return
	if _path_index < _path_points.size():
		_path_points.insert(_path_index, nudge)
	else:
		_path_points.append(nudge)
		_path_index = _path_points.size() - 1
	target_position = nudge
	has_target = true
	_stall_last_distance = global_position.distance_to(target_position)
	_stall_timer = 0.0
	_peer_peel_cooldown = _PEER_PEEL_RESET


func _plan_path_to(pos: Vector2) -> bool:
	# Throttle: if we already have an active path and replanned very
	# recently, skip this call and keep walking the existing path.
	# Prevents tight stall-recovery loops (player blocking, peer wedge)
	# from hammering Theta* several times per frame.
	var now: float = Time.get_ticks_msec() / 1000.0
	var interval: float = _MIN_PLAN_INTERVAL + _plan_phase_offset
	if has_target and not _path_points.is_empty() and now - _last_plan_time < interval:
		return true
	_last_plan_time = now
	var path: Array[Vector2] = _find_path(global_position, pos)
	if path.is_empty() and _meeting_anchor != null:
		# Meeting flow-field fallback. Even when Theta* can't find
		# a path to the requested landing (blockers disconnect the
		# start or goal) the flow field — built once on
		# join_meeting — always has a gradient toward the anchor,
		# wrapping around walls by construction. Step one downhill
		# waypoint, walk it in a normal WALKING state (fixing the
		# anim+speed bug the old seek fallback introduced), and
		# the next replan fires from a cleaner position.
		var wp: Vector2 = _flow_step_waypoint(global_position)
		if wp.distance_squared_to(global_position) > 4.0:
			path = [wp]
	if path.is_empty():
		_abort_movement()
		return false
	_path_points = path
	_path_index = 0
	target_position = _path_points[0]
	has_target = true
	current_state = State.WALKING
	_stall_timer = 0.0
	_stall_last_distance = global_position.distance_to(target_position)
	return true


func _advance_waypoint() -> bool:
	# Called when the agent reaches the current waypoint. Returns true
	# if a next waypoint exists (so the caller keeps walking without
	# dropping WALKING state), false if the path is finished. Crossing
	# a waypoint is real progress, so we reset the replan counter AND
	# restamp the wedge anchor — an agent consuming its path is not
	# wedged, even when the waypoints loop through a small area (short
	# wander hops, ring landings near a POI).
	_path_index += 1
	_wedge_anchor = global_position
	_wedge_anchor_timer = 0.0
	if _path_index >= _path_points.size():
		_has_goal = false
		return false
	target_position = _path_points[_path_index]
	_stall_timer = 0.0
	_stall_last_distance = global_position.distance_to(target_position)
	_replan_attempts = 0
	return true


func _tick_supervisor(delta: float, current_distance: float) -> void:
	# Distance-to-waypoint progress monitor. If the distance shrinks by
	# more than 1px in a frame we reset the stall timer; otherwise it
	# ticks up and eventually triggers _handle_stall to replan.
	if current_distance + 1.0 < _stall_last_distance:
		_stall_last_distance = current_distance
		_stall_timer = 0.0
		return
	_stall_timer += delta
	if _stall_timer >= _stall_threshold:
		_handle_stall()


func _handle_stall() -> void:
	# Shared recovery path for both stall detectors (position-based in
	# _apply_movement, distance-based in _tick_supervisor). Peels off a
	# physically-touching peer first since replanning won't un-wedge
	# body contact, otherwise replans from the current pose toward the
	# original goal. Aborts after _MAX_REPLANS consecutive failures.
	# The slower wedge tracker handles cases where these per-call
	# replans keep producing the same wedged plan across _walk_to()
	# resets — this layer is only the fast peer-peel + replan loop.
	_stall_timer = 0.0
	_replan_attempts += 1
	if _replan_attempts > _MAX_REPLANS:
		_abort_movement()
		return
	var crowder: Agent = _nearest_crowding_peer()
	# Meeting bailout before anything else — if our stall resolves
	# by just staying where we are, do that instead of burning a
	# replan attempt.
	if _meeting_anchor != null and _meeting_try_accept_current(crowder):
		return
	if crowder != null:
		var away: Vector2 = _peel_direction(crowder)
		if away != Vector2.ZERO:
			var nudge: Vector2 = global_position + away * display_height
			nudge.x = clampf(nudge.x, _room_min.x, _room_max.x)
			nudge.y = clampf(nudge.y, _room_min.y, _room_max.y)
			# Validate the nudge: the destination must be a walkable
			# cell AND the segment from here to there must actually fit
			# the body. Otherwise we'd peel directly into a wall and
			# wedge harder than before. If either check fails we fall
			# through to a full replan.
			if _is_walkable_point(nudge) and _segment_is_clear(global_position, nudge):
				_path_points.insert(_path_index, nudge)
				target_position = nudge
				_stall_last_distance = global_position.distance_to(target_position)
				return
	if _has_goal:
		# Strict retry during meetings: treat every peer as a
		# blocker so the new path curves around walking crowd. If
		# that succeeds we're done; if it doesn't (too many peers
		# disconnect the graph) fall through to a normal replan.
		if _meeting_anchor != null:
			_plan_strict_blockers = true
			var ok: bool = _plan_path_to(_goal_position)
			_plan_strict_blockers = false
			if ok:
				return
		_plan_path_to(_goal_position)


func _tick_wedge_tracker(delta: float) -> void:
	# Long-window pin detector that survives _walk_to() resets — the
	# per-call stall logic can't see this case because every summon /
	# meeting / wander retry resets _replan_attempts. Once we've
	# stayed inside _WEDGE_PIN_RADIUS of _wedge_anchor for
	# _WEDGE_DETECT_TIME, fire local tactical recovery.
	if _wedge_escape_cooldown > 0.0:
		_wedge_escape_cooldown = maxf(_wedge_escape_cooldown - delta, 0.0)
	if not _has_goal or _wedge_escape_cooldown > 0.0:
		return
	var pin_radius: float = display_height * _WEDGE_PIN_RADIUS_MULT
	var progress_radius: float = display_height * _WEDGE_PROGRESS_RADIUS_MULT
	if _wedge_anchor == Vector2.INF:
		_wedge_anchor = global_position
		_wedge_anchor_timer = 0.0
		return
	var d: float = global_position.distance_to(_wedge_anchor)
	if d > progress_radius:
		# Real travel — we got out on our own. Reset everything.
		_wedge_anchor = global_position
		_wedge_anchor_timer = 0.0
		return
	if d > pin_radius:
		# Wandering inside the anchor zone (peer-peel sidesteps, etc.).
		# Hold the timer — neither tick nor reset — until we either
		# escape the zone or settle back to the pin radius.
		return
	# Only accrue wedge time while the body is demonstrably failing to
	# translate at its commanded speed. A wedge is "told to move, not
	# moving" — velocity collapsed against a peer or wall. An agent
	# cruising through short segments near its anchor (slow moods,
	# speed-jittered walks, ring landings) is making progress and must
	# not trip the detector: the old absolute time-in-radius check sat
	# 0.1s from firing at cruise speed, and any speed texture pushed it
	# over, which chained escape nudges into a permanent orbit.
	if velocity.length() > _smoothed_speed * 0.5:
		return
	_wedge_anchor_timer += delta
	if _wedge_anchor_timer >= _WEDGE_DETECT_TIME:
		_trigger_wedge_escape()


func _trigger_wedge_escape() -> void:
	# Local tactical recovery only. Try the cheap moves first; if both
	# fail, the situation is geometrically pinned right now — bail with
	# a cooldown so we don't burn cycles every 1.5s, and let the
	# higher-level driver (summon target moving, peer shifting) change
	# the situation. Theta* already finds the right global path; we
	# never strategically replace it from this layer.
	_wedge_anchor_timer = 0.0
	# The current wander heading demonstrably led to a pin — drop it
	# so the next explore roll picks a fresh direction instead of
	# perturbing ± around the bad one.
	wander_brain.reset_heading()
	if _try_waypoint_skip():
		# Skip moved us up the path — restamp the anchor so the next
		# wedge detection is measured from the new committed position.
		_wedge_anchor = global_position
		return
	if _try_perpendicular_nudge():
		_wedge_anchor = global_position
		return
	_wedge_anchor = Vector2.INF
	_wedge_escape_cooldown = _WEDGE_ESCAPE_COOLDOWN


func _try_waypoint_skip() -> bool:
	# If the path has a waypoint AFTER the current one and the segment
	# from here to it is body-clear, just advance the index. This cuts
	# the diagonal across corner-clip wedges (the classic case where
	# the agent is jammed pixels short of waypoint i but waypoint i+1
	# is reachable on a straight line). Costs nothing when no skip is
	# available — just an index check and one Bresenham segment.
	if _path_index + 1 >= _path_points.size():
		return false
	var next_wp: Vector2 = _path_points[_path_index + 1]
	if not _segment_is_clear(global_position, next_wp):
		return false
	_path_index += 1
	target_position = next_wp
	has_target = true
	_stall_timer = 0.0
	_stall_last_distance = global_position.distance_to(target_position)
	_replan_attempts = 0
	return true


func _try_perpendicular_nudge() -> bool:
	# One body-width sidestep perpendicular to our current heading,
	# inserted as a temporary waypoint so the agent re-approaches the
	# original waypoint from a fresh angle. Picks whichever side
	# (left/right) lands closer to the active goal so the nudge moves
	# us along the path, not away from it. Validates both a walkable
	# destination AND a clear segment to it; otherwise refuses (would
	# wedge harder).
	if not has_target:
		return false
	var to_target: Vector2 = target_position - global_position
	if to_target.length_squared() < 1.0:
		return false
	var heading: Vector2 = to_target.normalized()
	var perp: Vector2 = Vector2(-heading.y, heading.x)
	var step: float = display_height * _WEDGE_NUDGE_DIST_MULT
	var left: Vector2 = global_position + perp * step
	var right: Vector2 = global_position - perp * step
	left.x = clampf(left.x, _room_min.x, _room_max.x)
	left.y = clampf(left.y, _room_min.y, _room_max.y)
	right.x = clampf(right.x, _room_min.x, _room_max.x)
	right.y = clampf(right.y, _room_min.y, _room_max.y)
	var left_ok: bool = _is_walkable_point(left) and _segment_is_clear(global_position, left)
	var right_ok: bool = _is_walkable_point(right) and _segment_is_clear(global_position, right)
	if not left_ok and not right_ok:
		return false
	var goal_ref: Vector2 = _goal_position if _has_goal else target_position
	var nudge: Vector2
	if left_ok and right_ok:
		nudge = left if left.distance_squared_to(goal_ref) < right.distance_squared_to(goal_ref) else right
	elif left_ok:
		nudge = left
	else:
		nudge = right
	_path_points.insert(_path_index, nudge)
	target_position = nudge
	has_target = true
	_stall_timer = 0.0
	_stall_last_distance = global_position.distance_to(target_position)
	_replan_attempts = 0
	return true


func _abort_movement() -> void:
	_path_points.clear()
	_path_index = 0
	has_target = false
	_has_goal = false
	_walk_is_wander = false
	_replan_attempts = 0
	current_state = State.IDLE
	idle_timer = randf_range(0.5, 1.2)
	_play_anim("idle")


func _build_nav_grid() -> void:
	# Shape-test every cell with a circle of agent radius. If the
	# probe doesn't overlap any static body, the cell is walkable
	# and gets stored in _nav_grid. The grid is static: walls don't
	# move, so we build it once. Connectivity isn't stored
	# explicitly — _cell_neighbors computes 8-direction neighbors
	# on the fly with the same diagonal constraint the old AStar2D
	# connection pass used (a diagonal step requires BOTH flanking
	# orthogonals to be walkable too, so we can't slip through a
	# 1-cell wall corner).
	if _room_max == Vector2.ZERO:
		return
	var t0: int = Time.get_ticks_usec()
	var probe_radius: float = WorldBuilder.FOOT_RADIUS
	# Grid cell size controls Theta* search cost quadratically: doubling
	# the cell size drops cell count 4× and path-expansion cost along
	# with it. 2.2× the feet probe gives 13.2 px cells (191×107 on a
	# 2560×1440 map, ~20 ms per agent) that keep forest gaps open. Any path
	# accuracy lost is absorbed by RVO avoidance at walk time.
	_grid_cell_size = probe_radius * 2.2
	_grid_origin = _room_min
	var width: float = _room_max.x - _room_min.x
	var height: float = _room_max.y - _room_min.y
	_grid_cols = int(ceil(width / _grid_cell_size))
	_grid_rows = int(ceil(height / _grid_cell_size))

	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = probe_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = _dynamic_body_exclusions()

	_nav_grid.clear()
	_cell_anchor.clear()
	var shift: float = _grid_cell_size * 0.25
	var offsets: Array[Vector2] = [Vector2(0, shift), Vector2(0, -shift), Vector2(shift, 0), Vector2(-shift, 0)]
	for y in range(_grid_rows):
		for x in range(_grid_cols):
			var cell := Vector2i(x, y)
			var center: Vector2 = _grid_cell_center(cell)
			query.transform = Transform2D(0.0, center)
			if space.intersect_shape(query, 1).is_empty():
				_nav_grid[cell] = true
				continue
			# A bridge deck can be narrower than a cell: retry at offsets when the wall is at least probe - shift away.
			shape.radius = probe_radius - shift
			var near_edge: bool = space.intersect_shape(query, 1).is_empty()
			shape.radius = probe_radius
			if not near_edge:
				continue
			for off: Vector2 in offsets:
				query.transform = Transform2D(0.0, center + off)
				if space.intersect_shape(query, 1).is_empty():
					_nav_grid[cell] = true
					_cell_anchor[cell] = center + off
					break
	print("[agent:%s] nav grid %dx%d cell=%.1f walkable=%d anchored=%d %.0fms" % [
		display_name, _grid_cols, _grid_rows, _grid_cell_size, _nav_grid.size(), _cell_anchor.size(),
		(Time.get_ticks_usec() - t0) / 1000.0,
	])


func _grid_cell_center(c: Vector2i) -> Vector2:
	return _grid_origin + (Vector2(c) + Vector2(0.5, 0.5)) * _grid_cell_size


## Walk point of a cell: its anchor when the centre is blocked, else the centre.
func _cell_point(c: Vector2i) -> Vector2:
	return _cell_anchor.get(c, _grid_cell_center(c))


func _cell_neighbors(c: Vector2i) -> Array[Vector2i]:
	# 8-directional walkable neighbors. Diagonal moves require
	# BOTH flanking orthogonals to also be walkable — prevents
	# corner clipping through 1-cell wall gaps. This matches the
	# connectivity the old AStar2D build pass enforced.
	var out: Array[Vector2i] = []
	var offsets: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for d: Vector2i in offsets:
		var n: Vector2i = c + d
		if not _nav_grid.has(n):
			continue
		if d.x != 0 and d.y != 0:
			if not _nav_grid.has(Vector2i(c.x + d.x, c.y)):
				continue
			if not _nav_grid.has(Vector2i(c.x, c.y + d.y)):
				continue
		out.append(n)
	return out


func _cell_distance(a: Vector2i, b: Vector2i) -> float:
	var dx: float = float(a.x - b.x)
	var dy: float = float(a.y - b.y)
	return sqrt(dx * dx + dy * dy)


func _world_to_cell(p: Vector2) -> Vector2i:
	var local: Vector2 = p - _grid_origin
	return Vector2i(int(floor(local.x / _grid_cell_size)), int(floor(local.y / _grid_cell_size)))


func _nearest_walkable_cell(p: Vector2) -> Vector2i:
	# Returns the nearest walkable cell to a world point. Exact cell
	# first; otherwise spiral out one ring at a time until we find one
	# (or exhaust the grid and return the snapped cell unchanged, which
	# _find_path then handles as a lookup failure).
	var base: Vector2i = _world_to_cell(p)
	if _nav_grid.has(base):
		return base
	var max_radius: int = maxi(_grid_cols, _grid_rows)
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := Vector2i(base.x + dx, base.y + dy)
				if _nav_grid.has(c):
					return c
	return base


func _find_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	# Path planner — runs Theta* over the walkable grid with a
	# per-call blocker mask. Theta* is an any-angle variant of A*:
	# during search it performs line-of-sight checks between a
	# candidate node and its grandparent, and when LOS exists the
	# node adopts the grandparent as its parent directly. The result
	# is a naturally curved path that hugs the obstacle silhouette
	# instead of the jagged cell-edge path vanilla A* produces.
	# String-pulling smoothing is no longer needed — Theta*
	# already picks any-angle waypoints during expansion.
	#
	# Blocker mask: cells occupied by stationary peers (held,
	# socially-busy, meeting-bound, or physically wedged) and the
	# player are excluded from the search so the path curves around
	# them. If the mask leaves the graph disconnected, we fall back
	# to an unmasked search; some path is better than none, and the
	# flow-field fallback in _plan_path_to will catch truly impossible
	# cases during meeting mode.
	var empty: Array[Vector2] = []
	if _nav_grid.is_empty():
		var direct: Array[Vector2] = []
		direct.append(to)
		return direct
	var start_cell: Vector2i = _nearest_walkable_cell(from)
	var goal_cell: Vector2i = _nearest_walkable_cell(to)
	if not _nav_grid.has(start_cell) or not _nav_grid.has(goal_cell):
		return empty
	var blocked: Dictionary = _collect_blocker_cells()
	# Don't let blocker cells trap the start or goal themselves.
	blocked.erase(start_cell)
	blocked.erase(goal_cell)
	var path: Array[Vector2] = _theta_star(start_cell, goal_cell, from, to, blocked)
	if path.is_empty():
		# Blocker mask disconnected the grid — retry with no
		# blockers at all. RVO + the stall supervisor will handle
		# any residual peer contact on the unmasked path.
		path = _theta_star(start_cell, goal_cell, from, to, {})
	return path


func _theta_star(
	start_cell: Vector2i,
	goal_cell: Vector2i,
	start_world: Vector2,
	goal_world: Vector2,
	blocked: Dictionary,
) -> Array[Vector2]:
	# Any-angle A* with line-of-sight parent promotion.
	#
	# Pseudocode (per Nash & Koenig 2007):
	#   g(s) = cost-so-far from start to s
	#   parent(s) = predecessor used to reach s
	#   f(s) = g(s) + h(s, goal)    -- standard A* f-score
	#
	# On expansion of node s:
	#   for each neighbor n of s (walkable, not blocked):
	#     if LOS(parent(s), n):
	#         # promote: n adopts s's parent as its own, skipping s.
	#         new_g = g(parent(s)) + dist(parent(s), n)
	#         new_parent = parent(s)
	#     else:
	#         # standard A*: n links through s.
	#         new_g = g(s) + dist(s, n)
	#         new_parent = s
	#     if new_g < g(n):
	#         g(n) = new_g; parent(n) = new_parent
	#         push n into open with priority new_g + h(n, goal)
	#
	# LOS is a cheap Bresenham walk over the walkable grid, confirmed
	# by a feet-circle sweep (_segment_is_clear); fallback steps get the
	# same sweep, so no link cuts a wall corner.
	#
	# Open-list priority queue: flat array, linear-scan min. Grid
	# sizes here are small (≤ a few hundred cells) so the O(n) pop
	# is fine and avoids the verbosity of a GDScript binary heap.
	var empty: Array[Vector2] = []
	if start_cell == goal_cell:
		var single: Array[Vector2] = []
		single.append(goal_world)
		return single
	# Clear-and-reuse scratch state (declared as member vars) so Theta*
	# does not allocate a single Dictionary or Array per call. This was
	# the biggest remaining source of object churn under replan storms.
	_theta_g.clear()
	_theta_parent.clear()
	_theta_closed.clear()
	_theta_open_f.clear()
	_theta_open_cell.clear()
	_theta_g[start_cell] = 0.0
	_theta_parent[start_cell] = start_cell
	_heap_push_parallel(_theta_open_f, _theta_open_cell, _cell_distance(start_cell, goal_cell), start_cell)
	# Hard expansion cap: every walkable cell once, so cross-map paths on the big feet grid still resolve.
	var max_expansions: int = _nav_grid.size()
	var expansions: int = 0
	while not _theta_open_cell.is_empty():
		var current: Vector2i = _heap_pop_parallel(_theta_open_f, _theta_open_cell)
		if _theta_closed.has(current):
			continue  # stale heap entry — a better path already closed this cell
		expansions += 1
		if expansions > max_expansions:
			return empty
		if current == goal_cell:
			return _theta_reconstruct(_theta_parent, current, start_world, goal_world)
		_theta_closed[current] = true
		var current_parent: Vector2i = _theta_parent[current]
		# Inlined 8-direction neighbor expansion — allocation-free hot path.
		# Diagonal moves require both flanking orthogonals walkable (no
		# corner clipping). Replaces _cell_neighbors() which allocated an
		# Array[Vector2i] per expansion (dominant source of per-plan churn).
		for oi: int in range(8):
			var dx: int
			var dy: int
			match oi:
				0: dx = 1; dy = 0
				1: dx = -1; dy = 0
				2: dx = 0; dy = 1
				3: dx = 0; dy = -1
				4: dx = 1; dy = 1
				5: dx = -1; dy = 1
				6: dx = 1; dy = -1
				_: dx = -1; dy = -1
			var neighbor := Vector2i(current.x + dx, current.y + dy)
			if not _nav_grid.has(neighbor):
				continue
			if dx != 0 and dy != 0:
				if not _nav_grid.has(Vector2i(current.x + dx, current.y)):
					continue
				if not _nav_grid.has(Vector2i(current.x, current.y + dy)):
					continue
			if _theta_closed.has(neighbor):
				continue
			if blocked.has(neighbor):
				continue
			var new_g: float
			var new_parent: Vector2i
			if _cell_los(current_parent, neighbor, blocked) \
					and _segment_is_clear(_cell_point(current_parent), _cell_point(neighbor)):
				new_g = float(_theta_g[current_parent]) + _cell_distance(current_parent, neighbor)
				new_parent = current_parent
			elif _segment_is_clear(_cell_point(current), _cell_point(neighbor)):
				new_g = float(_theta_g[current]) + _cell_distance(current, neighbor)
				new_parent = current
			else:
				continue
			if new_g < float(_theta_g.get(neighbor, INF)):
				_theta_g[neighbor] = new_g
				_theta_parent[neighbor] = new_parent
				_heap_push_parallel(_theta_open_f, _theta_open_cell, new_g + _cell_distance(neighbor, goal_cell), neighbor)
	return empty


# Parallel-array binary min-heap. Two arrays (float f-scores + Vector2i
# cells) swapped together instead of pair sub-arrays — keeps the heap
# allocation-free after the initial buffer grows.

static func _heap_push_parallel(heap_f: Array[float], heap_c: Array[Vector2i], f: float, cell: Vector2i) -> void:
	heap_f.append(f)
	heap_c.append(cell)
	var i: int = heap_f.size() - 1
	while i > 0:
		var p: int = (i - 1) >> 1
		if heap_f[p] <= heap_f[i]:
			break
		var tf: float = heap_f[p]
		var tc: Vector2i = heap_c[p]
		heap_f[p] = heap_f[i]
		heap_c[p] = heap_c[i]
		heap_f[i] = tf
		heap_c[i] = tc
		i = p


static func _heap_pop_parallel(heap_f: Array[float], heap_c: Array[Vector2i]) -> Vector2i:
	var top: Vector2i = heap_c[0]
	var last_f: float = heap_f.pop_back()
	var last_c: Vector2i = heap_c.pop_back()
	if heap_c.is_empty():
		return top
	heap_f[0] = last_f
	heap_c[0] = last_c
	var i: int = 0
	var n: int = heap_c.size()
	while true:
		var l: int = 2 * i + 1
		var r: int = 2 * i + 2
		var smallest: int = i
		if l < n and heap_f[l] < heap_f[smallest]:
			smallest = l
		if r < n and heap_f[r] < heap_f[smallest]:
			smallest = r
		if smallest == i:
			break
		var tf: float = heap_f[i]
		var tc: Vector2i = heap_c[i]
		heap_f[i] = heap_f[smallest]
		heap_c[i] = heap_c[smallest]
		heap_f[smallest] = tf
		heap_c[smallest] = tc
		i = smallest
	return top


func _theta_reconstruct(
	parent: Dictionary,
	goal: Vector2i,
	start_world: Vector2,
	goal_world: Vector2,
) -> Array[Vector2]:
	# Walk the parent chain from goal back to start, producing a
	# world-space waypoint list in forward order. The first entry
	# uses the real goal position (not the goal cell center) so the
	# agent arrives exactly where asked; intermediate waypoints are
	# cell centers. Because Theta* promoted parents during search,
	# each link in the chain is already any-angle — no smoothing
	# pass is necessary.
	var reversed: Array[Vector2] = []
	var goal_point: Vector2 = _cell_point(goal)
	var before_goal: Vector2 = _cell_point(parent.get(goal, goal))
	# The goal cell's point joins the chain when the last link to the raw goal would clip a wall.
	if _segment_is_clear(before_goal, goal_world):
		reversed.append(goal_world)
	elif _segment_is_clear(goal_point, goal_world):
		reversed.append(goal_world)
		reversed.append(goal_point)
	else:
		reversed.append(goal_point)
	var cursor: Vector2i = goal
	while true:
		var p: Vector2i = parent.get(cursor, cursor)
		if p == cursor:
			break
		reversed.append(_cell_point(p))
		cursor = p
	# Drop the start cell's point when the agent is beside it and can head straight for the next one.
	if reversed.size() > 1:
		var last: Vector2 = reversed[reversed.size() - 1]
		if last.distance_squared_to(start_world) < (_grid_cell_size * 0.6) * (_grid_cell_size * 0.6) \
				and _segment_is_clear(start_world, reversed[reversed.size() - 2]):
			reversed.remove_at(reversed.size() - 1)
	var forward: Array[Vector2] = []
	for i in range(reversed.size() - 1, -1, -1):
		forward.append(reversed[i])
	return forward


func _cell_los(a: Vector2i, b: Vector2i, blocked: Dictionary) -> bool:
	# Bresenham line walk through the walkable grid. Every cell the
	# line passes through must be in _nav_grid AND not in the
	# blocker mask. Bresenham uses only int arithmetic — no physics
	# queries — so this is fast enough to call O(cells) times per
	# path. The grid was probed with a body-sized circle during
	# _build_nav_grid, so any Bresenham line through walkable cells
	# has body-width clearance at the cell centers it crosses.
	if a == b:
		return true
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		var cell := Vector2i(x0, y0)
		if not _nav_grid.has(cell):
			return false
		if blocked.has(cell):
			return false
		if x0 == x1 and y0 == y1:
			return true
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return true


# ── Flow field (many-agents-to-one-point convergence) ──────────

func _build_flow_field(source_cell: Vector2i) -> void:
	# BFS from the source through the walkable grid, recording
	# cumulative distance in cell units. The result is a scalar
	# field over _nav_grid; agents read the gradient at their own
	# cell to get a direction toward the source that curves around
	# walls for free — the BFS frontier naturally wraps around
	# obstacles.
	#
	# This is the classic crowd-simulation flow field used when
	# many agents share a single goal. Amit Patel's graph search
	# variants page explicitly recommends it for "many agents
	# finding paths to the same destination" — which is exactly
	# the meeting case where per-agent A* runs were the bottleneck.
	# BFS is O(cells) per rebuild, cheap enough to call on every
	# join_meeting.
	#
	# Edge cost: orthogonal = 1, diagonal = √2. Not strictly
	# optimal because BFS visits each cell once in insertion order
	# (breadth-first), but distances are monotonic over the
	# frontier so gradient direction is still correct.
	_flow_field.clear()
	_flow_field_source_cell = source_cell
	if not _nav_grid.has(source_cell):
		return
	_flow_field[source_cell] = 0.0
	var queue: Array[Vector2i] = [source_cell]
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var d: float = float(_flow_field[cell])
		for n: Vector2i in _cell_neighbors(cell):
			if _flow_field.has(n):
				continue
			_flow_field[n] = d + _cell_distance(cell, n)
			queue.append(n)


func _flow_step_waypoint(from_pos: Vector2) -> Vector2:
	# Returns a world-space waypoint a few cells downhill on the
	# flow field — the direction that curves toward the meeting
	# anchor while avoiding walls. Used as the fallback when Theta*
	# can't find a blocker-safe path; the agent walks the short
	# flow-field step, which puts it in a cleaner position from
	# which the next Theta* attempt usually succeeds.
	#
	# The walk "chains" up to 4 cells downhill so the resulting
	# waypoint is far enough that the agent commits to a real walk
	# segment instead of arriving in one frame and replanning
	# immediately. Chain breaks on any cell that has no strictly
	# downhill neighbor (either at the source or at a plateau).
	if _flow_field.is_empty():
		return from_pos
	var start_cell: Vector2i = _nearest_walkable_cell(from_pos)
	var cursor: Vector2i = start_cell
	var cursor_dist: float = float(_flow_field.get(cursor, INF))
	if cursor_dist == INF:
		return from_pos
	for _i in range(4):
		var best: Vector2i = cursor
		var best_dist: float = cursor_dist
		for n: Vector2i in _cell_neighbors(cursor):
			var nd: float = float(_flow_field.get(n, INF))
			if nd < best_dist:
				best_dist = nd
				best = n
		if best == cursor:
			break
		cursor = best
		cursor_dist = best_dist
	if cursor == start_cell:
		return from_pos
	return _cell_point(cursor)


func _collect_blocker_cells() -> Dictionary:
	# Returns the set of grid cells that stationary blockers occupy
	# — peers the agent shouldn't plan through (see
	# _is_peer_stationary for the definition) plus the player. Each
	# blocker disables a 3x3 ring centered on its cell so there's
	# body-width clearance around the obstacle even on diagonal
	# approaches. Called per Theta* invocation, so the dict is
	# short-lived and the cost is bounded by (blocker_count * 9)
	# dict insertions — negligible.
	var blocked: Dictionary = {}
	if world_loader == null:
		return blocked
	var positions: Array[Vector2] = []
	if world_loader.agents_container != null:
		for other: Node in world_loader.agents_container.get_children():
			if other == self or not is_instance_valid(other) or not (other is Agent):
				continue
			var peer: Agent = other
			if not _is_peer_stationary(peer):
				continue
			positions.append(peer.global_position)
	if is_instance_valid(world_loader.player):
		positions.append(world_loader.player.global_position)
	for pos: Vector2 in positions:
		var center: Vector2i = _world_to_cell(pos)
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				blocked[Vector2i(center.x + dx, center.y + dy)] = true
	return blocked


# ── Blocker awareness for path planning ─────────────────────────

func _is_peer_stationary(peer: Agent) -> bool:
	# A peer counts as a blocker for path planning if it won't
	# step aside on its own. Plain wandering / walking peers are
	# normally NOT blockers — RVO handles dynamic separation while
	# both are moving. But the net the planner has to throw widens
	# in three extra cases, all of which caused wedging before:
	#   • _plan_strict_blockers — caller explicitly asks to treat
	#     every peer as an obstacle (used by stall-retry).
	#   • peer is committed to a meeting — it is converging on a
	#     landing and will be sitting in our way soon, so we'd
	#     rather curve around its current position than plan a
	#     line that only works while it's still moving.
	#   • peer has been physically stuck for >0.2s — RVO already
	#     failed to separate them, so we route around instead of
	#     shoulder-checking them harder.
	if _plan_strict_blockers:
		return true
	if peer._meeting_held:
		return true
	if peer.is_socially_busy():
		return true
	if peer._meeting_anchor != null:
		return true
	if peer.stuck_timer > 0.2:
		return true
	return false


func _update_facing(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		facing = "right" if direction.x > 0.0 else "left"
	else:
		facing = "down" if direction.y > 0.0 else "up"


func _play_anim(prefix: String) -> void:
	var sprite := get_node_or_null("CharSprite")
	if not sprite:
		return
	var anim_name := prefix + "_" + facing
	if sprite.animation != anim_name:
		sprite.play(anim_name)
