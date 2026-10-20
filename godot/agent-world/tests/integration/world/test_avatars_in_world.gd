extends RefCounted
## Booted big worlds (offline): avatars y-sort by their feet, collide by a feet circle, and path around walls.

const WORLDS := ["magic_forest", "darkwood"]
const SAMPLE_STEP := 3.0
## Path links may touch a wall edge but never enter it.
const GRAZE := 0.0

var failure_message: String = ""


func run() -> bool:
	var was_offline: bool = WorldBuilder.offline
	WorldBuilder.offline = true
	var ok := true
	for id: String in WORLDS:
		if not _check_world(id):
			ok = false
			break
	WorldBuilder.offline = was_offline
	return ok


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _check_world(id: String) -> bool:
	var host := Node2D.new()
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene else tree.root).add_child(host)
	var loader := (load("res://scenes/world.tscn") as PackedScene).instantiate() as WorldLoader
	loader.room_config_path = "res://assets/worlds/%s/world.json" % id
	host.add_child(loader)
	var ok := _check_loaded(id, loader)
	host.free()
	return ok


func _check_loaded(id: String, loader: WorldLoader) -> bool:
	var world := loader.get_node_or_null("World") as Node2D
	for child: Node in loader.get_children():
		if child.has_method("ysort_root"):
			world = child
	var ys: Node2D = WorldBuilder.ysort_root(world)
	if ys == null:
		return _fail("%s: no ysort_root" % id)
	if loader.player.get_parent() != ys:
		return _fail("%s: player parent %s is not ysort_root" % [id, loader.player.get_parent()])
	if not _check_body(id, loader.player, "player"):
		return false
	var agents: Array[Agent] = []
	for child: Node in loader.agents_container.get_children():
		if child is Agent:
			agents.append(child)
	if agents.is_empty():
		return _fail("%s: no agents spawned" % id)
	if loader.agents_container.get_parent() != ys or not loader.agents_container.y_sort_enabled:
		return _fail("%s: agents container is not a y-sorted child of ysort_root" % id)
	for agent: Agent in agents:
		if not _check_body(id, agent, agent.agent_id):
			return false
	if not _check_occlusion(id, loader.player):
		return false
	return _check_paths(id, agents[0], world)


## Parked just behind the biggest y-sorted tree, the player reports itself occluded (its outline ghost shows).
func _check_occlusion(id: String, player: CharacterBody2D) -> bool:
	var built: Dictionary = GameState.load_json("res://assets/worlds/%s/art/built.json" % id, "built")
	var best: Dictionary = {}
	for n: Dictionary in built.get("nodes", []):
		if str(n.get("layer", "")) == "ysort" and float(n["w"]) * float(n["h"]) > float(best.get("w", 0)) * float(best.get("h", 0)):
			best = n
	if best.is_empty():
		return _fail("%s: no y-sorted sprite in built.json" % id)
	var was: Vector2 = player.global_position
	player.global_position = Vector2(float(best["x"]) + float(best["w"]) * 0.5, float(best["sort"]) - 2.0 * WorldBuilder.FOOT_RADIUS)
	var hidden: bool = player.call("is_occluded")
	player.global_position = was
	if not hidden:
		return _fail("%s: player behind %s not reported occluded" % [id, best.get("name", "?")])
	return true


func _check_body(id: String, body: CharacterBody2D, who: String) -> bool:
	var sprite := body.get_node_or_null("CharSprite") as AnimatedSprite2D
	if sprite == null or sprite.position != Vector2.ZERO:
		return _fail("%s/%s: CharSprite missing or not at the body origin" % [id, who])
	var feet: float = _feet_y(sprite)
	if absf(feet) > WorldBuilder.FOOT_RADIUS:
		return _fail("%s/%s: lowest sprite pixel %.1f px from the feet origin" % [id, who, feet])
	var circles: int = 0
	for child: Node in body.get_children():
		var col := child as CollisionShape2D
		if col == null:
			continue
		var circle := col.shape as CircleShape2D
		if circle == null or not is_equal_approx(circle.radius, WorldBuilder.FOOT_RADIUS) or col.position != Vector2.ZERO:
			return _fail("%s/%s: body collider is not a %.0f px feet circle at the origin" % [id, who, WorldBuilder.FOOT_RADIUS])
		circles += 1
	if circles != 1:
		return _fail("%s/%s: %d body colliders, want 1" % [id, who, circles])
	return true


## Lowest opaque pixel of idle_down frame 0, relative to the body origin.
func _feet_y(sprite: AnimatedSprite2D) -> float:
	var atlas := sprite.sprite_frames.get_frame_texture("idle_down", 0) as AtlasTexture
	var sheet: Texture2D = atlas.atlas
	if sheet is CanvasTexture:
		sheet = (sheet as CanvasTexture).diffuse_texture
	var used: Rect2i = sheet.get_image().get_region(Rect2i(atlas.region)).get_used_rect()
	return (float(used.end.y) + sprite.offset.y) * sprite.scale.y


func _check_paths(id: String, agent: Agent, world: Node2D) -> bool:
	agent._cache_room_data()
	if agent._nav_grid.is_empty():
		return _fail("%s: nav grid empty" % id)
	var walker: Dictionary = GameState.load_json("res://assets/worlds/%s/scene.json" % id, "scene").get("walker", {})
	var goals: Dictionary = walker.get("goals", {})
	if goals.is_empty():
		return _fail("%s: scene.json has no walker goals" % id)
	var start := Vector2(walker["start"][0], walker["start"][1])
	var polys := _wall_polygons(world.get_node("Walls"))
	var rects: Array[Rect2] = []
	for poly: PackedVector2Array in polys:
		rects.append(_poly_rect(poly))
	for goal_name: String in goals:
		var goal := Vector2(goals[goal_name][0], goals[goal_name][1])
		var path: Array[Vector2] = agent._find_path(start, goal)
		if path.is_empty():
			return _fail("%s: no path %s -> %s (%s)" % [id, start, goal, goal_name])
		var prev := start
		for point: Vector2 in path:
			var hit: Variant = _wall_hit(prev, point, polys, rects)
			if hit != null:
				return _fail("%s: path to %s crosses a wall at %s" % [id, goal_name, hit])
			prev = point
		if prev.distance_to(goal) > agent._grid_cell_size * 1.5:
			return _fail("%s: path to %s ends at %s" % [id, goal_name, prev])
	return true


## First sample on segment a-b deeper than GRAZE inside a wall polygon, else null.
func _wall_hit(a: Vector2, b: Vector2, polys: Array[PackedVector2Array], rects: Array[Rect2]) -> Variant:
	var steps: int = maxi(1, ceili(a.distance_to(b) / SAMPLE_STEP))
	for i in range(steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		for k in polys.size():
			if rects[k].has_point(p) and Geometry2D.is_point_in_polygon(p, polys[k]) and _depth(p, polys[k]) > GRAZE:
				return p
	return null


## Distance from a point to the nearest polygon edge.
func _depth(p: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	for j in poly.size():
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[j], poly[(j + 1) % poly.size()])))
	return d


## Bounding rect of a polygon (is_point_in_polygon can report far-away points inside small polygons).
func _poly_rect(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q: Vector2 in poly:
		r = r.expand(q)
	return r.grow(0.01)


func _wall_polygons(walls: Node) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for child: Node in walls.get_children():
		var cp := child as CollisionPolygon2D
		if cp:
			out.append(cp.global_transform * cp.polygon)
	return out
