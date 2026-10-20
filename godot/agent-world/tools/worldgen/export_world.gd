extends SceneTree
## Writes DIR/world.tscn from DIR/art/built.json + the spec's game block; `-- --selftest` checks a synthetic world.

const WORLD_ART := "res://scripts/world_art/world_art.gd"
const PROP := "res://scripts/prop.gd"
const MASKS := ["block_face.png", "block_water.png"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest"):
		quit(_selftest())
		return
	if args.size() < 2:
		push_error("usage: -s tools/worldgen/export_world.gd -- DIR SPEC.json | --selftest")
		quit(2)
		return
	var dir: String = args[0]
	var built: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("art/built.json")))
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var masks: Array[Image] = []
	for nm in MASKS:
		var img := Image.load_from_file(dir.path_join("art").path_join(nm))
		if img:
			masks.append(img)
	var root := build_scene(built, spec.get("game", {}), masks)
	var err := save_scene(root, dir.path_join("world.tscn"))
	print("EXPORT ok walls %d props %d zones %d landmarks %d" % [root.get_node("Walls").get_child_count(),
		root.get_node("Props").get_child_count(), root.get_node("Zones").get_child_count(),
		root.get_node("Landmarks").get_child_count()] if err == OK else "EXPORT failed %d" % err)
	root.free()
	quit(0 if err == OK else 1)


## Builds the World node tree of the scene contract (PLAN "Contracts").
static func build_scene(built: Dictionary, game: Dictionary, masks: Array[Image]) -> Node2D:
	var root := Node2D.new()
	root.name = "World"
	root.set_script(load(WORLD_ART))
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.centered = false
	_own(root, root, bg)
	_own(root, root, _named(Node2D.new(), "Art"))
	_own(root, root, _walls(built, masks))
	_own(root, root, _props(game.get("props", {})))
	_own(root, root, _spawns(game.get("spawn", {}), built["size"]))
	_own(root, root, _zones(game.get("zones", [])))
	_own(root, root, _landmarks(game.get("landmarks", [])))
	return root


