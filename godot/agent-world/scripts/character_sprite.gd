extends AnimatedSprite2D
## Plays a /pixel-avatar layout.json sheet (normal-mapped, glow pass, feet on the origin) or an LPC 9x4 walk sheet.

const COLS := 9
const ROWS := 4
# LPC native row order
const DIRS := ["up", "left", "down", "right"]
const WALK_FPS := 12
const ANIM_FPS := {"idle": 6, "walk": 12, "talk": 8}
const SIGNATURE_FPS := 10
const GLOW_LIGHT_ENERGY := 1.4
const GLOW_LIGHT_SCALE := 0.5
const RIM_COLOR := Color(0.62, 0.76, 1.0)
const RIM_DAY_LUMA := 0.6
const RIM_NIGHT_LUMA := 0.25
const FILL_MASK_BIT := 19
const FILL_ENERGY := 1.05
const FILL_HEIGHT := 60.0
const FILL_OFFSET := Vector2(-20, -36)
const FILL_REACH := 3.0
const RIM_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform vec4 rim_color : source_color;
uniform float strength = 1.0;
#define CLEAR(uv) (1.0 - step(0.5, texture(TEXTURE, uv).a))
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float a = step(0.5, texture(TEXTURE, UV).a);
	float moon = max(CLEAR(UV - vec2(0.0, px.y)), CLEAR(UV - vec2(px.x, 0.0)));
	float moon2 = max(CLEAR(UV - vec2(0.0, 2.0 * px.y)), CLEAR(UV - vec2(2.0 * px.x, 0.0)));
	float far = max(CLEAR(UV + vec2(px.x, 0.0)), 0.4 * CLEAR(UV + vec2(0.0, px.y)));
	COLOR = vec4(rim_color.rgb, a * max(max(moon, 0.5 * moon2), 0.4 * far) * strength);
}
"""

## Target display height in pixels (how tall the sprite renders in-world).
## The sprite is scaled so its frame height matches this value.
## Set to 0 to use the raw frame size with no scaling.
@export var display_height: float = 0.0
## Moonlit silhouette rim (2 px on the moon side, 1 px dim on the far side) plus a head-to-feet moon fill light on this sprite only, scaled by how dark the scene is (off in daylight).
@export var night_rim: bool = false

var layout: Dictionary = {}
var glow_sprite: AnimatedSprite2D
var glow_light: PointLight2D
var rim_sprite: AnimatedSprite2D
var fill_light: PointLight2D


func load_spritesheet(path: String) -> void:
	var texture: Texture2D = GameState.load_texture(path)
	if not texture:
		push_warning("Could not load sprite: %s" % path)
		return
	_clear_glow()
	layout = find_layout(path)
	if layout.is_empty():
		_load_lpc(texture)
	else:
		_load_layout(path, texture)
	play("idle_down")


## Layout entry for a sheet: sibling <name>.json, else <name> in the folder's layout.json.
static func find_layout(path: String) -> Dictionary:
	var sheet_name := path.get_file().get_basename()
	var sibling: Dictionary = GameState.load_json(path.get_basename() + ".json")
	if sibling.has("anims"):
		return sibling
	if sibling.get(sheet_name) is Dictionary:
		return sibling[sheet_name]
	var folder: Dictionary = GameState.load_json(path.get_base_dir().path_join("layout.json"))
	var entry: Variant = folder.get(sheet_name)
	return entry if entry is Dictionary and (entry as Dictionary).has("anims") else {}


func _load_layout(path: String, texture: Texture2D) -> void:
	var cell := int(layout.get("cell", 96))
	var pivot_raw: Array = layout.get("pivot", [cell * 0.5, cell])
	var base := path.get_basename()
	var lit: Texture2D = texture
	var normal: Texture2D = GameState.load_texture(base + "_n.png") if FileAccess.file_exists(base + "_n.png") else null
	if normal:
		var canvas := CanvasTexture.new()
		canvas.diffuse_texture = texture
		canvas.normal_texture = normal
		lit = canvas
	sprite_frames = _layout_frames(lit, cell)
	centered = false
	offset = -Vector2(float(pivot_raw[0]), float(pivot_raw[1]))
	var k := maxi(1, roundi(display_height / float(cell))) if display_height > 0.0 else 1
	scale = Vector2(k, k)
	var glow_path := base + "_g.png"
	if FileAccess.file_exists(glow_path):
		var glow_tex: Texture2D = GameState.load_texture(glow_path)
		if glow_tex and glow_tex.get_image() and glow_tex.get_image().get_used_rect().has_area():
			_add_glow_sprite(glow_tex, cell)
			_add_glow_light(glow_tex.get_image(), cell)
	if night_rim:
		_add_rim(texture, cell)
	frame_changed.connect(_sync_glow)
	animation_changed.connect(_sync_glow)


func _layout_frames(texture: Texture2D, cell: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var anims: Dictionary = layout.get("anims", {})
	for anim_name: String in anims:
		var spec: Dictionary = anims[anim_name]
		var kind := anim_name.get_slice("_", 0)
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, ANIM_FPS.get(kind, SIGNATURE_FPS))
		frames.set_animation_loop(anim_name, ANIM_FPS.has(kind))
		var row := int(spec.get("row", 0))
		for col in int(spec.get("frames", 1)):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * cell, row * cell, cell, cell)
			frames.add_frame(anim_name, atlas)
	return frames


func _add_glow_sprite(glow_tex: Texture2D, cell: int) -> void:
	glow_sprite = AnimatedSprite2D.new()
	glow_sprite.name = "Glow"
	glow_sprite.sprite_frames = _layout_frames(glow_tex, cell)
	glow_sprite.centered = false
	glow_sprite.offset = offset
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow_sprite.material = mat
	add_child(glow_sprite)


func _add_rim(texture: Texture2D, cell: int) -> void:
	var k := rim_strength(self)
	if k <= 0.0:
		return
	rim_sprite = AnimatedSprite2D.new()
	rim_sprite.name = "Rim"
	rim_sprite.sprite_frames = _layout_frames(texture, cell)
	rim_sprite.centered = false
	rim_sprite.offset = offset
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = RIM_SHADER
	mat.set_shader_parameter("rim_color", RIM_COLOR)
	mat.set_shader_parameter("strength", k)
	rim_sprite.material = mat
	add_child(rim_sprite)
	light_mask |= 1 << FILL_MASK_BIT
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	fill_light = PointLight2D.new()
	fill_light.name = "NightFill"
	fill_light.texture = tex
	fill_light.texture_scale = FILL_REACH * cell / 64.0
	fill_light.position = FILL_OFFSET
	fill_light.height = FILL_HEIGHT
	fill_light.color = RIM_COLOR
	fill_light.energy = FILL_ENERGY * k
	fill_light.range_item_cull_mask = 1 << FILL_MASK_BIT
	add_child(fill_light)


## 0 in daylight, 1 at night: from the luminance of the first CanvasModulate in the tree.
static func rim_strength(node: Node) -> float:
	if not node.is_inside_tree():
		return 0.0
	var mods := node.get_tree().root.find_children("*", "CanvasModulate", true, false)
	if mods.is_empty():
		return 0.0
	var luma := (mods[0] as CanvasModulate).color.get_luminance()
	return clampf((RIM_DAY_LUMA - luma) / (RIM_DAY_LUMA - RIM_NIGHT_LUMA), 0.0, 1.0)


func _add_glow_light(glow_img: Image, cell: int) -> void:
	var anims: Dictionary = layout.get("anims", {})
	var first := Vector2(-1, -1)
	var first_row := 0
	for anim_name: String in anims:
		var g: Dictionary = (anims[anim_name] as Dictionary).get("glow", {})
		if g.has("0"):
			first = Vector2(float(g["0"][0]), float(g["0"][1]))
			first_row = int(anims[anim_name]["row"])
			break
	if first.x < 0.0:
		return
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	glow_light = PointLight2D.new()
	glow_light.name = "GlowLight"
	glow_light.texture = tex
	glow_light.texture_scale = GLOW_LIGHT_SCALE
	glow_light.color = _brightest_near(glow_img, Vector2i(first) + Vector2i(0, first_row * cell))
	add_child(glow_light)


static func _brightest_near(img: Image, at: Vector2i) -> Color:
	var best := Color(0.8, 0.8, 1.0)
	var lum := -1.0
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var p := at + Vector2i(dx, dy)
			if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
				continue
			var c := img.get_pixelv(p)
			if c.a > 0.0 and c.get_luminance() > lum:
				lum = c.get_luminance()
				best = Color(c.r, c.g, c.b)
	return best


func _sync_glow() -> void:
	if rim_sprite:
		if rim_sprite.animation != animation and rim_sprite.sprite_frames.has_animation(animation):
			rim_sprite.animation = animation
		rim_sprite.frame = frame
		rim_sprite.flip_h = flip_h
	if glow_sprite:
		if glow_sprite.animation != animation and glow_sprite.sprite_frames.has_animation(animation):
			glow_sprite.animation = animation
		glow_sprite.frame = frame
		glow_sprite.flip_h = flip_h
	if glow_light:
		var spec: Dictionary = (layout.get("anims", {}) as Dictionary).get(animation, {})
		var g: Variant = (spec.get("glow", {}) as Dictionary).get(str(frame))
		glow_light.visible = g is Array
		if g is Array:
			glow_light.position = offset + Vector2(float(g[0]), float(g[1]))
			glow_light.energy = float(g[2]) * GLOW_LIGHT_ENERGY


func _clear_glow() -> void:
	for node: Node in [glow_sprite, glow_light, rim_sprite, fill_light]:
		if is_instance_valid(node):
			node.queue_free()
	glow_sprite = null
	glow_light = null
	rim_sprite = null
	fill_light = null
	light_mask &= ~(1 << FILL_MASK_BIT)
	if frame_changed.is_connected(_sync_glow):
		frame_changed.disconnect(_sync_glow)
		animation_changed.disconnect(_sync_glow)


func _load_lpc(texture: Texture2D) -> void:
	# LPC frames are square. Derive frame size from texture HEIGHT only
	# (height is always exactly 4 rows). The texture width may be larger than
	# 9*frame_size if there's empty padding to the right — that's fine, we
	# only read the first 9 cols.
	var frame_h := texture.get_height() / ROWS
	var frame_w := frame_h

	var frames := SpriteFrames.new()

	# Remove default animation
	if frames.has_animation("default"):
		frames.remove_animation("default")

	for dir_i in range(ROWS):
		var dir_name: String = DIRS[dir_i]

		# Walk animation — cols 1-8 (8 frames, looping). Col 0 is the idle pose.
		var walk_name := "walk_" + dir_name
		frames.add_animation(walk_name)
		frames.set_animation_speed(walk_name, WALK_FPS)
		frames.set_animation_loop(walk_name, true)

		for col in range(1, COLS):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_w, dir_i * frame_h, frame_w, frame_h)
			frames.add_frame(walk_name, atlas)

		# Idle animation (column 0 = standing pose)
		var idle_name := "idle_" + dir_name
		frames.add_animation(idle_name)
		frames.set_animation_speed(idle_name, 1)
		frames.set_animation_loop(idle_name, false)

		var idle_atlas := AtlasTexture.new()
		idle_atlas.atlas = texture
		idle_atlas.region = Rect2(0, dir_i * frame_h, frame_w, frame_h)
		frames.add_frame(idle_name, idle_atlas)

	sprite_frames = frames
	centered = true
	offset = Vector2.ZERO

	# Scale sprite so it displays at target height (keeps proportions)
	if display_height > 0.0 and frame_h > 0:
		var s := display_height / float(frame_h)
		scale = Vector2(s, s)
