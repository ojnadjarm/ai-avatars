class_name TestCharacterSprite
extends RefCounted
## Unit tests for character_sprite.gd layout sheets, the LPC fallback, sprite listing and portraits.

const LUNA := "res://assets/characters/luna.png"
const DIRS := ["down", "left", "right", "up"]

var failure_message: String = ""


func run() -> bool:
	return _test_luna_anims() and _test_luna_pivot_scale() and _test_luna_normal_map() \
		and _test_glow_light() and _test_lpc_fallback() and _test_sprite_list() and _test_portraits() and _test_night_rim()


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _make(path: String, height: float = 0.0) -> AnimatedSprite2D:
	var spr := AnimatedSprite2D.new()
	spr.set_script(load("res://scripts/character_sprite.gd"))
	spr.display_height = height
	spr.load_spritesheet(path)
	return spr


func _test_luna_anims() -> bool:
	var spr := _make(LUNA)
	var sf: SpriteFrames = spr.sprite_frames
	var want := {"idle": 6, "walk": 8, "talk": 4}
	var fps := {"idle": 6.0, "walk": 12.0, "talk": 8.0}
	for kind: String in want:
		for d: String in DIRS:
			var a := "%s_%s" % [kind, d]
			if not sf.has_animation(a):
				spr.free()
				return _fail("luna lacks %s" % a)
			if sf.get_frame_count(a) != want[kind] or not is_equal_approx(sf.get_animation_speed(a), fps[kind]):
				spr.free()
				return _fail("%s: %d frames at %s fps" % [a, sf.get_frame_count(a), sf.get_animation_speed(a)])
	var ok := sf.has_animation("draw_down") and not sf.get_animation_loop("draw_down") \
		and is_equal_approx(sf.get_animation_speed("draw_down"), 10.0) and spr.animation == "idle_down"
	spr.free()
	return ok or _fail("signature draw_down must be 10 fps, not looped; start on idle_down")


func _test_luna_pivot_scale() -> bool:
	var spr := _make(LUNA, 200.0)
	var frame_img: Image = (spr.sprite_frames.get_frame_texture("idle_down", 0) as AtlasTexture).atlas.get_image()
	var used: Rect2i = frame_img.get_region(Rect2i(0, 0, 96, 96)).get_used_rect()
	var feet_y: float = spr.offset.y + used.end.y
	var ok := not spr.centered and spr.offset == Vector2(-48, -88) and absf(feet_y) <= 4.0
	var s := spr.scale
	var off := spr.offset
	spr.free()
	if not ok:
		return _fail("feet not on origin: offset %s, feet at %s" % [off, feet_y])
	if s != Vector2(2, 2):
		return _fail("scale %s is not the integer 2 for height 200 / cell 96" % s)
	var one := _make(LUNA, 130.0)
	var s1 := one.scale
	one.free()
	return s1 == Vector2.ONE or _fail("scale %s is not the integer 1 for height 130" % s1)


func _test_luna_normal_map() -> bool:
	var spr := _make(LUNA)
	var tex := spr.sprite_frames.get_frame_texture("walk_left", 3) as AtlasTexture
	var canvas := tex.atlas as CanvasTexture if tex else null
	var ok := canvas != null and canvas.normal_texture != null and canvas.diffuse_texture != null \
		and tex.region == Rect2(3 * 96, 5 * 96, 96, 96)
	spr.free()
	return ok or _fail("walk_left frame 3 is not an AtlasTexture over a CanvasTexture with a normal map")


func _test_glow_light() -> bool:
	var spr := _make("res://assets/characters/darksaddler.png")
	var light: PointLight2D = spr.get("glow_light")
	var glow: AnimatedSprite2D = spr.get("glow_sprite")
	if light == null or glow == null:
		spr.free()
		return _fail("darksaddler has no glow sprite or glow light")
	spr.play("cast_left")
	spr.frame = 4
	var ok := glow.animation == "cast_left" and glow.frame == 4 and light.visible \
		and light.position.is_equal_approx(spr.offset + Vector2(15.2, 3.3))
	var plain := _make("res://assets/characters/player_default.png")
	ok = ok and plain.get("glow_sprite") == null and plain.get("glow_light") == null
	spr.free()
	plain.free()
	return ok or _fail("glow does not follow cast_left frame 4")


func _test_lpc_fallback() -> bool:
	var img := Image.create(9 * 32, 4 * 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.3, 0.2, 1.0))
	var path := "user://test_lpc_sheet.png"
	img.save_png(path)
	var spr := _make(path)
	var sf: SpriteFrames = spr.sprite_frames
	var ok := sf != null
	for d: String in DIRS:
		ok = ok and sf.get_frame_count("walk_" + d) == 8 and sf.get_frame_count("idle_" + d) == 1
	ok = ok and spr.centered and spr.get("glow_sprite") == null
	spr.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return ok or _fail("LPC 9x4 sheet lacks walk_*/idle_* in 4 dirs")


func _test_sprite_list() -> bool:
	var names: Array = []
	for info: Dictionary in GameState.scan_available_sprites():
		if info["is_builtin"]:
			names.append(info["name"])
	names.sort()
	var want := ["darksaddler", "grok", "luna", "player_default"]
	return names == want or _fail("sprite list %s != %s" % [names, want])


func _test_portraits() -> bool:
	var p: Texture2D = GameState.load_portrait_texture(LUNA)
	if p == null or p.get_size() != Vector2(96, 96):
		return _fail("luna portrait %s is not 96x96" % (p.get_size() if p else "null"))
	var frames: Array[Texture2D] = GameState.load_portrait_frames(LUNA)
	if frames.size() != 4 or (frames[3] as AtlasTexture).region != Rect2(288, 0, 96, 96):
		return _fail("luna portrait strip gives %d frames" % frames.size())
	var rect := GameState.make_portrait_rect(p, Vector2(200, 200))
	var ok := rect.custom_minimum_size == Vector2(192, 192) and rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
	rect.free()
	return ok or _fail("portrait rect not at integer scale x2 with nearest filter")


func _rim_under(amb: Color) -> Array:
	var tree_root := (Engine.get_main_loop() as SceneTree).root
	var root := tree_root.get_child(tree_root.get_child_count() - 1)
	var cm := CanvasModulate.new()
	cm.color = amb
	root.add_child(cm)
	var spr := AnimatedSprite2D.new()
	spr.set_script(load("res://scripts/character_sprite.gd"))
	spr.night_rim = true
	root.add_child(spr)
	spr.load_spritesheet("res://assets/characters/player_default.png")
	var got := [spr.get_node_or_null("Rim") != null, spr.get_node_or_null("NightFill") != null, spr.light_mask]
	spr.free()
	cm.free()
	return got


func _test_night_rim() -> bool:
	var night := _rim_under(Color8(40, 46, 98))
	if not (night[0] and night[1] and int(night[2]) & (1 << 19)):
		return _fail("night: player needs Rim + NightFill and light_mask bit 19, got %s" % [night])
	var day := _rim_under(Color8(236, 228, 206))
	return (not day[0] and not day[1]) or _fail("day: no rim or fill expected, got %s" % [day])
