extends RefCounted
## Settings screen backdrop is the live title scene (no title menu) and moves over 1 s.

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")

var failure_message: String = ""


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	var screen: Node = load("res://scenes/settings_screen.tscn").instantiate()
	host.add_child(screen)
	var ok := _check(screen)
	host.remove_child(screen)
	screen.free()
	return ok


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _check(screen: Node) -> bool:
	var backdrops := screen.find_children("*", "SubViewportContainer", true, false).filter(func(n: Node) -> bool: return n.get_script() == MenuBackdrop)
	if backdrops.size() != 1:
		return _fail("expected 1 menu_backdrop.gd, found %d" % backdrops.size())
	var bd: SubViewportContainer = backdrops[0]
	if bd.get("view") == null or bd.get("title") == null or bd.get("title").get_parent() != bd.get("view"):
		return _fail("title scene not hosted in the backdrop SubViewport")
	if screen.find_children("*", "TextureRect", true, false).any(func(n: Node) -> bool: return n.get_parent() == screen):
		return _fail("static backdrop TextureRect still present")
	if bd.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return _fail("backdrop takes mouse input")
	var menu: Node = (bd.get("title") as Node).get("menu")
	if (menu.get_parent() as CanvasLayer).visible or menu.process_mode != Node.PROCESS_MODE_DISABLED:
		return _fail("title menu still visible or active behind the settings screen")
	var planes: Array = (bd.get("title") as Node).get("planes")
	if planes.is_empty():
		return _fail("title built no parallax planes")
	var before: Array = planes.map(func(p: Array) -> Vector2: return p[0].position)
	(bd.get("title") as Node).call("_process", 1.0)
	var moved := 0
	for i in planes.size():
		if planes[i][0].position != before[i]:
			moved += 1
	if moved == 0:
		return _fail("no title plane moved after 1 s")
	return true
