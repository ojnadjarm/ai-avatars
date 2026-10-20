extends Node2D
## World root: builds the lit, animated pixel-scene art from <world dir>/art/built.json under the game camera.

const Tex := preload("res://scripts/world_art/art_textures.gd")
const Anim := preload("res://scripts/world_art/art_animator.gd")
const Layers := preload("res://scripts/world_art/art_layers.gd")
const Lights := preload("res://scripts/world_art/art_lights.gd")
const Atmos := preload("res://scripts/world_art/art_atmosphere.gd")
const Particles := preload("res://scripts/world_art/art_particles.gd")
const GLOW_LAYER := 1
const FX_Z := 12
## Ground drawn as tiles so each tile only runs the lights that reach it (one full-map sprite runs every light in view per pixel).
const GROUND_TILE := 96

var sc: Dictionary = {}
var anim: RefCounted
var _ysort: Node2D
var _t := 0.0


func _ready() -> void:
	var art := get_node("Art") as Node2D
	var g := Layers.make(art)
	_ysort = g["ysort"]
	var dir := scene_file_path.get_base_dir().path_join("art")
	if not FileAccess.file_exists(dir.path_join("built.json")):
		push_warning("[world_art] no built.json in %s" % dir)
		return
	sc = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("built.json")))
	var tex := Tex.new(dir)
	var amb := Tex.color8(sc["ambient"])
	anim = Anim.new(float(sc["period"]))
	_background(tex)
	var sprites := Layers.fill(g, sc, tex, amb, anim)
	var glow := CanvasLayer.new()
	glow.name = "Glow"
	glow.layer = GLOW_LAYER
	glow.follow_viewport_enabled = true
	add_child(glow)
	var lights := Node2D.new()
	lights.name = "Lights"
	art.add_child(lights)
	Lights.build(self, lights, glow, sc, tex, anim, amb)
	Atmos.build(self, glow, sc, tex)
	var fx := Node2D.new()
	fx.name = "Particles"
	fx.z_index = FX_Z
	art.add_child(fx)
	var emitters := Particles.build(fx, glow, sc, tex, anim)
	print("[world_art] sprites %d lights %d emitters %d culled %d day %s" % [sprites, sc["lights"].size(), emitters,
		anim.culled.size(), sc.get("day", false)])


## The y-sorted node the player and agents join so they sort against trees and props.
func ysort_root() -> Node2D:
	return _ysort


## Visible world rect under the current camera.
func view_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()


func _background(tex) -> void:
	var bg := get_node_or_null("Background") as Sprite2D
	if bg == null:
		return
	for n in sc["nodes"]:
		if n["layer"] == "ground":
			bg.texture = tex.canvas(n["files"])
			bg.position = Vector2(n["x"], n["y"])
	if bg.z_index == 0:
		bg.z_index = -10
	if bg.texture == null:
		return
	var tiles := Node2D.new()
	tiles.name = "GroundTiles"
	tiles.z_index = bg.z_index
	tiles.position = bg.position
	add_child(tiles)
	move_child(tiles, bg.get_index())
	var size := bg.texture.get_size()
	for y in range(0, int(size.y), GROUND_TILE):
		for x in range(0, int(size.x), GROUND_TILE):
			var t := Sprite2D.new()
			t.texture = bg.texture
			t.centered = false
			t.region_enabled = true
			t.region_rect = Rect2(x, y, mini(GROUND_TILE, int(size.x) - x), mini(GROUND_TILE, int(size.y) - y))
			t.position = Vector2(x, y)
			tiles.add_child(t)
	bg.visible = false


func _process(delta: float) -> void:
	if anim == null:
		return
	_t += delta
	anim.update(_t, view_rect())
