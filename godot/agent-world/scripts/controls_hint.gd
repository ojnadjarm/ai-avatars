extends CanvasLayer
## Keycap hint row pinned to the bottom-left, like the title's footer.
## A Shift-run hint always leads; set `hints` before adding to the tree for the rest.
## Each hint: {glyph: "C", text}, {mod: "Ctrl", key: "L", text} or {cap: "wheel", text}; kit keycaps are used when they exist.

const MARGIN := 8

var hints: Array = []
## Hidden while this dialogue is showing (injected by world_loader).
var dialogue: DialogueCloud
var _panel: PanelContainer


func _ready() -> void:
	layer = 5
	_build_ui()


func _process(_delta: float) -> void:
	_panel.visible = not (dialogue != null and dialogue.is_showing)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	_panel = panel
	panel.name = "Hints"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = MARGIN
	panel.offset_bottom = -MARGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UITheme.kit_style("panel_dim", 6, 4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var run_hint := {"cap": "shift", "text": Strings.get_string("controls.run")}
	for hint: Dictionary in [run_hint] + hints:
		row.add_child(_build_hint(hint))
	panel.add_child(row)
	add_child(panel)


func _build_hint(hint: Dictionary) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 3)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hint.has("mod"):
		var combo := "%s_%s" % [String(hint["mod"]).to_lower(), String(hint["key"]).to_lower()]
		if UITheme.keycap_texture(combo) != null:
			item.add_child(_key_cap(combo))
		else:
			item.add_child(_key_cap(String(hint["mod"])))
			item.add_child(_hud_label("+"))
			item.add_child(_key_cap(String(hint["key"])))
	else:
		item.add_child(_key_cap(String(hint.get("cap", hint.get("glyph", "?")))))
	item.add_child(_hud_label(String(hint.get("text", "")).to_upper()))
	return item


## Kit keycap texture when the kit has one, else the key9 plate with the glyph.
func _key_cap(glyph: String) -> Control:
	var tex := UITheme.keycap_texture(glyph.to_lower())
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", UITheme.kit_style("key9", 3, 2))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lbl := _hud_label(glyph.to_upper())
	lbl.add_theme_color_override("font_color", UITheme.TEXT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(lbl)
	return cap


func _hud_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	UITheme.ensure_fonts_loaded()
	lbl.add_theme_font_override("font", UITheme.FONT_HUD)
	lbl.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl
