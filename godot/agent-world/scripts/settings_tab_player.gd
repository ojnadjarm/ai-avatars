class_name SettingsTabPlayer
extends RefCounted
## Player settings tab — avatar picker grid + content folder paths.

const PORTRAIT_SIZE := Vector2(96, 96)
const GRID_COLUMNS := 4
const FIELD_LABEL_WIDTH := SettingsForm.LABEL_WIDTH
const BROWSE_W := 64

var owner_node: CanvasLayer
var available_sprites: Array = []

var _player_cells: Array = []  # [{container, label}]
var _player_selected_idx: int = -1

var content_folder_field: LineEdit
var characters_folder_field: LineEdit


func _init(screen: CanvasLayer, sprites: Array) -> void:
	owner_node = screen
	available_sprites = sprites


func build(parent: VBoxContainer) -> void:
	_build_avatar_section(parent)
	parent.add_child(HSeparator.new())
	_build_paths_section(parent)


func commit() -> void:
	GameState.content_folder = content_folder_field.text.strip_edges()
	GameState.characters_folder = characters_folder_field.text.strip_edges()


# ── Avatar grid ──

## strings.json "avatar.<id>" when present, else the sheet id.
static func _display_name(sprite_id: String) -> String:
	var key := "avatar." + sprite_id
	var shown := Strings.get_string(key)
	return sprite_id if shown == key else shown


func _build_avatar_section(parent: VBoxContainer) -> void:
	parent.add_child(SettingsForm.section_header("settings.player_avatar"))
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in range(available_sprites.size()):
		var sprite_info: Dictionary = available_sprites[i]
		grid.add_child(_make_avatar_cell(sprite_info, i))
		if sprite_info["filename"] == GameState.player_sprite:
			_player_selected_idx = i
			_highlight_cell(i, true)
	parent.add_child(grid)


func _make_avatar_cell(sprite_info: Dictionary, idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.kit_style("panel_dim", 4, 4))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var portrait: TextureRect = GameState.load_portrait_for_sprite(sprite_info, PORTRAIT_SIZE)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(portrait)

	var name_label := Label.new()
	name_label.text = _display_name(String(sprite_info["name"])).to_upper()
	UITheme.ensure_fonts_loaded()
	name_label.add_theme_font_override("font", UITheme.FONT_HUD)
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	name_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(PORTRAIT_SIZE.x, 0)
	vbox.add_child(name_label)

	panel.add_child(vbox)
	panel.gui_input.connect(_on_cell_input.bind(idx))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_player_cells.append({"container": panel, "label": name_label})
	return panel


func _on_cell_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_avatar(idx)


func _select_avatar(idx: int) -> void:
	if _player_selected_idx >= 0:
		_highlight_cell(_player_selected_idx, false)
	_player_selected_idx = idx
	_highlight_cell(idx, true)
	GameState.player_sprite = available_sprites[idx]["filename"]


func _highlight_cell(idx: int, selected: bool) -> void:
	if idx < 0 or idx >= _player_cells.size():
		return
	var cell: Dictionary = _player_cells[idx]
	(cell["container"] as PanelContainer).add_theme_stylebox_override("panel", UITheme.kit_style("portrait_frame" if selected else "panel_dim", 4, 4))
	(cell["label"] as Label).add_theme_color_override("font_color", UITheme.ACCENT if selected else UITheme.TEXT_DIM)


# ── Content paths ──

func _build_paths_section(parent: VBoxContainer) -> void:
	parent.add_child(SettingsForm.section_header("settings.content_paths"))
	var paths_vbox := VBoxContainer.new()
	paths_vbox.add_theme_constant_override("separation", 4)

	content_folder_field = _make_path_row(paths_vbox, "settings.content_folder", GameState.content_folder)
	characters_folder_field = _make_path_row(paths_vbox, "settings.characters_folder", GameState.characters_folder)

	paths_vbox.add_child(SettingsForm.hint(Strings.get_string("settings.path_hint")))

	parent.add_child(paths_vbox)


func _make_path_row(parent: VBoxContainer, label_key: String, current_value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SettingsForm.ROW_SEP)

	var lbl := SettingsForm.form_label(label_key)
	lbl.custom_minimum_size = Vector2(FIELD_LABEL_WIDTH, 0)
	row.add_child(lbl)

	var field := LineEdit.new()
	field.text = current_value
	field.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.placeholder_text = Strings.get_string("settings.placeholder.path")
	row.add_child(field)

	var browse := UITheme.action_button(Strings.get_string("settings.browse"))
	browse.size_flags_horizontal = Control.SIZE_SHRINK_END
	browse.custom_minimum_size = Vector2(BROWSE_W, 0)
	browse.pressed.connect(_open_dir_dialog.bind(field))
	row.add_child(browse)

	parent.add_child(row)
	return field


func _open_dir_dialog(target_field: LineEdit) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = Strings.get_string("settings.browse").to_upper()
	dialog.min_size = Vector2i(560, 300)
	if target_field.text != "":
		dialog.current_dir = target_field.text
	dialog.dir_selected.connect(func(dir: String): target_field.text = dir)
	owner_node.add_child(dialog)
	dialog.popup_centered()
