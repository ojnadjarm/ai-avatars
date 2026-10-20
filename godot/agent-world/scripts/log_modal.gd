class_name LogModal
extends CanvasLayer
## Reusable modal for displaying a large scrollable log — used for both the
## per-vessel causal log and the expanded world log.
##
## Usage:
##   LogModal.show_entries(parent, "World Log", lines)
##   # lines is an Array[String] of BBCode-enabled lines, rendered top-to-bottom.
##   # The modal installs itself under `parent` and closes on Close/Esc/backdrop.
##
## Esc hierarchy: LogModal instances track themselves via _open_count so other
## Esc handlers (dialogue_cloud, world_loader) can check is_any_open() and
## yield — the modal always wins Esc while visible.

const PANEL_SIZE := Vector2(560, 312)

static var _open_count: int = 0


static func is_any_open() -> bool:
	return _open_count > 0


static func show_entries(parent: Node, title_text: String, entries: Array[String]) -> LogModal:
	var modal := LogModal.new()
	modal.layer = 60
	modal._build(title_text, entries)
	parent.add_child(modal)
	return modal


func _build(title_text: String, entries: Array[String]) -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UITheme.MODAL_BACKDROP
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "LogPanel"
	panel.add_theme_stylebox_override("panel", UITheme.kit_style("modal", UITheme.PAD_FRAMED_X, UITheme.PAD_FRAMED_Y))
	panel.custom_minimum_size = PANEL_SIZE
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = title_text.to_upper()
	UITheme.ensure_fonts_loaded()
	if UITheme.FONT_TITLE != null:
		title.add_theme_font_override("font", UITheme.FONT_TITLE)
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.add_theme_color_override("font_shadow_color", UITheme.LABEL_SHADOW_HEAVY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	header.add_child(title)

	var close_btn := UITheme.action_button(Strings.get_string("log_modal.close"))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(close_btn)
	outer.add_child(header)
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var log_label := RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key: String in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		log_label.add_theme_font_size_override(key, UITheme.FONT_SIZE_BODY)
	log_label.add_theme_color_override("default_color", UITheme.TEXT)
	log_label.add_theme_constant_override("paragraph_separation", 4)
	log_label.add_theme_constant_override("line_separation", 0)

	if entries.is_empty():
		log_label.text = "[color=#%s]%s[/color]" % [UITheme.TEXT_DIM_HEX, Strings.get_string("log_modal.empty")]
	else:
		log_label.text = "\n".join(PackedStringArray(entries))

	scroll.add_child(log_label)
	outer.add_child(scroll)

	close_btn.pressed.connect(_close)
	backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)

	var scroll_bottom := func() -> void:
		if is_instance_valid(scroll):
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	scroll_bottom.call_deferred()


func _enter_tree() -> void:
	LogModal._open_count += 1


func _exit_tree() -> void:
	LogModal._open_count -= 1
	if LogModal._open_count < 0:
		LogModal._open_count = 0


func _input(event: InputEvent) -> void:
	# Esc closes the modal and swallows the event so dialogue_cloud /
	# world_loader don't also react to it.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	queue_free()
