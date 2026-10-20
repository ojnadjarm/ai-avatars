extends SceneTree
## Headless world validator — checks every assets/worlds/<id>/ folder
## against the scene contract and sidecar schema. Exit 0 = all valid.
##
##   godot --headless --path godot/agent-world -s tools/validate_worlds.gd
##
## Errors fail the run; warnings (prose length) print but pass.

const WORLDS_ROOT := "res://assets/worlds/"
const REQUIRED_KEYS: Array[String] = ["id", "name", "description"]
const OBSERVATION_PROMPT_COUNT := 4
const GATE_KINDS: Array[String] = ["skill", "item", "flag"]
## Fourth-wall rule: agent-facing prose never mentions these.
const FORBIDDEN_WORDS: Array[String] = ["game", "simulation", "player", "npc"]
## Descriptions beyond this many sentences degrade agent responses.
const MAX_SENTENCES := 3

var _errors: int = 0
var _warnings: int = 0
var _current: String = ""


func _init() -> void:
	var world_count: int = 0
	for dir_name: String in DirAccess.get_directories_at(WORLDS_ROOT):
		var sidecar_path: String = WORLDS_ROOT + dir_name + "/world.json"
		if not FileAccess.file_exists(sidecar_path):
			continue
		world_count += 1
		_current = dir_name
		_validate_world(WORLDS_ROOT + dir_name + "/")
	print("[validate] %d world(s): %d error(s), %d warning(s)" % [world_count, _errors, _warnings])
	quit(0 if (_errors == 0 and world_count > 0) else 1)


func _validate_world(world_dir: String) -> void:
	var sidecar: Dictionary = _load_json(world_dir + "world.json")
	if sidecar.is_empty():
		_error("world.json missing or unparseable")
		return

	for key: String in REQUIRED_KEYS:
		if str(sidecar.get(key, "")) == "":
			_error("sidecar missing required key '%s'" % key)
	var prompts: Array = sidecar.get("observation_prompts", [])
	if prompts.size() != OBSERVATION_PROMPT_COUNT:
		_error("observation_prompts must have exactly %d entries, has %d" % [OBSERVATION_PROMPT_COUNT, prompts.size()])

	_lint_prose("description", str(sidecar.get("description", "")))
	_lint_fourth_wall("ambient", str(sidecar.get("ambient", "")))
	for i: int in range(prompts.size()):
		_lint_fourth_wall("observation_prompts[%d]" % i, str(prompts[i]))
	var transitions: Dictionary = sidecar.get("transitions", {})
	for from_id: String in transitions:
		_lint_fourth_wall("transitions.%s" % from_id, str(transitions[from_id]))

	# Scene contract
	var scene_path: String = world_dir + "world.tscn"
	if not ResourceLoader.exists(scene_path):
		_error("world.tscn missing")
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	var scene_root: Node2D = packed.instantiate() as Node2D
	if scene_root == null:
		_error("world.tscn root is not a Node2D")
		return

	var bounds: Rect2 = _scene_bounds(scene_root, world_dir)
	if bounds.size == Vector2.ZERO:
		_error("no Ground TileMapLayer or Background sprite — bounds underivable")

	_validate_props(scene_root, sidecar)
	_validate_spawns(scene_root, bounds)
	scene_root.free()


func _scene_bounds(scene_root: Node2D, world_dir: String) -> Rect2:
	var ground := scene_root.get_node_or_null("Ground") as TileMapLayer
	if ground and ground.tile_set:
		var tile_px := Vector2(ground.tile_set.tile_size)
		var used: Rect2i = ground.get_used_rect()
		return Rect2(Vector2(used.position) * tile_px, Vector2(used.size) * tile_px)
	var background := scene_root.get_node_or_null("Background") as Sprite2D
	if background and background.texture:
		var size: Vector2 = background.texture.get_size()
		var canopy := scene_root.get_node_or_null("Canopy") as Sprite2D
		if canopy and canopy.texture and canopy.texture.get_size() != size:
			_error("canopy size %s != background size %s" % [canopy.texture.get_size(), size])
		return Rect2(background.position, size)
	return _built_bounds(world_dir)


