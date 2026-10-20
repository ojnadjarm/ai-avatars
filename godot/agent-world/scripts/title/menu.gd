extends Control
## Title menu: shimmering logo, 9-slice panel, animated selection (bar wipe, slide, gem cursor), intro and confirm transitions.

const ART := "res://assets/menu/"
const FONTS := "res://assets/fonts/"
const PANEL := Rect2(82, 190, 176, 118)
const PANEL_BOTTOM := 308.0
const ROW := 19.0
const GOLD := Color8(242, 196, 90)
const PALE := Color8(200, 219, 240)
const DIM := Color8(120, 148, 196)
const HINT := Color8(160, 184, 226)

signal confirmed(index: int)

var demo := false
var items: Array = ["Worlds", "Settings", "Quit"]
var online_text := ""
var origin := PANEL.position
var done := false
var phase := 0.0
var t := 0.0
var sel := 0
var prev := -1
var sel_t := 9.0
var confirm_t := -1.0
var labels: Array[Label] = []
var logo: TextureRect
var logo_glow: TextureRect
var subtitle: TextureRect
var panel: NinePatchRect
var bar: NinePatchRect
var gem: TextureRect
var spark: Control
var fade: ColorRect
var footer: Control
var font: FontFile
var font_small: FontFile

func _tex(n: String) -> Texture2D:
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(ART + n + ".png")))

func _font(n: String) -> FontFile:
	var f := FontFile.new()
	f.load_dynamic_font(FONTS + n)
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f

func _ready() -> void:
	size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = _font("PixelifySans.ttf")
	font_small = _font("Silkscreen-Regular.ttf")
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	logo_glow = TextureRect.new()
	logo_glow.texture = _tex("logo_glow")
	logo_glow.material = add
	add_child(logo_glow)
	logo = TextureRect.new()
	logo.texture = _tex("logo")
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/title/shimmer.gdshader")
	sm.set_shader_parameter("mask", _tex("logo_mask"))
	logo.material = sm
	add_child(logo)
	subtitle = TextureRect.new()
	subtitle.texture = _tex("subtitle")
	add_child(subtitle)
	panel = _nine("panel9", 8)
	panel.position = PANEL.position
	panel.size = PANEL.size
	add_child(panel)
	bar = _nine("select9", 3)
	bar.patch_margin_left = 2
	bar.patch_margin_right = 2
	bar.material = add
	add_child(bar)
	set_items(items)
	gem = TextureRect.new()
	gem.texture = _tex("gem")
	add_child(gem)
	spark = Control.new()
	spark.draw.connect(_draw_spark)
	spark.material = add
	add_child(spark)
	_footer()
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.size = Vector2(640, 360)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

## Rebuilds the menu rows and fits the panel to them, bottom-aligned above the footer.
func set_items(names: Array) -> void:
	items = names
	for l in labels:
		l.queue_free()
	labels.clear()
	if panel == null:
		return
	var h := 23.0 + items.size() * ROW
	origin = Vector2(PANEL.position.x, minf(PANEL.position.y, PANEL_BOTTOM - h))
	panel.size = Vector2(PANEL.size.x, h)
	for i in items.size():
		var l := Label.new()
		l.text = items[i]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_shadow_color", Color8(6, 7, 26, 220))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 1)
		var lm := ShaderMaterial.new()
		lm.shader = load("res://shaders/title/textshine.gdshader")
		l.material = lm
		add_child(l)
		move_child(l, bar.get_index() + 1)
		labels.append(l)
	sel = clampi(sel, 0, maxi(0, items.size() - 1))

func _nine(n: String, m: int) -> NinePatchRect:
	var r := NinePatchRect.new()
	r.texture = _tex(n)
	r.patch_margin_left = m
	r.patch_margin_right = m
	r.patch_margin_top = m
	r.patch_margin_bottom = m
	return r

