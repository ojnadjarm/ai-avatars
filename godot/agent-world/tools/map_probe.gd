extends Node2D
## Visual world probe — loads one world through the scene-based
## WorldBuilder path (no agents, no LLM, no UI), prints structural
## checks, saves a full-world screenshot, and quits.
##
## Runs WITHOUT the editor open (WSL2 stutter rule). A display (WSLg)
## is required for the screenshot — --headless renders nothing.
##
## Usage:
##   godot --path godot/agent-world res://tools/map_probe.tscn -- <world.json> <out.png>

var _shot_path: String = ""
var _frames_waited: int = 0

## Frames to let the renderer settle before capturing. First frames can
## present an empty backbuffer; a handful of draws guarantees the world
## textures are on screen.
const SETTLE_FRAMES := 5


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("[probe] Usage: ... -- <world.json> <out.png>")
		get_tree().quit(2)
		return
	var sidecar_path: String = args[0]
	_shot_path = args[1]

	var config: Dictionary = GameState.load_json(sidecar_path, "probe")
	if config.is_empty():
		push_error("[probe] Could not load %s" % sidecar_path)
		get_tree().quit(2)
		return

	var world_scene: Node2D = WorldBuilder.instantiate_world(self, sidecar_path.get_base_dir())
	if world_scene == null:
		get_tree().quit(2)
		return
	var bounds: Rect2 = WorldBuilder.derive_bounds(world_scene)
	WorldBuilder.build_perimeter_walls(self, bounds, config)
	var props_container: Node2D = WorldBuilder.prepare_props(world_scene, config)
	WorldBuilder.synthesize_spawn(world_scene, config)

	var walls_node: Node2D = world_scene.get_node_or_null("Walls") as Node2D
	var wall_count: int = walls_node.get_child_count() if walls_node else 0
	print("[probe] id=%s bounds=%s props=%d walls=%d spawn=%s" % [
		config.get("id", "?"), bounds, props_container.get_child_count(),
		wall_count, config.get("spawn", {}),
	])
	if bounds.size == Vector2.ZERO:
		push_error("[probe] FAIL: zero bounds")
		get_tree().quit(1)
		return
	var synthesized: Array = config.get("props", [])
	if synthesized.size() != props_container.get_child_count():
		push_error("[probe] FAIL: synthesized props (%d) != prop nodes (%d)" % [
			synthesized.size(), props_container.get_child_count()])
		get_tree().quit(1)
		return
	for entry: Dictionary in synthesized:
		if str(entry.get("name", "")) == "" or str(entry.get("description", "")) == "":
			push_error("[probe] FAIL: prop %s missing sidecar prose" % entry.get("entity_id", "?"))
			get_tree().quit(1)
			return

	_fit_camera(bounds)


func _fit_camera(bounds: Rect2) -> void:
	var camera := Camera2D.new()
	camera.position = bounds.get_center()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = minf(vp.x / bounds.size.x, vp.y / bounds.size.y)
	camera.zoom = Vector2(fit, fit)
	add_child(camera)
	camera.make_current()


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_frames_waited += 1
	if _frames_waited < SETTLE_FRAMES:
		return
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(_shot_path)
	if err != OK:
		push_error("[probe] FAIL: could not save %s (%d)" % [_shot_path, err])
		get_tree().quit(1)
		return
	print("[probe] screenshot → %s" % _shot_path)
	print("[probe] PASS")
	get_tree().quit(0)
