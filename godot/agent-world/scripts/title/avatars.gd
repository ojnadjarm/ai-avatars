extends Node2D
## Campfire avatars: idle frames of the player and NPC sheets at half scale, lit by the fire through their normal maps.

const DIR := "res://assets/characters/"
const PAD := 24.0
const HALF := 2
const FPS_CYCLES := 12
## [sheet, anim, feet position in title px]: bedroll left of the fire, seat log right of it.
const SPOTS := [
	["luna", "idle_right", Vector2(524, 296)],
	["grok", "idle_right", Vector2(540, 290)],
	["player_default", "idle_left", Vector2(584, 293)],
	["darksaddler", "idle_left", Vector2(601, 295)],
]

var dark := Vector3(0.5, 0.5, 0.6)
var figures: Array = []   # [Sprite2D, frames: Array[CanvasTexture]]

func _ready() -> void:
	var layout: Dictionary = {}
	if FileAccess.file_exists(DIR + "layout.json"):
		layout = JSON.parse_string(FileAccess.get_file_as_string(DIR + "layout.json"))
	var shader := load("res://shaders/title/lit.gdshader")
	for spot in SPOTS:
		var name: String = spot[0]
		if not layout.has(name) or not FileAccess.file_exists(DIR + name + ".png"):
			continue
		var frames := _frames(name, layout[name], spot[1])
		if frames.is_empty():
			continue
		var s := Sprite2D.new()
		s.centered = false
		s.texture = frames[0]
		var pivot: Array = layout[name].get("pivot", [48, 88])
		s.position = spot[2] + Vector2(PAD, 0) - Vector2(pivot[0], pivot[1]) / HALF
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("dark", dark)
		s.material = m
		s.light_mask = 2
		add_child(s)
		figures.append([s, frames])

## Returns one CanvasTexture per frame of `anim`, halved with a coverage-aware box filter.
func _frames(name: String, entry: Dictionary, anim: String) -> Array:
	var info: Dictionary = entry.get("anims", {}).get(anim, {})
	if info.is_empty():
		return []
	var cell := int(entry.get("cell", 96))
	var albedo := Image.load_from_file(ProjectSettings.globalize_path(DIR + name + ".png"))
	var normal: Image = null
	if FileAccess.file_exists(DIR + name + "_n.png"):
		normal = Image.load_from_file(ProjectSettings.globalize_path(DIR + name + "_n.png"))
	var out: Array = []
	for f in int(info["frames"]):
		var r := Rect2i(f * cell, int(info["row"]) * cell, cell, cell)
		var ct := CanvasTexture.new()
		ct.diffuse_texture = ImageTexture.create_from_image(_halve(albedo.get_region(r)))
		if normal != null:
			ct.normal_texture = ImageTexture.create_from_image(_halve(normal.get_region(r)))
		out.append(ct)
	return out

## Halves an image: each 2x2 block takes its most opaque, darkest-outline-preserving pixel.
func _halve(src: Image) -> Image:
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width() / HALF
	var h := src.get_height() / HALF
	var dst := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var best := Color(0, 0, 0, 0)
			var n := 0
			for dy in HALF:
				for dx in HALF:
					var c := src.get_pixel(x * HALF + dx, y * HALF + dy)
					if c.a > 0.5:
						n += 1
						if best.a <= 0.5 or c.get_luminance() < best.get_luminance():
							best = c
			dst.set_pixel(x, y, best if n >= 2 else Color(0, 0, 0, 0))
	return dst

func _process(_d: float) -> void:
	var p: float = get_parent().cur_phase
	for fg in figures:
		var frames: Array = fg[1]
		(fg[0] as Sprite2D).texture = frames[int(p * FPS_CYCLES * frames.size()) % frames.size()]