func _footer() -> void:
	footer = Control.new()
	add_child(footer)
	var x := 92.0
	for pair in [["ENTER", "Select"], ["W/S", "Move"]]:
		var k := _nine("key9", 4)
		var kl := Label.new()
		kl.text = pair[0]
		kl.add_theme_font_override("font", font_small)
		kl.add_theme_font_size_override("font_size", 8)
		kl.add_theme_color_override("font_color", PALE)
		var w := font_small.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		k.position = Vector2(x, 318)
		k.size = Vector2(w + 8, 12)
		kl.position = Vector2(x + 4, 318)
		footer.add_child(k)
		footer.add_child(kl)
		footer.add_child(_plate("hint_bg_%s" % pair[1], Vector2(x + w + 8, 319), pair[1]))
		var dl := Label.new()
		dl.text = pair[1]
		dl.add_theme_font_override("font", font_small)
		dl.add_theme_font_size_override("font_size", 8)
		dl.add_theme_color_override("font_color", HINT)
		_outline(dl)
		dl.position = Vector2(x + w + 12, 318)
		footer.add_child(dl)
		x += w + 12 + font_small.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 14
	footer.add_child(_plate("online_bg", Vector2(16, 345), online_text))
	var on := Label.new()
	on.text = online_text
	on.name = "online"
	on.add_theme_font_override("font", font_small)
	on.add_theme_font_size_override("font_size", 8)
	on.add_theme_color_override("font_color", Color8(164, 240, 204))
	_outline(on)
	on.position = Vector2(20, 344)
	footer.add_child(on)
	footer.add_child(_plate("version_bg", Vector2(594, 345), "V0.9"))
	var v := Label.new()
	v.text = "V0.9"
	v.add_theme_font_override("font", font_small)
	v.add_theme_font_size_override("font_size", 8)
	v.add_theme_color_override("font_color", PALE)
	_outline(v)
	v.position = Vector2(598, 344)
	footer.add_child(v)

## Gives a footer label a 1 px night outline so it reads over the lit grass.
func _outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color8(6, 7, 26))
	l.add_theme_constant_override("outline_size", 2)

