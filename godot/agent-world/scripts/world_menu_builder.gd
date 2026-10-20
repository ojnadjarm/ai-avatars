class_name WorldMenuBuilder
extends RefCounted
## In-world top-left menu stack, toast label, and modal dialogs (quit confirm,
## call-agent picker, summon-meeting picker). Owns the dialog instances and
## the main menu CanvasLayer, but everything is parented to `world_loader` so
## the helper itself can stay RefCounted.
##
## world_loader composes one of these in _ready() and routes:
##   • menu chrome construction → build()
##   • toast confirmations      → show_toast(text)
##   • main-menu visibility     → set_menu_visible(bool)
##   • C / Shift+C input        → show_call_picker() / show_meeting_picker()
##   • Esc input                → try_dismiss_open() (returns true when handled)
## Public callers (call_agent_to_player, call_all_agents_to_player, end_meeting)
## reach the helper through world_loader.menu_builder.

## Wrap width of modal body text at the 640x360 base.
const MODAL_TEXT_W := 260

var world_loader: WorldLoader
var _quit_dialog: CanvasLayer = null
var _call_dialog: CanvasLayer = null
var _meeting_dialog: CanvasLayer = null
var _main_menu_layer: CanvasLayer = null
var _toast_label: Label = null


func _init(wl: WorldLoader) -> void:
	world_loader = wl


## Construct the top-left menu stack + toast label and attach them to
## world_loader as a single CanvasLayer at WorldLoader.LAYER_MENU.
func build() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MainMenu"
	layer.layer = WorldLoader.LAYER_MENU

	var anchor := Control.new()
	anchor.name = "MenuAnchor"
	anchor.anchor_left = 0.0
	anchor.anchor_top = 0.0
	anchor.anchor_right = 0.0
	anchor.anchor_bottom = 0.0
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(anchor)

	var stack := VBoxContainer.new()
	stack.name = "MenuStack"
	stack.add_theme_constant_override("separation", UITheme.MENU_STACK_SEPARATION)
	stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	stack.offset_left = UITheme.MENU_STACK_OFFSET_LEFT
	stack.offset_top = UITheme.MENU_STACK_OFFSET_TOP
	stack.offset_right = UITheme.MENU_STACK_OFFSET_RIGHT
	stack.offset_bottom = UITheme.MENU_STACK_OFFSET_BOTTOM
	anchor.add_child(stack)

	var menu_btn := UITheme.prominent_button(Strings.get_string("world.main_menu"))
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu_btn.pressed.connect(show_quit_confirm)
	stack.add_child(menu_btn)

	_toast_label = UITheme.build_toast_label()
	layer.add_child(_toast_label)

	world_loader.add_child(layer)
	_main_menu_layer = layer


## Fade a transient confirmation through the persistent toast label.
func show_toast(text: String) -> void:
	UITheme.show_toast(_toast_label, text)


## Toggle the in-world main menu layer (hidden during an active group chat).
func set_menu_visible(visible: bool) -> void:
	if _main_menu_layer != null:
		_main_menu_layer.visible = visible


## Esc dispatcher. Returns true when a modal was dismissed; false when no
## modal was open, so world_loader can fall through to opening quit confirm.
func try_dismiss_open() -> bool:
	if is_instance_valid(_quit_dialog):
		_quit_dialog.queue_free()
		_quit_dialog = null
		return true
	if is_instance_valid(_call_dialog):
		_dismiss_call_dialog()
		return true
	if is_instance_valid(_meeting_dialog):
		_dismiss_meeting_dialog()
		return true
	return false


