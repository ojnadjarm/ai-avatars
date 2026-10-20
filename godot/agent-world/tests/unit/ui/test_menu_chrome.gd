extends RefCounted
## Menu chrome: 9-slice panel_style, avatar display names, corner-only focus shimmer, Shift-run hint, whole top line in the dialogue.

const LONG_REPLY := "The lanterns along the shore went out one by one as the mist came over the bridge at dusk, as if they bowed to it. Follow the glow and you may find where the light went. The stones remember every step and every name spoken near the water, and the reeds answer when the wind is low."

var failure_message: String = ""


func run() -> bool:
	return _check_panel_style() and _check_avatar_names() and _check_shimmer() \
			and _check_run_hint() and _check_dialogue_top_line()


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _host() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene else tree.root


func _check_panel_style() -> bool:
	var style := UITheme.panel_style()
	if not style is StyleBoxTexture:
		return _fail("panel_style() is not the kit 9-slice StyleBoxTexture")
	var themed := UITheme.build_default_theme().get_stylebox("panel", "PanelContainer")
	if not themed is StyleBoxTexture or (themed as StyleBoxTexture).texture != (style as StyleBoxTexture).texture \
			or themed.content_margin_left != style.content_margin_left:
		return _fail("PanelContainer theme panel is not panel_style()")
	return true


func _check_avatar_names() -> bool:
	var screen: Node = load("res://scenes/settings_screen.tscn").instantiate()
	_host().add_child(screen)
	var raw: Array = screen.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text.contains("_"))
	var names: Array = screen.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	screen.free()
	if not raw.is_empty():
		return _fail("raw sheet id shown in settings: %s" % (raw[0] as Label).text)
	if not names.has(Strings.get_string("avatar.player_default").to_upper()):
		return _fail("player_default display name missing from the avatar grid")
	return true


## Every shimmer frame keeps its glint inside the 9-slice corners, so the tiled edge middles are plain.
func _check_shimmer() -> bool:
	var meta := UITheme.kit_meta("focus_shimmer")
	var img: Image = UITheme.kit_texture("focus_shimmer").get_image()
	var w: int = meta["size"][0]
	var h: int = meta["size"][1]
	var m: Array = meta["margin"]
	for f in UITheme.kit_frames("focus_shimmer"):
		var ox := f * w
		var edge := img.get_pixel(ox + m[0], 0)
		for x in range(m[0], w - m[2]):
			for y: int in [0, h - 1]:
				if img.get_pixel(ox + x, y) != edge:
					return _fail("shimmer frame %d glint at (%d,%d) tiles along the edge" % [f, x, y])
		for y in range(m[1], h - m[3]):
			for x: int in [0, w - 1]:
				if img.get_pixel(ox + x, y) != edge:
					return _fail("shimmer frame %d glint at (%d,%d) tiles along the edge" % [f, x, y])
	return true


func _check_run_hint() -> bool:
	var hint := CanvasLayer.new()
	hint.set_script(load("res://scripts/controls_hint.gd"))
	_host().add_child(hint)
	var labels: Array = hint.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	var caps: Array = hint.find_children("*", "TextureRect", true, false).map(func(t: TextureRect) -> Texture2D: return t.texture)
	hint.free()
	if labels.is_empty() or labels[0] != Strings.get_string("controls.run").to_upper():
		return _fail("controls hint does not lead with Shift-run: %s" % [labels])
	if UITheme.keycap_texture("shift") == null or not caps.has(UITheme.keycap_texture("shift")):
		return _fail("controls hint lacks the kit Shift keycap")
	return true


## Overflowing reply scrolled to the bottom: the top visible line starts at or below the scroll top, the last line ends inside it.
func _check_dialogue_top_line() -> bool:
	var dc := DialogueCloud.new()
	_host().add_child(dc)
	dc.panel.visible = true
	dc.history_label.text = "\n".join([LONG_REPLY, LONG_REPLY, LONG_REPLY])
	_sort(dc.panel)
	dc.history_label.update_minimum_size()
	_sort(dc.panel)
	var label: RichTextLabel = dc.history_label
	var view: float = dc.scroll.size.y
	var content: float = label.get_content_height()
	var ok := true
	if content <= view:
		ok = _fail("test reply does not overflow (%d <= %d)" % [content, view])
	else:
		dc.scroll.scroll_vertical = dc._line_aligned_top(content)
		var top := dc.scroll.scroll_vertical
		var first := -1
		for i in label.get_line_count():
			if label.get_line_offset(i) >= top:
				first = i
				break
		if first < 0 or int(label.get_line_offset(first)) != top:
			ok = _fail("scroll %d is not on a line top (first visible line clipped)" % top)
		elif label.get_line_offset(first) - top < 0.0:
			ok = _fail("first line y %.1f above the content top" % (label.get_line_offset(first) - top))
		elif content - top > view:
			ok = _fail("last line cut: content %d - scroll %d > view %d" % [content, top, view])
	dc.free()
	return ok


func _sort(c: Control) -> void:
	if c is Container:
		c.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in c.get_children():
		if child is Control:
			_sort(child)
