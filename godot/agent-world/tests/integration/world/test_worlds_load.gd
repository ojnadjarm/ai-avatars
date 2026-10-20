extends RefCounted
## Both big worlds load through WorldBuilder: bounds, prop ids, spawn points and the y-sort root.

const WORLDS := ["magic_forest", "darkwood"]
const MIN_SIZE := Vector2(1920, 1080)

var failure_message: String = ""


func run() -> bool:
	for id: String in WORLDS:
		if not _check_world(id):
			return false
	return true


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _check_world(id: String) -> bool:
	var dir := "res://assets/worlds/%s" % id
	var host := Node2D.new()
	# The runner scene, not root: root is still busy adding it while suites run.
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene else tree.root).add_child(host)
	var world: Node2D = WorldBuilder.instantiate_world(host, dir)
	var ok := _check_scene(id, dir, world)
	host.free()
	return ok


func _check_scene(id: String, dir: String, world: Node2D) -> bool:
	if world == null:
		return _fail("%s: instantiate_world returned null" % id)
	var bounds: Rect2 = WorldBuilder.derive_bounds(world)
	if bounds.size.x < MIN_SIZE.x or bounds.size.y < MIN_SIZE.y:
		return _fail("%s: bounds %s smaller than %s" % [id, bounds, MIN_SIZE])
	var ys: Node2D = WorldBuilder.ysort_root(world)
	if ys == null or not ys.y_sort_enabled:
		return _fail("%s: no y-sorted ysort_root()" % id)
	var sidecar: Dictionary = GameState.load_json(dir.path_join("world.json"), "world")
	var want: Array = (sidecar.get("props", {}) as Dictionary).keys()
	var got: Array = []
	for child: Node in world.get_node("Props").get_children():
		got.append(String(child.name))
	want.sort()
	got.sort()
	if want != got:
		return _fail("%s: Props %s != world.json props %s" % [id, got, want])
	var polys := _wall_polygons(world.get_node("Walls"))
	if polys.is_empty():
		return _fail("%s: Walls has no polygons" % id)
	for marker_name: String in ["Player", "Agents"]:
		var marker := world.get_node_or_null("SpawnPoints/" + marker_name) as Marker2D
		if marker == null:
			return _fail("%s: SpawnPoints/%s missing" % [id, marker_name])
		var p: Vector2 = marker.global_position
		if not bounds.grow(-WorldBuilder.FOOT_RADIUS).has_point(p):
			return _fail("%s: spawn %s %s outside bounds %s" % [id, marker_name, p, bounds])
		for poly: PackedVector2Array in polys:
			if Geometry2D.is_point_in_polygon(p, poly) or _edge_distance(p, poly) < WorldBuilder.FOOT_RADIUS:
				return _fail("%s: spawn %s %s inside a wall" % [id, marker_name, p])
	return true


func _wall_polygons(walls: Node) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for child: Node in walls.get_children():
		var cp := child as CollisionPolygon2D
		if cp == null:
			continue
		out.append(cp.global_transform * cp.polygon)
	return out


func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best