## Night-glass backing plate sized to `text`, so the footer line reads over the lit foreground.
func _plate(n: String, at: Vector2, text: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = n
	r.color = Color8(6, 7, 26, 200)
	r.position = at
	_fit_plate(r, text)
	return r

func _fit_plate(r: ColorRect, text: String) -> void:
	r.visible = text != ""
	r.size = Vector2(font_small.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 8, 11)

## Sets the footer status line (e.g. the configured agent count).
func set_online_text(s: String) -> void:
	online_text = s
	if footer != null:
		(footer.get_node("online") as Label).text = s
		_fit_plate(footer.get_node("online_bg") as ColorRect, s)

func _input(e: InputEvent) -> void:
	if demo or confirm_t >= 0.0 or items.is_empty():
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode in [KEY_DOWN, KEY_S]:
			_select((sel + 1) % items.size())
		elif e.keycode in [KEY_UP, KEY_W]:
			_select((sel - 1 + items.size()) % items.size())
		elif e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			confirm_t = 0.0
	elif e is InputEventMouseMotion:
		var r := _row_at(e.position)
		if r >= 0:
			_select(r)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var r := _row_at(e.position)
		if r >= 0:
			_select(r)
			confirm_t = 0.0

func _row_at(p: Vector2) -> int:
	var y := p.y - (origin.y + 10.0)
	if p.x < origin.x or p.x > origin.x + PANEL.size.x or y < 0.0:
		return -1
	var r := int(y / ROW)
	return r if r < items.size() else -1

func _select(i: int) -> void:
	if i == sel:
		return
	prev = sel
	sel = i
	sel_t = 0.0

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _process(delta: float) -> void:
	var intro := 99.0 if demo else t
	if demo:
		var n := maxi(1, items.size() - 1)
		var k := phase * 4.0
		var i := int(k) % n
		sel = i
		prev = (i + n - 1) % n
		sel_t = (k - floorf(k)) * 3.0
	else:
		sel_t += delta
	var a := TAU * phase
	# logo
	var lw := logo.texture.get_width()
	var lt := _ease((intro - 0.5) / 1.2)
	var lx := 170.0 - lw / 2.0
	var ly := 36.0 + roundf(1.4 * sin(a)) - (1.0 - lt) * 16.0
	logo.position = Vector2(lx, ly)
	logo.modulate.a = lt
	logo_glow.position = Vector2(lx - 18, ly - 18)
	logo_glow.modulate = Color(1, 1, 1, lt * (0.55 + 0.25 * sin(a * 2.0)))
	(logo.material as ShaderMaterial).set_shader_parameter("sweep", fmod(phase * 2.0, 1.0) if demo else fmod(maxf(0.0, intro - 1.2) / 6.0, 1.0))
	var st := _ease((intro - 1.1) / 0.8)
	subtitle.position = Vector2(170.0 - subtitle.texture.get_width() / 2.0, ly + logo.texture.get_height() + 4)
	subtitle.modulate.a = st
	# panel and items
	var pt := _ease((intro - 1.3) / 0.6)
	panel.modulate.a = pt * 0.95
	panel.position = origin + Vector2(-(1.0 - pt) * 12.0, 0)
	for i in labels.size():
		var l := labels[i]
		var it := _ease((intro - 1.45 - i * 0.08) / 0.45)
		var on := i == sel
		var was := i == prev
		var w := _ease(sel_t / 0.28) if on else (1.0 - _ease(sel_t / 0.2) if was else 0.0)
		l.position = Vector2(origin.x + 26.0 + roundf(w * 6.0) - (1.0 - it) * 24.0, origin.y + 10.0 + i * ROW)
		l.modulate.a = it
		l.add_theme_color_override("font_color", PALE.lerp(GOLD, w) if i < labels.size() - 1 else DIM.lerp(GOLD, w))
		(l.material as ShaderMaterial).set_shader_parameter("sweep", clampf(sel_t / 0.6, 0.0, 1.0) if on else -1.0)
	var bw := _ease(sel_t / 0.3)
	bar.position = Vector2(origin.x + 6.0, origin.y + 10.0 + sel * ROW + 1.0)
	bar.size = Vector2(maxf(4.0, bw * 160.0), 17)
	bar.modulate = Color(1.4, 1.2, 1.4, pt)
	gem.position = Vector2(origin.x + 12.0 + roundf(sin(t * 5.0 if not demo else a * 12.0)), origin.y + 16.0 + sel * ROW)
	gem.modulate = Color(1.8, 1.8, 1.8, pt * _ease(sel_t / 0.15))
	spark.queue_redraw()
	footer.modulate.a = _ease((intro - 2.0) / 0.6)
	var on_l := footer.get_node("online") as Label
	on_l.modulate.a = 0.9 + 0.1 * sin(a * 6.0)
	# fades: intro from black, confirm flash to black
	var f := 1.0 - _ease(intro / 1.0)
	if confirm_t >= 0.0:
		confirm_t += delta
		f = maxf(f, clampf((confirm_t - 0.1) / 0.6, 0.0, 1.0))
		fade.color = Color(1, 0.9, 0.7, 0.5) if confirm_t < 0.08 else Color(0, 0, 0, f)
		if confirm_t >= 0.75 and not done:
			done = true
			confirmed.emit(sel)
	else:
		fade.color = Color(0, 0, 0, f)

func _draw_spark() -> void:
	var s := clampf(sel_t / 0.5, 0.0, 1.0)
	if s >= 1.0:
		return
	var c := Vector2(origin.x + 14.5, origin.y + 18.5 + sel * ROW)
	var r := 2.0 + s * 7.0
	var col := Color(2.0, 1.6, 0.8, 1.0 - s)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		spark.draw_rect(Rect2((c + d * r).floor(), Vector2(1, 1)), col)
		spark.draw_rect(Rect2((c + d * r * 0.5).floor(), Vector2(1, 1)), col)
