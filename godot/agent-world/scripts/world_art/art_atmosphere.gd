extends RefCounted
## World-space fog, haze and moon rays in the glow layer; screen-space post grade; 2D glow environment unless built.json glow is false.

const FOG := preload("res://shaders/world/fog.gdshader")
const RAYS := preload("res://shaders/world/rays.gdshader")
const POST := preload("res://shaders/world/post.gdshader")
const SCREEN_H := 360.0
const POST_LAYER := 4
## Rays rect around the beam (origin - pad, box size) for rays.gdshader's default dir (0.5, 1) and reach 250; nothing is drawn outside it.
const RAYS_PAD := Vector2(100, 60)
const RAYS_BOX := Vector2(300, 360)


static func build(world: Node2D, glow: CanvasLayer, sc: Dictionary, tex) -> void:
	var size := Vector2(sc["size"][0], sc["size"][1])
	var period := float(sc["period"])
	var fog := _rect(size)
	var fm := ShaderMaterial.new()
	fm.shader = FOG
	fm.set_shader_parameter("mask", tex.img("fog.png"))
	fm.set_shader_parameter("noise", _fog_noise())
	fm.set_shader_parameter("period", period)
	fm.set_shader_parameter("art", size)
	fog.material = fm
	glow.add_child(fog)
	glow.add_child(_haze(sc["haze"], size))
	if sc["moon_gap"] != null:
		var origin := Vector2(sc["moon_gap"][0], sc["moon_gap"][1] - 30)
		var beam := Rect2(origin - Vector2(RAYS_PAD.x, RAYS_PAD.y), RAYS_BOX).intersection(Rect2(Vector2.ZERO, size))
		var rays := _rect(beam.size)
		rays.position = beam.position
		var rm := ShaderMaterial.new()
		rm.shader = RAYS
		rm.set_shader_parameter("origin", origin)
		rm.set_shader_parameter("period", period)
		rm.set_shader_parameter("art", beam.size)
		rm.set_shader_parameter("offset", beam.position)
		rm.set_shader_parameter("strength", float(sc["rays"]))
		rays.material = rm
		glow.add_child(rays)
	_post(world)
	if sc.get("glow", true):
		_environment(world)


## Seamless soft noise for the fog banks (sampled twice per pixel instead of an 8-octave procedural fbm).
static func _fog_noise() -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.seed = 714
	fn.frequency = 0.012
	fn.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.noise = fn
	return nt


static func _rect(size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Additive haze band at the top of the map: fades to black 0.4 screen down, so the rect stops there.
static func _haze(hz: Array, size: Vector2) -> TextureRect:
	var top := Color(hz[0], hz[1], hz[2], 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = preload("res://scripts/world_art/art_textures.gd").grad([[0.0, top], [0.5, Color(top.r * 0.4, top.g * 0.4, top.b * 0.4, 1.0)],
		[1.0, Color.BLACK]])
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	var haze := TextureRect.new()
	haze.texture = gt
	haze.size = Vector2(size.x, minf(SCREEN_H * 0.4, size.y))
	haze.stretch_mode = TextureRect.STRETCH_SCALE
	haze.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hm := CanvasItemMaterial.new()
	hm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	haze.material = hm
	return haze


static func _post(world: Node2D) -> void:
	var post := CanvasLayer.new()
	post.name = "PostGrade"
	post.layer = POST_LAYER
	world.add_child(post)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = POST
	r.material = m
	post.add_child(r)


static func _environment(world: Node2D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.75
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(4, 0.3)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
