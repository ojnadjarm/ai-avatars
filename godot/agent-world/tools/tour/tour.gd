extends Node
## Scripted Movie Maker tour: title, Magic Forest walk + dialogue, title, Darkwood at night, Settings; stills to `-- --out DIR`.

signal walk_done

const SELECTOR_SCENE := preload("res://scenes/room_selector.tscn")
const WORLD_SCENE := preload("res://scenes/world.tscn")
const SETTINGS_SCENE := preload("res://scenes/settings_screen.tscn")
const MinimapScript := preload("res://scripts/hud/minimap.gd")
const ZoneBanner := preload("res://scripts/hud/zone_banner.gd")
const WORLDS := "res://assets/worlds/%s/world.json"
## Legs of path waypoints per world (from the specs' paths); each later leg starts with a fade cut.
const ROUTES := {
	"magic_forest": [[
		Vector2(1300, 840), Vector2(1230, 700), Vector2(1260, 560), Vector2(1420, 450), Vector2(1600, 400),
		Vector2(1850, 310), Vector2(1952, 300), Vector2(2100, 310), Vector2(2330, 440), Vector2(2470, 600),
		Vector2(2470, 820),
	]],
	"darkwood": [[
		Vector2(1466, 577), Vector2(1600, 585), Vector2(1630, 690), Vector2(1700, 790), Vector2(1820, 850),
		Vector2(1940, 872), Vector2(2040, 874),
	], [
		Vector2(1700, 1120), Vector2(1680, 1166), Vector2(1520, 1150), Vector2(1250, 1150), Vector2(980, 1100),
		Vector2(870, 1046),
	]],
}
## Point the player passes when the camera zooms out to the widest integer level and back.
const ZOOM_AT := {"magic_forest": Vector2(1850, 310)}
const SNAG_TIME := 1.0
## Route grid: cell size and the feet radius (FOOT_RADIUS 6 plus 1 px clearance) probed against the world's bodies.
const CELL := 8
const PROBE_RADIUS := 7.0
const PLAYER_LINE := "Luna, the old lanterns by the bridge went dark again. Did you see who passed?"
const LUNA_REPLY := "I saw a fox with a moth-light tied to its tail slip under the bridge at dusk. The lanterns dimmed one by one as it passed, as if they bowed to it. Follow the glow and you may find where the light went."

var out_dir := ""
var current: Node
var world: Node
var fade: ColorRect
var stills: Array[String] = []
var snags := 0
var _route: Array = []
var _wp := 0
var _zoom_at := Vector2.INF
var _speed := 0.0
var _walking := false
var _stuck_t := 0.0
var _zones: Array[Dictionary] = []
var _seen: Dictionary = {}
var _prefix := ""
var _grid: AStarGrid2D


