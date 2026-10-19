class_name WorldLoader
extends Node2D
## Generic world loader — orchestrates one room's scene graph.
## ONE .tscn with this script attached = any room. Everything else comes
## from JSON. Delegates:
##   - world construction → WorldBuilder (background, walls, props, audio)
##   - agent spawning → AgentSpawner
##   - LLM I/O + response handling → LLMCoordinator
##   - multi-turn A2A encounters → EncounterDispatcher
## Remains the single "world context" object agents, dialogue, and the
## encounter dispatcher all hold a reference to — so its public surface
## (config, room_bounds, llm, activity_gate, narration_log,
## find_agent, request_agent_*) must stay stable.

@export var room_config_path: String = ""

const PlayerScript: GDScript = preload("res://scripts/player.gd")
const ActionPromptScript: GDScript = preload("res://scripts/action_prompt.gd")
const NarrationLogScript: GDScript = preload("res://scripts/narration_log.gd")
const ControlsHintScript: GDScript = preload("res://scripts/controls_hint.gd")

var config: Dictionary = {}
var llm: LLMClient
var dialogue: DialogueCloud
var player: CharacterBody2D
var agents_container: Node2D
var props_container: Node2D
var action_prompt: CanvasLayer
var narration_log: CanvasLayer
var room_bounds: Rect2 = Rect2()

# Menu chrome + modal dialogs (quit confirm, call picker, meeting picker)
# live in WorldMenuBuilder. world_loader delegates Esc handling, toast
# fades, and main-menu visibility through it.
var menu_builder: WorldMenuBuilder

# Meeting state. While true, every eligible agent has been assigned
# a slot on a circle around the player and holds position there
# until end_meeting() is called.
var meeting_active: bool = false

# Conversation layer on top of the spatial meeting: snapshot of the
# agent ids invited when Summon Meeting was pressed, plus a flag that
# tracks whether we've already opened the unified chat for this meeting.
# The arrival watcher in _process waits until every invited id reports
# agent.is_meeting_held() == true before flipping the chat open exactly once.
var meeting_orchestrator: MeetingOrchestrator
var _meeting_invited_ids: Array[String] = []
var _meeting_chat_open: bool = false

# Opaque-id queue for in-flight LLM requests. Callers register a Callable,
# get back an id, pass the id to llm.llm_chat; when the response signal
# fires we dispatch back to the registered Callable.
var llm_request_queue: LLMRequestQueue = LLMRequestQueue.new()
var _diag_accum: float = 0.0

# Global "something is happening" lockout. Any agent triggering an activity
# starts a cooldown during which no other agent may trigger. Tick from
# _process. Duration from game_config.defaults.activity_global_cooldown.
var activity_gate: ActivityGate = ActivityGate.new()

# Multi-turn A2A encounter flow between two agents. Owns the A2ARouter.
var encounter_dispatcher: EncounterDispatcher

# Puzzle-layer state + resolver (Story 006 — ADR-0001 §1/§4). WorldState
# loads once from user://saves/world_state_<id>.json; ActionResolver wraps
# it with the puzzle list for the current world. Both are
# constructed/configured in _ready() BEFORE agent_spawner.spawn_all so
# agents observe a fully-set-up puzzle layer from their first tick.
var world_state: WorldState
var action_resolver: ActionResolver

# Debounced WorldState save timer — child Timer node, one_shot + 5s wait_time.
# queue_world_state_save(false) restarts the countdown (most actions);
# queue_world_state_save(true) stops the timer and flushes immediately
# (solve broadcasts per R15).
var _save_timer: Timer

# Internal helpers — retained as fields so their Callables stay valid.
var _agent_spawner: AgentSpawner
var _llm_coordinator: LLMCoordinator

# agent_id -> true while a one-shot `call_arrived` handler is registered.
# Prevents re-pressing Call on the same in-flight agent from connecting a
# second handler that would double-open the dialogue when they arrive.
# Cleared on arrival (_on_agent_call_arrived) and on agent destruction
# (_on_pending_call_agent_exiting) so a freed-mid-flight agent does not
# leave a stale entry that would silently swallow a future Call press.
var _pending_calls: Dictionary[String, bool] = {}

