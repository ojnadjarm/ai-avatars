extends RefCounted
## HUD layout in both booted worlds: banner on screen, minimap labels clear and crisp, night map dark, prompt clear of the name, log whole.

const WORLDS := ["magic_forest", "darkwood"]
const MinimapScript := preload("res://scripts/hud/minimap.gd")

var failure_message: String = ""
var _luma: Dictionary = {}


func run() -> bool:
	var was_offline: bool = WorldBuilder.offline
	WorldBuilder.offline = true
	var ok := true
	for id: String in WORLDS:
		if not _check_world(id):
			ok = false
			break
	WorldBuilder.offline = was_offline
	if ok and not (_luma["darkwood"] < 0.25 and _luma["darkwood"] < _luma["magic_forest"] * 0.6):
		return _fail("night minimap not dark: darkwood luma %.2f vs magic_forest %.2f" % [_luma["darkwood"], _luma["magic_forest"]])
	return ok


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _check_world(id: String) -> bool:
	var host := Node2D.new()
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene else tree.root).add_child(host)
	var loader := (load("res://scenes/world.tscn") as PackedScene).instantiate() as WorldLoader
	loader.room_config_path = "res://assets/worlds/%s/world.json" % id
	host.add_child(loader)
	var view := Rect2(Vector2.ZERO, loader.get_viewport().get_visible_rect().size)
	var ok := _check_banner(id, loader, view) and _check_minimap(id, loader) and _check_prompt(id, loader) \
			and _check_log(id, loader, view)
	host.free()
	return ok


func _check_banner(id: String, loader: WorldLoader, view: Rect2) -> bool:
	var b: CanvasLayer = loader.zone_banner
	var slide: float = b.SLIDE
	var hold: float = b.HOLD
	for z: Dictionary in MinimapScript.read_zones(loader._world_scene):
		for e: float in [0.02, slide * 0.5, slide + 0.1, slide * 2.0 + hold - 0.02]:
			b.present(z["name"], e)
			var r: Rect2 = b.plate_rect()
			if (b.shown() == 1.0 and not r.has_area()) or (r.has_area() and not view.encloses(r)):
				return _fail("%s: banner '%s' at %.2f s rect %s outside %s" % [id, z["name"], e, r, view])
	return true


func _check_minimap(id: String, loader: WorldLoader) -> bool:
	var m: CanvasLayer = loader.minimap
	if m.map_texture_rect().texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		return _fail("%s: minimap texture filter is not NEAREST" % id)
	var img: Image = m.map_texture_rect().texture.get_image()
	var sum := 0.0
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y).get_luminance()
	_luma[id] = sum / float(img.get_width() * img.get_height())
	var player: Node2D = loader.player
	var cam := player.get_node("Camera2D") as Camera2D
	var was := player.global_position
	for z: Dictionary in m.zones:
		player.global_position = (z["rect"] as Rect2).get_center()
		cam.reset_smoothing()
		cam.force_update_scroll()
		var labels: Array[Dictionary] = m.label_layout()
		if not labels.any(func(l: Dictionary) -> bool: return l["name"] == z["name"]):
			return _fail("%s: no minimap label for the player's zone %s" % [id, z["name"]])
		var pb: Rect2 = m.player_box()
		var vf: Rect2 = m.view_box()
		if not vf.has_area():
			return _fail("%s: no minimap view frame with the player in %s" % [id, z["name"]])
		for i in labels.size():
			var a: Rect2 = labels[i]["rect"]
			if a.intersects(pb):
				return _fail("%s: label %s covers the player marker in %s" % [id, labels[i]["name"], z["name"]])
			if MinimapScript.crosses_frame(a, vf):
				return _fail("%s: label %s %s crosses the view frame %s in %s" % [id, labels[i]["name"], a, vf, z["name"]])
			for j in range(i + 1, labels.size()):
				if a.intersects(labels[j]["rect"]):
					return _fail("%s: labels %s and %s overlap" % [id, labels[i]["name"], labels[j]["name"]])
	player.global_position = was
	return true


func _check_prompt(id: String, loader: WorldLoader) -> bool:
	var agent: Agent = null
	for c: Node in loader.agents_container.get_children():
		if c is Agent:
			agent = c
			break
	if agent == null:
		return _fail("%s: no agent" % id)
	var label := agent.get_node("NameLabel") as Control
	var cam := loader.player.get_node("Camera2D") as Camera2D
	var vp := loader.get_viewport()
	var prompt: CanvasLayer = loader.action_prompt
	loader.player.nearby_agent = agent
	var size := Vector2(loader.room_bounds.size)
	for z: float in PixelZoom.levels(3, PixelZoom.BASE_VIEW, size, 2.0):
		cam.zoom = Vector2(z, z)
		agent.call("_update_label_scale")
		vp.canvas_transform = Transform2D(0.0, Vector2(z, z), 0.0, PixelZoom.BASE_VIEW * 0.5 - agent.global_position * z)
		prompt.call("_process", 0.0)
		var pr := Rect2(prompt.panel.position, prompt.panel.size)
		var lr: Rect2 = vp.canvas_transform * label.get_global_rect()
		if not prompt.panel.visible or pr.intersects(lr):
			return _fail("%s zoom %.2f: prompt %s collides with name label %s" % [id, z, pr, lr])
	loader.player.nearby_agent = null
	return true


func _check_log(id: String, loader: WorldLoader, view: Rect2) -> bool:
	var log: CanvasLayer = loader.narration_log
	for i in 20:
		log.add_entry("Entry %d: Grok says the bridge planks by the old mill are loose again tonight." % i, "dialogue")
	log.set_open(true)
	var r: Rect2 = log.panel.get_global_rect()
	if not view.encloses(r) or r.end.y > view.size.y - log.BOTTOM_GAP:
		return _fail("%s: world log %s not inside %s above the bottom gap" % [id, r, view])
	if r.position.y < loader.minimap.bottom() or not is_equal_approx(r.size.x, log.WIDTH):
		return _fail("%s: world log %s overlaps the minimap or is wider than %d" % [id, r, log.WIDTH])
	for c: Node in [log.panel] + log.panel.find_children("*", "Container", true, false):
		c.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var text: RichTextLabel = log.log_label
	if text.get_line_count() < 2:
		return _fail("%s: world log shows %d lines" % [id, text.get_line_count()])
	if not log_cut(r, text).is_empty():
		return _fail("%s: world log %s" % [id, log_cut(r, text)])
	return true


## Why the log text is cut by its panel ("" when every line shows whole).
static func log_cut(panel_rect: Rect2, text: RichTextLabel) -> String:
	var tr := text.get_global_rect()
	if not panel_rect.encloses(tr):
		return "text %s clipped by panel %s" % [tr, panel_rect]
	if text.get_content_height() > tr.size.y + 0.5:
		return "text content %d px cut to %d px" % [text.get_content_height(), tr.size.y]
	return ""