## Quit-to-main-menu confirmation modal. OK swaps scenes, Cancel just frees
## the dialog. Re-invoking while the dialog is open is a no-op.
func show_quit_confirm() -> void:
	if not is_instance_valid(world_loader):
		return
	if is_instance_valid(_quit_dialog):
		return
	var modal: UITheme.ModalResult = UITheme.modal(
		Strings.get_string("world.quit_confirm_title"),
		Strings.get_string("world.quit_confirm_yes"),
		Strings.get_string("world.quit_confirm_no"),
	)
	var body: VBoxContainer = modal.body
	var text := Label.new()
	text.text = Strings.get_string("world.quit_confirm_text")
	text.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	text.add_theme_color_override("font_color", UITheme.TEXT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(MODAL_TEXT_W, 0)
	body.add_child(text)

	_quit_dialog = modal.layer
	world_loader.add_child(_quit_dialog)

	modal.ok_button.pressed.connect(func() -> void:
		if not is_instance_valid(world_loader):
			return
		world_loader.get_tree().change_scene_to_file("res://scenes/room_selector.tscn")
	)
	modal.cancel_button.pressed.connect(func() -> void:
		if is_instance_valid(_quit_dialog):
			_quit_dialog.queue_free()
		_quit_dialog = null
	)


## Single-agent picker modal. Reuses UITheme.modal for visual consistency
## but hides the OK button (picking an agent IS the action). One
## action_button per live agent; empty-world fallback shows a note.
func show_call_picker() -> void:
	if not is_instance_valid(world_loader):
		return
	if is_instance_valid(_call_dialog):
		return
	var modal: UITheme.ModalResult = UITheme.modal(
		Strings.get_string("world.call_agent_title"),
		"",
		Strings.get_string("world.call_agent_close"),
	)
	var body: VBoxContainer = modal.body
	modal.ok_button.visible = false

	var found_any: bool = false
	var agents_container: Node2D = world_loader.agents_container
	if agents_container != null:
		for child: Node in agents_container.get_children():
			if not (child is Agent):
				continue
			var a: Agent = child
			var row: Button = UITheme.action_button(a.display_name)
			var captured_id: String = a.agent_id
			row.pressed.connect(func() -> void:
				if not is_instance_valid(world_loader):
					return
				world_loader.call_agent_to_player(captured_id)
				_dismiss_call_dialog()
			)
			body.add_child(row)
			found_any = true
	if not found_any:
		body.add_child(_empty_agents_label())

	_call_dialog = modal.layer
	world_loader.add_child(_call_dialog)

	modal.cancel_button.pressed.connect(_dismiss_call_dialog)


## Multi-agent picker modal for Summon Meeting. Each row is a CheckButton
## (defaulted ON); OK collects every checked id and forwards to
## call_all_agents_to_player(ids). Empty-world fallback hides OK and shows
## the same "no agents" note as the 1:1 picker.
func show_meeting_picker() -> void:
	if not is_instance_valid(world_loader):
		return
	if is_instance_valid(_meeting_dialog):
		return
	var modal: UITheme.ModalResult = UITheme.modal(
		Strings.get_string("world.meeting_picker_title"),
		Strings.get_string("world.meeting_picker_ok"),
		Strings.get_string("world.meeting_picker_cancel"),
	)
	var body: VBoxContainer = modal.body
	var ok_button: Button = modal.ok_button

	var checks: Array[Dictionary] = _build_meeting_check_rows(body)

	if checks.is_empty():
		ok_button.visible = false
		body.add_child(_empty_agents_label())
	else:
		body.add_child(_meeting_picker_hint())

	_meeting_dialog = modal.layer
	world_loader.add_child(_meeting_dialog)

	ok_button.pressed.connect(func() -> void:
		var selected: Array[String] = []
		for entry: Dictionary in checks:
			var cb: CheckButton = entry["check"]
			if cb.button_pressed:
				selected.append(entry["id"])
		_dismiss_meeting_dialog()
		if not selected.is_empty() and is_instance_valid(world_loader):
			world_loader.call_all_agents_to_player(selected)
	)
	modal.cancel_button.pressed.connect(_dismiss_meeting_dialog)


# ── Internal ─────────────────────────────────────────────────────────────

func _dismiss_call_dialog() -> void:
	if is_instance_valid(_call_dialog):
		_call_dialog.queue_free()
	_call_dialog = null


func _dismiss_meeting_dialog() -> void:
	if is_instance_valid(_meeting_dialog):
		_meeting_dialog.queue_free()
	_meeting_dialog = null


func _build_meeting_check_rows(body: VBoxContainer) -> Array[Dictionary]:
	var checks: Array[Dictionary] = []
	var agents_container: Node2D = world_loader.agents_container
	if agents_container == null:
		return checks
	for child: Node in agents_container.get_children():
		if not (child is Agent):
			continue
		var a: Agent = child
		var check := CheckButton.new()
		check.text = a.display_name.to_upper()
		check.button_pressed = true
		check.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
		body.add_child(check)
		checks.append({"id": a.agent_id, "check": check})
	return checks


func _empty_agents_label() -> Label:
	var empty := Label.new()
	empty.text = Strings.get_string("world.call_agent_none")
	empty.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	empty.add_theme_color_override("font_color", UITheme.TEXT)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.custom_minimum_size = Vector2(MODAL_TEXT_W, 0)
	return empty


func _meeting_picker_hint() -> Label:
	var hint := Label.new()
	hint.text = Strings.get_string("world.meeting_picker_hint")
	UITheme.ensure_fonts_loaded()
	hint.add_theme_font_override("font", UITheme.FONT_HUD)
	hint.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return hint
