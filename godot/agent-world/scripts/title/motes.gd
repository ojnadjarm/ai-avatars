extends Node2D
## Periodic particles (fireflies, embers, spores, moon dust, petals): every path is a function of the loop phase, so the loop is seamless.

const PAD := 24.0
const FIRE := Vector2(560.0, 284.0)

var front := false
var parts: Array = []

func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m
	var r := RandomNumberGenerator.new()
	r.seed = 704 if not front else 1704
	if front:
		for i in 7:
			parts.append({"k": "bokeh", "x": r.randf_range(20, 640), "y": r.randf_range(250, 350), "f": r.randi_range(1, 2), "o": r.randf(), "c": [Color(1.6, 1.3, 0.5), Color(0.6, 1.6, 1.1)][i % 2]})
		for i in 9:
			parts.append({"k": "petal", "x": r.randf_range(-10, 260), "y": r.randf_range(-10, 40), "f": r.randi_range(1, 2), "o": r.randf(), "c": [Color(1.4, 0.5, 0.95), Color(0.9, 0.55, 1.3)][i % 2]})
		return
	for i in 46:
		var shore := i < 14
		parts.append({"k": "fly", "x": r.randf_range(10, 250) if shore else r.randf_range(0, 640), "y": r.randf_range(236, 290) if shore else r.randf_range(292, 350),
			"f": r.randi_range(1, 3), "o": r.randf(), "c": [Color(2.4, 1.9, 0.7), Color(0.9, 2.3, 1.5), Color(2.2, 2.0, 1.0)][i % 3]})
	for i in 22:
		parts.append({"k": "ember", "f": r.randi_range(3, 6), "o": r.randf(), "s": r.randf_range(-1, 1)})
	for i in 14:
		parts.append({"k": "spore", "x": r.randf_range(495, 548), "y": r.randf_range(240, 282), "f": r.randi_range(1, 3), "o": r.randf()})
	for i in 40:
		parts.append({"k": "dust", "x": r.randf_range(200, 560), "y": r.randf_range(70, 300), "f": 1, "o": r.randf()})

func _process(_d: float) -> void:
	queue_redraw()

func _px(v: Vector2, c: Color, s := 1.0) -> void:
	draw_rect(Rect2((v + Vector2(PAD, 0)).floor(), Vector2(s, s)), c)

func _draw() -> void:
	var p: float = get_parent().cur_phase
	for q in parts:
		var a: float = TAU * (p * q["f"] + q["o"])
		match q["k"]:
			"fly":
				var pos := Vector2(q["x"] + 9.0 * sin(a) + 4.0 * sin(2.0 * a + 1.0), q["y"] + 5.0 * sin(a * 2.0 + 0.5) + 3.0 * cos(a))
				var blink := pow(maxf(0.0, sin(a * 2.0 + q["o"] * 9.0)), 3.0)
				var c: Color = q["c"]
				_px(pos, Color(c.r, c.g, c.b, 0.25 + 0.75 * blink))
				if blink > 0.4:
					for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
						_px(pos + o, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, blink * 0.5))
			"ember":
				var life := fmod(p * q["f"] + q["o"], 1.0)
				var pos := FIRE + Vector2(q["s"] * 4.0 + sin(life * 7.0 + q["o"] * 6.0) * 4.0 * life + life * 14.0, -life * 74.0)
				var c := Color(3.0, 2.2, 0.8).lerp(Color(2.2, 0.6, 0.2), life)
				c.a = (1.0 - life) * minf(1.0, life * 8.0)
				_px(pos, c)
			"spore":
				var life := fmod(p * q["f"] + q["o"], 1.0)
				var pos := Vector2(q["x"] + sin(life * 6.0) * 2.0, q["y"] - life * 22.0)
				_px(pos, Color(2.2, 0.7, 1.6, sin(life * PI) * 0.9))
			"dust":
				var life := fmod(p + q["o"], 1.0)
				var pos := Vector2(q["x"] - life * 30.0, q["y"] + life * 18.0 + sin(a * 3.0) * 2.0)
				_px(pos, Color(0.7, 0.8, 1.3, sin(life * PI) * 0.45))
			"bokeh":
				var pos := Vector2(q["x"] + 14.0 * sin(a), q["y"] + 8.0 * sin(2.0 * a + 1.0))
				var blink := pow(maxf(0.0, sin(a * 2.0 + q["o"] * 5.0)), 2.0)
				var c: Color = q["c"]
				draw_circle(pos + Vector2(PAD, 0), 2.5, Color(c.r, c.g, c.b, 0.22 * blink))
				draw_circle(pos + Vector2(PAD, 0), 1.2, Color(c.r, c.g, c.b, 0.5 * blink))
			"petal":
				var life := fmod(p * q["f"] + q["o"], 1.0)
				var pos := Vector2(q["x"] + life * 170.0 + sin(life * 11.0 + q["o"] * 4.0) * 10.0, q["y"] + life * 380.0)
				var c: Color = q["c"]
				c.a = minf(1.0, (1.0 - life) * 4.0) * 0.8
				var flip := int(life * 24.0) % 3
				_px(pos, c)
				_px(pos + ([Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)][flip]), Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, c.a))