# Pre-allocated work arrays for the meeting arrival watcher. Cleared and
# reused each frame during the gather window so we do not allocate while
# the watcher polls for held attendees.
var _meeting_attendees_buf: Array[Dictionary] = []
var _meeting_ids_buf: Array[String] = []

# CanvasLayer z-stack (low → high). Multiple owners at the same layer are
# z-ordered by scene-tree order, so action_prompt renders before
# controls_hint at LAYER_HUD. WorldMenuBuilder builds its own layer at
# LAYER_MENU; LogModal builds its own at LAYER_MODAL.
const LAYER_HUD: int = 1
const LAYER_SIDEBAR: int = 2
const LAYER_MENU: int = 10


func _ready() -> void:
	if room_config_path == "":
		room_config_path = GameState.room_config_path
	if room_config_path == "":
		push_error("[world] No room_config_path set")
		return
	_load_config()
	activity_gate.cooldown_time = GameState.get_float("activity_global_cooldown", activity_gate.cooldown_time)
	# Startup grace period — nothing autonomous fires until this drains.
	# Arrivals don't touch the gate so they still happen at spawn; only
	# observations and encounters wait. Gives the world a chance to settle
	# and the player a beat before the first activity kicks off.
	activity_gate.set_initial_delay(GameState.get_float("initial_activity_delay", 30.0))
	var encounter_turns: int = int(GameState.get_default("encounter_turns", 3))
	_setup_llm_client()
	encounter_dispatcher = EncounterDispatcher.new(self, encounter_turns)
	_llm_coordinator = LLMCoordinator.new(self)
	meeting_orchestrator = MeetingOrchestrator.new(self)
	_setup_dialogue()
	var world_scene: Node2D = WorldBuilder.instantiate_world(self, room_config_path.get_base_dir())
	room_bounds = WorldBuilder.derive_bounds(world_scene)
	WorldBuilder.build_perimeter_walls(self, room_bounds, config)
	if world_scene:
		props_container = WorldBuilder.prepare_props(world_scene, config)
		WorldBuilder.synthesize_spawn(world_scene, config)
	else:
		props_container = Node2D.new()
		props_container.name = "Props"
		add_child(props_container)
	_setup_agents_container()
	_setup_player()
	WorldBuilder.build_audio(self, config)
	_setup_ui()
	# Dialogue talks back to world_loader for both chat routing and the
	# "player dismissed the panel" signal (so we can release talking agents).
	dialogue.world_loader = self
	dialogue.dismissed.connect(_on_dialogue_dismissed)
	dialogue.meeting_dismissed.connect(_on_meeting_dismissed)
	_setup_puzzle_layer()
	_setup_save_timer()
	_agent_spawner = AgentSpawner.new(self, agents_container, props_container, player, _character_height(), config)
	_agent_spawner.spawn_all(narration_log, _llm_coordinator.request_arrive)
	get_viewport().size_changed.connect(_on_viewport_resized)
	# Bound LAST, after world_state/action_resolver and every agent exist, so
	# an MCP tools/call arriving the instant the server is bound sees a fully
	# ready world (find_agent works, submit_agent_action has a resolver).
	McpServer.bind_world(self)


func _exit_tree() -> void:
	# Mirror of bind_world() above — fires on scene teardown (quit to menu)
	# and on app quit alike, since Godot frees the whole tree on exit.
	# Without this, McpServer would keep dispatching tools/call against a
	# freed world_loader the moment this scene starts tearing down.
	McpServer.unbind_world()


# MUST run before agents spawn so their first observations and actions see a
# ready WorldState + ActionResolver. Called from _ready() between UI setup
# and agent spawning.
func _setup_puzzle_layer() -> void:
	var world_id: String = str(config.get("id", ""))
	world_state = WorldState.load_for(world_id)
	_warn_unknown_gate_kinds(config, world_id)
	var puzzle_list: Array[Dictionary] = _load_puzzles_for_world(world_id)
	_warn_unknown_starting_items(config, puzzle_list)
	var world_nothing_happens: String = str(config.get("nothing_happens_text", ""))
	var agents_supplier: Callable = _puzzle_agents_supplier
	action_resolver = ActionResolver.new(
		world_state,
		self,
		puzzle_list,
		world_nothing_happens,
		agents_supplier,
	)
	# R21 path (b) — the resolver listens for completed call_agent encounters
	# to credit the invited agent as collaborator (AC-FE-07). The dispatcher
	# exists before this point (constructed earlier in _ready).
	if not encounter_dispatcher.encounter_complete.is_connected(_on_puzzle_encounter_complete):
		encounter_dispatcher.encounter_complete.connect(_on_puzzle_encounter_complete)


