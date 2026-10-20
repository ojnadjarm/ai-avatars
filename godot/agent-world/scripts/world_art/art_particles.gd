extends RefCounted
## GPU particle emitters (fire, motes, mist, leaves, petals, halos, moon dust), tiled per screen cell and culled.

const Tex := preload("res://scripts/world_art/art_textures.gd")
const Lights := preload("res://scripts/world_art/art_lights.gd")
const CELL := Vector2(640, 360)


static func build(art: Node2D, glow: CanvasLayer, sc: Dictionary, tex, anim) -> int:
	var size := Vector2(sc["size"][0], sc["size"][1])
	var day: bool = sc.get("day", false)
	var n := 0
	var fc: Array = sc["falling"]
	var fall := Color(fc[0], fc[1], fc[2])
	for cy in ceili(size.y / CELL.y):
		for cx in ceili(size.x / CELL.x):
			var o := Vector2(cx, cy) * CELL
			if sc["motes"]:
				_motes(glow, o, tex, anim)
				n += 2
			_emit(art, anim, o + CELL * 0.5, 7, 9.0, Vector2(CELL.x * 0.47, CELL.y * 0.5), Vector2(3, 10), Vector2(0, 3),
				Tex.grad([[0.0, Color(fall, 0)], [0.1, fall], [0.9, fall * 0.7], [1.0, Color(fall * 0.7, 0)]]),
				tex.leaf, tex, 1.0, false, 1.0, 30.0)
			n += 1
	if sc["moon_gap"] != null and not day:
		_emit(glow, anim, Vector2(sc["moon_gap"][0] + 24, sc["moon_gap"][1] + 100), 40, 8.0, Vector2(40, 70), Vector2(2, 3),
			Vector2.ZERO, Tex.grad([[0.0, Color(0.7, 0.8, 1.0, 0)], [0.5, Color(0.7, 0.8, 1.0, 0.55)], [1.0, Color(0.7, 0.8, 1.0, 0)]]),
			tex.px, tex, 0.11, true, 0.3, 180.0)
		n += 1
	for e in sc["emit"]:
		n += _entry(e, art, glow, tex, anim)
	return n


static func _motes(glow: CanvasLayer, o: Vector2, tex, anim) -> void:
	var gold := Color(1.0, 0.86, 0.45)
	var mint := Color(0.5, 1.0, 0.8)
	var cx := CELL.x * 0.5
	var cy := CELL.y * 0.58
	_emit(glow, anim, o + Vector2(cx, cy), 46, 7.0, Vector2(cx - 20, cy * 0.67), Vector2(4, -3), Vector2.ZERO,
		Tex.grad([[0.0, Color(gold, 0)], [0.2, gold], [0.35, Color(gold, 0.2)], [0.5, gold], [0.8, Color(gold, 0.6)], [1.0, Color(gold, 0)]]),
		tex.dot, tex, 0.33, true, 0.6, 180.0)
	_emit(glow, anim, o + Vector2(cx - 20, cy - 10), 18, 6.0, Vector2(cx - 60, cy * 0.57), Vector2(3, -2), Vector2.ZERO,
		Tex.grad([[0.0, Color(mint, 0)], [0.3, mint], [0.6, Color(mint, 0.3)], [1.0, Color(mint, 0)]]),
		tex.dot, tex, 0.28, true, 0.6, 180.0)


