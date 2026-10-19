extends CanvasLayer
## Contextual action prompt — "[E] Talk" / "[E] Examine" near interactables.
## Floats near the prop/agent in world space.

var panel: PanelContainer
var label: RichTextLabel
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
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var style := UITheme.panel_style()
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.modulate.a = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("normal_font_size", 32)
	label.add_theme_font_size_override("bold_font_size", 32)
	label.add_theme_color_override("default_color", UITheme.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	panel.add_child(label)
	add_child(panel)


func _process(delta: float) -> void:
	if not player:
		return

	if dialogue and dialogue.is_showing:
		_set_text("")
		panel.modulate.a = 0.0
		return

	var text := ""
	var world_pos := Vector2.ZERO

	if player.nearby_agent:
		text = "[color=#%s]E[/color]  [color=#%s]%s[/color]" % [UITheme.ACCENT_HEX, UITheme.TEXT_HEX, Strings.get_string("action.talk").to_upper()]
		world_pos = player.nearby_agent.global_position
	elif player.nearby_prop:
		text = "[color=#%s]E[/color]  [color=#%s]%s[/color]" % [UITheme.ACCENT_HEX, UITheme.TEXT_HEX, Strings.get_string("action.examine").to_upper()]
		world_pos = player.nearby_prop.global_position

	_set_text(text)
	# Binary snap — pixel UI does not fade.
	panel.modulate.a = 1.0 if text != "" else 0.0

	if text != "":
		var camera := get_viewport().get_camera_2d()
		if camera:
			var viewport_size := get_viewport().get_visible_rect().size
			var screen_pos: Vector2 = (world_pos - camera.get_screen_center_position()) * camera.zoom + viewport_size * 0.5
			# Snap to 2px grid so the prompt never sub-pixels.
			var snapped := (screen_pos + Vector2(-30, -35))
			snapped = (snapped / 2.0).round() * 2.0
			panel.position = snapped


func _set_text(text: String) -> void:
	if text != current_text:
		current_text = text
		label.text = text