func _ready() -> void:
	seed(714)
	out_dir = _arg("--out", ProjectSettings.globalize_path("user://tour"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var layer := CanvasLayer.new()
	layer.layer = 120
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)
	add_child(layer)
	_run()


func _run() -> void:
	await _title("magic_forest", 8.0, "title")
	await _enter_world("magic_forest", "mf")
	await _walk_legs("magic_forest")
	await _dialogue()
	await _fade_to(1.0, 0.5)
	await _title("darkwood", 4.0, "title-return")
	await _enter_world("darkwood", "dw")
	await _walk_legs("darkwood")
	await _fade_to(1.0, 0.5)
	await _settings()
	await _fade_to(1.0, 0.5)
	print("[tour] done stills=%d snags=%d" % [stills.size(), snags])
	get_tree().quit()


func _swap(node: Node) -> void:
	if current:
		remove_child(current)
		current.queue_free()
	world = null
	current = node
	add_child(node)
	move_child(node, 0)


## Shows the title for `hold` s, then moves the gem to `world_id` and confirms through the menu's own fade.
func _title(world_id: String, hold: float, still: String) -> void:
	var sel: Node = SELECTOR_SCENE.instantiate()
	_swap(sel)
	var menu: Node = sel.title.menu
	menu.confirmed.disconnect(sel._on_confirmed)
	fade.modulate.a = 0.0
	await _wait(hold - 1.2)
	await _still(still)
	var index := 0
	for i in sel.rooms.size():
		if String(sel.rooms[i]["path"]) == WORLDS % world_id:
			index = i
	if index != menu.sel:
		menu._select(index)
	await _wait(1.2)
	menu.confirm_t = 0.0
	await menu.confirmed
	fade.modulate.a = 1.0


func _enter_world(world_id: String, prefix: String) -> void:
	WorldBuilder.offline = true
	var w: Node = WORLD_SCENE.instantiate()
	w.room_config_path = WORLDS % world_id
	_swap(w)
	world = w
	for i in 8:
		await get_tree().physics_frame
	world.minimap.visible = true
	world.player.set_physics_process(false)
	_speed = world.player.max_speed * world.player.sprint_mult
	world.player.char_sprite.speed_scale = world.player.sprint_mult
	_zones = MinimapScript.read_zones(world._world_scene)
	_build_grid()
	_seen.clear()
	_prefix = prefix
	print("[tour] %s speed=%.1f zones=%d" % [world_id, _speed, _zones.size()])
	await _wait(0.2)
	await _fade_to(0.0, 0.6)
	await _wait(1.2)


func _walk_legs(world_id: String) -> void:
	var legs: Array = ROUTES[world_id]
	for i in legs.size():
		if i > 0:
			await _fade_to(1.0, 0.35)
			_teleport(_grid.get_point_position(_free_cell(legs[i][0])))
			await _wait(0.15)
			await _fade_to(0.0, 0.35)
		_route = _plan([world.player.global_position] + legs[i])
		_zoom_at = ZOOM_AT.get(world_id, Vector2.INF) if i == 0 else Vector2.INF
		_wp = 0
		_stuck_t = 0.0
		_walking = true
		await walk_done
		await _wait(0.6)


## Marks every cell whose feet circle overlaps a static body (walls, trees, props, water masks) as solid.
func _build_grid() -> void:
	var p: CharacterBody2D = world.player
	var bounds: Rect2 = world.room_bounds
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, Vector2i((bounds.size / CELL).floor()))
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = bounds.position + Vector2(CELL, CELL) * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var shape := CircleShape2D.new()
	shape.radius = PROBE_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = p.collision_mask
	var ex: Array[RID] = [p.get_rid()]
	for a: Node in world.agents_container.get_children():
		if a is CollisionObject2D:
			ex.append((a as CollisionObject2D).get_rid())
	q.exclude = ex
	var space := p.get_world_2d().direct_space_state
	var t0 := Time.get_ticks_msec()
	var solid := 0
	for y in _grid.region.size.y:
		for x in _grid.region.size.x:
			q.transform = Transform2D(0.0, _grid.offset + Vector2(x, y) * CELL)
			if not space.intersect_shape(q, 1).is_empty():
				_grid.set_point_solid(Vector2i(x, y))
				solid += 1
	print("[tour] grid %s solid=%d in %d ms" % [_grid.region.size, solid, Time.get_ticks_msec() - t0])


## A* between consecutive waypoints on the grid, then string-pulled to the farthest point in clear sight.
func _plan(waypoints: Array) -> Array:
	var cells: Array[Vector2i] = []
	for i in waypoints.size() - 1:
		var path := _grid.get_id_path(_free_cell(waypoints[i]), _free_cell(waypoints[i + 1]))
		if path.is_empty():
			print("[tour] no path %s -> %s" % [waypoints[i], waypoints[i + 1]])
			path = [_free_cell(waypoints[i]), _free_cell(waypoints[i + 1])]
		for c: Vector2i in path:
			if cells.is_empty() or cells[-1] != c:
				cells.append(c)
	var out: Array = [_grid.get_point_position(cells[0])]
	var at := 0
	while at < cells.size() - 1:
		var nxt := at + 1
		for j in range(cells.size() - 1, at + 1, -1):
			if _clear(cells[at], cells[j]):
				nxt = j
				break
		out.append(_grid.get_point_position(cells[nxt]))
		at = nxt
	return out


func _free_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(((p - _grid.offset) / CELL).round())
	for r in 8:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if _grid.is_in_boundsv(n) and not _grid.is_point_solid(n):
					return n
	return c


