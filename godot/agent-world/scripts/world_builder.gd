class_name WorldBuilder
extends RefCounted
## Stateless scene-based world construction. A world is a folder:
##   assets/worlds/<id>/world.tscn — geometry, art, physics
##   assets/worlds/<id>/world.json — agent-facing prose sidecar (loaded
##                                   into `config` by world_loader)
##
## Scene contract (well-known child names, all optional unless noted):
##   Ground      TileMapLayer — bounds source: get_used_rect() × tile size
##   GroundDetail TileMapLayer — decals; no loader semantics
##   Obstacles   TileMapLayer — collision comes from its TileSet physics layer
##   Canopy      TileMapLayer or Sprite2D — occlusion; z from defaults
##   Background  Sprite2D — bounds source for painterly worlds (fallback
##               when there is no Ground layer)
##   Walls       Node2D of StaticBody2D — shapes tiles can't express
##   Props       Node2D of Prop (Area2D) — node name = entity_id; prose is
##               enriched from the sidecar at load time
##   SpawnPoints Node2D with Player / Agents Marker2D children
##
## After prepare_props()/synthesize_spawn() run, `config` carries the same
## "props" array and "spawn" dict shapes the legacy flat format had, so
## agents, the puzzle layer, and prompt building stay format-agnostic.


## Instantiate <world_dir>/world.tscn under root and apply configured
## z-indexes. Returns null (with an error) when the scene is missing.
static func instantiate_world(root: Node2D, world_dir: String) -> Node2D:
	var scene_path: String = world_dir.path_join("world.tscn")
	if not ResourceLoader.exists(scene_path):
		push_error("[world] Missing world scene: %s" % scene_path)
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("[world] Could not load world scene: %s" % scene_path)
		return null
	var world_scene: Node2D = packed.instantiate() as Node2D
	if world_scene == null:
		push_error("[world] World scene root is not a Node2D: %s" % scene_path)
		return null
	root.add_child(world_scene)

	var background := world_scene.get_node_or_null("Background") as Node2D
	if background:
		background.z_index = int(GameState.get_default("background_z_index", -10))
	var canopy := world_scene.get_node_or_null("Canopy") as Node2D
	if canopy:
		canopy.z_index = int(GameState.get_default("canopy_z_index", 10))
	return world_scene


## World bounds in pixels. Ground TileMapLayer wins (used rect × tile
## size); painterly worlds fall back to the Background sprite's texture.
static func derive_bounds(world_scene: Node2D) -> Rect2:
	if world_scene == null:
		return Rect2()
	var ground := world_scene.get_node_or_null("Ground") as TileMapLayer
	if ground:
		var tile_px: Vector2 = Vector2(GameState.get_float("tile_size", 64.0), GameState.get_float("tile_size", 64.0))
		if ground.tile_set:
			tile_px = Vector2(ground.tile_set.tile_size)
		var used: Rect2i = ground.get_used_rect()
		var bounds := Rect2(Vector2(used.position) * tile_px, Vector2(used.size) * tile_px)
		print("[world] ground=%s tiles → bounds=%s" % [used.size, bounds])
		return bounds
	var background := world_scene.get_node_or_null("Background") as Sprite2D
	if background and background.texture:
		var bounds := Rect2(background.position, background.texture.get_size())
		print("[world] bg=%s → bounds=%s" % [background.texture.get_size(), bounds])
		return bounds
	push_warning("[world] No Ground layer or Background sprite — bounds unknown")
	return Rect2()


## Perimeter walls are always loader-generated: bounds inset by the
## sidecar "wall_inset" (falling back to defaults.wall_inset).
static func build_perimeter_walls(root: Node2D, bounds: Rect2, config: Dictionary) -> void:
	if bounds.size == Vector2.ZERO:
		return
	var inset: float = float(config.get("wall_inset", GameState.get_float("wall_inset", 12.0)))
	var inner_min := bounds.position + Vector2(inset, inset)
	var inner_max := bounds.end - Vector2(inset, inset)
	var inner_size := inner_max - inner_min
	var center := (inner_min + inner_max) / 2.0
	var t: float = GameState.get_float("wall_thickness", 32.0)
	_create_wall(root, Vector2(inner_min.x - t / 2.0, center.y), Vector2(t, inner_size.y + t))
	_create_wall(root, Vector2(inner_max.x + t / 2.0, center.y), Vector2(t, inner_size.y + t))
	_create_wall(root, Vector2(center.x, inner_min.y - t / 2.0), Vector2(inner_size.x + t, t))
	_create_wall(root, Vector2(center.x, inner_max.y + t / 2.0), Vector2(inner_size.x + t, t))


