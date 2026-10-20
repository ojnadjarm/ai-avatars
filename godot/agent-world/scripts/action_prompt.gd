extends CanvasLayer
## Contextual action prompt: the E keycap and the verb on a kit tooltip plate, floating over the agent's head or the prop.

## World px above an agent's feet (clears the tallest 96 px avatar's head).
const HEAD_CLEARANCE := 80.0
## World px above a prop's origin.
const PROP_CLEARANCE := 12.0
## Screen px between the prompt plate and the agent's name label.
const NAME_GAP := 2.0

var panel: PanelContainer
var label: Label
var current_text: String = ""
var target_alpha: float = 0.0

# Injected by world_loader.
var player: CharacterBody2D
var dialogue: DialogueCloud


func _ready() -> void:
	layer = 8
	_build_ui()


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.kit_style("tooltip", 3, 2))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key := TextureRect.new()
	key.texture = UITheme.keycap_texture("e")
	key.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	key.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)

	label = Label.new()
	UITheme.ensure_fonts_loaded()
	label.add_theme_font_override("font", UITheme.FONT_HUD)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	label.add_theme_color_override("font_color", UITheme.TEXT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	panel.add_child(row)
	add_child(panel)


func _process(_delta: float) -> void:
	if not player:
		return
	if dialogue and dialogue.is_showing:
		_set_text("")
		return

	var text := ""
	var world_pos := Vector2.ZERO
	var name_label: Control = null
	if player.nearby_agent:
		text = Strings.get_string("action.talk").to_upper()
		world_pos = player.nearby_agent.global_position - Vector2(0, HEAD_CLEARANCE)
		name_label = player.nearby_agent.get_node_or_null("NameLabel") as Control
	elif player.nearby_prop:
		text = Strings.get_string("action.examine").to_upper()
		world_pos = player.nearby_prop.global_position - Vector2(0, PROP_CLEARANCE)
	_set_text(text)
	if text == "":
		return
	# Binary snap — pixel UI does not fade; whole pixels so the plate never shimmers.
	panel.reset_size()
	var xf := get_viewport().get_canvas_transform()
	var screen: Vector2 = xf * world_pos
	if name_label and name_label.visible:
		screen.y = minf(screen.y, (xf * name_label.get_global_rect()).position.y - NAME_GAP)
	panel.position = (screen - Vector2(panel.size.x * 0.5, panel.size.y)).round()


func _set_text(text: String) -> void:
	panel.visible = text != ""
	if text != current_text:
		current_text = text
		label.text = text
