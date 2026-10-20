extends CanvasLayer
## Kit preview: every UITheme widget on the menu backdrop at the 640x360 base (render with tools/render/run.sh still).


func _ready() -> void:
	UITheme.apply_default_theme()
	UITheme.wallpaper_background(self, false)
	_settings_panel()
	_dialogue()
	_hud()


func _settings_panel() -> void:
	var frame := PanelContainer.new()
	frame.position = Vector2(16, 16)
	frame.custom_minimum_size = Vector2(300, 0)
	frame.add_theme_stylebox_override("panel", UITheme.framed_panel_style())
	add_child(frame)
	UITheme.attach_arcane_corners(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	frame.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_override("font", UITheme.FONT_TITLE)
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var save := UITheme.primary_button("Save")
	var back := UITheme.primary_button("Back")
	back.add_theme_stylebox_override("normal", UITheme.kit_style("btn_hover", UITheme.PAD_BUTTON_LG_X, UITheme.PAD_BUTTON_LG_Y))
	back.add_theme_color_override("font_color", UITheme.ACCENT)
	var off := UITheme.primary_button("Reset")
	off.disabled = true
	for b in [save, back, off]:
		row.add_child(b)
	v.add_child(row)
	var sep := HSeparator.new()
	v.add_child(sep)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 150)
	v.add_child(tabs)
	var form := VBoxContainer.new()
	form.name = "PLAYER"
	form.add_theme_constant_override("separation", 4)
	tabs.add_child(form)
	for n in ["GATEWAYS", "AGENTS", "WORLD"]:
		var c := Control.new()
		c.name = n
		tabs.add_child(c)
	form.add_child(UITheme.section_header("Avatar"))
	var name_row := HBoxContainer.new()
	name_row.add_child(UITheme.form_label("Name"))
	var field := LineEdit.new()
	field.text = "Wanderer"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(field)
	form.add_child(name_row)
	var empty := LineEdit.new()
	empty.placeholder_text = "http://127.0.0.1:8642"
	form.add_child(empty)
	var checks := HBoxContainer.new()
	var c1 := CheckBox.new()
	c1.text = "Music"
	c1.button_pressed = true
	var c2 := CheckBox.new()
	c2.text = "Hints"
	var r1 := CheckBox.new()
	r1.text = "Day"
	r1.button_group = ButtonGroup.new()
	r1.button_pressed = true
	var r2 := CheckBox.new()
	r2.text = "Night"
	r2.button_group = r1.button_group
	for c in [c1, c2, r1, r2]:
		checks.add_child(c)
	form.add_child(checks)
	var opt := OptionButton.new()
	opt.add_item("Hermes")
	opt.add_item("OpenClaw")
	name_row.add_child(opt)
	var slider := HSlider.new()
	slider.value = 60
	form.add_child(slider)
	for bar in ["energy", "patience", "social_battery"]:
		var b := UITheme.build_stat_bar(bar, Vector2(0, 6))
		b.value = 0.3 + 0.2 * ["energy", "patience", "social_battery"].find(bar)
		form.add_child(b)


func _dialogue() -> void:
	var box := PanelContainer.new()
	box.position = Vector2(332, 250)
	box.custom_minimum_size = Vector2(292, 94)
	box.add_theme_stylebox_override("panel", UITheme.kit_style("dialogue", 10, 8))
	add_child(box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	box.add_child(h)
	var portrait := Panel.new()
	portrait.custom_minimum_size = Vector2(52, 52)
	portrait.add_theme_stylebox_override("panel", UITheme.kit_style("portrait_frame"))
	h.add_child(portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var tag := Label.new()
	tag.text = "Luna"
	tag.add_theme_stylebox_override("normal", UITheme.kit_style("nametag", 8, 0))
	tag.add_theme_color_override("font_color", UITheme.ACCENT)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(tag)
	var text := Label.new()
	text.text = "The lake remembers every lantern."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.custom_minimum_size = Vector2(200, 0)
	v.add_child(text)


func _hud() -> void:
	var banner := PanelContainer.new()
	banner.position = Vector2(360, 16)
	banner.custom_minimum_size = Vector2(200, 24)
	banner.add_theme_stylebox_override("panel", UITheme.kit_style("zone_banner", 30, 4))
	add_child(banner)
	var zl := Label.new()
	zl.text = "Hollowmere Shore"
	zl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zl.add_theme_color_override("font_color", UITheme.ACCENT)
	banner.add_child(zl)
	var mini := Panel.new()
	mini.position = Vector2(556, 52)
	mini.size = Vector2(72, 72)
	mini.add_theme_stylebox_override("panel", UITheme.kit_style("minimap_frame"))
	add_child(mini)
	var log := PanelContainer.new()
	log.position = Vector2(332, 52)
	log.custom_minimum_size = Vector2(214, 92)
	log.add_theme_stylebox_override("panel", UITheme.kit_style("panel_dim", 8, 7))
	add_child(log)
	var lv := VBoxContainer.new()
	log.add_child(lv)
	for line: String in ["[event] Mist rolls over the shore.", "[thought] Luna studies the stones.", "[solve] The rune lights up."]:
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		var kind: String = line.get_slice("]", 0).trim_prefix("[")
		l.text = "[color=#%s]%s[/color]" % [UITheme.narration_color(kind), line.get_slice("] ", 1)]
		l.add_theme_font_override("normal_font", UITheme.FONT_HUD)
		l.add_theme_font_size_override("normal_font_size", UITheme.FONT_SIZE_HUD)
		lv.add_child(l)
	var tip := PanelContainer.new()
	tip.position = Vector2(332, 152)
	tip.add_theme_stylebox_override("panel", UITheme.kit_style("tooltip", 5, 3))
	add_child(tip)
	var tl := Label.new()
	tl.text = "Talk to Luna"
	tl.add_theme_font_override("font", UITheme.FONT_HUD)
	tl.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	tip.add_child(tl)
	var keys := HBoxContainer.new()
	keys.position = Vector2(332, 176)
	keys.add_theme_constant_override("separation", 3)
	add_child(keys)
	for k in ["e", "esc", "ctrl_l", "enter", "up", "down", "left", "right", "wheel"]:
		var t := TextureRect.new()
		t.texture = UITheme.keycap_texture(k)
		keys.add_child(t)
	var pill := UITheme.prominent_button("Main Menu")
	pill.position = Vector2(332, 196)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(pill)
	var focus := Panel.new()
	focus.position = Vector2(420, 196)
	focus.size = Vector2(60, 16)
	focus.add_theme_stylebox_override("panel", UITheme.kit_style("focus_shimmer", 0, 0, 2))
	add_child(focus)
	var sc := VScrollBar.new()
	sc.position = Vector2(538, 152)
	sc.size = Vector2(7, 60)
	sc.page = 30
	sc.max_value = 100
	add_child(sc)
	var cur := TextureRect.new()
	cur.texture = UITheme.kit_texture("cursor")
	cur.position = Vector2(200, 72)
	add_child(cur)
