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

const PANEL_MIN := Vector2(780, 560)
const TITLE_FONT := 48
const BODY_FONT := 32

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
	panel.add_theme_stylebox_override("panel", UITheme.framed_panel_style())
	panel.custom_minimum_size = PANEL_MIN
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = title_text.to_upper()
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := UITheme.small_menu_button(Strings.get_string("log_modal.close"))
	header.add_child(close_btn)
	outer.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", UITheme.line_style())
	outer.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(PANEL_MIN.x - 40, PANEL_MIN.y - 120)

	var log_label := RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override("normal_font_size", BODY_FONT)
	log_label.add_theme_font_size_override("bold_font_size", BODY_FONT)
	log_label.add_theme_font_size_override("italics_font_size", BODY_FONT)
	log_label.add_theme_color_override("default_color", UITheme.TEXT)

	if entries.is_empty():
		log_label.text = "[color=#%s]%s[/color]" % [UITheme.TEXT_DIM_HEX, Strings.get_string("log_modal.empty")]
	else:
		log_label.text = "\n".join(PackedStringArray(entries))

	scroll.add_child(log_label)
	outer.add_child(scroll)

	UITheme.attach_arcane_corners(panel)

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