func _on_puzzle_encounter_complete(sender_id: String, listener_id: String, context_id: String) -> void:
	if action_resolver == null:
		return
	if action_resolver.on_encounter_complete(sender_id, listener_id, context_id):
		queue_world_state_save(false)


func _process(delta: float) -> void:
	activity_gate.tick(delta)
	_tick_meeting_arrival_watcher()
	# `[diag]` output is Oscar's primary signal for perf regressions
	# (see feedback_diag_first). Release builds skip the print so end
	# users don't see counter spam in stdout.
	if not OS.is_debug_build():
		return
	_diag_accum += delta
	var diag_interval: float = GameState.get_float("diag_log_interval", 2.0)
	if _diag_accum >= diag_interval:
		_diag_accum = 0.0
		var fps: float = Engine.get_frames_per_second()
		var obj_count: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var orphan_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var res_count: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
		var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var tween_count: int = get_tree().get_processed_tweens().size()
		print("[diag] fps=%.1f obj=%d nodes=%d orphans=%d res=%d tweens=%d proc=%.1fms phys=%.1fms" % [
			fps, obj_count, node_count, orphan_count, res_count, tween_count, proc_ms, phys_ms,
		])


func _on_viewport_resized() -> void:
	if not player:
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if not camera:
		return
	var min_zoom: float = _min_camera_zoom()
	if min_zoom <= 0.0:
		return
	# Clamp current zoom — if user was zoomed out further than the new min, snap up.
	var z: float = maxf(camera.zoom.x, min_zoom)
	camera.zoom = Vector2(z, z)


func _min_camera_zoom() -> float:
	if room_bounds.size == Vector2.ZERO:
		return 0.0
	var vp_size := get_viewport().get_visible_rect().size
	return maxf(vp_size.x / room_bounds.size.x, vp_size.y / room_bounds.size.y)


# ── Config ──

func _character_height() -> float:
	"""Room config override → game_config defaults → constant fallback."""
	return float(config.get("character_height", GameState.get_float("character_height", 140.0)))


func _load_config() -> void:
	config = GameState.load_json(room_config_path, "world")
	if config.is_empty():
		push_error("[world] Empty/invalid world config at %s — nothing will spawn." % room_config_path)
		return
	print("[world] Loaded: %s" % config.get("name", room_config_path))


# ── Core Nodes ──

func _setup_llm_client() -> void:
	llm = LLMClient.new()
	llm.name = "LLMClient"
	add_child(llm)
	llm.llm_response_received.connect(_on_llm_response)


func _setup_dialogue() -> void:
	dialogue = DialogueCloud.new()
	dialogue.name = "DialogueCloud"
	add_child(dialogue)


func _setup_agents_container() -> void:
	agents_container = Node2D.new()
	agents_container.name = "Agents"
	add_child(agents_container)


# ── Player ──

func _setup_player() -> void:
	var player_h: float = _character_height()
	_setup_player_body()
	var detection_area: Area2D = _setup_player_detection(player_h)
	_setup_player_camera()
	player.global_position = _resolve_player_spawn()
	player.sprite_path = GameState.get_player_sprite_path()
	player.display_height = player_h
	player.agent_detect_range = player.display_height
	player.dialogue = dialogue
	player.agents_container = agents_container
	player.wants_to_talk.connect(_on_player_wants_to_talk)
	player.wants_to_examine.connect(_on_player_wants_to_examine)
	add_child(player)
	# Detection signals are wired AFTER add_child so the connection lives on
	# an in-tree node — protects against any future Player._ready rebuild of
	# the Area2D from silently dropping these slots.
	player.register_detection_area(detection_area)
	if room_bounds.size != Vector2.ZERO:
		player.set_camera_limits(room_bounds)


