extends CanvasLayer
## World log — right sidebar (Ctrl+L) under the minimap: the latest timestamped, colour-coded events that fit whole.

const MAX_ENTRIES := 20
const SHOWN_ENTRIES := 4
const MARGIN := 8
const WIDTH := 232
const BOTTOM_GAP := 40
const PAD_X := 8
const PAD_Y := 6

## Screen px from the top where the sidebar starts (world_loader puts it under the minimap).
var top_offset: float = MARGIN
var panel: PanelContainer
var log_label: RichTextLabel
var entries: Array[String] = []
var _start_time: float = 0.0
var _visible := false


func _ready() -> void:
	layer = 5
	_start_time = Time.get_ticks_msec() / 1000.0
	_build_ui()
	panel.visible = _visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L and event.ctrl_pressed:
			set_open(not _visible)
			get_viewport().set_input_as_handled()


## Shows or hides the sidebar.
func set_open(open: bool) -> void:
	_visible = open
	if panel:
		panel.visible = open
		if open:
			_render()


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "WorldLog"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -(MARGIN + WIDTH)
	panel.offset_right = -MARGIN
	panel.offset_top = top_offset
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", UITheme.kit_style("panel_dim", PAD_X, PAD_Y))
	panel.clip_contents = true

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 3)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = Strings.get_string("narration.title").to_upper()
	UITheme.ensure_fonts_loaded()
	if UITheme.FONT_TITLE != null:
		title.add_theme_font_override("font", UITheme.FONT_TITLE)
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var full_btn := UITheme.prominent_button(Strings.get_string("narration.view_full_log"))
	full_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	full_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	full_btn.pressed.connect(_on_view_full_pressed)
	title_row.add_child(full_btn)
	content_vbox.add_child(title_row)
	content_vbox.add_child(HSeparator.new())

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key: String in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		log_label.add_theme_font_size_override(key, UITheme.FONT_SIZE_BODY)
	log_label.add_theme_color_override("default_color", UITheme.TEXT_DIM)
	log_label.add_theme_constant_override("paragraph_separation", 3)
	log_label.add_theme_constant_override("line_separation", 0)

	content_vbox.add_child(log_label)
	panel.add_child(content_vbox)
	add_child(panel)


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


## Shows the newest entries that fit whole between top_offset and the bottom gap, and sizes the panel to them.
func _render() -> void:
	if not panel.is_inside_tree():
		return
	var inner_w: float = WIDTH - _hpad()
	log_label.custom_minimum_size.x = inner_w
	log_label.size.x = inner_w
	var room: float = panel.get_viewport_rect().size.y - BOTTOM_GAP - top_offset
	var n: int = mini(SHOWN_ENTRIES, entries.size())
	while true:
		log_label.text = "\n".join(PackedStringArray(entries.slice(entries.size() - n)))
		panel.offset_bottom = panel.offset_top
		panel.reset_size()
		if panel.size.y <= room or n <= 1:
			break
		n -= 1
	panel.offset_bottom = panel.offset_top + panel.size.y


func _hpad() -> float:
	var sb := panel.get_theme_stylebox("panel")
	return sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb else 0.0


func _on_view_full_pressed() -> void:
	LogModal.show_entries(get_tree().root, Strings.get_string("log_modal.title_world"), entries)
