class_name TestWorldBuilderMerge
extends RefCounted
## Unit tests for WorldBuilder's sidecar-merge/synthesis statics.
## Covers the "scene geometry + sidecar prose → legacy dict shape" contract
## documented at the top of scripts/world_builder.gd:
##   prepare_props()    — Props container enrichment + config["props"]
##   synthesize_spawn() — SpawnPoints markers + config["spawn"]
##   derive_bounds()    — Background Sprite2D fallback path
##
## All scenes are built off-tree in memory (Node2D/Prop/Marker2D/Sprite2D
## constructed directly, never loaded from res://). Each test owns a single
## root Node2D and frees it before returning — free() on a parent cascades
## to every child it was given, so one call cleans up the whole fixture.

var failure_message: String = ""


func run() -> bool:
	if not _test_prepare_props_full_merge_enriches_prop_and_config():
		return false
	if not _test_prepare_props_scene_prop_absent_from_sidecar_keeps_scene_values():
		return false
	if not _test_prepare_props_no_container_creates_empty_and_default_config():
		return false
	if not _test_synthesize_spawn_markers_present_write_legacy_shape():
		return false
	if not _test_synthesize_spawn_scene_wins_over_existing_sidecar_value():
		return false
	if not _test_synthesize_spawn_missing_marker_leaves_existing_value_untouched():
		return false
	if not _test_synthesize_spawn_no_container_leaves_config_untouched():
		return false
	if not _test_derive_bounds_background_sprite_returns_texture_size_rect():
		return false
	if not _test_derive_bounds_no_ground_no_background_returns_empty_rect():
		return false
	return true


# ── Fixtures ──────────────────────────────────────────────────────────────

func _make_props_container(world_scene: Node2D) -> Node2D:
	var container := Node2D.new()
	container.name = "Props"
	world_scene.add_child(container)
	return container


func _make_prop(node_name: String, prop_position: Vector2) -> Prop:
	var prop := Prop.new()
	prop.name = node_name
	prop.position = prop_position
	return prop


func _add_collision_shape(prop: Prop, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	prop.add_child(col)


func _add_body(prop: Prop) -> void:
	var body := StaticBody2D.new()
	body.name = "Body"
	prop.add_child(body)


func _make_spawn_points(world_scene: Node2D) -> Node2D:
	var container := Node2D.new()
	container.name = "SpawnPoints"
	world_scene.add_child(container)
	return container


func _add_marker(container: Node2D, marker_name: String, marker_position: Vector2) -> void:
	var marker := Marker2D.new()
	marker.name = marker_name
	marker.position = marker_position
	container.add_child(marker)


func _make_background_texture(width: int, height: int) -> ImageTexture:
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)


func _fail(world_scene: Node2D, msg: String) -> bool:
	if is_instance_valid(world_scene):
		world_scene.free()
	failure_message = msg
	return false


# ── prepare_props ────────────────────────────────────────────────────────

func _test_prepare_props_full_merge_enriches_prop_and_config() -> bool:
	## Prop present in both scene and sidecar: prop node gets sidecar prose,
	## config["props"] gets a legacy entry with scene geometry + sidecar prose.
	## A non-Prop sibling in the container must be skipped, not crash the merge.
	# Arrange
	var world_scene := Node2D.new()
	var container := _make_props_container(world_scene)
	var torch := _make_prop("torch", Vector2(100, 200))
	_add_collision_shape(torch, Vector2(32, 48))
	_add_body(torch)
	container.add_child(torch)
	var decoration := Node2D.new()
	decoration.name = "Decoration"
	container.add_child(decoration)
	var layers: Array = [{"gate": {"kind": "skill", "id": "fire_lore"}, "text": "The flame flickers oddly."}]
	var config: Dictionary = {
		"props": {
			"torch": {
				"name": "Old Torch",
				"description": "A flickering torch mounted on the wall.",
				"layers": layers,
			},
		},
	}

	# Act
	var result_container: Node2D = WorldBuilder.prepare_props(world_scene, config)

	# Assert — existing container is reused, not replaced
	if result_container != container:
		return _fail(world_scene, "full merge: expected existing Props container to be returned")

	# Assert — node prose enriched from sidecar
	if torch.prop_id != "torch":
		return _fail(world_scene, "full merge: prop_id not derived from node name, got '%s'" % torch.prop_id)
	if torch.prop_name != "Old Torch":
		return _fail(world_scene, "full merge: prop_name not enriched, got '%s'" % torch.prop_name)
	if torch.prop_description != "A flickering torch mounted on the wall.":
		return _fail(world_scene, "full merge: prop_description not enriched, got '%s'" % torch.prop_description)

	# Assert — legacy config["props"] array shape
	var props_raw: Variant = config.get("props")
	if not (props_raw is Array):
		return _fail(world_scene, "full merge: config[\"props\"] is not an Array")
	var entries: Array = props_raw as Array
	if entries.size() != 1:
		return _fail(world_scene, "full merge: expected 1 legacy entry (Decoration must be skipped), got %d" % entries.size())
	var entry: Dictionary = entries[0] as Dictionary
	if entry.get("entity_id") != "torch":
		return _fail(world_scene, "full merge: entity_id mismatch, got '%s'" % str(entry.get("entity_id")))
	if entry.get("name") != "Old Torch":
		return _fail(world_scene, "full merge: entry name mismatch, got '%s'" % str(entry.get("name")))
	if entry.get("description") != "A flickering torch mounted on the wall.":
		return _fail(world_scene, "full merge: entry description mismatch, got '%s'" % str(entry.get("description")))
	if entry.get("position") != [100.0, 200.0]:
		return _fail(world_scene, "full merge: entry position mismatch, got %s" % str(entry.get("position")))
	if entry.get("size") != [32.0, 48.0]:
		return _fail(world_scene, "full merge: entry size mismatch, got %s" % str(entry.get("size")))
	if entry.get("collision") != true:
		return _fail(world_scene, "full merge: collision should be true (Body child present)")
	if entry.get("layers") != layers:
		return _fail(world_scene, "full merge: layers not carried over from sidecar, got %s" % str(entry.get("layers")))

	world_scene.free()
	return true


