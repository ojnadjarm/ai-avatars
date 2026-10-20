extends RefCounted
## Ambient CanvasModulate, moon/sun DirectionalLight2D, PointLight2D pools, additive halos; fireflies are halos only (no light).

const Tex := preload("res://scripts/world_art/art_textures.gd")


static func build(world: Node2D, lights: Node2D, glow: CanvasLayer, sc: Dictionary, tex, anim, amb: Color) -> void:
	var cm := CanvasModulate.new()
	cm.color = amb
	world.add_child(cm)
	var moon: Dictionary = sc["moon"]
	var dl := DirectionalLight2D.new()
	dl.name = "Sun" if sc.get("day", false) else "Moon"
	dl.color = Tex.color8(moon["color"])
	dl.energy = moon["energy"]
	dl.height = moon["height"]
	dl.rotation_degrees = 50.0
	lights.add_child(dl)
	var k: float = 1.35 / (amb.r + amb.g + amb.b)
	var day: bool = sc.get("day", false)
	for l in sc["lights"]:
		if l["kind"] == "firefly" and day:
			continue
		var pos := Vector2(l["x"], l["y"])
		if l["kind"] == "firefly":
			var h := halo(glow, pos, Color8(255, 220, 130), 12.0, 0.65, tex)
			anim.add_fly(h, pos, float(l.get("phase", 0.0)))
			anim.add_cull(h, Rect2(pos - Vector2(42, 42), Vector2(84, 84)))
			continue
		var p := PointLight2D.new()
		p.color = Tex.color8(l["color"])
		p.position = pos
		p.height = l["z"]
		p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		p.energy = l["energy"] * k
		var r := float(l["radius"])
		if l["kind"] == "moon_pool":
			p.texture = tex.img("dapple.png")
			p.texture_scale = r * 2.0 / 256.0
			p.energy = l["energy"] * k * 0.6
			anim.add_flicker(p, p.energy, 0.06, 0.0, "energy")
		else:
			p.texture = tex.radial(int(r))
			if l.has("flicker"):
				anim.add_flicker(p, p.energy, float(l["flicker"]), pos.x * 0.37, "energy")
		lights.add_child(p)
		var reach := Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0)
		if l["kind"] == "point" and r >= 100.0:
			var h := halo(glow, pos, Tex.color8(l["color"]), r * 0.4, 0.16, tex)
			anim.add_flicker(h, 0.16, float(l.get("flicker", 0.1)), pos.x * 0.37, "alpha")
			anim.add_cull(h, reach)
		anim.add_cull(p, reach)


## Additive glow sprite in the glow layer; culled by its own radius.
static func halo(glow: CanvasLayer, pos: Vector2, col: Color, radius: float, alpha: float, tex) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex.radial(64, 2.2)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.position = pos
	s.scale = Vector2.ONE * radius / 64.0
	s.modulate = Color(col.r, col.g, col.b, alpha)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	glow.add_child(s)
	return s
