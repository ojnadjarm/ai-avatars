extends RefCounted
## Sprite layers of built.json as z-ordered Node2D children of Art at scale 1: lit sprites, foliage atlases, shade, water (+ mirror), waterfall.

const ORDER := ["shade", "plateau", "water", "fall", "bridge", "ysort", "canopy", "fg"]
const Z := {"canopy": 10, "fg": 11}
## Y-sorted sprites live in nested y-sorted chunk nodes of this many px, hidden off view so the sort skips them.
const CHUNK := 256
const WATER := preload("res://shaders/world/water.gdshader")
## Water is drawn as tiles of this many px that hold water, so the shader skips dry screen area and off-view tiles cull.
const WATER_TILE := 128
const FALL := preload("res://shaders/world/fall.gdshader")


## Creates the layer nodes (YSort included) and returns {layer name: Node2D}.
static func make(art: Node2D) -> Dictionary:
	var g := {}
	for nm in ORDER:
		var n := Node2D.new()
		n.name = "YSort" if nm == "ysort" else nm.capitalize()
		n.z_index = Z.get(nm, 0)
		n.y_sort_enabled = nm in ["ysort", "plateau"]
		art.add_child(n)
		g[nm] = n
	return g


static func fill(g: Dictionary, sc: Dictionary, tex, amb: Color, anim) -> int:
	var nodes: Array = sc["nodes"].duplicate()
	nodes.sort_custom(func(p, q): return p["sort"] < q["sort"])
	var period := float(sc["period"])
	var n := 0
	var chunks := {}
	var mirror := {}
	for node in nodes:
		var layer: String = node["layer"]
		if layer == "ground":
			continue
		if layer == "mirror":
			mirror = node
			continue
		if layer == "fall":
			_waterfall(node, g["fall"], period)
		elif layer == "shade":
			_shade(node, g["shade"], tex)
		else:
			var parent: Node2D = g.get(layer, g["ysort"])
			if parent.y_sort_enabled:
				parent = _chunk(parent, node, chunks)
			_sprite(node, parent, tex, amb, sc.get("foliage", {}), anim)
		n += 1
	for c in chunks.values():
		c[0].set_meta("rect", c[1])
		anim.add_cull(c[0], c[1])
	_water(g["water"], sc, tex, amb, mirror)
	return n


## The y-sorted chunk node of a layer that holds a sprite by its feet cell; grows the chunk's culling rect.
static func _chunk(layer: Node2D, n: Dictionary, chunks: Dictionary) -> Node2D:
	var key := "%s:%d:%d" % [layer.name, int(n["x"]) / CHUNK, int(n["sort"]) / CHUNK]
	var rect := Rect2(n["x"], n["y"], n["w"], n["h"])
	if chunks.has(key):
		chunks[key][1] = (chunks[key][1] as Rect2).merge(rect)
	else:
		var c := Node2D.new()
		c.y_sort_enabled = true
		layer.add_child(c)
		chunks[key] = [c, rect]
	return chunks[key][0]


static func _sprite(n: Dictionary, parent: Node2D, tex, amb: Color, foliage: Dictionary, anim) -> void:
	var f: Dictionary = n["files"]
	var s := Sprite2D.new()
	s.texture = tex.canvas(f, Vector2i(int(n["w"]), int(n["h"])))
	var bm: BitMap = tex.mask(f["albedo"])
	if bm:
		s.set_meta("mask", bm)
	s.centered = false
	s.position = Vector2(n["x"], n["sort"])
	s.offset = Vector2(0, n["y"] - n["sort"])
	var fa: Dictionary = foliage.get(n.get("anim", ""), {})
	if not fa.is_empty():
		s.hframes = int(fa["cols"])
		s.vframes = int(fa["rows"])
		anim.add_foliage(s, PackedInt32Array(fa["seq"]), float(fa["fps"]), float(fa["speed"]),
			Rect2(n["x"], n["y"], n["w"], n["h"]), parent if parent.y_sort_enabled else null)
	parent.add_child(s)
	if f.has("emissive"):
		var e := Sprite2D.new()
		e.texture = tex.img(f["emissive"])
		e.centered = false
		e.offset = s.offset
		e.hframes = s.hframes
		e.vframes = s.vframes
		var em := CanvasItemMaterial.new()
		em.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		em.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		e.material = em
		e.modulate = Color(0.5 / amb.r, 0.5 / amb.g, 0.5 / amb.b)
		s.add_child(e)


static func _shade(n: Dictionary, parent: Node2D, tex) -> void:
	var s := Sprite2D.new()
	s.texture = tex.img(n["files"]["albedo"])
	s.centered = false
	s.position = Vector2(n["x"], n["y"])
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	s.material = m
	parent.add_child(s)


## `mirror`: optional node whose albedo (trees flipped about their feet, cut to still water) the shader shows as reflection.
static func _water(parent: Node2D, sc: Dictionary, tex, amb: Color, mirror: Dictionary) -> void:
	var water: Texture2D = tex.img("water.png")
	if water == null:
		return
	var m := ShaderMaterial.new()
	m.shader = WATER
	m.set_shader_parameter("waterline", float(sc["waterline"]))
	m.set_shader_parameter("art", Vector2(sc["size"][0], sc["size"][1]))
	m.set_shader_parameter("cliff", float(sc["cliff"]))
	var mr = sc.get("moon_reflect")
	if mr is Array:
		m.set_shader_parameter("moon", Vector2(mr[0], mr[1]))
	m.set_shader_parameter("moon_on", 1.0 if mr is Array else 0.0)
	m.set_shader_parameter("day", 1.0 if sc.get("day", false) else 0.0)
	m.set_shader_parameter("ambient", Vector3(amb.r, amb.g, amb.b))
	m.set_shader_parameter("period", float(sc["period"]))
	if not mirror.is_empty():
		m.set_shader_parameter("mirror_tex", tex.img(mirror["files"]["albedo"]))
		m.set_shader_parameter("mirror_rect", Vector4(mirror["x"], mirror["y"], mirror["w"], mirror["h"]))
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	parent.add_child(bb)
	var im := water.get_image()
	for y in range(0, im.get_height(), WATER_TILE):
		for x in range(0, im.get_width(), WATER_TILE):
			var r := Rect2i(x, y, WATER_TILE, WATER_TILE).intersection(Rect2i(Vector2i.ZERO, im.get_size()))
			if im.get_region(r).is_invisible():
				continue
			var s := Sprite2D.new()
			s.texture = water
			s.centered = false
			s.region_enabled = true
			s.region_rect = Rect2(r)
			s.position = Vector2(r.position)
			s.material = m
			parent.add_child(s)

static func _waterfall(n: Dictionary, parent: Node2D, period: float) -> void:
	var r := ColorRect.new()
	r.position = Vector2(n["x"], n["y"])
	r.size = Vector2(n["w"], n["h"])
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = FALL
	m.set_shader_parameter("size", Vector2(n["w"], n["h"]))
	m.set_shader_parameter("period", period)
	r.material = m
	parent.add_child(r)