func _resolve_player_spawn() -> Vector2:
	var spawn_section: Dictionary = config.get("spawn", {})
	var fallback: Array = GameState.get_default("player_spawn_fallback", [160.0, 120.0])
	var spawn: Variant = spawn_section.get("player", fallback)
	if not (spawn is Array) or (spawn as Array).size() < 2:
		push_warning("[world] spawn.player malformed in world config — using origin")
		return Vector2.ZERO
	var spawn_arr: Array[float] = [float((spawn as Array)[0]), float((spawn as Array)[1])]
	return Vector2(spawn_arr[0], spawn_arr[1])


func _setup_player_body() -> void:
	player = CharacterBody2D.new()
	player.name = "Player"
	player.set_script(PlayerScript)
	player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Player stays on layer 1 (default) but masks layer 2 as well so it
	# still physically blocks against agents, even though agents no longer
	# collide with each other. Default `3` is the bit-OR of layers 1 and 2.
	player.collision_mask = int(GameState.get_default("player_collision_mask", 3))
	# Renders above agents (default z=0) and below canopy (z=10).
	player.z_index = int(GameState.get_default("player_z_index", 5))
	var body_col := CollisionShape2D.new()
	body_col.name = "Collision"
	var body_shape := RectangleShape2D.new()
	var body_size: float = GameState.get_float("player_collision_size", 12.0)
	body_shape.size = Vector2(body_size, body_size)
	body_col.shape = body_shape
	player.add_child(body_col)


## Build the proximity Area2D and parent it under `player`. Returns the
## Area2D so the caller can hand it to `Player.register_detection_area`
## once `player` is added to the scene tree — keeps the `_on_detection_*`
## handlers private to player.gd.
func _setup_player_detection(player_h: float) -> Area2D:
	var detection := Area2D.new()
	detection.name = "Detection"
	var detect_col := CollisionShape2D.new()
	detect_col.name = "Shape"
	var detect_shape := CircleShape2D.new()
	var detect_ratio: float = GameState.get_float("player_detection_ratio", 0.3)
	detect_shape.radius = player_h * detect_ratio
	detect_col.shape = detect_shape
	detection.add_child(detect_col)
	player.add_child(detection)
	return detection


func _setup_player_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	# Start fully zoomed out — just enough to cover the viewport with the image.
	var zoom_floor: float = GameState.get_float("camera_min_zoom_floor", 0.1)
	var initial_zoom: float = maxf(_min_camera_zoom(), zoom_floor)
	camera.zoom = Vector2(initial_zoom, initial_zoom)
	# Camera staggering root cause: project.godot sets
	# `common/physics_interpolation=true`, which means Godot's engine
	# interpolates every Node2D's rendered transform between physics frames
	# on render frames. Camera2D's own `position_smoothing` operates on the
	# raw physics-frame target position, so with smoothing ON the camera
	# lerps toward a value that's one physics tick behind what the renderer
	# is showing the player at — producing visible discrete catch-up jumps.
	# The fix is to disable the camera's own smoothing and rely on the
	# engine interpolation: the camera is a child of the player, so it
	# inherits the player's smoothly-interpolated transform for free and
	# renders frame-perfect without any extra lerping.
	camera.position_smoothing_enabled = false
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	player.add_child(camera)


# ── Agent finder (public — used by dialogue, encounter dispatcher, a2a_router) ──

## Resolve a spawned agent by id. Returns null when the spawner is not yet
## constructed or no agent with that id is present in the world.
func find_agent(agent_id: String) -> Agent:
	if _agent_spawner == null:
		return null
	return _agent_spawner.find(agent_id)


# ── UI ──

func _setup_ui() -> void:
	# z-stack constants are declared at file top — see LAYER_HUD/SIDEBAR/MENU.
	action_prompt = CanvasLayer.new()
	action_prompt.name = "ActionPrompt"
	action_prompt.layer = LAYER_HUD
	action_prompt.set_script(ActionPromptScript)
	action_prompt.player = player
	action_prompt.dialogue = dialogue
	add_child(action_prompt)
	narration_log = CanvasLayer.new()
	narration_log.name = "NarrationLog"
	narration_log.layer = LAYER_SIDEBAR
	narration_log.set_script(NarrationLogScript)
	add_child(narration_log)
	var controls_hint := CanvasLayer.new()
	controls_hint.name = "ControlsHint"
	controls_hint.layer = LAYER_HUD
	controls_hint.set_script(ControlsHintScript)
	controls_hint.hints = [
		{"glyph": "\u2B8B", "font_size": UITheme.FONT_SIZE_HUD, "text": Strings.get_string("controls.zoom")},
		{"mod": "Ctrl", "key": "L", "text": Strings.get_string("controls.toggle_log")},
		{"glyph": "C", "text": Strings.get_string("world.call_agent")},
		{"mod": "Shift", "key": "C", "text": Strings.get_string("world.summon_meeting")},
	]
	add_child(controls_hint)
	menu_builder = WorldMenuBuilder.new(self)
	menu_builder.build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Esc hierarchy (world_loader layer).
		# LogModal owns Esc while open (it calls set_input_as_handled in its
		# own _input, so this usually won't fire then — but guard anyway).
		# dialogue_cloud handles its own Esc via _input() before this fires,
		# so only the menu_builder modals need handling here.
		if LogModal.is_any_open():
			return
		get_viewport().set_input_as_handled()
		if not menu_builder.try_dismiss_open():
			menu_builder.show_quit_confirm()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		# Plain C / Shift+C trigger call flows. Ctrl/Alt modifiers are
		# excluded so system shortcuts (copy, etc.) stay out of our way.
		if key_event.keycode == KEY_C and not key_event.ctrl_pressed and not key_event.alt_pressed:
			get_viewport().set_input_as_handled()
			if key_event.shift_pressed:
				menu_builder.show_meeting_picker()
			else:
				menu_builder.show_call_picker()


# ── Agent summon / meeting ──

## Tell one agent to pathfind to the player. When they physically arrive,
## open their chat and fire the "your user is calling you" narrative prompt.
## `_pending_calls` deduplicates re-presses on the same in-flight agent so a
## second Call doesn't connect a second handler that would double-open the
## dialogue on arrival.
func call_agent_to_player(agent_id: String) -> void:
	if not is_instance_valid(player):
		return
	var agent: Agent = find_agent(agent_id)
	if agent == null:
		return
	agent.summon_to(player)
	menu_builder.show_toast(Strings.get_string("world.toast_calling_agent", {"name": agent.display_name}))
	# Don't replace an active group meeting chat with a 1:1 panel.
	if meeting_active:
		return
	if _pending_calls.has(agent_id):
		return
	_pending_calls[agent_id] = true
	agent.call_arrived.connect(_on_agent_call_arrived.bind(agent_id), CONNECT_ONE_SHOT)
	# If the agent is freed before arriving, the call_arrived one-shot never
	# fires and _pending_calls would keep a stale entry that silently swallows
	# the next Call press. tree_exiting clears it regardless of the cause.
	agent.tree_exiting.connect(_on_pending_call_agent_exiting.bind(agent_id), CONNECT_ONE_SHOT)


func _on_agent_call_arrived(agent_id: String) -> void:
	_pending_calls.erase(agent_id)
	# A meeting may have been summoned after the original Call press but
	# before the agent arrived. The 1:1 panel must not stomp on the group
	# chat — drop the arrival quietly and let the meeting own the UI.
	if meeting_active:
		return
	if not is_instance_valid(dialogue):
		return
	var agent: Agent = find_agent(agent_id)
	if agent == null:
		return
	agent.start_talking()
	dialogue.show_input(agent_id, agent.display_name)
	_llm_coordinator.request_call(agent_id)


func _on_pending_call_agent_exiting(agent_id: String) -> void:
	_pending_calls.erase(agent_id)


## "Summon Meeting" — tells the chosen agents (or all agents when
## `selected_ids` is empty) to gather within the meeting zone around the
## player. Each agent picks its own landing spot dynamically (see
## `Agent._pick_meeting_landing`); world_loader no longer pre-allocates
## specific slots, which is what caused agents to commit to stale fixed
## points. Busy agents get their invitation via `queue_meeting` and auto-join
## the moment their current activity finishes — no agent is silently dropped
## from the call. Re-pressing during an active meeting prompts every agent to
## re-evaluate.
##
## Invited roster is also snapshotted into `_meeting_invited_ids` so the
## arrival watcher in `_process` knows who to wait for before opening the
## unified group chat. Re-pressing during an active meeting (before the chat
## has opened) refreshes the roster; re-pressing with the chat already open
## is a no-op for the conversation layer — only the spatial assignments get
## refreshed.
func call_all_agents_to_player(selected_ids: Array[String] = []) -> void:
	if not is_instance_valid(player) or agents_container == null:
		return
	var radius: float = GameState.get_float("meeting_circle_radius", 220.0)
	var filter: Dictionary = {}
	for id: String in selected_ids:
		filter[id] = true
	var invited: Array[String] = []
	for child: Node in agents_container.get_children():
		if not (child is Agent):
			continue
		var agent: Agent = child
		if not filter.is_empty() and not filter.has(agent.agent_id):
			continue
		invited.append(agent.agent_id)
		if agent.is_socially_busy():
			agent.queue_meeting(player, radius)
		else:
			agent.join_meeting(player, radius)
	if invited.is_empty():
		return
	if not _meeting_chat_open:
		_meeting_invited_ids = invited
	meeting_active = true
	menu_builder.show_toast(Strings.get_string("world.toast_summon_meeting"))


## Release every agent from meeting mode. Held agents stay where they are;
## arriving agents finish whatever path they were on. The state machine
## resumes normal wander/observe/encounter rolls on the next physics frame.
## Also tears down the conversation layer: stops the orchestrator and closes
## the unified chat if open.
func end_meeting() -> void:
	if not meeting_active:
		return
	meeting_active = false
	if agents_container != null:
		for child: Node in agents_container.get_children():
			if child is Agent:
				(child as Agent).leave_meeting()
	if meeting_orchestrator != null:
		meeting_orchestrator.end()
	if _meeting_chat_open and is_instance_valid(dialogue):
		dialogue.close_meeting()
	_meeting_chat_open = false
	_meeting_invited_ids.clear()
	menu_builder.set_menu_visible(true)
	menu_builder.show_toast(Strings.get_string("world.toast_meeting_ended"))


func _tick_meeting_arrival_watcher() -> void:
	# Once every invited agent is held at the meeting circle, open the
	# unified chat exactly once. Re-pressing Summon Meeting during the
	# gather refreshes _meeting_invited_ids (until the chat opens) so
	# late-added agents still count. Missing/destroyed agents are
	# dropped from the wait list silently. Work arrays are pre-allocated
	# fields (_meeting_attendees_buf / _meeting_ids_buf) cleared in place
	# so the per-frame gather window does not allocate.
	if not meeting_active or _meeting_chat_open or _meeting_invited_ids.is_empty():
		return
	_meeting_attendees_buf.clear()
	_meeting_ids_buf.clear()
	for id: String in _meeting_invited_ids:
		var agent: Agent = find_agent(id)
		if agent == null:
			continue
		if not agent.is_meeting_held():
			return  # still traveling, wait another frame
		_meeting_attendees_buf.append({"id": agent.agent_id, "name": agent.display_name})
		_meeting_ids_buf.append(agent.agent_id)
	if _meeting_attendees_buf.is_empty():
		# Every invited agent disappeared before arriving — tear the meeting
		# down cleanly instead of leaving meeting_active stuck true with an
		# empty roster.
		end_meeting()
		return
	_meeting_chat_open = true
	menu_builder.set_menu_visible(false)
	if is_instance_valid(dialogue):
		dialogue.show_meeting(_meeting_attendees_buf)
	if meeting_orchestrator != null:
		meeting_orchestrator.start(_meeting_ids_buf)
	menu_builder.show_toast(Strings.get_string("world.toast_meeting_chat_open"))


## Called by dialogue_cloud when the player submits a message in meeting
## mode. Delegates directly to the orchestrator; response rendering happens
## back through `dialogue.append_meeting_line` as each agent replies.
func request_meeting_message(text: String) -> void:
	if meeting_orchestrator != null:
		meeting_orchestrator.submit_user_message(text)


func _on_meeting_dismissed() -> void:
	# The player closed the meeting panel via Esc or the X button.
	# Funnel through end_meeting() so spatial release + orchestrator
	# teardown happen the same way the End Meeting button does.
	end_meeting()


# ── Player / Dialogue Signal Handlers ──

