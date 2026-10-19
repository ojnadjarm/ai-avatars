extends SceneTree
## One-shot converter: legacy flat world (assets/worlds/<id>.json + <id>.png)
## → scene-based world folder (assets/worlds/<id>/world.tscn + world.json).
##
## Run AFTER the world PNGs have been moved into assets/worlds/<id>/ and
## reimported:
##   godot --headless --path godot/agent-world --import
##   godot --headless --path godot/agent-world -s tools/migrate_world.gd
##
## The scene owns geometry/art/physics; the sidecar world.json keeps only
## agent-facing prose. Prop entity_ids are preserved verbatim so
## WorldState saves and puzzle rules keep working.

const WORLDS_ROOT := "res://assets/worlds/"
## Legacy editor drag-artifacts ([0,0,4,4] rects) are dropped — any wall
## thinner than this in both axes cannot block a 12px player collider.
const JUNK_WALL_MAX := 8.0

## Sidecar keys carried over from the legacy config verbatim when present.
const PROSE_KEYS: Array[String] = [
	"id", "name", "biome", "description", "ambient", "character_height",
	"observation_prompts", "transitions", "nothing_happens_text",
	"audio", "audio_volume_db",
]


func _init() -> void:
	var migrated: int = 0
	for file_name: String in DirAccess.get_files_at(WORLDS_ROOT):
		if not file_name.ends_with(".json"):
			continue
		var world_id: String = file_name.get_basename()
		if _migrate(world_id):
			migrated += 1
	print("[migrate] %d world(s) migrated" % migrated)
	quit(0 if migrated > 0 else 1)


func _migrate(world_id: String) -> bool:
	var legacy_path: String = WORLDS_ROOT + world_id + ".json"
	var legacy: Dictionary = _load_json(legacy_path)
	if legacy.is_empty():
		push_error("[migrate] Could not read %s" % legacy_path)
		return false

	var world_dir: String = WORLDS_ROOT + world_id + "/"
	if not DirAccess.dir_exists_absolute(world_dir):
		push_error("[migrate] Missing folder %s — move the PNGs there first" % world_dir)
		return false

	var root := Node2D.new()
	root.name = "World_" + world_id

	_add_background(root, world_dir, world_id)
	_add_canopy(root, world_dir, world_id)
	_add_walls(root, legacy.get("walls", []))
	_add_props(root, legacy.get("props", []))
	_add_spawn_points(root, legacy.get("spawn", {}))
	_own_recursive(root, root)

	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		push_error("[migrate] pack() failed for %s: %d" % [world_id, pack_err])
		return false
	var save_err: int = ResourceSaver.save(packed, world_dir + "world.tscn")
	if save_err != OK:
		push_error("[migrate] save failed for %s: %d" % [world_id, save_err])
		return false

	if not _write_sidecar(world_dir, legacy):
		return false
	print("[migrate] %s → %sworld.tscn + world.json" % [world_id, world_dir])
	return true


func _add_background(root: Node2D, world_dir: String, world_id: String) -> void:
	var png_path: String = world_dir + world_id + ".png"
	if not ResourceLoader.exists(png_path):
		push_error("[migrate] Background missing: %s" % png_path)
		return
	var sprite := Sprite2D.new()
	sprite.name = "Background"
	sprite.texture = load(png_path) as Texture2D
	sprite.centered = false
	sprite.z_index = -10
	root.add_child(sprite)


func _add_canopy(root: Node2D, world_dir: String, world_id: String) -> void:
	var png_path: String = world_dir + world_id + "_canopy.png"
	if not ResourceLoader.exists(png_path):
		return
	var sprite := Sprite2D.new()
	sprite.name = "Canopy"
	sprite.texture = load(png_path) as Texture2D
	sprite.centered = false
	sprite.z_index = 10
	root.add_child(sprite)