func _test_prepare_props_scene_prop_absent_from_sidecar_keeps_scene_values() -> bool:
	## A scene Prop with no matching sidecar entry must keep its own
	## (scene-baked) prop_name/prop_description untouched, fall back to the
	## default (16, 16) shape size, and get no "layers" key.
	# Arrange
	var world_scene := Node2D.new()
	var container := _make_props_container(world_scene)
	var rock := _make_prop("unknown_prop", Vector2(5, 5))
	rock.prop_name = "Mossy Rock"
	rock.prop_description = "Just a rock."
	container.add_child(rock)
	var config: Dictionary = {
		"props": {
			"other_prop": {"name": "Not This One", "description": "Irrelevant."},
		},
	}

	# Act
	WorldBuilder.prepare_props(world_scene, config)

	# Assert — scene-baked prose survives an absent sidecar entry
	if rock.prop_id != "unknown_prop":
		return _fail(world_scene, "absent sidecar: prop_id not derived from node name, got '%s'" % rock.prop_id)
	if rock.prop_name != "Mossy Rock":
		return _fail(world_scene, "absent sidecar: prop_name changed unexpectedly, got '%s'" % rock.prop_name)
	if rock.prop_description != "Just a rock.":
		return _fail(world_scene, "absent sidecar: prop_description changed unexpectedly, got '%s'" % rock.prop_description)

	var entries: Array = config.get("props") as Array
	if entries.size() != 1:
		return _fail(world_scene, "absent sidecar: expected 1 legacy entry, got %d" % entries.size())
	var entry: Dictionary = entries[0] as Dictionary
	if entry.get("entity_id") != "unknown_prop":
		return _fail(world_scene, "absent sidecar: entity_id mismatch, got '%s'" % str(entry.get("entity_id")))
	if entry.get("name") != "Mossy Rock":
		return _fail(world_scene, "absent sidecar: entry name should mirror scene value, got '%s'" % str(entry.get("name")))
	if entry.get("size") != [16.0, 16.0]:
		return _fail(world_scene, "absent sidecar: expected default (16,16) shape size, got %s" % str(entry.get("size")))
	if entry.get("collision") != false:
		return _fail(world_scene, "absent sidecar: collision should be false (no Body child)")
	if entry.has("layers"):
		return _fail(world_scene, "absent sidecar: entry should have no 'layers' key")

	world_scene.free()
	return true


func _test_prepare_props_no_container_creates_empty_and_default_config() -> bool:
	## No Props node in the scene at all: prepare_props must create + attach
	## an empty container and synthesize an empty config["props"] array.
	# Arrange
	var world_scene := Node2D.new()
	var config: Dictionary = {}

	# Act
	var result_container: Node2D = WorldBuilder.prepare_props(world_scene, config)

	# Assert
	if result_container == null:
		return _fail(world_scene, "no container: prepare_props returned null")
	if result_container.name != "Props":
		return _fail(world_scene, "no container: created container not named 'Props', got '%s'" % result_container.name)
	if result_container.get_parent() != world_scene:
		return _fail(world_scene, "no container: created container not attached under world_scene")
	if world_scene.get_node_or_null("Props") != result_container:
		return _fail(world_scene, "no container: world_scene does not resolve 'Props' to the created container")

	var props_raw: Variant = config.get("props")
	if not (props_raw is Array):
		return _fail(world_scene, "no container: config[\"props\"] is not an Array")
	if (props_raw as Array).size() != 0:
		return _fail(world_scene, "no container: expected empty legacy props array, got %d entries" % (props_raw as Array).size())

	world_scene.free()
	return true


# ── synthesize_spawn ─────────────────────────────────────────────────────

