extends CanvasLayer
## Small controls cloud pinned to the bottom-left.
## Configurable: set `hints` before adding to the tree.
## Each hint: {glyph: "X", text: "..."} or {mod: "Ctrl", key: "L", text: "..."}

const KEY_CAP_MIN := Vector2(32, 24)

var hints: Array = []


func _ready() -> void:
	layer = 5
	_build_ui()


func _build_ui() -> void:
	# Anchor to the bottom-left point and let the PanelContainer auto-size
	# from its children, growing right-and-up. Manual height math broke
	# when font sizes bumped — now the panel owns its own size.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 14
	panel.offset_bottom = -14
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var style := UITheme.panel_style()
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	for hint in hints:
		var key_node: Control
		if hint.has("mod"):
			key_node = _make_combo(hint["mod"], hint["key"])
		else:
			key_node = _make_key_cap(hint.get("glyph", "?"), hint.get("font_size", 16), false)
		vbox.add_child(_build_hint_row(key_node, hint.get("text", "")))

	panel.add_child(vbox)
	add_child(panel)


func _build_hint_row(key_node: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	row.add_child(key_node)

	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(lbl)

	return row


func _make_combo(mod: String, key: String) -> HBoxContainer:
	var combo := HBoxContainer.new()
	combo.add_theme_constant_override("separation", 3)
	combo.add_child(_make_key_cap(mod, 16, true))
	var plus := Label.new()
	plus.text = "+"
	plus.add_theme_font_size_override("font_size", 32)
	plus.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	combo.add_child(plus)
	combo.add_child(_make_key_cap(key, 16, false))
	return combo


func _make_key_cap(glyph: String, font_size: int = 16, is_modifier: bool = false) -> PanelContainer:
	# Beveled pixel-art keycap — asymmetric borders give a chunky raised look
	# (dark bottom/right = cast shadow, lit top/left via brighter bg).
	# Modifier keys (Ctrl/Shift) are darker to distinguish them at a glance.
	var cap := PanelContainer.new()
	cap.custom_minimum_size = KEY_CAP_MIN

	var cap_style := StyleBoxFlat.new()
	if is_modifier:
		cap_style.bg_color = UITheme.BG
	else:
		cap_style.bg_color = UITheme.CONTROLS_HINT_KEY_BG
	cap_style.border_color = UITheme.BEVEL_SHADOW
	cap_style.set_corner_radius_all(0)
	cap_style.border_width_top = 1
	cap_style.border_width_left = 1
	cap_style.border_width_right = 2
	cap_style.border_width_bottom = 2
	cap_style.content_margin_left = 5
	cap_style.content_margin_right = 5
	cap_style.content_margin_top = 1
	cap_style.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", cap_style)

	var lbl := Label.new()
	lbl.text = glyph
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM if is_modifier else UITheme.TEXT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(lbl)

	return cap