func _on_player_wants_to_talk(agent: Agent) -> void:
	if not is_instance_valid(agent):
		return
	agent.start_talking()
	dialogue.show_input(agent.agent_id, agent.display_name)


func _on_player_wants_to_examine(prop: Prop) -> void:
	if not is_instance_valid(prop):
		return
	var text: String = Strings.get_string("world.examine_prop_format", {
		"color": "#" + UITheme.ACCENT_HEX,
		"name": prop.prop_name,
		"description": prop.prop_description,
	})
	dialogue.show_text(text)


func _on_dialogue_dismissed() -> void:
	# Release whichever agent was mid-conversation back to its normal loop.
	# dialogue.dismissed fires BEFORE dialogue.current_agent_id is cleared
	# (see dialogue_cloud.dismiss()), so we can target the one agent that
	# was talking instead of iterating the whole container.
	if not is_instance_valid(dialogue):
		return
	var agent: Agent = find_agent(dialogue.current_agent_id)
	if agent != null:
		agent.stop_talking()


# ── LLM + encounter facade (public API — kept stable for external callers) ──

func _on_llm_response(request_id: String, text: String) -> void:
	llm_request_queue.dispatch(request_id, text)


## Fire an observation prompt for `agent_id` against the named entity.
## Routed through `LLMCoordinator`; result narration arrives via the same
## queue-dispatched response path as every other LLM request.
func request_agent_observe(agent_id: String, entity_id: String, entity_name: String, entity_desc: String) -> void:
	_llm_coordinator.request_observe(agent_id, entity_id, entity_name, entity_desc)


## Fire a player-talk prompt for `agent_id` with the player's free-form
## message. Bypasses ActivityGate per the player-initiated chat rule.
func request_agent_talk(agent_id: String, player_message: String) -> void:
	_llm_coordinator.request_talk(agent_id, player_message)


## Extended signature (Story 008 / TR-puzzle-026). context_id is forwarded to
## EncounterDispatcher.start() unchanged; defaults to "" for proximity callers.
func request_agent_encounter(sender_id: String, listener_id: String, context_id: String = "") -> void:
	if encounter_dispatcher == null:
		return
	encounter_dispatcher.start(sender_id, listener_id, context_id)


## Facade over activity_gate for external callers (TD-002) — ActionResolver
## asks through this instead of reaching into the activity_gate property.
## Null-safe so a mid-construction loader answers false instead of crashing.
func can_trigger_activity() -> bool:
	return activity_gate != null and activity_gate.can_trigger()


# ── Puzzle layer helpers (Story 006) ──

## Single choke point every action-resolution transport routes through
## before ActionResolver.resolve() runs — XML via
## LLMCoordinator._resolve_action_from_response, MCP via mcp_server.gd.
## Actions always resolve immediately: `on_result` is invoked synchronously,
## before this call returns, with ActionResolver.resolve()'s own return
## value ({narration, state_changed}) — there is no approval hold, so both
## transports see the exact same result shape they always have. `source` is
## caller provenance ("xml" / "mcp") — not currently interpreted here, kept
## for callers that may want it for logging.
func submit_agent_action(agent: Object, action: Dictionary, source: String, on_result: Callable) -> void:
	if action_resolver == null:
		on_result.call({"narration": "", "state_changed": false})
		return
	on_result.call(action_resolver.resolve(agent, action))


## Debounced persistence for the puzzle layer. force=false restarts the
## debounce timer (most actions); force=true cancels the timer and flushes
## synchronously (solve broadcasts per R15). Debounce interval is
## `defaults.world_state_save_debounce` (default 5s).
func queue_world_state_save(force: bool) -> void:
	if world_state == null:
		return
	if force:
		if _save_timer != null:
			_save_timer.stop()
		world_state.flush()
		return
	if _save_timer != null:
		_save_timer.start()


func _setup_save_timer() -> void:
	_save_timer = Timer.new()
	_save_timer.name = "SaveDebounceTimer"
	_save_timer.one_shot = true
	# Story 006 Implementation Notes prescribe 5s; tunable via defaults.
	_save_timer.wait_time = GameState.get_float("world_state_save_debounce", 5.0)
	_save_timer.timeout.connect(_on_save_timer_timeout)
	add_child(_save_timer)


