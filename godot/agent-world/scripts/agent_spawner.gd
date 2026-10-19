class_name AgentSpawner
extends RefCounted
## Spawns agents into a world. Holds the dependencies each new agent
## needs — container, player, props, display height, and a reference
## back to world_loader (which agents use as their context for activity
## gates, room bounds, and LLM requests).

const SPAWN_FAN_RADIUS := 60.0

var world_loader: WorldLoader
var agents_container: Node2D
var props_container: Node2D
var player: CharacterBody2D
var display_height: float
var config: Dictionary


func _init(wl: WorldLoader, container: Node2D, props: Node2D, pl: CharacterBody2D, height: float, cfg: Dictionary) -> void:
	world_loader = wl
	agents_container = container
	props_container = props
	player = pl
	display_height = height
	config = cfg


func find(agent_id: String) -> Agent:
	for child: Node in agents_container.get_children():
		if child.name == agent_id and child is Agent:
			return child
	return null


func spawn_all(narration_log: CanvasLayer, on_arrive: Callable) -> void:
	# Only enabled agents get spawned — disabled agents don't exist in the world.
	var enabled_ids: Array = []
	for aid in GameState.agents.keys():
		if GameState.agents[aid].get("enabled", true):
			enabled_ids.append(aid)
	var total: int = enabled_ids.size()
	for i in range(total):
		var agent_id: String = enabled_ids[i]
		if find(agent_id):
			continue
		var agent_cfg: Dictionary = GameState.agents[agent_id]
		_spawn_one(agent_id, agent_cfg, i, total, narration_log)
		# Arrival always fires, regardless of the interactions flag.
		# `interactions` gates autonomous behavior (wandering, observation,
		# encounters), but the player can still initiate dialogue with a
		# disabled-interaction agent — and that agent needs the current
		# world in its session for any response to make sense. The
		# same-world skip inside request_arrive suppresses redundant
		# re-entry prompts automatically.
		on_arrive.call(agent_id)
		# Mark the visit AFTER on_arrive — request_arrive reads the
		# pre-visit state to compute is_new for the prompt.
		var spawned: Agent = find(agent_id)
		if spawned and spawned.memory:
			spawned.memory.visit_location(config.get("id", ""))
			spawned.memory.save_to_disk()
	var current_location: String = config.get("id", "")
	print("[world] %s — %d agents" % [current_location, total])
	narration_log.add_entry(
		Strings.get_string("world.entered", {"name": config.get("name", current_location)}),
		"event",
	)


func _spawn_one(agent_id: String, info: Dictionary, index: int, total: int, narration_log: CanvasLayer) -> void:
	var agent := CharacterBody2D.new()
	agent.name = agent_id
	agent.set_script(load("res://scripts/agent.gd"))
	agent.agent_id = agent_id
	agent.display_name = GameState.str_safe(info, "display_name", agent_id)
	agent.interactions = info.get("interactions", true)
	agent.wandering = info.get("wandering", true)
	agent.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Agents live on layer 2 and only mask layer 1 — they physically collide
	# with walls, props, and the player, but pass straight through each
	# other. Prevents RVO/collision deadlocks when two agents meet, since
	# the conversational encounter system is what we actually use to
	# resolve proximity.
	agent.collision_layer = 2
	agent.collision_mask = 1
	agent.world_loader = world_loader
	agent.player = player
	agent.props_container = props_container
	agent.display_height = display_height
	# Behavior tuning (move_speed, encounter ranges, curiosity, etc.)
	# is loaded from game_config.defaults inside Agent._load_defaults()
	# which runs on _ready.

	# Narrower width, top edge of the collision sits at y=0 (body origin).
	var col_w: float = display_height * 0.50
	var col_h: float = display_height * 0.70
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(col_w, col_h)
	collision.shape = shape
	collision.position = Vector2(0, -display_height * 0.3)
	agent.add_child(collision)

	var char_sprite := AnimatedSprite2D.new()
	char_sprite.name = "CharSprite"
	char_sprite.set_script(load("res://scripts/character_sprite.gd"))
	char_sprite.display_height = display_height
	agent.add_child(char_sprite)
	var sprite_file: String = GameState.get_agent_sprite(agent_id)
	char_sprite.load_spritesheet(GameState.resolve_character_asset(sprite_file))

	var label := Label.new()
	label.text = GameState.str_safe(info, "display_name", agent_id)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", UITheme.agent_color(agent_id))
	label.add_theme_color_override("font_shadow_color", UITheme.LABEL_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.name = "NameLabel"
	# Pivot at the label's center so counter-scaling stays anchored on the agent.
	label.pivot_offset = Vector2(30, 10)
	label.position = Vector2(-30, -70)
	# Render the name above the canopy (canopy is z=10).
	label.z_as_relative = false
	label.z_index = 15
	agent.add_child(label)

	agent.emotion_engine = EmotionEngine.new()
	agent.memory = AgentMemory.load_from_disk(agent_id)
	# NB: visit_location is NOT called here — request_arrive needs to
	# read the pre-visit state to compute is_new. The spawner marks the
	# visit in spawn_all, AFTER on_arrive.call has fired.

	var spawn: Array = config.get("spawn", {}).get("agents", [180, 120])
	var spawn_center := Vector2(spawn[0], spawn[1])
	# Fan agents around the spawn point so they don't stack when wandering is off.
	if total > 1:
		var angle: float = TAU * float(index) / float(total)
		spawn_center += Vector2(cos(angle), sin(angle)) * SPAWN_FAN_RADIUS
	agent.global_position = spawn_center
	agents_container.add_child(agent)

	var display_name: String = GameState.str_safe(info, "display_name", agent_id)
	print("[world] Spawned: %s" % display_name)
	var colored := "[color=%s]%s[/color]" % [UITheme.agent_color_hex(agent_id), display_name]
	narration_log.add_entry(Strings.get_string("world.agent_here", {"name": colored}), "event")