static func _entry(e: Dictionary, art: Node2D, glow: CanvasLayer, tex, anim) -> int:
	var pos := Vector2(e["x"], e["y"])
	match e["kind"]:
		"fire":
			_emit(glow, anim, pos, 110, 0.9, Vector2(4, 1.5), Vector2(0, -20), Vector2(0, -26),
				Tex.grad([[0.0, Color(1, 0.97, 0.7)], [0.25, Color(1, 0.78, 0.3)], [0.55, Color(1, 0.45, 0.12)], [0.8, Color(0.75, 0.15, 0.08, 0.7)], [1.0, Color(0.5, 0.1, 0.1, 0)]]),
				tex.px, tex, 0.34, true, 0.4, 14.0)
			_emit(glow, anim, pos, 10, 2.2, Vector2(3, 1), Vector2(0, -30), Vector2(0, -6),
				Tex.grad([[0.0, Color(1, 0.9, 0.5)], [0.7, Color(1, 0.5, 0.15, 0.8)], [1.0, Color(1, 0.3, 0.1, 0)]]),
				tex.px, tex, 0.34, true, 1.2, 25.0)
			_emit(art, anim, pos + Vector2(0, -8), 16, 3.5, Vector2(2, 1), Vector2(2, -12), Vector2(3, -4),
				Tex.grad([[0.0, Color(0.6, 0.62, 0.75, 0)], [0.3, Color(0.6, 0.62, 0.75, 0.35)], [1.0, Color(0.6, 0.62, 0.75, 0)]]),
				tex.dot, tex, 0.5, false, 0.5, 12.0)
			_halo(glow, pos + Vector2(0, -6), Color(1, 0.55, 0.2), 60.0, 0.32, tex, anim, false)
			return 4
		"motes":
			var a := Color(1, 0.6, 0.95)
			var b := Color(0.6, 0.4, 1, 0)
			if e.has("color"):
				a = Tex.color8(e["color"])
				b = Color(a.r, a.g * 0.7, a.b * 0.5, 0)
			_emit(glow, anim, pos, 28, 3.0, Vector2(e["w"], e["h"]), Vector2(0, -12), Vector2(0, -3),
				Tex.grad([[0.0, Color(a, 0)], [0.3, a], [1.0, b]]), tex.px, tex, 0.34, true, 0.6, 20.0)
		"mist":
			_emit(glow, anim, pos, 34, 2.4, Vector2(e["w"] * 0.5, 2), Vector2(0, 8), Vector2(0, -3),
				Tex.grad([[0.0, Color(0.8, 0.88, 1, 0)], [0.25, Color(0.8, 0.88, 1, 0.22)], [1.0, Color(0.8, 0.88, 1, 0)]]),
				tex.dot, tex, 1.2, false, 0.8, 70.0)
		"leaves", "petals":
			var leaves: bool = e["kind"] == "leaves"
			var lc := Color(0.45, 0.75, 0.6) if leaves else Color(1.0, 0.55, 0.85)
			if e.has("color"):
				lc = Tex.color8(e["color"])
			_emit(art if leaves else glow, anim, pos, 4 if leaves else 3, 6.0, Vector2(e["w"], e["h"]), Vector2(3, 7), Vector2(0, 2),
				Tex.grad([[0.0, Color(lc, 0)], [0.15, lc], [0.8, Color(lc, 0.8)], [1.0, Color(lc, 0)]]),
				tex.leaf, tex, 1.0, not leaves, 1.2, 40.0)
		"halo":
			_halo(glow, pos, Tex.color8(e["color"]), float(e["size"]), 0.35, tex, anim, true)
	return 1


static func _halo(glow: CanvasLayer, pos: Vector2, col: Color, radius: float, alpha: float, tex, anim, flicker: bool) -> void:
	var h := Lights.halo(glow, pos, col, radius, alpha, tex)
	if flicker:
		anim.add_flicker(h, alpha, 0.15, pos.x * 0.37, "alpha")
	anim.add_cull(h, Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0))


## One emitter with a visibility rect covering its whole travel, registered for culling.
static func _emit(parent: Node, anim, pos: Vector2, amount: int, life: float, box: Vector2, vel: Vector2, grav: Vector2,
		ramp: Gradient, texture: Texture2D, tex, scale: float, add: bool, turb: float, spread: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.texture = texture
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if texture == tex.dot else CanvasItem.TEXTURE_FILTER_NEAREST
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(box.x, box.y, 0)
	m.direction = Vector3(vel.normalized().x, vel.normalized().y, 0) if vel.length() > 0.0 else Vector3(0, -1, 0)
	m.spread = spread
	m.initial_velocity_min = vel.length() * 0.5
	m.initial_velocity_max = vel.length()
	m.gravity = Vector3(grav.x, grav.y, 0)
	m.scale_min = scale
	m.scale_max = scale * 1.4
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	m.color_ramp = gt
	if turb > 0.0:
		m.turbulence_enabled = true
		m.turbulence_noise_strength = turb
		m.turbulence_noise_scale = 3.0
		m.turbulence_influence_min = 0.05
		m.turbulence_influence_max = 0.15
	p.process_material = m
	if add:
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = cm
	var travel := vel.length() * life + 0.5 * grav.length() * life * life + 16.0
	var reach := box + Vector2(travel, travel)
	p.visibility_rect = Rect2(-reach, reach * 2.0)
	parent.add_child(p)
	anim.add_cull(p, Rect2(pos - reach, reach * 2.0))
	return p
