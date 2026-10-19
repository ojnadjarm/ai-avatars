extends CanvasLayer
## Room selector — lists the scene-based worlds bundled under
## assets/worlds/<id>/ (world.tscn + world.json sidecar pairs).

const WORLD_SCENE := "res://scenes/world.tscn"
const SETTINGS_SCENE := "res://scenes/settings_screen.tscn"
const WORLDS_ROOT := "res://assets/worlds/"

var rooms: Array = []


func _ready() -> void:
	_scan_rooms()
	_build_ui()


func _scan_rooms() -> void:
	rooms.clear()
	var seen_ids: Dictionary = {}
	for dir_name: String in DirAccess.get_directories_at(WORLDS_ROOT):
		var sidecar_path: String = WORLDS_ROOT + dir_name + "/world.json"
		if not FileAccess.file_exists(sidecar_path):
			continue
		var data: Dictionary = GameState.load_json(sidecar_path)
		if data.is_empty():
			continue
		var room_id: String = str(data.get("id", dir_name))
		if seen_ids.has(room_id):
			continue
		seen_ids[room_id] = true
		rooms.append({
			"path": sidecar_path,
			"id": room_id,
			"name": str(data.get("name", dir_name)),
		})
	print("[selector] Found %d rooms" % rooms.size())


func _build_ui() -> void:
	UITheme.wallpaper_background(self)

	# Center layout (shifted down so the wallpaper title stays visible)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.offset_top = 150
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.framed_panel_style())
	panel.custom_minimum_size = Vector2(420, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)

	# Title
	var title := Label.new()
	title.text = Strings.get_string("room_selector.title").to_upper()
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	if rooms.is_empty():
		var empty := Label.new()
		empty.text = Strings.get_string("room_selector.no_rooms", {"dir": Strings.get_string("default.worlds_dir")})
		empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty)
	else:
		for room: Dictionary in rooms:
			var play_btn := UITheme.primary_button(room["name"])
			play_btn.pressed.connect(_on_room_selected.bind(room["path"]))
			vbox.add_child(play_btn)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", UITheme.line_style())
	vbox.add_child(sep)

	# Settings button — full width so the menu reads as one vertical column.
	var settings_btn := UITheme.primary_button(Strings.get_string("settings.title"))
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)

	panel.add_child(vbox)
	center.add_child(panel)
	UITheme.attach_arcane_corners(panel)


# ── Navigation ──


func _on_room_selected(path: String) -> void:
	print("[selector] Selected: %s" % path)
	GameState.room_config_path = path
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)
