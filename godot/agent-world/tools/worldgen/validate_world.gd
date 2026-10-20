extends SceneTree
## Map-scale gate: size, zones, landmarks, spawns, reachability, raised levels, night lights and density of one world.
##
##   godot --headless --path . -s tools/worldgen/validate_world.gd -- res://assets/worlds/<id> [--report OUT.json] [--png OUT.png]
##   godot --headless --path . -s tools/worldgen/validate_world.gd -- --selftest

const SCREEN := Vector2(640, 360)
const SCREEN_AREA := 640.0 * 360.0
const WIDEST_VIEW := PixelZoom.MAX_VIEW
## 2 widest views per axis: 27.7 heights of a 78 px avatar; 30 would need 2340 px tall worlds (both are 2160).
const MIN_SIZE := WIDEST_VIEW * 2.0
const CELL := 8.0
const FOOT_RADIUS := 6.0
const MIN_ZONES := 10
const ZONE_MIN_SCREENS := 0.5
const ZONE_MAX_SCREENS := 4.0
const MIN_TALL := 2
const ZONE_REACH := 0.2
const PROP_REACH := 24.0
const MAP_REACH := 0.35
const MIN_LEVELS := 2
const NIGHT_LIGHTS := 3
const DENSITY_AVG := 20.0
const DENSITY_MIN := 8
const DENSE_LAYERS: Array[String] = ["ysort", "plateau", "canopy", "fg"]
const CHECKS: Array[String] = ["size", "zones", "landmarks", "spawns", "reach", "levels", "night", "density"]


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--selftest"):
		var ok: bool = await _selftest()
		quit(0 if ok else 1)
		return
	var dir: String = ""
	var report_path: String = ""
	var png_path: String = ""
	var i: int = 0
	while i < args.size():
		if args[i] == "--report" and i + 1 < args.size():
			i += 1
			report_path = args[i]
		elif args[i] == "--png" and i + 1 < args.size():
			i += 1
			png_path = args[i]
		else:
			dir = args[i]
		i += 1
	if dir == "":
		print("MAPSCALE fail: usage validate_world.gd -- res://assets/worlds/<id> [--report OUT.json] [--png OUT.png]")
		quit(1)
		return
	var packed: PackedScene = load(dir.path_join("world.tscn")) as PackedScene
	if packed == null:
		print("MAPSCALE fail: cannot load %s" % dir.path_join("world.tscn"))
		quit(1)
		return
	var r: Dictionary = await validate(packed.instantiate(), _read_built(dir))
	_print_result(r)
	if report_path != "":
		_write_text(report_path, JSON.stringify(r.report, "  "))
	if png_path != "":
		_mkdir_for(png_path)
		(r.image as Image).save_png(ProjectSettings.globalize_path(png_path))
	quit(0 if r.fails.is_empty() else 1)


func _read_built(dir: String) -> Dictionary:
	var path: String = dir.path_join("art/built.json")
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func validate(world: Node2D, built: Dictionary) -> Dictionary:
	root.add_child(world)
	for _f in 3:
		await physics_frame
	var r: Dictionary = _check(world, built)
	root.remove_child(world)
	world.free()
	await physics_frame
	return r


