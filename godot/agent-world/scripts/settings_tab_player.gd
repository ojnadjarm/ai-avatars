class_name SettingsTabPlayer
extends RefCounted
## Player settings tab — avatar picker grid + content folder paths.

const PORTRAIT_SIZE := Vector2(64, 64)
const GRID_COLUMNS := 5
const FIELD_LABEL_WIDTH := 130

var owner_node: CanvasLayer
var available_sprites: Array = []

var _player_cells: Array = []  # [{container, style}]
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

func _build_avatar_section(parent: VBoxContainer) -> void:
	parent.add_child(SettingsForm.section_header("settings.player_avatar"))
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for i in range(available_sprites.size()):
		var sprite_info: Dictionary = available_sprites[i]
		grid.add_child(_make_avatar_cell(sprite_info, i))
		if sprite_info["filename"] == GameState.player_sprite:
			_player_selected_idx = i
			_highlight_cell(i, true)
	parent.add_child(grid)


func _make_avatar_cell(sprite_info: Dictionary, idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = UITheme.CELL_BG
	normal_style.set_corner_radius_all(UITheme.CORNER)
	normal_style.set_border_width_all(UITheme.BORDER_W)
	normal_style.border_color = UITheme.BORDER
	normal_style.content_margin_left = 4
	normal_style.content_margin_right = 4
	normal_style.content_margin_top = 4
	normal_style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", normal_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var portrait: TextureRect = GameState.load_portrait_for_sprite(sprite_info, PORTRAIT_SIZE)
	vbox.add_child(portrait)

	var name_label := Label.new()
	name_label.text = sprite_info["name"]
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	panel.add_child(vbox)
	panel.gui_input.connect(_on_cell_input.bind(idx))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_player_cells.append({"container": panel, "style": normal_style})
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
	var style: StyleBoxFlat = _player_cells[idx]["style"]
	style.border_color = UITheme.ACCENT if selected else UITheme.BORDER


# ── Content paths ──

func _build_paths_section(parent: VBoxContainer) -> void:
	parent.add_child(SettingsForm.section_header("settings.content_paths"))
	var paths_vbox := VBoxContainer.new()
	paths_vbox.add_theme_constant_override("separation", 8)

	content_folder_field = _make_path_row(paths_vbox, "settings.content_folder", GameState.content_folder)
	characters_folder_field = _make_path_row(paths_vbox, "settings.characters_folder", GameState.characters_folder)

	var hint := Label.new()
	hint.text = Strings.get_string("settings.path_hint")
	hint.add_theme_font_size_override("font_size", 32)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paths_vbox.add_child(hint)

	parent.add_child(paths_vbox)


func _make_path_row(parent: VBoxContainer, label_key: String, current_value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = Strings.get_string(label_key).to_upper()
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	lbl.custom_minimum_size = Vector2(FIELD_LABEL_WIDTH, 0)
	row.add_child(lbl)

	var field := LineEdit.new()
	field.text = current_value
	field.add_theme_font_size_override("font_size", 32)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.placeholder_text = Strings.get_string("settings.placeholder.path")
	row.add_child(field)

	var browse := UITheme.action_button(Strings.get_string("settings.browse"))
	browse.size_flags_horizontal = Control.SIZE_SHRINK_END
	browse.custom_minimum_size = Vector2(90, 28)
	browse.pressed.connect(_open_dir_dialog.bind(field))
	row.add_child(browse)

	parent.add_child(row)
	return field


func _open_dir_dialog(target_field: LineEdit) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = Strings.get_string("settings.browse").to_upper()
	dialog.min_size = Vector2i(600, 400)
	if target_field.text != "":
		dialog.current_dir = target_field.text
	dialog.dir_selected.connect(func(dir: String): target_field.text = dir)
	owner_node.add_child(dialog)
	dialog.popup_centered()
