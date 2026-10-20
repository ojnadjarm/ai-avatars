extends Node2D
## World preview: `-- --world res://DIR [--at x,y] [--zoom k | --fit] [--avatars [--player-at x,y] [--no-rim] [--hide-player]]`; k = screen px per art px.

const SUFFIXES := ["_n", "_e", "_g", "_portrait", "_portrait_n"]
const AVATAR_GAP := 40.0

var world: Node2D
var cam: Camera2D


func _ready() -> void:
	var opt := _args()
	var dir: String = opt.get("world", "")
	if dir == "" or not ResourceLoader.exists(dir.path_join("world.tscn")):
		push_error("[preview] usage: -- --world res://DIR [--at x,y] [--zoom k | --fit] [--avatars]")
		get_tree().quit(2)
		return
	world = (load(dir.path_join("world.tscn")) as PackedScene).instantiate() as Node2D
	add_child(world)
	var bounds := _bounds()
	cam = Camera2D.new()
	add_child(cam)
	cam.position = bounds.get_center()
	if opt.has("at"):
		var xy: PackedStringArray = opt["at"].split(",")
		cam.position = Vector2(float(xy[0]), float(xy[1]))
	var screen := Vector2(get_window().size)
	var k := float(opt.get("zoom", 3.0))
	if opt.has("fit"):
		var f := minf(screen.x / bounds.size.x, screen.y / bounds.size.y)
		k = floorf(f) if f >= 1.0 else f
	cam.zoom = Vector2.ONE * k * get_viewport().get_visible_rect().size.y / screen.y
	cam.make_current()
	if opt.has("avatars"):
		_avatars(opt)
	print("[preview] %s bounds %s zoom k=%s at %s" % [dir, bounds, k, cam.position])


func _args() -> Dictionary:
	var a := OS.get_cmdline_user_args()
	var opt := {}
	var i := 0
	while i < a.size():
		var key := a[i].trim_prefix("--")
		if i + 1 < a.size() and not a[i + 1].begins_with("--"):
			opt[key] = a[i + 1]
			i += 2
		else:
			opt[key] = true
			i += 1
	return opt


func _bounds() -> Rect2:
	var bg := world.get_node_or_null("Background") as Sprite2D
	if bg and bg.texture:
		return Rect2(bg.position, bg.texture.get_size())
	return Rect2(0, 0, 640, 360)


## Every character sheet in assets/characters, loaded as agent_spawner.gd does; player_default as the real player.gd node (its own night rim) at the player spawn.
func _avatars(opt: Dictionary) -> void:
	var root := "res://assets/characters"
	if not DirAccess.dir_exists_absolute(root):
		return
	var sheets: Array[String] = []
	for f in DirAccess.get_files_at(root):
		if f.get_extension() == "png" and not SUFFIXES.any(func(s): return f.get_basename().ends_with(s)):
			sheets.append(f)
	sheets.sort()
	var parent: Node2D = world.ysort_root() if world.has_method("ysort_root") and world.ysort_root() else world
	var player := world.get_node_or_null("SpawnPoints/Player") as Marker2D
	var agents := world.get_node_or_null("SpawnPoints/Agents") as Marker2D
	var spot: Vector2 = player.position if player else cam.position
	if opt.has("player-at"):
		var xy: PackedStringArray = opt["player-at"].split(",")
		spot = Vector2(float(xy[0]), float(xy[1]))
	var npc := 0
	for i in sheets.size():
		var is_player := sheets[i].get_basename() == "player_default"
		if is_player and opt.has("hide-player"):
			continue
		if is_player:
			_player(parent, root.path_join(sheets[i]), spot, opt.has("no-rim"))
			continue
		var spr := AnimatedSprite2D.new()
		spr.name = sheets[i].get_basename()
		spr.set_script(load("res://scripts/character_sprite.gd"))
		parent.add_child(spr)
		spr.load_spritesheet(ProjectSettings.globalize_path(root.path_join(sheets[i])))
		var base := agents.position if agents else cam.position
		spr.position = base + Vector2((npc - sheets.size() * 0.5) * AVATAR_GAP, 0)
		npc += 1


## The player exactly as world_loader builds it (player.gd sprite, rim and fill), frozen in place.
func _player(parent: Node2D, sheet: String, spot: Vector2, no_rim: bool) -> void:
	var body := CharacterBody2D.new()
	body.name = "Player"
	body.set_script(load("res://scripts/player.gd"))
	body.sprite_path = ProjectSettings.globalize_path(sheet)
	body.display_height = GameState.get_float("character_height", 140.0)
	body.position = spot
	parent.add_child(body)
	body.set_physics_process(false)
	if no_rim:
		body.char_sprite.night_rim = false
		body.char_sprite.load_spritesheet(body.sprite_path)