static func save_scene(root: Node2D, path: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	return err if err != OK else ResourceSaver.save(packed, path)


static func _own(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root
	for c in child.get_children():
		_own_tree(root, c)


static func _own_tree(root: Node, n: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_own_tree(root, c)


static func _named(n: Node, nm: String) -> Node:
	n.name = nm
	return n


static func _slug(s: String) -> String:
	return s.to_snake_case().validate_node_name().replace(" ", "_")


static func _rect_shape(size: Vector2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	return cs


static func _walls(built: Dictionary, masks: Array[Image]) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Walls"
	var polys: Array[PackedVector2Array] = []
	for c in built.get("collide", []):
		var pts := PackedVector2Array()
		if c[0] == "rect":
			pts = PackedVector2Array([Vector2(c[1], c[2]), Vector2(c[1] + c[3], c[2]),
				Vector2(c[1] + c[3], c[2] + c[4]), Vector2(c[1], c[2] + c[4])])
		else:
			for i in 12:
				var a := TAU * i / 12.0
				pts.append(Vector2(c[1] + cos(a) * c[3], c[2] + sin(a) * c[4]))
		polys.append(pts)
	for img in masks:
		polys.append_array(mask_polygons(img))
	for pts in polys:
		var cp := CollisionPolygon2D.new()
		cp.polygon = pts
		body.add_child(cp)
	return body


## Opaque regions of a grayscale block mask (white = blocked) as collision polygons.
static func mask_polygons(src: Image) -> Array[PackedVector2Array]:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_L8)
	img.convert(Image.FORMAT_RG8)
	var la := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_LA8, img.get_data())
	var bm := BitMap.new()
	bm.create_from_image_alpha(la)
	var out: Array[PackedVector2Array] = []
	out.assign(bm.opaque_to_polygons(Rect2i(0, 0, img.get_width(), img.get_height()), 1.5))
	return out


static func _props(props: Dictionary) -> Node2D:
	var box := _named(Node2D.new(), "Props") as Node2D
	for id in props:
		var e: Dictionary = props[id]
		var p := Area2D.new()
		p.set_script(load(PROP))
		p.name = id
		p.set("prop_id", id)
		p.position = Vector2(e["at"][0], e["at"][1])
		var size := Vector2(e["size"][0], e["size"][1])
		p.add_child(_rect_shape(size))
		if e.get("collision", false):
			var b := _named(StaticBody2D.new(), "Body")
			b.add_child(_rect_shape(size))
			p.add_child(b)
		box.add_child(p)
	return box


static func _spawns(spawn: Dictionary, size: Array) -> Node2D:
	var box := _named(Node2D.new(), "SpawnPoints") as Node2D
	var mid: Array = [size[0] * 0.5, size[1] * 0.5]
	for key in ["player", "agents"]:
		var m := Marker2D.new()
		m.name = key.capitalize()
		var at: Array = spawn.get(key, mid)
		m.position = Vector2(at[0], at[1])
		box.add_child(m)
	return box


static func _zones(zones: Array) -> Node2D:
	var box := _named(Node2D.new(), "Zones") as Node2D
	for z in zones:
		var r: Array = z["rect"]
		var a := Area2D.new()
		a.name = _slug(z["name"])
		a.set_meta("zone_name", z["name"])
		a.position = Vector2(r[0] + r[2] * 0.5, r[1] + r[3] * 0.5)
		a.monitorable = false
		a.add_child(_rect_shape(Vector2(r[2], r[3])))
		box.add_child(a)
	return box


static func _landmarks(marks: Array) -> Node2D:
	var box := _named(Node2D.new(), "Landmarks") as Node2D
	for l in marks:
		var m := Marker2D.new()
		m.name = _slug(l["name"])
		m.set_meta("landmark_name", l["name"])
		m.set_meta("tall", bool(l.get("tall", false)))
		m.position = Vector2(l["at"][0], l["at"][1])
		box.add_child(m)
	return box


func _selftest() -> int:
	var built := {"size": [320, 180], "collide": [["rect", 10, 10, 20, 8], ["ellipse", 100, 60, 8, 5]]}
	var game := {"spawn": {"player": [40, 150], "agents": [60, 150]},
		"zones": [{"name": "Moon Plaza", "rect": [100, 40, 80, 60]}],
		"landmarks": [{"name": "Old Hokora", "at": [140, 60], "tall": true}],
		"props": {"prop_1": {"at": [200, 120], "size": [24, 16], "collision": true}, "prop_2": {"at": [250, 120], "size": [10, 10], "collision": false}}}
	var face := Image.create(320, 180, false, Image.FORMAT_L8)
	face.fill_rect(Rect2i(0, 40, 90, 20), Color.WHITE)
	var water := Image.create(320, 180, false, Image.FORMAT_L8)
	water.fill_rect(Rect2i(200, 20, 40, 30), Color.WHITE)
	var path := OS.get_cache_dir().path_join("export_world_selftest.tscn")
	var root := build_scene(built, game, [face, water])
	var err := save_scene(root, path)
	root.free()
	var text := FileAccess.get_file_as_string(path)
	var w := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node2D
	var fails: Array[String] = []
	var check := func(ok: bool, what: String) -> void:
		if not ok:
			fails.append(what)
	check.call(err == OK, "save")
	check.call(w.name == "World" and w.get_script().resource_path == WORLD_ART, "root")
	var bg := w.get_node_or_null("Background") as Sprite2D
	check.call(bg != null and not bg.centered and bg.position == Vector2.ZERO and bg.texture == null, "Background")
	check.call(w.get_node_or_null("Art") is Node2D, "Art")
	var walls := w.get_node_or_null("Walls") as StaticBody2D
	check.call(walls != null and walls.get_child_count() == 4, "Walls 2 shapes + 2 mask polygons")
	if walls and walls.get_child_count() == 4:
		var face_poly := (walls.get_child(2) as CollisionPolygon2D).polygon
		check.call(Geometry2D.is_point_in_polygon(Vector2(45, 50), face_poly), "face polygon covers the mask")
	var p1 := w.get_node_or_null("Props/prop_1") as Area2D
	check.call(p1 != null and p1.get("prop_id") == "prop_1" and p1.position == Vector2(200, 120), "prop_1")
	check.call(p1 != null and p1.get_node_or_null("Body") is StaticBody2D, "prop_1 Body")
	check.call(p1 != null and (p1.get_child(0) as CollisionShape2D).shape.size == Vector2(24, 16), "prop_1 shape")
	check.call(w.get_node_or_null("Props/prop_2") != null and w.get_node("Props/prop_2").get_node_or_null("Body") == null, "prop_2 no Body")
	check.call(w.get_node_or_null("SpawnPoints/Player") is Marker2D and w.get_node("SpawnPoints/Agents").position == Vector2(60, 150), "SpawnPoints")
	var z := w.get_node_or_null("Zones").get_child(0) as Area2D
	check.call(z != null and z.get_meta("zone_name") == "Moon Plaza" and z.position == Vector2(140, 70), "Zones")
	var lm := w.get_node_or_null("Landmarks").get_child(0) as Marker2D
	check.call(lm != null and lm.get_meta("landmark_name") == "Old Hokora" and lm.get_meta("tall") == true, "Landmarks")
	check.call(not text.contains("type=\"Texture2D\"") and not text.contains("CompressedTexture2D"), "no texture ext_resources")
	w.free()
	DirAccess.remove_absolute(path)
	if fails.is_empty():
		print("EXPORT SELFTEST ok")
		return 0
	print("EXPORT SELFTEST FAIL ", fails)
	return 1
