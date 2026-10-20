extends CanvasLayer
## Main menu: the T704 title hosted in an HDR SubViewport, listing the worlds
## bundled under assets/worlds/<id>/ (world.tscn + world.json sidecar pairs).

const WORLD_SCENE := "res://scenes/world.tscn"
const SETTINGS_SCENE := "res://scenes/settings_screen.tscn"
const WORLDS_ROOT := "res://assets/worlds/"

var rooms: Array = []

@onready var title: Node = $Screen/View/Title
@onready var screen: SubViewportContainer = $Screen
@onready var view: SubViewport = $Screen/View


func _ready() -> void:
	_scan_rooms()
	_build_menu()
	_fit()
	get_tree().root.size_changed.connect(_fit)


## Renders the 640x360 title at the window's integer scale so its glow and sub-pixel parallax match T704.
func _fit() -> void:
	var win: Vector2i = get_tree().root.size
	var k: int = maxi(1, mini(win.x / 640, win.y / 360))
	view.size = Vector2i(640, 360) * k
	screen.size = Vector2(640, 360) * k
	screen.scale = Vector2.ONE / k


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


func _build_menu() -> void:
	var names: Array = []
	for room: Dictionary in rooms:
		names.append(room["name"])
	names.append(Strings.get_string("settings.title"))
	names.append("Quit")
	var menu: Node = title.menu
	menu.set_items(names)
	menu.set_online_text("%d AGENTS CONFIGURED" % GameState.agents.size())
	menu.confirmed.connect(_on_confirmed)


# ── Navigation ──


func _on_confirmed(index: int) -> void:
	if index < rooms.size():
		_on_room_selected(rooms[index]["path"])
	elif index == rooms.size():
		_on_settings_pressed()
	else:
		get_tree().quit()


func _on_room_selected(path: String) -> void:
	print("[selector] Selected: %s" % path)
	GameState.room_config_path = path
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)
