extends CharacterBody2D

## Emitted when the player wants to start a conversation with a nearby agent.
## world_loader owns the resulting state transition and dialogue display.
signal wants_to_talk(agent: Agent)
## Emitted when the player wants to examine a nearby prop.
signal wants_to_examine(prop: Prop)

# Movement tuning — populated from game_config.defaults in _ready.
var max_speed: float = 300.0
var acceleration: float = 2000.0
var friction: float = 1500.0
@export var sprite_path: String = "player_default.png"
@export var display_height: float = 0.0
var agent_detect_range: float = 150.0

enum Facing { DOWN, UP, LEFT, RIGHT }
var facing: int = Facing.DOWN
var was_moving: bool = false

# Injected by world_loader before first frame.
var dialogue: DialogueCloud
var agents_container: Node2D

var nearby_prop: Prop = null
var nearby_agent: Agent = null

var char_sprite: AnimatedSprite2D


func _ready() -> void:
	max_speed = GameState.get_float("player_max_speed", max_speed)
	acceleration = GameState.get_float("player_acceleration", acceleration)
	friction = GameState.get_float("player_friction", friction)
	_setup_sprite()


## Wire the player's prop-detection slots to an Area2D built upstream by
## world_loader. Keeps the `_on_detection_area_*` handlers private to player.gd
## while letting world_loader own Area2D construction (radius depends on
## `display_height`, which is known at world build time).
func register_detection_area(area: Area2D) -> void:
	area.area_entered.connect(_on_detection_area_entered)
	area.area_exited.connect(_on_detection_area_exited)


func set_camera_limits(bounds: Rect2) -> void:
	var camera := get_node_or_null("Camera2D") as Camera2D
	if not camera or bounds.size == Vector2.ZERO:
		return
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)
	camera.limit_smoothed = true
	print("[player] camera=%s" % bounds)


func _setup_sprite() -> void:
	char_sprite = AnimatedSprite2D.new()
	char_sprite.name = "CharSprite"
	char_sprite.set_script(load("res://scripts/character_sprite.gd"))
	if display_height > 0.0:
		char_sprite.display_height = display_height
	add_child(char_sprite)
	char_sprite.load_spritesheet(sprite_path)


func _is_typing() -> bool:
	return dialogue.is_input_mode and dialogue.input_field != null and dialogue.input_field.has_focus()


func _physics_process(delta: float) -> void:
	if _is_typing():
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return

	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		input.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		input.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		input.y += 1

	var is_moving := input != Vector2.ZERO

	if is_moving:
		input = input.normalized()
		velocity = velocity.move_toward(input * max_speed, acceleration * delta)
		_update_facing(input)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	_update_animation(is_moving)
	_check_agent_proximity()


func _update_facing(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		facing = Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	else:
		facing = Facing.DOWN if direction.y > 0.0 else Facing.UP


func _update_animation(is_moving: bool) -> void:
	if not char_sprite:
		return
	var dir_name: String
	match facing:
		Facing.DOWN: dir_name = "down"
		Facing.UP: dir_name = "up"
		Facing.LEFT: dir_name = "left"
		Facing.RIGHT: dir_name = "right"
		_: dir_name = "down"

	if is_moving:
		var anim := "walk_" + dir_name
		if char_sprite.animation != anim:
			char_sprite.play(anim)
	else:
		var anim := "idle_" + dir_name
		if char_sprite.animation != anim or was_moving:
			char_sprite.play(anim)

	was_moving = is_moving


func _unhandled_input(event: InputEvent) -> void:
	if _is_typing():
		return

	# Zoom with scroll wheel
	if event is InputEventMouseButton:
		var camera := get_node_or_null("Camera2D") as Camera2D
		if camera:
			# Calculate min zoom so viewport doesn't exceed map bounds
			var vp_size := get_viewport().get_visible_rect().size
			var map_w := float(camera.limit_right - camera.limit_left)
			var map_h := float(camera.limit_bottom - camera.limit_top)
			var min_zoom := 0.3
			if map_w > 0 and map_h > 0:
				min_zoom = maxf(vp_size.x / map_w, vp_size.y / map_h)
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				camera.zoom = clampf_vec(camera.zoom * 1.1, min_zoom, 3.0)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				camera.zoom = clampf_vec(camera.zoom * 0.9, min_zoom, 3.0)
				get_viewport().set_input_as_handled()

	if event.is_action_pressed("interact"):
		if dialogue.is_showing:
			dialogue.dismiss()
		elif nearby_agent:
			print("[player] talk -> %s" % nearby_agent.display_name)
			wants_to_talk.emit(nearby_agent)
		elif nearby_prop:
			print("[player] examine %s" % nearby_prop.prop_name)
			wants_to_examine.emit(nearby_prop)


static func clampf_vec(v: Vector2, min_val: float, max_val: float) -> Vector2:
	return Vector2(clampf(v.x, min_val, max_val), clampf(v.y, min_val, max_val))


func _check_agent_proximity() -> void:
	if not agents_container:
		if nearby_agent:
			nearby_agent = null
		return

	var closest: Agent = null
	var closest_dist: float = agent_detect_range

	for child: Node in agents_container.get_children():
		if child is Agent:
			var candidate: Agent = child
			var dist: float = global_position.distance_to(candidate.global_position)
			if dist < closest_dist:
				closest = candidate
				closest_dist = dist

	if closest != nearby_agent:
		if closest:
			print("[player] near %s" % closest.display_name)
		nearby_agent = closest


func _on_detection_area_entered(area: Area2D) -> void:
	if area is Prop and (area as Prop).prop_id != "":
		nearby_prop = area
		print("[player] near %s" % (area as Prop).prop_name)


func _on_detection_area_exited(area: Area2D) -> void:
	if area == nearby_prop:
		nearby_prop = null
