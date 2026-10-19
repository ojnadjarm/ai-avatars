extends CanvasLayer
## World log — right sidebar with timestamped, color-coded events.

const MAX_ENTRIES := 20

var panel: PanelContainer
var scroll: ScrollContainer
var log_label: RichTextLabel
var entries: Array[String] = []
var _start_time: float = 0.0
var _visible := false
var _content_margin_x: int = 16
var _scrollbar_reserve: int = 16


func _ready() -> void:
	layer = 5
	_start_time = Time.get_ticks_msec() / 1000.0
	_build_ui()
	panel.visible = _visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L and event.ctrl_pressed:
			_visible = not _visible
			panel.visible = _visible
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	panel = PanelContainer.new()
	# Anchor the panel to the right edge with a fixed pixel margin so the gap
	# stays consistent across viewport sizes. Left is pulled back a fixed
	# distance, giving a stable panel width that doesn't collapse on small
	# windows or bleed wider on large ones.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.02
	panel.anchor_bottom = 0.48
	panel.offset_left = -420.0
	panel.offset_right = -16.0

	# Reads as "history / read-only" and visually recedes behind active UI
	# like the dialogue cloud (LOG_BG lives in UITheme).
	var style := UITheme.panel_style(UITheme.LOG_BG, UITheme.BORDER)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	panel.clip_contents = true

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 4)

	# Title row: title + View Full Log button
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = Strings.get_string("narration.title").to_upper()
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var full_btn := UITheme.small_menu_button(Strings.get_string("narration.view_full_log"))
	full_btn.pressed.connect(_on_view_full_pressed)
	title_row.add_child(full_btn)

	content_vbox.add_child(title_row)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	sep.add_theme_stylebox_override("separator", UITheme.line_style())
	content_vbox.add_child(sep)

	# Scrollable log. Horizontal scroll disabled — content must wrap within the
	# sidebar; otherwise long entries run off the right edge.
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, 0)
	log_label.add_theme_font_size_override("normal_font_size", 32)
	log_label.add_theme_font_size_override("bold_font_size", 32)
	log_label.add_theme_font_size_override("italics_font_size", 32)
	log_label.add_theme_color_override("default_color", UITheme.TEXT_DIM)

	scroll.add_child(log_label)
	content_vbox.add_child(scroll)
	panel.add_child(content_vbox)
	add_child(panel)

	# Clamp the log label's width to the panel's inner width each time the
	# sidebar resizes. Without this, RichTextLabel inside a ScrollContainer
	# reports its intrinsic (unwrapped) width as its minimum, and long lines
	# can push past the right edge before the outer panel clips them.
	_content_margin_x = style.content_margin_left + style.content_margin_right
	# Panel is anchored to the viewport via CanvasLayer; resize on viewport
	# change rather than on panel.resized (which doesn't always fire for
	# anchor-only resizes in a CanvasLayer).
	panel.resized.connect(_clamp_label_width)
	get_viewport().size_changed.connect(_clamp_label_width)
	_clamp_label_width.call_deferred()


func _clamp_label_width() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(log_label):
		return
	var available: float = panel.size.x - float(_content_margin_x) - float(_scrollbar_reserve)
	if available < 40.0:
		available = 40.0
	log_label.custom_minimum_size.x = available


func add_entry(text: String, type: String = "event") -> void:
	var color: String = UITheme.narration_color(type)
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _start_time
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60

	var formatted: String = "[color=#%s]%d:%02d[/color]  [color=#%s]%s[/color]" % [UITheme.TIMESTAMP_HEX, mins, secs, color, text]
	entries.append(formatted)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	_render()


func _render() -> void:
	log_label.text = "\n".join(PackedStringArray(entries))
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	if scroll:
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value


func _on_view_full_pressed() -> void:
	LogModal.show_entries(get_tree().root, Strings.get_string("log_modal.title_world"), entries)