func _clear(a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	for k in n + 1:
		var c := Vector2i((Vector2(a).lerp(Vector2(b), float(k) / maxf(1.0, n))).round())
		if _grid.is_point_solid(c):
			return false
	return true


func _teleport(p: Vector2) -> void:
	world.player.global_position = p
	world.player.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not _walking or world == null:
		return
	var p: CharacterBody2D = world.player
	var to: Vector2 = _route[_wp] - p.global_position
	if to.length() <= maxf(3.0, _speed * delta):
		_wp += 1
		_stuck_t = 0.0
		if _wp >= _route.size():
			_walking = false
			p.velocity = Vector2.ZERO
			p._update_animation(false)
			walk_done.emit()
			return
		to = _route[_wp] - p.global_position
	var dir := to.normalized()
	var before := p.global_position
	p.velocity = dir * _speed
	p.move_and_slide()
	p._update_facing(dir)
	p._update_animation(true)
	_stuck_t = _stuck_t + delta if before.distance_to(p.global_position) < _speed * delta * 0.3 else 0.0
	if _stuck_t > SNAG_TIME:
		snags += 1
		print("[tour] snag at %s -> %s" % [p.global_position, _route[_wp]])
		_teleport(_route[_wp])
		_stuck_t = 0.0
	_track_zone(p.global_position)
	if p.global_position.distance_to(_zoom_at) < 24.0:
		_zoom_at = Vector2.INF
		_zoom_reveal()


## Takes one still per zone the first time the player's feet enter it, once its banner is fully unfurled (4 s at most).
func _track_zone(at: Vector2) -> void:
	for z: Dictionary in _zones:
		if (z["rect"] as Rect2).has_point(at) and not _seen.has(z["name"]):
			_seen[z["name"]] = true
			print("[tour] zone %s" % z["name"])
			_zone_still(z["name"], "%s-%s" % [_prefix, String(z["name"]).to_snake_case().replace(" ", "_")])


func _zone_still(zone_name: String, name: String) -> void:
	var banner: Node = world.zone_banner
	var waited := 0.0
	while waited < 4.0 and is_instance_valid(banner) and not (banner.zone == zone_name and banner.phase() == ZoneBanner.Phase.HOLD):
		await _wait(0.1)
		waited += 0.1
	await _wait(0.2)
	if not is_instance_valid(banner):
		return
	print("[tour] banner %s %s" % [zone_name, "full" if banner.zone == zone_name and banner.shown() == 1.0 else "PARTIAL"])
	await _still(name)


## Steps the camera out one integer level at a time to the widest, holds, and steps back.
func _zoom_reveal() -> void:
	var cam := world.player.get_node("Camera2D") as Camera2D
	var levels: Array[float] = world._camera_zoom_levels()
	var start := cam.zoom.x
	while cam.zoom.x > levels[0] + 0.001:
		cam.zoom = Vector2.ONE * PixelZoom.step(cam.zoom.x, -1, levels)
		await _wait(0.45)
	await _wait(0.6)
	await _still("%s-overview" % _prefix)
	await _wait(1.2)
	while cam.zoom.x < start - 0.001:
		cam.zoom = Vector2.ONE * PixelZoom.step(cam.zoom.x, 1, levels)
		await _wait(0.45)


func _dialogue() -> void:
	var p: CharacterBody2D = world.player
	var luna: Node = world.find_agent("luna")
	if luna:
		luna.set_physics_process(false)
		(luna as CharacterBody2D).velocity = Vector2.ZERO
		luna.global_position = p.global_position + Vector2(-28, 2)
		luna.reset_physics_interpolation()
	p._update_facing(Vector2.LEFT)
	p._update_animation(false)
	await _wait(0.8)
	world.dialogue.show_input("luna", "Luna")
	world.dialogue.conversation_history.append({"speaker": "You", "text": PLAYER_LINE, "is_player": true})
	world.dialogue.show_response("Luna", LUNA_REPLY)
	world.dialogue.set_mood("curious")
	await _wait(8.5)
	await _still("mf-dialogue")
	await _wait(1.5)
	world.dialogue.dismiss()
	await _wait(1.0)


func _settings() -> void:
	var screen: Node = SETTINGS_SCENE.instantiate()
	_swap(screen)
	await get_tree().process_frame
	await _fade_to(0.0, 0.5)
	for i in 4:
		screen.select_tab(i)
		await _wait(0.5)
		await _still("settings-%d" % (i + 1))
		await _wait(1.6)


func _fade_to(alpha: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", alpha, secs)
	await tw.finished


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs, true, true).timeout


func _still(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	stills.append(path)
	print("[tour] still %s" % path)


func _arg(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with(key + "="):
			return args[i].trim_prefix(key + "=")
	return fallback
