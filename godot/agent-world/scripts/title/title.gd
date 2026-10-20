extends Node2D
## Title key art: parallax night planes, shader sky/water/mist/rays, lit foreground, periodic motes and the menu.

const PAD := 24.0
const LOOP := 12.0
const HY := 214.0
const ART := "res://assets/menu/"
const LIFT := 1.7
const DARK := Color(0.95 / LIFT, 0.95 / LIFT, 1.12 / LIFT)

var t := 0.0
var cur_phase := 0.0
var demo := false
var still_path := ""
var still_frame := 0
var planes: Array = []   # [node, depth, base position]
var lights: Array = []   # [PointLight2D, base_energy, seed]
var menu: Node
var pools: Array = []
var boat: Sprite2D
var boat_pool: Sprite2D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	demo = "--demo" in args
	if "--still" in args:
		still_path = args[args.find("--still") + 1]
		still_frame = int(args[args.find("--at") + 1]) if "--at" in args else 60
	_build_world()
	menu = preload("res://scripts/title/menu.gd").new()
	menu.demo = demo or still_path != ""
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	ui.add_child(menu)
	_env()

func _tex(name: String) -> Texture2D:
	var p := ART + name + ".png"
	if not FileAccess.file_exists(p):
		return null
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(p)))

func _sprite(name: String, depth: float, mat: Material = null, normal := false, at := Vector2.ZERO) -> Sprite2D:
	var tx := _tex(name)
	if tx == null:
		return null
	var s := Sprite2D.new()
	s.centered = false
	if normal and _tex(name + "_n") != null:
		var ct := CanvasTexture.new()
		ct.diffuse_texture = tx
		ct.normal_texture = _tex(name + "_n")
		s.texture = ct
	else:
		s.texture = tx
	s.material = mat
	s.position = at
	if normal:
		if mat == null:
			var lm := ShaderMaterial.new()
			lm.shader = load("res://shaders/title/lit.gdshader")
			s.material = lm
		var k := 0.7 if name.begins_with("fg") else 1.0
		(s.material as ShaderMaterial).set_shader_parameter("dark", Vector3(DARK.r, DARK.g, DARK.b) * k)
		s.light_mask = 2
	add_child(s)
	_reg(s, depth)
	var e := _tex(name + "_e")
	if e != null:
		var g := Sprite2D.new()
		g.centered = false
		g.texture = e
		g.modulate = Color(2.2, 2.2, 2.2)
		g.material = _add_mat()
		g.position = at
		add_child(g)
		_reg(g, depth)
	return s

func _reg(n: CanvasItem, depth: float) -> void:
	var p: Vector2 = n.position if n is Node2D else (n as Control).position
	planes.append([n, depth, p - Vector2(PAD, 0)])

func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

func _shader_rect(path: String, rect: Rect2, depth: float, params := {}) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	r.material = m
	add_child(r)
	if depth >= 0.0:
		_reg(r, depth)
	return r