func _test_synthesize_spawn_markers_present_write_legacy_shape() -> bool:
	## Player + Agents markers in SpawnPoints land in config["spawn"] under
	## the legacy "player"/"agents" keys, as [x, y] pairs.
	# Arrange
	var world_scene := Node2D.new()
	var spawn_points := _make_spawn_points(world_scene)
	_add_marker(spawn_points, "Player", Vector2(10, 20))
	_add_marker(spawn_points, "Agents", Vector2(30, 40))
	var config: Dictionary = {}

	# Act
	WorldBuilder.synthesize_spawn(world_scene, config)

	# Assert
	var spawn_raw: Variant = config.get("spawn")
	if not (spawn_raw is Dictionary):
		return _fail(world_scene, "markers present: config[\"spawn\"] is not a Dictionary")
	var spawn: Dictionary = spawn_raw as Dictionary
	if spawn.get("player") != [10.0, 20.0]:
		return _fail(world_scene, "markers present: spawn.player mismatch, got %s" % str(spawn.get("player")))
	if spawn.get("agents") != [30.0, 40.0]:
		return _fail(world_scene, "markers present: spawn.agents mismatch, got %s" % str(spawn.get("agents")))

	world_scene.free()
	return true


func _test_synthesize_spawn_scene_wins_over_existing_sidecar_value() -> bool:
	## When both a sidecar spawn value and a scene marker exist, the scene
	## marker's position must win.
	# Arrange
	var world_scene := Node2D.new()
	var spawn_points := _make_spawn_points(world_scene)
	_add_marker(spawn_points, "Player", Vector2(1, 2))
	_add_marker(spawn_points, "Agents", Vector2(3, 4))
	var config: Dictionary = {
		"spawn": {"player": [999.0, 999.0], "agents": [888.0, 888.0]},
	}

	# Act
	WorldBuilder.synthesize_spawn(world_scene, config)

	# Assert
	var spawn: Dictionary = config["spawn"] as Dictionary
	if spawn.get("player") != [1.0, 2.0]:
		return _fail(world_scene, "scene wins: spawn.player did not take scene value, got %s" % str(spawn.get("player")))
	if spawn.get("agents") != [3.0, 4.0]:
		return _fail(world_scene, "scene wins: spawn.agents did not take scene value, got %s" % str(spawn.get("agents")))

	world_scene.free()
	return true


func _test_synthesize_spawn_missing_marker_leaves_existing_value_untouched() -> bool:
	## SpawnPoints present but only a Player marker exists: the Agents key
	## already in config["spawn"] must survive unchanged.
	# Arrange
	var world_scene := Node2D.new()
	var spawn_points := _make_spawn_points(world_scene)
	_add_marker(spawn_points, "Player", Vector2(50, 60))
	var config: Dictionary = {
		"spawn": {"player": [5.0, 6.0], "agents": [7.0, 8.0]},
	}

	# Act
	WorldBuilder.synthesize_spawn(world_scene, config)

	# Assert
	var spawn: Dictionary = config["spawn"] as Dictionary
	if spawn.get("player") != [50.0, 60.0]:
		return _fail(world_scene, "missing marker: spawn.player should update from scene, got %s" % str(spawn.get("player")))
	if spawn.get("agents") != [7.0, 8.0]:
		return _fail(world_scene, "missing marker: spawn.agents should stay untouched, got %s" % str(spawn.get("agents")))

	world_scene.free()
	return true


func _test_synthesize_spawn_no_container_leaves_config_untouched() -> bool:
	## No SpawnPoints node in the scene at all: synthesize_spawn must early-out
	## without adding a "spawn" key to config.
	# Arrange
	var world_scene := Node2D.new()
	var config: Dictionary = {}

	# Act
	WorldBuilder.synthesize_spawn(world_scene, config)

	# Assert
	if config.has("spawn"):
		return _fail(world_scene, "no container: config should not gain a 'spawn' key, got %s" % str(config.get("spawn")))

	world_scene.free()
	return true


# ── derive_bounds ────────────────────────────────────────────────────────

func _test_derive_bounds_background_sprite_returns_texture_size_rect() -> bool:
	## No Ground layer: bounds fall back to the Background sprite's position
	## and texture size.
	# Arrange
	var world_scene := Node2D.new()
	var background := Sprite2D.new()
	background.name = "Background"
	background.position = Vector2(15, 25)
	background.texture = _make_background_texture(320, 240)
	world_scene.add_child(background)

	# Act
	var bounds: Rect2 = WorldBuilder.derive_bounds(world_scene)

	# Assert
	if bounds.position != Vector2(15, 25):
		return _fail(world_scene, "background fallback: bounds.position mismatch, got %s" % str(bounds.position))
	if bounds.size != Vector2(320, 240):
		return _fail(world_scene, "background fallback: bounds.size mismatch, got %s" % str(bounds.size))

	world_scene.free()
	return true


func _test_derive_bounds_no_ground_no_background_returns_empty_rect() -> bool:
	## Neither a Ground layer nor a Background sprite: bounds are unknown,
	## derive_bounds returns a zeroed Rect2 rather than crashing.
	# Arrange
	var world_scene := Node2D.new()

	# Act
	var bounds: Rect2 = WorldBuilder.derive_bounds(world_scene)

	# Assert
	if bounds != Rect2():
		return _fail(world_scene, "no geometry: expected zeroed Rect2, got %s" % str(bounds))

	world_scene.free()
	return true