func _check(world: Node2D, built: Dictionary) -> Dictionary:
	var lines: Dictionary = {}
	var fails: Dictionary = {}
	var report: Dictionary = {}
	var b: Rect2 = _bounds(world)
	var screens := Vector2i(maxi(1, roundi(b.size.x / SCREEN.x)), maxi(1, roundi(b.size.y / SCREEN.y)))
	var n_screens: int = screens.x * screens.y

	report.size = {"w": b.size.x, "h": b.size.y, "screens": n_screens}
	lines.size = "%dx%d px, %d screens, %.1fx the widest view (min %dx%d)" % [b.size.x, b.size.y, n_screens,
		b.get_area() / (WIDEST_VIEW.x * WIDEST_VIEW.y), MIN_SIZE.x, MIN_SIZE.y]
	if b.size.x < MIN_SIZE.x or b.size.y < MIN_SIZE.y:
		fails.size = "size %dx%d < %dx%d" % [b.size.x, b.size.y, MIN_SIZE.x, MIN_SIZE.y]
	if b.size.x < CELL or b.size.y < CELL:
		fails.size = "no Background texture"
		return {"lines": lines, "fails": fails, "report": report, "image": Image.create(1, 1, false, Image.FORMAT_RGBA8)}

	var zones: Array[Dictionary] = []
	var zone_node: Node = world.get_node_or_null("Zones")
	if zone_node != null:
		for z: Node in zone_node.get_children():
			if z is Area2D:
				zones.append({"name": str(z.get_meta("zone_name", "")), "rect": _shape_rect(z)})
	var zone_bad: Array[String] = []
	var seen_names: Dictionary = {}
	for z: Dictionary in zones:
		var area: float = (z.rect as Rect2).get_area() / SCREEN_AREA
		z.screens = snappedf(area, 0.01)
		if z.name == "" or seen_names.has(z.name):
			zone_bad.append("name '%s' empty or repeated" % z.name)
		seen_names[z.name] = true
		if area < ZONE_MIN_SCREENS or area > ZONE_MAX_SCREENS:
			zone_bad.append("'%s' %.2f screens" % [z.name, area])
	if zones.size() < MIN_ZONES:
		zone_bad.push_front("%d zones < %d" % [zones.size(), MIN_ZONES])
	lines.zones = "%d zones %s" % [zones.size(), ", ".join(zones.map(func(z: Dictionary) -> String: return "%s %.2f" % [z.name, z.screens]))]
	if not zone_bad.is_empty():
		fails.zones = "zones: " + "; ".join(zone_bad)

	var marks: Array[Dictionary] = []
	var mark_node: Node = world.get_node_or_null("Landmarks")
	if mark_node != null:
		for m: Node in mark_node.get_children():
			if m is Node2D:
				marks.append({"name": str(m.get_meta("landmark_name", m.name)), "at": (m as Node2D).global_position, "tall": bool(m.get_meta("tall", false))})
	var mark_cells: PackedInt32Array = _per_screen(marks.map(func(m: Dictionary) -> Vector2: return m.at), b, screens)
	var empty_screens: Array[String] = _screens_under(mark_cells, 1, screens)
	var tall: int = marks.filter(func(m: Dictionary) -> bool: return m.tall).size()
	report.landmarks = {"count": marks.size(), "tall": tall, "per_screen": Array(mark_cells), "empty": empty_screens}
	lines.landmarks = "%d markers, %d tall, screens without one: %d" % [marks.size(), tall, empty_screens.size()]
	var lm_bad: Array[String] = []
	if not empty_screens.is_empty():
		lm_bad.append("no landmark in screens %s" % _short(empty_screens))
	if tall < MIN_TALL:
		lm_bad.append("%d tall < %d" % [tall, MIN_TALL])
	if not lm_bad.is_empty():
		fails.landmarks = "landmarks: " + "; ".join(lm_bad)

	var gs := Vector2i(ceili(b.size.x / CELL), ceili(b.size.y / CELL))
	var walk := PackedByteArray()
	walk.resize(gs.x * gs.y)
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	var probe := CircleShape2D.new()
	probe.radius = FOOT_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = probe
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for y in gs.y:
		for x in gs.x:
			q.transform = Transform2D(0.0, _cell_center(Vector2i(x, y), b))
			walk[y * gs.x + x] = 1 if space.intersect_shape(q, 1).is_empty() else 0

	var spawn: Dictionary = {}
	var sp_bad: Array[String] = []
	for key: String in ["Player", "Agents"]:
		var m: Node2D = world.get_node_or_null("SpawnPoints/" + key) as Node2D
		if m == null:
			sp_bad.append("%s missing" % key)
			continue
		var c: Vector2i = _cell_of(m.global_position, b)
		spawn[key] = c
		if not b.has_point(m.global_position):
			sp_bad.append("%s out of bounds" % key)
		elif walk[c.y * gs.x + c.x] == 0:
			sp_bad.append("%s on a blocked cell" % key)
	lines.spawns = "Player %s, Agents %s" % [spawn.get("Player", "-"), spawn.get("Agents", "-")]
	if not sp_bad.is_empty():
		fails.spawns = "spawns: " + "; ".join(sp_bad)

	var reach := PackedByteArray()
	reach.resize(gs.x * gs.y)
	if spawn.has("Player") and walk[(spawn.Player as Vector2i).y * gs.x + (spawn.Player as Vector2i).x] == 1:
		_flood(walk, reach, gs, spawn.Player)
	var walkable: int = walk.count(1)
	var reached: int = reach.count(1)
	var share: float = float(reached) / float(gs.x * gs.y)
	var re_bad: Array[String] = []
	for z: Dictionary in zones:
		var zc: Vector2i = _count_in_rect(reach, gs, b, z.rect)
		z.reach = snappedf(float(zc.x) / maxf(1.0, float(zc.y)), 0.001)
		if z.reach < ZONE_REACH:
			re_bad.append("zone '%s' %.0f%% reachable" % [z.name, z.reach * 100.0])
	var props_bad: Array[String] = []
	var prop_node: Node = world.get_node_or_null("Props")
	var n_props: int = 0
	if prop_node != null:
		for p: Node in prop_node.get_children():
			if not p is Node2D:
				continue
			n_props += 1
			if not _near_reached(reach, gs, b, _shape_rect(p as Node2D)):
				props_bad.append(str(p.name))
	if not props_bad.is_empty():
		re_bad.append("%d props unreachable (%s)" % [props_bad.size(), " ".join(props_bad.slice(0, 5))])
	if spawn.has("Agents") and reach[(spawn.Agents as Vector2i).y * gs.x + (spawn.Agents as Vector2i).x] == 0:
		re_bad.append("Agents spawn unreachable")
	if share < MAP_REACH:
		re_bad.append("map %.0f%% reachable < %.0f%%" % [share * 100.0, MAP_REACH * 100.0])
	report.zones = zones.map(func(z: Dictionary) -> Dictionary:
		var rr: Rect2 = z.rect
		return {"name": z.name, "rect": [rr.position.x, rr.position.y, rr.size.x, rr.size.y], "screens": z.screens, "reach": z.get("reach", 0.0)})
	report.reach = {"grid": [gs.x, gs.y], "walkable": walkable, "reached": reached, "share": snappedf(share, 0.001),
		"props": n_props, "props_unreachable": props_bad}
	lines.reach = "grid %dx%d, walkable %.0f%%, reached %.0f%%, props %d (%d unreachable), zones min %.0f%%" % [
		gs.x, gs.y, 100.0 * walkable / (gs.x * gs.y), share * 100.0, n_props, props_bad.size(),
		100.0 * zones.reduce(func(a: float, z: Dictionary) -> float: return minf(a, z.reach), 1.0 if zones.size() > 0 else 0.0)]
	if not re_bad.is_empty():
		fails.reach = "reach: " + "; ".join(re_bad)

	var levels: Array[Dictionary] = _levels(built, reach, gs, b, world)
	var heights: Dictionary = {}
	var lv_bad: Array[String] = []
	for lv: Dictionary in levels:
		if lv.reach >= ZONE_REACH:
			heights[lv.elevation] = true
		else:
			lv_bad.append("level '%s' %.0f%% reachable" % [lv.name, lv.reach * 100.0])
	report.levels = levels
	lines.levels = "%d raised levels, %d distinct reachable heights %s" % [levels.size(), heights.size(),
		", ".join(levels.map(func(l: Dictionary) -> String: return "%s +%d %.0f%%" % [l.name, l.elevation, l.reach * 100.0]))]
	if heights.size() < MIN_LEVELS:
		lv_bad.push_front("%d reachable raised heights < %d" % [heights.size(), MIN_LEVELS])
		fails.levels = "levels: " + "; ".join(lv_bad)

	var day: bool = bool(built.get("day", false))
	var light_pts: Array = []
	for l: Variant in built.get("lights", []):
		light_pts.append(world.global_transform * Vector2(float(l.x), float(l.y)))
	var art: Node = world.get_node_or_null("Art")
	for l: Node in world.find_children("*", "PointLight2D", true, false):
		if art == null or not art.is_ancestor_of(l):
			light_pts.append((l as Node2D).global_position)
	var light_cells: PackedInt32Array = _per_screen(light_pts, b, screens)
	var dark: Array[String] = _screens_under(light_cells, NIGHT_LIGHTS, screens)
	report.night = {"day": day, "lights": light_pts.size(), "per_screen": Array(light_cells), "dark": dark}
	lines.night = "day world, skipped" if day else "%d lights, min %d per screen, dark screens: %d" % [light_pts.size(), _min(light_cells), dark.size()]
	if not day and not dark.is_empty():
		fails.night = "night: < %d lights in screens %s" % [NIGHT_LIGHTS, _short(dark)]

	var dense_pts: Array = []
	for n: Variant in built.get("nodes", []):
		if DENSE_LAYERS.has(str(n.get("layer", ""))):
			var px: float = float(n.get("x", 0)) + float(n.get("w", 0)) * 0.5
			var py: float = float(n.get("sort", float(n.get("y", 0)) + float(n.get("h", 0))))
			dense_pts.append(world.global_transform * Vector2(px, py))
	var dense_cells: PackedInt32Array = _per_screen(dense_pts, b, screens)
	var avg: float = float(dense_pts.size()) / n_screens
	var sparse: Array[String] = _screens_under(dense_cells, DENSITY_MIN, screens)
	report.density = {"nodes": dense_pts.size(), "avg": snappedf(avg, 0.01), "min": _min(dense_cells), "per_screen": Array(dense_cells), "sparse": sparse}
	lines.density = "%d nodes, avg %.1f per screen, min %d" % [dense_pts.size(), avg, _min(dense_cells)]
	var de_bad: Array[String] = []
	if avg < DENSITY_AVG:
		de_bad.append("avg %.1f < %.0f" % [avg, DENSITY_AVG])
	if not sparse.is_empty():
		de_bad.append("< %d in screens %s" % [DENSITY_MIN, _short(sparse)])
	if not de_bad.is_empty():
		fails.density = "density: " + "; ".join(de_bad)

	report.pass = fails.is_empty()
	report.fails = fails.values()
	var img: Image = _overview(walk, reach, gs, b, zones, marks, world)
	return {"lines": lines, "fails": fails, "report": report, "image": img}


