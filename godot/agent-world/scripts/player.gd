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
## Shift-run: speed and walk-cycle fps both scale by this, so the planted foot stays still.
var sprint_mult: float = 2.5
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

## Y-sorted layer (sprites below the feet line cover the player) and always-in-front layers (canopy, fg).
var ysort_layer: Node2D
var front_layers: Array[Node2D] = []
var _ghost: AnimatedSprite2D
var _occlusion_accum: float = 0.0
var _head_y: float = 0.0

const OCCLUSION_INTERVAL := 0.1
const GHOST_Z := 14
const GHOST_SHADER := """
shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float a = texture(TEXTURE, UV).a;
	float n = min(min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	COLOR = vec4(1.0, 0.86, 0.52, max(a * (1.0 - n) * 0.9, a * 0.28));
}
"""


func _ready() -> void:
	max_speed = GameState.get_float("player_max_speed", max_speed)
	acceleration = GameState.get_float("player_acceleration", acceleration)
	friction = GameState.get_float("player_friction", friction)
	sprint_mult = GameState.get_float("player_sprint_multiplier", sprint_mult)
	_setup_sprite()
	max_speed = WorldBuilder.walk_speed(char_sprite, max_speed)
	_head_y = WorldBuilder.head_y(char_sprite, -display_height * 0.8)
	_setup_ghost()


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
	char_sprite.night_rim = true
	if display_height > 0.0:
		char_sprite.display_height = display_height
	add_child(char_sprite)
	char_sprite.load_spritesheet(sprite_path)


## Outline silhouette drawn above trees and canopy, shown only while something covers the player.
func _setup_ghost() -> void:
	_ghost = AnimatedSprite2D.new()
	_ghost.name = "Ghost"
	_ghost.sprite_frames = char_sprite.sprite_frames
	_ghost.centered = char_sprite.centered
	_ghost.offset = char_sprite.offset
	_ghost.scale = char_sprite.scale
	_ghost.z_as_relative = false
	_ghost.z_index = GHOST_Z
	var shader := Shader.new()
	shader.code = GHOST_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_ghost.material = mat
	_ghost.visible = false
	add_child(_ghost)


func _process(delta: float) -> void:
	_occlusion_accum += delta
	if _occlusion_accum >= OCCLUSION_INTERVAL:
		_occlusion_accum = 0.0
		_ghost.visible = is_occluded()
	if _ghost.visible:
		_ghost.animation = char_sprite.animation
		_ghost.frame = char_sprite.frame
		_ghost.flip_h = char_sprite.flip_h


## True when an opaque pixel of a sprite drawn in front covers the player's head, chest or shins.
func is_occluded() -> bool:
	var probes: Array[Vector2] = []
	for f: float in [0.15, 0.5, 0.85]:
		probes.append(global_position + Vector2(0.0, _head_y * f))
	if ysort_layer and _behind_any(ysort_layer, probes):
		return true
	for layer: Node2D in front_layers:
		for child: Node in layer.get_children():
			var s := child as Sprite2D
			if s and _covers(s, probes):
				return true
	return false


## A y-sorted sprite below the player's feet covers a probe; descends into nested y-sorted chunk nodes near the probes.
func _behind_any(parent: Node, probes: Array[Vector2]) -> bool:
	for child: Node in parent.get_children():
		var s := child as Sprite2D
		if s:
			if s.global_position.y > global_position.y and _covers(s, probes):
				return true
		elif child is Node2D and (child as Node2D).y_sort_enabled and _chunk_near(child, probes) and _behind_any(child, probes):
			return true
	return false


## False for a y-sorted chunk whose "rect" meta (world bounds of its sprites) misses every probe.
func _chunk_near(chunk: Node, probes: Array[Vector2]) -> bool:
	if not chunk.has_meta("rect"):
		return true
	var r: Rect2 = chunk.get_meta("rect")
	for p: Vector2 in probes:
		if r.has_point(p):
			return true
	return false


## Reads the sprite's "mask" meta (frame-0 alpha BitMap) when set; is_pixel_opaque otherwise.
func _covers(s: Sprite2D, probes: Array[Vector2]) -> bool:
	if not s.visible or s.texture == null:
		return false
	var rect: Rect2 = s.get_rect()
	var bm: BitMap = s.get_meta("mask") if s.has_meta("mask") else null
	for p: Vector2 in probes:
		var local: Vector2 = s.to_local(p)
		if not rect.has_point(local):
			continue
		if bm:
			var q := Vector2i(local - rect.position)
			if q.x < bm.get_size().x and q.y < bm.get_size().y and bm.get_bitv(q):
				return true
		elif s.is_pixel_opaque(local):
			return true
	return false


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
	var running := is_moving and Input.is_key_pressed(KEY_SHIFT)
	if char_sprite:
		char_sprite.speed_scale = sprint_mult if running else 1.0

	if is_moving:
		input = input.normalized()
		velocity = velocity.move_toward(input * max_speed * (sprint_mult if running else 1.0), acceleration * delta)
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

	# Zoom with scroll wheel, one integer pixel level per notch
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var camera := get_node_or_null("Camera2D") as Camera2D
		if camera:
			var map_size := Vector2(camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top)
			var s: int = PixelZoom.stretch_factor(Vector2(get_window().size))
			var levels: Array[float] = PixelZoom.levels(s, PixelZoom.BASE_VIEW, map_size, GameState.get_float("camera_zoom_max_mult", 2.0))
			var dir: int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			var z: float = PixelZoom.step(camera.zoom.x, dir, levels)
			camera.zoom = Vector2(z, z)
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