func _add_walls(root: Node2D, walls_cfg: Array) -> void:
	var container := Node2D.new()
	container.name = "Walls"
	root.add_child(container)
	var index: int = 0
	for wall_cfg: Variant in walls_cfg:
		if not (wall_cfg is Dictionary) or not (wall_cfg as Dictionary).has("rect"):
			continue  # perimeter entries become the sidecar wall_inset key
		var r: Array = (wall_cfg as Dictionary)["rect"]
		var size := Vector2(float(r[2]), float(r[3]))
		if size.x <= JUNK_WALL_MAX and size.y <= JUNK_WALL_MAX:
			print("[migrate]   dropped junk wall rect %s" % [r])
			continue
		var body := StaticBody2D.new()
		body.name = "Wall%d" % index
		index += 1
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		body.position = Vector2(float(r[0]) + size.x / 2.0, float(r[1]) + size.y / 2.0)
		container.add_child(body)


func _add_props(root: Node2D, props_cfg: Array) -> void:
	var container := Node2D.new()
	container.name = "Props"
	root.add_child(container)
	var prop_script: Script = load("res://scripts/prop.gd")
	for prop_cfg: Variant in props_cfg:
		if not (prop_cfg is Dictionary):
			continue
		var cfg: Dictionary = prop_cfg
		var entity_id: String = str(cfg.get("entity_id", ""))
		if entity_id == "":
			continue
		var prop := Area2D.new()
		prop.name = entity_id
		prop.set_script(prop_script)
		prop.set("prop_id", entity_id)
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		var sz: Array = cfg.get("size", [16, 16])
		shape.size = Vector2(float(sz[0]), float(sz[1]))
		col.shape = shape
		prop.add_child(col)
		var pos: Array = cfg.get("position", [0, 0])
		prop.position = Vector2(float(pos[0]), float(pos[1]))
		if cfg.get("collision", false):
			var body := StaticBody2D.new()
			body.name = "Body"
			var body_col := CollisionShape2D.new()
			var body_shape := RectangleShape2D.new()
			body_shape.size = shape.size
			body_col.shape = body_shape
			body.add_child(body_col)
			prop.add_child(body)
		container.add_child(prop)


func _add_spawn_points(root: Node2D, spawn_cfg: Dictionary) -> void:
	var container := Node2D.new()
	container.name = "SpawnPoints"
	root.add_child(container)
	for key: String in ["player", "agents"]:
		var pos: Variant = spawn_cfg.get(key, null)
		if not (pos is Array) or (pos as Array).size() < 2:
			continue
		var marker := Marker2D.new()
		marker.name = key.capitalize()
		marker.position = Vector2(float((pos as Array)[0]), float((pos as Array)[1]))
		container.add_child(marker)


func _own_recursive(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_own_recursive(child, root)


func _write_sidecar(world_dir: String, legacy: Dictionary) -> bool:
	var sidecar: Dictionary = {}
	for key: String in PROSE_KEYS:
		if legacy.has(key):
			sidecar[key] = legacy[key]

	# Legacy perimeter inset survives as a plain sidecar key.
	for wall_cfg: Variant in legacy.get("walls", []):
		if wall_cfg is Dictionary and (wall_cfg as Dictionary).get("side", "") == "perimeter":
			sidecar["wall_inset"] = float((wall_cfg as Dictionary).get("inset", 12.0))
			break

	# Prop prose keyed by entity_id — geometry stays in the scene.
	var prose: Dictionary = {}
	for prop_cfg: Variant in legacy.get("props", []):
		if not (prop_cfg is Dictionary):
			continue
		var cfg: Dictionary = prop_cfg
		var entity_id: String = str(cfg.get("entity_id", ""))
		if entity_id == "":
			continue
		var entry: Dictionary = {
			"name": cfg.get("name", ""),
			"description": cfg.get("description", ""),
		}
		if cfg.has("layers"):
			entry["layers"] = cfg["layers"]
		prose[entity_id] = entry
	sidecar["props"] = prose

	var file := FileAccess.open(world_dir + "world.json", FileAccess.WRITE)
	if file == null:
		push_error("[migrate] Cannot write %sworld.json" % world_dir)
		return false
	file.store_string(JSON.stringify(sidecar, "  ", true) + "\n")
	file.close()
	return true


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}