## Painterly worlds whose Background is textured at runtime: the ground node of art/built.json.
func _built_bounds(world_dir: String) -> Rect2:
	var built: Dictionary = _load_json(world_dir + "art/built.json")
	for n: Variant in built.get("nodes", []):
		if n is Dictionary and str(n.get("layer", "")) == "ground":
			var size: Array = built.get("size", [0, 0])
			return Rect2(float(n["x"]), float(n["y"]), float(size[0]), float(size[1]))
	return Rect2()


func _validate_props(scene_root: Node2D, sidecar: Dictionary) -> void:
	var prose: Dictionary = sidecar.get("props", {})
	var container := scene_root.get_node_or_null("Props") as Node2D
	var scene_ids: Dictionary = {}
	if container:
		for child: Node in container.get_children():
			var prop := child as Prop
			if prop == null:
				_error("Props child '%s' is not a Prop node" % child.name)
				continue
			var entity_id: String = prop.prop_id if prop.prop_id != "" else String(prop.name)
			if scene_ids.has(entity_id):
				_error("duplicate entity_id '%s' in scene" % entity_id)
			scene_ids[entity_id] = true
			if not prose.has(entity_id):
				_error("scene prop '%s' has no sidecar prose entry" % entity_id)

	for entity_id: String in prose:
		if not scene_ids.has(entity_id):
			_error("sidecar prop '%s' has no scene node" % entity_id)
		var entry: Dictionary = prose[entity_id]
		if str(entry.get("name", "")) == "" or str(entry.get("description", "")) == "":
			_error("prop '%s' missing name or description" % entity_id)
		_lint_prose("props.%s.description" % entity_id, str(entry.get("description", "")))
		for layer: Variant in entry.get("layers", []):
			if not (layer is Dictionary):
				_error("prop '%s' has a non-dict layer" % entity_id)
				continue
			var gate: Dictionary = (layer as Dictionary).get("gate", {})
			var kind: String = str(gate.get("kind", ""))
			if not GATE_KINDS.has(kind):
				_error("prop '%s' layer gate kind '%s' unknown (want %s)" % [entity_id, kind, GATE_KINDS])
			_lint_fourth_wall("props.%s.layer" % entity_id, str((layer as Dictionary).get("text", "")))


func _validate_spawns(scene_root: Node2D, bounds: Rect2) -> void:
	var container := scene_root.get_node_or_null("SpawnPoints") as Node2D
	if container == null:
		_warn("no SpawnPoints node — loader will use fallback spawn")
		return
	for key: String in ["Player", "Agents"]:
		var marker := container.get_node_or_null(key) as Marker2D
		if marker == null:
			_warn("SpawnPoints/%s marker missing" % key)
			continue
		if bounds.size != Vector2.ZERO and not bounds.has_point(marker.position):
			_error("SpawnPoints/%s at %s is outside bounds %s" % [key, marker.position, bounds])


func _lint_prose(label: String, text: String) -> void:
	_lint_fourth_wall(label, text)
	if text == "":
		return
	var sentences: int = 0
	for part: String in text.split(".", false):
		if part.strip_edges() != "":
			sentences += 1
	if sentences > MAX_SENTENCES + 1:
		_warn("%s runs %d sentences — long prose degrades agent responses" % [label, sentences])


func _lint_fourth_wall(label: String, text: String) -> void:
	var lower: String = text.to_lower()
	for word: String in FORBIDDEN_WORDS:
		var regex := RegEx.new()
		regex.compile("\\b%s\\b" % word)
		if regex.search(lower) != null:
			_error("%s breaks the fourth wall — contains '%s'" % [label, word])


func _error(msg: String) -> void:
	_errors += 1
	print("[validate] ERROR %s: %s" % [_current, msg])


func _warn(msg: String) -> void:
	_warnings += 1
	print("[validate] warn  %s: %s" % [_current, msg])


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}
