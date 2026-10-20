extends CanvasLayer
## Corner minimap: the world's ground downscaled by an integer, zone labels, player and agent dots, the camera's view frame; M toggles it.

const MAP_W := 160
const MARGIN := 8
const BORDER := 4
const REFRESH := 0.1
const LABEL_PAD := 1
const BLUR := 2
const FEATURE_DIFF := 30.0 / 255.0
const TONE_STEPS := 6.0
const PLAYER_CLEAR := 2.0

var world_rect: Rect2 = Rect2()
var factor: int = 1
var zones: Array[Dictionary] = []
var player: Node2D
var agents: Node
var _frame: PanelContainer
var _canvas: Control
var _map: TextureRect
var _accum: float = 0.0


## Integer downscale so the map is at most MAP_W wide.
static func factor_for(world_size: Vector2, map_w: int = MAP_W) -> int:
	return maxi(1, ceili(world_size.x / float(map_w) - 0.0001))


## Map pixel of a world point.
static func world_to_map(p: Vector2, rect: Rect2, f: int) -> Vector2:
	return (p - rect.position) / float(f)


## Map rect of the camera's visible world (view_size / zoom around center, clamped to the world).
static func view_frame(center: Vector2, zoom: float, view_size: Vector2, rect: Rect2, f: int) -> Rect2:
	var size: Vector2 = view_size / zoom
	var top_left: Vector2 = center - size * 0.5
	top_left.x = clampf(top_left.x, rect.position.x, maxf(rect.position.x, rect.end.x - size.x))
	top_left.y = clampf(top_left.y, rect.position.y, maxf(rect.position.y, rect.end.y - size.y))
	var r := Rect2(top_left, size).intersection(rect)
	return Rect2(world_to_map(r.position, rect, f), r.size / float(f))