func _on_save_timer_timeout() -> void:
	if world_state != null:
		world_state.flush()


## Scan assets/puzzles/*.json, return puzzles whose "world" field matches
## world_id. Gracefully handles an absent directory (AC-PERF-03 — no
## puzzle files must produce identical v0.7 behaviour).
func _load_puzzles_for_world(world_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world_id.is_empty():
		return result
	var dir_path: String = "res://assets/puzzles/"
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return result
	for filename: String in dir.get_files():
		if not filename.ends_with(".json"):
			continue
		var data: Dictionary = GameState.load_json(dir_path + filename, "puzzle")
		if not data.is_empty() and str(data.get("world", "")) == world_id:
			result.append(data)
	return result


## Supplier callable passed to ActionResolver so it can enumerate live
## agents for solve broadcasts without reaching into our internals.
## Returned as untyped Array — resolver casts entries to Object.
func _puzzle_agents_supplier() -> Array:
	var out: Array = []
	if agents_container == null:
		return out
	for child: Node in agents_container.get_children():
		if child is Agent:
			out.append(child)
	return out


## Story 005 deferral — emit a load-time push_warning for each prop layer
## whose gate.kind is not one of {"skill", "item", "flag"}. Render-time
## false-evaluation already happens in PropLayers; this surfaces authoring
## mistakes at load time instead of silently showing only the base.
func _warn_unknown_gate_kinds(cfg: Dictionary, world_id: String) -> void:
	var props: Variant = cfg.get("props", [])
	if not (props is Array):
		return
	const KNOWN: Array[String] = ["skill", "item", "flag"]
	for prop_variant: Variant in (props as Array):
		if not (prop_variant is Dictionary):
			continue
		var prop: Dictionary = prop_variant
		var prop_id: String = str(prop.get("id", prop.get("entity_id", "")))
		var layers: Variant = prop.get("layers", [])
		if not (layers is Array):
			continue
		var idx: int = 0
		for layer_variant: Variant in (layers as Array):
			var kind: String = _extract_gate_kind(layer_variant)
			if not kind.is_empty() and not (kind in KNOWN):
				push_warning("[world_loader] World '%s' prop '%s' layer %d uses unknown gate kind '%s' — layer will be invisible to all agents." % [world_id, prop_id, idx, kind])
			idx += 1


## Flatten the three guarded casts (layer → gate → kind) into one helper so
## the gate-warning loop above stays readable. Returns "" when the layer
## entry, its gate, or its kind field is absent or malformed.
static func _extract_gate_kind(layer_variant: Variant) -> String:
	if not (layer_variant is Dictionary):
		return ""
	var gate: Variant = (layer_variant as Dictionary).get("gate", {})
	if not (gate is Dictionary):
		return ""
	return str((gate as Dictionary).get("kind", ""))


## TD-001 / GDD AC-CB-02 edge-2 — warn when an agent's starting_inventory
## names an item no puzzle rule or prop layer in this world can ever touch.
## The item stays in inventory (behavior unchanged); this only surfaces
## authoring gaps at load time. Vocabulary + diff computed by the pure
## WorldState static so it stays headless-testable.
func _warn_unknown_starting_items(cfg: Dictionary, puzzle_list: Array[Dictionary]) -> void:
	var unknown: Array[Dictionary] = WorldState.unknown_starting_items(
		GameState.agents, puzzle_list, cfg.get("props", []))
	for entry: Dictionary in unknown:
		push_warning("[world_loader] Agent '%s' starting_inventory item '%s' matches no puzzle rule or prop layer in this world." % [entry["agent_id"], entry["item_id"]])


## Return the config.props[] entry matching entity_id (checks both
## "id" and "entity_id" keys for robustness — world JSON uses
## "entity_id" today; ADR examples use "id"). Returns {} when no match.
func find_prop_config(entity_id: String) -> Dictionary:
	var props: Variant = config.get("props", [])
	if not (props is Array):
		return {}
	for prop_variant: Variant in (props as Array):
		if not (prop_variant is Dictionary):
			continue
		var prop: Dictionary = prop_variant
		if str(prop.get("entity_id", "")) == entity_id:
			return prop
		if str(prop.get("id", "")) == entity_id:
			return prop
	return {}