func _levels(built: Dictionary, reach: PackedByteArray, gs: Vector2i, b: Rect2, world: Node2D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Variant in built.get("levels", []):
		var pts := PackedVector2Array()
		for p: Variant in l.get("poly", []):
			pts.append(world.global_transform * Vector2(float(p[0]), float(p[1])))
		var lo: Vector2i = _cell_of(_poly_rect(pts).position, b)
		var hi: Vector2i = _cell_of(_poly_rect(pts).end, b)
		var hit: int = 0
		var total: int = 0
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				if Geometry2D.is_point_in_polygon(_cell_center(Vector2i(x, y), b), pts):
					total += 1
					hit += reach[y * gs.x + x]
		out.append({"name": str(l.get("name", "")), "elevation": int(l.get("elevation", 0)),
			"reach": snappedf(float(hit) / maxf(1.0, float(total)), 0.001)})
	return out.filter(func(l: Dictionary) -> bool: return l.elevation > 0)


func _poly_rect(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0] if pts.size() > 0 else Vector2.ZERO, Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	return r


func _print_result(r: Dictionary) -> void:
	for key: String in CHECKS:
		if r.lines.has(key):
			print("CHECK %-9s %s  %s" % [key, "FAIL" if r.fails.has(key) else "ok", r.lines[key]])
	if r.fails.is_empty():
		print("MAPSCALE pass")
	else:
		print("MAPSCALE fail: " + " | ".join(r.fails.values()))


func _bounds(world: Node2D) -> Rect2:
	var bg: Sprite2D = world.get_node_or_null("Background") as Sprite2D
	if bg == null or bg.texture == null:
		return Rect2()
	return bg.global_transform * bg.get_rect()


func _shape_rect(n: Node2D) -> Rect2:
	for c: Node in n.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			var s: Vector2 = ((c as CollisionShape2D).shape as RectangleShape2D).size
			return (c as CollisionShape2D).global_transform * Rect2(-s * 0.5, s)
	return Rect2(n.global_position, Vector2.ZERO)


func _cell_center(c: Vector2i, b: Rect2) -> Vector2:
	return b.position + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func _cell_of(p: Vector2, b: Rect2) -> Vector2i:
	var gs := Vector2i(ceili(b.size.x / CELL), ceili(b.size.y / CELL))
	var c := Vector2i(floori((p.x - b.position.x) / CELL), floori((p.y - b.position.y) / CELL))
	return c.clamp(Vector2i.ZERO, gs - Vector2i.ONE)


func _per_screen(points: Array, b: Rect2, screens: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(screens.x * screens.y)
	for p: Vector2 in points:
		if not b.grow(1.0).has_point(p):
			continue
		var sx: int = clampi(floori((p.x - b.position.x) / SCREEN.x), 0, screens.x - 1)
		var sy: int = clampi(floori((p.y - b.position.y) / SCREEN.y), 0, screens.y - 1)
		out[sy * screens.x + sx] += 1
	return out


func _screens_under(counts: PackedInt32Array, need: int, screens: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for i in counts.size():
		if counts[i] < need:
			out.append("%d,%d" % [i % screens.x, i / screens.x])
	return out


func _short(items: Array[String]) -> String:
	return " ".join(items.slice(0, 6)) + (" +%d more" % (items.size() - 6) if items.size() > 6 else "")


func _min(counts: PackedInt32Array) -> int:
	var m: int = counts[0] if counts.size() > 0 else 0
	for v in counts:
		m = mini(m, v)
	return m


func _flood(walk: PackedByteArray, reach: PackedByteArray, gs: Vector2i, start: Vector2i) -> void:
	var queue := PackedInt32Array([start.y * gs.x + start.x])
	reach[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % gs.x
		var y: int = i / gs.x
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx: int = x + dx
				var ny: int = y + dy
				if nx < 0 or ny < 0 or nx >= gs.x or ny >= gs.y:
					continue
				var j: int = ny * gs.x + nx
				if walk[j] == 0 or reach[j] == 1:
					continue
				if dx != 0 and dy != 0 and (walk[y * gs.x + nx] == 0 or walk[ny * gs.x + x] == 0):
					continue
				reach[j] = 1
				queue.append(j)


func _count_in_rect(reach: PackedByteArray, gs: Vector2i, b: Rect2, r: Rect2) -> Vector2i:
	var hit: int = 0
	var total: int = 0
	var lo: Vector2i = _cell_of(r.position, b)
	var hi: Vector2i = _cell_of(r.end, b)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if r.has_point(_cell_center(Vector2i(x, y), b)):
				total += 1
				hit += reach[y * gs.x + x]
	return Vector2i(hit, total)


func _near_reached(reach: PackedByteArray, gs: Vector2i, b: Rect2, r: Rect2) -> bool:
	var lo: Vector2i = _cell_of(r.position - Vector2.ONE * PROP_REACH, b)
	var hi: Vector2i = _cell_of(r.end + Vector2.ONE * PROP_REACH, b)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if reach[y * gs.x + x] == 0:
				continue
			var p: Vector2 = _cell_center(Vector2i(x, y), b)
			if p.distance_to(p.clamp(r.position, r.end)) <= PROP_REACH:
				return true
	return false


func _overview(walk: PackedByteArray, reach: PackedByteArray, gs: Vector2i, b: Rect2, zones: Array[Dictionary], marks: Array[Dictionary], world: Node2D) -> Image:
	var img: Image = Image.create(gs.x, gs.y, false, Image.FORMAT_RGBA8)
	for y in gs.y:
		for x in gs.x:
			var i: int = y * gs.x + x
			var c: Color = Color(0.36, 0.08, 0.1)
			if reach[i] == 1:
				c = Color(0.3, 0.68, 0.42)
			elif walk[i] == 1:
				c = Color(0.3, 0.3, 0.33)
			img.set_pixel(x, y, c)
	for zi in zones.size():
		var tint: Color = Color.from_hsv(float(zi) / maxf(1.0, zones.size()), 0.8, 1.0)
		var r: Rect2 = zones[zi].rect
		var lo: Vector2i = _cell_of(r.position, b)
		var hi: Vector2i = _cell_of(r.end, b)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(tint, 0.3))
	for m: Dictionary in marks:
		_dot(img, _cell_of(m.at, b), Color.WHITE if m.tall else Color(1.0, 0.85, 0.2))
	for key: String in ["Player", "Agents"]:
		var s: Node2D = world.get_node_or_null("SpawnPoints/" + key) as Node2D
		if s != null:
			_dot(img, _cell_of(s.global_position, b), Color(0.2, 0.8, 1.0) if key == "Player" else Color(1.0, 0.3, 0.9))
	return img


func _dot(img: Image, c: Vector2i, col: Color) -> void:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var p: Vector2i = c + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				img.set_pixelv(p, col)


func _mkdir_for(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())


func _write_text(path: String, text: String) -> void:
	_mkdir_for(path)
	var f: FileAccess = FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string(text)


func _selftest() -> bool:
	var cases: Array = [
		["pass", {}, []],
		["one widest view", {"cols": 3, "rows": 3}, ["size"]],
		["9 zones", {"zones": 9}, ["zones"]],
		["one raised level", {"levels": 1}, ["levels"]],
		["walled-off level", {"wall_level": true}, ["levels"]],
		["walled-off zone", {"wall_zone": true}, ["reach"]],
		["screen without landmark", {"no_landmark": true}, ["landmarks"]],
		["dark night screen", {"dark": true}, ["night"]],
		["sparse screen", {"sparse": true}, ["density"]],
	]
	var good: int = 0
	for c: Array in cases:
		var made: Array = _make_world(c[1])
		var r: Dictionary = await validate(made[0], made[1])
		var got: Array = r.fails.keys().map(func(k: Variant) -> String: return str(k))
		got.sort()
		var ok: bool = got == c[2]
		good += int(ok)
		print("SELFTEST %-24s %s  fails=%s expected=%s %s" % [c[0], "ok" if ok else "BAD", got, c[2], "" if ok else r.fails.values()])
	if good == cases.size():
		print("SELFTEST ok (%d/%d)" % [good, cases.size()])
		return true
	print("SELFTEST fail (%d/%d)" % [good, cases.size()])
	return false


func _make_world(o: Dictionary) -> Array:
	var cols: int = o.get("cols", 6)
	var rows: int = o.get("rows", 6)
	var w: float = cols * SCREEN.x
	var h: float = rows * SCREEN.y
	var world := Node2D.new()
	world.name = "World"
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.centered = false
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(w, h)
	bg.texture = tex
	world.add_child(bg)
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	world.add_child(walls)
	var props := Node2D.new()
	props.name = "Props"
	world.add_child(props)
	var spawns := Node2D.new()
	spawns.name = "SpawnPoints"
	world.add_child(spawns)
	var zones := Node2D.new()
	zones.name = "Zones"
	world.add_child(zones)
	var marks := Node2D.new()
	marks.name = "Landmarks"
	world.add_child(marks)
	var nodes: Array = []
	var lights: Array = []
	var centre: int = (rows / 2) * cols + cols / 2
	for sy in rows:
		for sx in cols:
			var o0 := Vector2(sx, sy) * SCREEN
			var si: int = sy * cols + sx
			_poly(walls, Rect2(o0 + Vector2(80, 60), Vector2(40, 40)))
			var prop := Area2D.new()
			prop.name = "prop_%d" % si
			prop.position = o0 + Vector2(440, 120)
			_rect_shape(prop, Vector2(32, 24))
			var body := StaticBody2D.new()
			body.name = "Body"
			_rect_shape(body, Vector2(32, 24))
			prop.add_child(body)
			props.add_child(prop)
			if not (o.get("no_landmark", false) and si == centre):
				var m := Marker2D.new()
				m.name = "lm_%d" % si
				m.position = o0 + Vector2(500, 300)
				m.set_meta("landmark_name", "Landmark %d" % si)
				m.set_meta("tall", si < MIN_TALL)
				marks.add_child(m)
			for k in (2 if o.get("sparse", false) and si == centre else 25):
				nodes.append({"name": "n%d_%d" % [si, k], "x": o0.x + 20 + (k % 5) * 120, "y": o0.y + 20 + (k / 5) * 64, "w": 24, "h": 32,
					"sort": o0.y + 52 + (k / 5) * 64, "layer": DENSE_LAYERS[k % DENSE_LAYERS.size()]})
			if not (o.get("dark", false) and si == centre):
				for k in (2 if si == 0 else 3):
					lights.append({"kind": "lamp", "x": o0.x + 200 + k * 100, "y": o0.y + 250, "color": [1, 0.8, 0.5], "energy": 1.0, "radius": 64, "z": 0})
	var lamp := PointLight2D.new()
	lamp.position = Vector2(560, 60)
	world.add_child(lamp)
	var zc: int = o.get("zones", MIN_ZONES)
	for zi in zc:
		var z := Area2D.new()
		z.name = "zone_%d" % zi
		z.set_meta("zone_name", "Zone %d" % zi)
		z.position = Vector2((zi % 5 + 0.5) * w / 5.0, (zi / 5 + 0.5) * h / 2.0)
		_rect_shape(z, Vector2(w / 5.0, h / 2.0))
		zones.add_child(z)
	if o.get("wall_zone", false):
		_poly(walls, Rect2(w * 4.0 / 5.0 - 8.0, h / 2.0 - 8.0, 16.0, h / 2.0 + 8.0))
		_poly(walls, Rect2(w * 4.0 / 5.0 - 8.0, h / 2.0 - 8.0, w / 5.0 + 8.0, 16.0))
	var levels: Array = []
	for li in o.get("levels", 2):
		var lr := Rect2(Vector2(li * 2, 1) * SCREEN + Vector2(160, 120), Vector2(240, 200))
		levels.append({"name": "Level %d" % li, "elevation": 30 + li * 40,
			"poly": [[lr.position.x, lr.position.y], [lr.end.x, lr.position.y], [lr.end.x, lr.end.y], [lr.position.x, lr.end.y]]})
		if li == 1 and o.get("wall_level", false):
			for e: Rect2 in [Rect2(lr.position - Vector2(16, 16), Vector2(lr.size.x + 32, 16)), Rect2(lr.position.x - 16, lr.end.y, lr.size.x + 32, 16),
					Rect2(lr.position.x - 16, lr.position.y, 16, lr.size.y), Rect2(lr.end.x, lr.position.y, 16, lr.size.y)]:
				_poly(walls, e)
	for pair: Array in [["Player", Vector2(320, 180)], ["Agents", Vector2(w - 320, 180)]]:
		var s := Marker2D.new()
		s.name = pair[0]
		s.position = pair[1]
		spawns.add_child(s)
	return [world, {"size": [w, h], "day": false, "nodes": nodes, "lights": lights, "levels": levels}]


func _poly(body: StaticBody2D, r: Rect2) -> void:
	var cp := CollisionPolygon2D.new()
	cp.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	body.add_child(cp)


func _rect_shape(n: Node, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	n.add_child(cs)