## Zones/<Area2D> of a world scene as [{name, rect}] in world px.
static func read_zones(world_scene: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := world_scene.get_node_or_null("Zones") if world_scene else null
	if root == null:
		return out
	for area: Node in root.get_children():
		if not (area is Area2D) or not area.has_meta("zone_name"):
			continue
		for shape: Node in area.get_children():
			if shape is CollisionShape2D and (shape as CollisionShape2D).shape is RectangleShape2D:
				var size: Vector2 = ((shape as CollisionShape2D).shape as RectangleShape2D).size
				var c: Vector2 = (shape as CollisionShape2D).global_position if shape.is_inside_tree() else (area as Area2D).position + (shape as CollisionShape2D).position
				out.append({"name": String(area.get_meta("zone_name")), "rect": Rect2(c - size * 0.5, size)})
	return out


## Ground albedo of a world scene: the Background texture, else <world dir>/art/ground.png.
static func ground_image(world_scene: Node) -> Image:
	var bg := world_scene.get_node_or_null("Background") as Sprite2D if world_scene else null
	var tex: Texture2D = bg.texture if bg else null
	if tex is CanvasTexture:
		tex = (tex as CanvasTexture).diffuse_texture
	var img: Image = tex.get_image() if tex else null
	if (img == null or img.is_empty()) and world_scene and world_scene.scene_file_path != "":
		img = Image.load_from_file(ProjectSettings.globalize_path(world_scene.scene_file_path.get_base_dir().path_join("art/ground.png")))
	return img


## Ambient light of a world scene (its CanvasModulate colour), white when it has none.
static func ambient(world_scene: Node) -> Color:
	var found := world_scene.find_children("*", "CanvasModulate", true, false) if world_scene else []
	return (found[0] as CanvasModulate).color if not found.is_empty() else Color.WHITE


## Flat-toned map art: ground blurred and stepped in value, paths and water kept crisp, graded by the ambient hue.
static func map_image(ground: Image, map_size: Vector2i, tint: Color) -> Image:
	var src := ground.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	src.resize(map_size.x, map_size.y, Image.INTERPOLATE_LANCZOS)
	var blur := _box_blur(src, BLUR)
	var m: float = maxf(tint.r, maxf(tint.g, tint.b))
	var grade := Color(tint.r / m, tint.g / m, tint.b / m) if m > 0.0 else Color.WHITE
	var out := Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	for y in map_size.y:
		for x in map_size.x:
			var c := src.get_pixel(x, y)
			var b := blur.get_pixel(x, y)
			if absf(c.r - b.r) + absf(c.g - b.g) + absf(c.b - b.b) <= FEATURE_DIFF:
				c = Color.from_hsv(b.h, b.s, roundf(b.v * TONE_STEPS) / TONE_STEPS)
			out.set_pixel(x, y, Color(c.r * grade.r, c.g * grade.g, c.b * grade.b))
	return out


static func _box_blur(img: Image, r: int) -> Image:
	var tmp := img.duplicate() as Image
	var out := img.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	for pass_i in 2:
		var from := img if pass_i == 0 else tmp
		var to := tmp if pass_i == 0 else out
		for y in h:
			for x in w:
				var acc := Color(0, 0, 0, 0)
				for k in range(-r, r + 1):
					acc += from.get_pixel(clampi(x + k, 0, w - 1), y) if pass_i == 0 else from.get_pixel(x, clampi(y + k, 0, h - 1))
				to.set_pixel(x, y, acc / float(2 * r + 1))
	return out


## Builds the map art (graded by `tint`, the world's ambient light) and lays the map out in the top-right corner.
func setup(ground: Image, rect: Rect2, zone_list: Array[Dictionary], player_node: Node2D, agents_root: Node, tint: Color = Color.WHITE) -> void:
	world_rect = rect
	factor = factor_for(rect.size)
	zones = zone_list
	player = player_node
	agents = agents_root
	var map_size := Vector2i(int(rect.size.x) / factor, int(rect.size.y) / factor)
	if ground != null and not ground.is_empty():
		_map.texture = ImageTexture.create_from_image(map_image(ground, map_size, tint))
	_map.custom_minimum_size = Vector2(map_size)
	_canvas.custom_minimum_size = Vector2(map_size)
	_frame.reset_size()
	_place()


func _ready() -> void:
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_theme_stylebox_override("panel", UITheme.kit_style("minimap_frame", BORDER, BORDER))
	_map = TextureRect.new()
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	var box := MarginContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_map)
	box.add_child(_canvas)
	_frame.add_child(box)
	add_child(_frame)
	get_viewport().size_changed.connect(_place)
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_M \
			and not (event as InputEventKey).ctrl_pressed and not (event as InputEventKey).alt_pressed:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH and visible:
		_accum = 0.0
		_canvas.queue_redraw()


## Top-right corner position of the framed map.
func _place() -> void:
	if _frame == null or not _frame.is_inside_tree():
		return
	_frame.reset_size()
	var vw: float = _frame.get_viewport_rect().size.x
	_frame.position = Vector2(vw - _frame.size.x - MARGIN, MARGIN)


## Bottom edge of the minimap frame in screen px (the world log stacks under it).
func bottom() -> float:
	return (_frame.position.y + _frame.size.y) if _frame else 0.0


func _draw_overlay() -> void:
	if factor <= 0 or world_rect.size == Vector2.ZERO:
		return
	var r := view_box()
	if r.has_area():
		_canvas.draw_rect(r.grow(1.0), UITheme.LABEL_SHADOW, false, 1.0)
		_canvas.draw_rect(r, UITheme.ACCENT, false, 1.0)
	_draw_labels(_current_zone())
	if agents:
		for a: Node in agents.get_children():
			if a is Node2D:
				var id: String = str(a.get("agent_id")) if a.get("agent_id") != null else String(a.name)
				_dot(world_to_map((a as Node2D).global_position, world_rect, factor), 2, UITheme.agent_color(id))
	if is_instance_valid(player):
		_dot(world_to_map(player.global_position, world_rect, factor), 3, UITheme.TEXT_PLAYER)


func _dot(p: Vector2, size: int, color: Color) -> void:
	var r := Rect2((p - Vector2(size, size) * 0.5).floor(), Vector2(size, size))
	_canvas.draw_rect(r.grow(1.0), UITheme.BEVEL_SHADOW)
	_canvas.draw_rect(r, color)