func _build_world() -> void:
	_shader_rect("res://shaders/title/sky.gdshader", Rect2(0, 0, 640 + 2 * PAD, 360), 0.01)
	_sprite("moon_halo", 0.02, _add_mat(), false, Vector2(476 - 110, 86 - 110))
	var mo := _sprite("moon", 0.02, null, false, Vector2(476 - 24, 86 - 24))
	mo.modulate = Color(1.35, 1.35, 1.45)
	var fire := _shader_rect("res://shaders/title/fire.gdshader", Rect2(560 + PAD - 8, 284 - 24, 16, 26), -1.0)
	_sprite("mtn_far", 0.05)
	_shader_rect("res://shaders/title/mist.gdshader", Rect2(0, 150, 640 + 2 * PAD, 70), 0.07,
		{"size": Vector2(688, 70), "tint": Color(0.62, 0.42, 0.78), "strength": 0.55, "scale": Vector2(0.02, 0.1), "drift": Vector2(1.0, 0.0), "seed": 1.0})
	_sprite("mtn_near", 0.09)
	_sprite("castle", 0.12)
	_sprite("pines_far", 0.14)
	_shader_rect("res://shaders/title/mist.gdshader", Rect2(0, 192, 640 + 2 * PAD, 30), 0.15,
		{"size": Vector2(688, 30), "tint": Color(0.7, 0.62, 0.95), "strength": 0.75, "scale": Vector2(0.025, 0.2), "drift": Vector2(1.6, 0.0), "seed": 4.0})
	var water := _shader_rect("res://shaders/title/water.gdshader", Rect2(-40, HY, 720, 146), -1.0)
	water.z_index = 0
	boat_pool = _sprite("pool_boat", 0.25, _add_mat(), false, Vector2(PAD + 352 - 6, 252))
	boat = _sprite("boat", 0.25, null, false, Vector2(PAD + 332, 236))
	_sprite("pines_right", 0.3)
	_sprite("pines_left", 0.3)
	_sprite("shore", 0.4, null, true)
	_shader_rect("res://shaders/title/mist.gdshader", Rect2(0, 236, 640 + 2 * PAD, 50), 0.45,
		{"size": Vector2(688, 50), "tint": Color(0.55, 0.55, 0.9), "strength": 0.45, "scale": Vector2(0.03, 0.15), "drift": Vector2(2.0, 0.0), "seed": 9.0})
	_sprite("mid", 0.55, null, true)
	var avatars := preload("res://scripts/title/avatars.gd").new()
	avatars.dark = Vector3(DARK.r, DARK.g, DARK.b)
	add_child(avatars)
	_reg(avatars, 0.55)
	move_child(fire, -1)
	_reg(fire, 0.55)
	for pl in [["pool_fire", Vector2(560, 290), 70, 26, 0.55], ["pool_stone", Vector2(522, 238), 30, 30, 0.55], ["pool_lantern", Vector2(598, 178), 46, 46, 1.0]]:
		var ps := _sprite(pl[0], pl[4], _add_mat(), false, pl[1] + Vector2(PAD - pl[2], -pl[3]))
		pools.append(ps)
	_shader_rect("res://shaders/title/rays.gdshader", Rect2(0, 0, 640 + 2 * PAD, 360), 0.02)
	var motes := preload("res://scripts/title/motes.gd").new()
	add_child(motes)
	_reg(motes, 0.7)
	_sprite("fg", 1.0, null, true)
	var sw := ShaderMaterial.new()
	sw.shader = load("res://shaders/title/sway.gdshader")
	sw.set_shader_parameter("wmap", _tex("fg_leaves_w"))
	sw.set_shader_parameter("amp", 1.6)
	_sprite("fg_leaves", 1.1, sw, true)
	var sg := ShaderMaterial.new()
	sg.shader = load("res://shaders/title/sway.gdshader")
	sg.set_shader_parameter("wmap", _tex("fg_grass_w"))
	sg.set_shader_parameter("amp", 1.2)
	sg.set_shader_parameter("freq", 3.0)
	_sprite("fg_grass", 1.15, sg, true)
	var front := preload("res://scripts/title/motes.gd").new()
	front.front = true
	add_child(front)
	_reg(front, 1.2)
	_lights()
	var grade := ColorRect.new()
	grade.size = Vector2(640, 360)
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/title/grade.gdshader")
	grade.material = gm
	var gl := CanvasLayer.new()
	gl.layer = 4
	gl.add_child(grade)
	add_child(gl)

func _lights() -> void:
	var meta_p := ART + "lights.json"
	if not FileAccess.file_exists(meta_p):
		return
	var meta: Array = JSON.parse_string(FileAccess.get_file_as_string(meta_p))
	for l in meta:
		var p := PointLight2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = int(l["radius"]) * 2
		gt.height = int(l["radius"]) * 2
		p.texture = gt
		p.position = Vector2(l["x"] + PAD, l["y"])
		p.color = Color8(l["color"][0], l["color"][1], l["color"][2])
		p.energy = l["energy"]
		p.height = l["z"]
		p.blend_mode = Light2D.BLEND_MODE_ADD
		p.range_item_cull_mask = 2
		add_child(p)
		_reg(p, float(l["depth"]))
		lights.append([p, float(l["energy"]), float(l["seed"])])

func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _process(delta: float) -> void:
	t += delta
	var p := fmod(t / LOOP, 1.0)
	cur_phase = p
	RenderingServer.global_shader_parameter_set("loop_phase", p)
	var a := TAU * p
	var sx := 7.0 * sin(a)
	var sy := 1.2 * sin(2.0 * a)
	for pl in planes:
		var d: float = pl[1]
		var pos: Vector2 = pl[2] + Vector2(sx * d, sy * maxf(0.0, d - 0.5))
		if pl[0] is Control:
			(pl[0] as Control).position = pos
		else:
			(pl[0] as Node2D).position = pos
	for l in lights:
		var s: float = l[2]
		var f := 0.82 + 0.1 * sin(a * 7.0 + s) + 0.06 * sin(a * 13.0 + s * 2.0) + 0.05 * sin(a * 29.0 + s * 3.0)
		(l[0] as PointLight2D).energy = l[1] * f
	boat.position.y = 236.0 + roundf(sin(a * 3.0))
	boat.rotation = 0.03 * sin(a * 3.0 + 0.8)
	for i in pools.size():
		(pools[i] as Sprite2D).modulate.a = 0.85 + 0.15 * sin(a * (7.0 + i * 4.0) + i)
	menu.phase = p
	menu.t = t
	if still_path != "" and Engine.get_process_frames() == still_frame:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
			img.linear_to_srgb()
		img.save_png(still_path)
		print("STILL ", still_path)
		get_tree().quit()