static func _create_wall(root: Node2D, pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	body.add_child(col)
	root.add_child(body)
	body.global_position = pos
	# NavigationObstacle2D on static geometry is intentionally omitted:
	# agents pathfind around walls via the Theta* grid (built once on
	# spawn). Feeding walls to RVO as well was redundant and caused
	# NavigationServer2D to iterate every obstacle on every physics tick,
	# producing unbounded RefCounted churn as agents moved. Dynamic RVO
	# avoidance is kept only between agents themselves.


## Enrich Prop nodes with sidecar prose and synthesize the legacy
## config["props"] array (geometry from the scene, prose + layers from the
## sidecar) so find_prop_config()/PropLayers keep their existing shapes.
## Returns the Props container (created empty when the scene has none).
static func prepare_props(world_scene: Node2D, config: Dictionary) -> Node2D:
	var container := world_scene.get_node_or_null("Props") as Node2D
	if container == null:
		container = Node2D.new()
		container.name = "Props"
		world_scene.add_child(container)

	var prose: Dictionary = {}
	var sidecar_props: Variant = config.get("props", {})
	if sidecar_props is Dictionary:
		prose = sidecar_props

	var legacy_entries: Array = []
	for child: Node in container.get_children():
		var prop := child as Prop
		if prop == null:
			continue
		if prop.prop_id == "":
			prop.prop_id = String(prop.name)
		var entry_prose: Dictionary = prose.get(prop.prop_id, {})
		prop.prop_name = str(entry_prose.get("name", prop.prop_name))
		prop.prop_description = str(entry_prose.get("description", prop.prop_description))

		var size: Vector2 = _prop_shape_size(prop)
		var entry: Dictionary = {
			"entity_id": prop.prop_id,
			"name": prop.prop_name,
			"description": prop.prop_description,
			"position": [prop.position.x, prop.position.y],
			"size": [size.x, size.y],
			"collision": prop.get_node_or_null("Body") != null,
		}
		if entry_prose.has("layers"):
			entry["layers"] = entry_prose["layers"]
		legacy_entries.append(entry)

	config["props"] = legacy_entries
	print("[world] %d props" % legacy_entries.size())
	return container


static func _prop_shape_size(prop: Area2D) -> Vector2:
	for child: Node in prop.get_children():
		var col := child as CollisionShape2D
		if col and col.shape is RectangleShape2D:
			return (col.shape as RectangleShape2D).size
	return Vector2(16, 16)


## Copy SpawnPoints marker positions into config["spawn"] (scene wins over
## any sidecar value; absent markers leave the existing fallback logic in
## world_loader/agent_spawner untouched).
static func synthesize_spawn(world_scene: Node2D, config: Dictionary) -> void:
	var container := world_scene.get_node_or_null("SpawnPoints") as Node2D
	if container == null:
		return
	var spawn: Dictionary = {}
	var existing: Variant = config.get("spawn", {})
	if existing is Dictionary:
		spawn = existing
	var player_marker := container.get_node_or_null("Player") as Marker2D
	if player_marker:
		spawn["player"] = [player_marker.position.x, player_marker.position.y]
	var agents_marker := container.get_node_or_null("Agents") as Marker2D
	if agents_marker:
		spawn["agents"] = [agents_marker.position.x, agents_marker.position.y]
	config["spawn"] = spawn


static func build_audio(root: Node2D, config: Dictionary) -> void:
	var audio_path: String = config.get("audio", "")
	if audio_path == "":
		return
	var stream: AudioStream = GameState.load_audio(audio_path)
	if not stream:
		push_warning("[world] Audio not found: %s" % audio_path)
		return
	var audio := AudioStreamPlayer.new()
	audio.name = "AmbientAudio"
	audio.stream = stream
	audio.autoplay = true
	audio.volume_db = config.get("audio_volume_db", -10.0)
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	root.add_child(audio)
	print("[world] ambient audio: %s" % audio_path)