## Zone labels, greedy without overlap: the player's zone first (gold), then the rest by size (dim).
func _draw_labels(cur: String) -> void:
	var font := _font()
	var fs := UITheme.FONT_SIZE_HUD
	for l: Dictionary in label_layout(cur):
		var base: Vector2 = (l["rect"] as Rect2).position + Vector2(LABEL_PAD, LABEL_PAD + font.get_ascent(fs))
		_canvas.draw_string_outline(font, base, l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, UITheme.LABEL_SHADOW_HEAVY)
		_canvas.draw_string(font, base, l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.ACCENT if l["name"] == cur else UITheme.TEXT)


## Placed labels [{name, text, rect}] in map px: centred on the zone, else above or below it (the player's zone also just outside the view frame); never over another label, the player or the frame's outline.
func label_layout(cur: String = _current_zone()) -> Array[Dictionary]:
	var font := _font()
	var fs := UITheme.FONT_SIZE_HUD
	var order: Array[Dictionary] = zones.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a["name"] == cur) != (b["name"] == cur):
			return a["name"] == cur
		return (a["rect"] as Rect2).get_area() > (b["rect"] as Rect2).get_area())
	var bounds := Rect2(Vector2.ZERO, _canvas.custom_minimum_size)
	var blocked: Array[Rect2] = []
	var pb := player_box()
	if pb.has_area():
		blocked.append(pb.grow(PLAYER_CLEAR))
	var vf := view_box()
	var h: float = fs + 2 * LABEL_PAD
	var out: Array[Dictionary] = []
	for z: Dictionary in order:
		var text: String = String(z["name"]).to_upper()
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c: Vector2 = world_to_map((z["rect"] as Rect2).get_center(), world_rect, factor)
		var ys: Array[float] = [c.y, c.y - h, c.y + h]
		if z["name"] == cur and vf.has_area():
			ys.append_array([vf.position.y - 3.0 - h * 0.5, vf.end.y + 3.0 + h * 0.5])
		for cy: float in ys:
			var box := Rect2(Vector2(roundf(c.x - w * 0.5), roundf(cy - fs * 0.5)), Vector2(w, fs)).grow(LABEL_PAD)
			box.position.x = clampf(box.position.x, 0.0, bounds.size.x - box.size.x)
			box.position.y = clampf(box.position.y, 0.0, bounds.size.y - box.size.y)
			if crosses_frame(box, vf) or blocked.any(func(o: Rect2) -> bool: return o.intersects(box)):
				continue
			blocked.append(box)
			out.append({"name": z["name"], "text": text, "rect": box})
			break
	return out


## The player's marker in map px (empty without a player).
func player_box() -> Rect2:
	if not is_instance_valid(player) or factor <= 0:
		return Rect2()
	var p := world_to_map(player.global_position, world_rect, factor)
	return Rect2((p - Vector2(1.5, 1.5)).floor(), Vector2(3, 3)).grow(1.0)


## The camera's view frame in map px as drawn (empty without a camera).
func view_box() -> Rect2:
	var cam := _canvas.get_viewport().get_camera_2d() if _canvas and _canvas.is_inside_tree() else null
	if cam == null or factor <= 0:
		return Rect2()
	var vf := view_frame(cam.get_screen_center_position(), cam.zoom.x, _canvas.get_viewport_rect().size, world_rect, factor)
	return Rect2(vf.position.floor(), vf.size.floor())


## True when `box` touches the drawn outline of `frame` (its shadow included); boxes fully inside or outside are clear.
static func crosses_frame(box: Rect2, frame: Rect2) -> bool:
	return frame.has_area() and frame.grow(2.0).intersects(box) and not frame.grow(-2.0).encloses(box)


## The framed map texture (tests read its filter).
func map_texture_rect() -> TextureRect:
	return _map


func _font() -> Font:
	return UITheme.FONT_HUD if UITheme.FONT_HUD else ThemeDB.fallback_font


func _current_zone() -> String:
	if not is_instance_valid(player):
		return ""
	for z: Dictionary in zones:
		if (z["rect"] as Rect2).has_point(player.global_position):
			return z["name"]
	return ""
