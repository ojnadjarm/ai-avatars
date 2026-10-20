extends SubViewportContainer
## The live T704 title scene without its menu, hosted in an HDR SubViewport as a menu background.

const TITLE_SCENE := preload("res://scenes/title/title.tscn")
const PRESENT := preload("res://shaders/title/present.gdshader")

var view: SubViewport
var title: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PRESENT
	material = mat
	view = SubViewport.new()
	view.own_world_3d = true
	view.handle_input_locally = false
	view.gui_disable_input = true
	view.use_hdr_2d = true
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	view.size_2d_override = Vector2i(640, 360)
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	title = TITLE_SCENE.instantiate()
	view.add_child(title)
	var menu: Node = title.get("menu")
	menu.process_mode = Node.PROCESS_MODE_DISABLED
	(menu.get_parent() as CanvasLayer).visible = false
	_fit()
	get_tree().root.size_changed.connect(_fit)


## Renders at the window's integer scale so glow and sub-pixel parallax match the title screen.
func _fit() -> void:
	var win: Vector2i = get_tree().root.size
	var k: int = maxi(1, mini(win.x / 640, win.y / 360))
	view.size = Vector2i(640, 360) * k
	size = Vector2(640, 360) * k
	scale = Vector2.ONE / k
