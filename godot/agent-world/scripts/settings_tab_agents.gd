class_name SettingsTabAgents
extends RefCounted
## Agents settings tab — per-agent config panels with an avatar picker.

const GRID_COLUMNS := 5
const AGENT_PORTRAIT_SIZE := Vector2(160, 160)
const PICKER_CELL_SIZE := Vector2(48, 48)
const ID_FIELD_WIDTH := 150
const DELETE_BUTTON_WIDTH := 90
const DELETE_BUTTON_HEIGHT := 28
const CHANGE_BUTTON_WIDTH := 180
const CHANGE_BUTTON_HEIGHT := 32

## Fallback when defaults.mcp.port is absent (a user://game_config.json
## override saved before the MCP feature shipped) — mirrors mcp_server.gd's
## DEFAULT_PORT so the hint URL always matches the server's own fallback.
const DEFAULT_MCP_PORT := 8975

var available_sprites: Array = []
var agents_config_container: VBoxContainer
var agent_fields: Dictionary = {}

# Per-agent avatar UI state
var _agent_portrait_rects: Dictionary = {}     # {agent_id: TextureRect}
var _agent_portrait_centers: Dictionary = {}   # {agent_id: CenterContainer}
var _agent_change_buttons: Dictionary = {}     # {agent_id: Button}
var _agent_picker_grids: Dictionary = {}       # {agent_id: Control}


func _init(sprites: Array) -> void:
	available_sprites = sprites


func build(parent: VBoxContainer) -> void:
	parent.add_child(SettingsForm.section_header("settings.agents"))
	agents_config_container = VBoxContainer.new()
	agents_config_container.add_theme_constant_override("separation", 10)
	for aid in GameState.agents:
		var agent_id: String = aid
		var cfg: Dictionary = GameState.agents[agent_id]
		_add_agent_panel(agent_id, cfg)
	parent.add_child(agents_config_container)

	var add_btn := UITheme.action_button(Strings.get_string("settings.add_agent"))
	add_btn.pressed.connect(_on_add)
	parent.add_child(add_btn)


func commit() -> Dictionary:
	"""Returns the rebuilt agents dict for the caller to merge into
	the config override."""
	var new_agents: Dictionary = {}
	for old_id in agent_fields:
		var fields: Dictionary = agent_fields[old_id]
		# Read the (possibly renamed) agent ID from the id field
		var id_field: LineEdit = fields["id_field"]
		var agent_id: String = id_field.text.strip_edges()
		if agent_id == "":
			agent_id = old_id
		var a: Dictionary = {}
		a["display_name"] = fields["display_name"].text.strip_edges()
		a["backend"] = fields["backend"].get_item_text(fields["backend"].selected) if fields["backend"].selected >= 0 else ""
		var agent_model: String = fields["model"].text.strip_edges()
		if agent_model != "":
			a["model"] = agent_model
		a["session_id"] = fields["session_id"].text.strip_edges()
		a["enabled"] = (fields["enabled"] as CheckButton).button_pressed
		a["interactions"] = (fields["interactions"] as CheckButton).button_pressed
		a["wandering"] = (fields["wandering"] as CheckButton).button_pressed
		a["mcp"] = (fields["mcp"] as CheckButton).button_pressed
		# Agent sprite override survives renames
		if GameState.agent_sprites.has(old_id):
			a["sprite"] = GameState.agent_sprites[old_id]
		elif GameState.agent_sprites.has(agent_id):
			a["sprite"] = GameState.agent_sprites[agent_id]
		new_agents[agent_id] = a
	return new_agents


func _add_agent_panel(agent_id: String, cfg: Dictionary) -> void:
	var panel := PanelContainer.new()
	var style := UITheme.panel_style()
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Header row: ID field + delete button
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_row.add_child(SettingsForm.form_label("settings.agent_id"))
	var id_field := LineEdit.new()
	id_field.text = agent_id
	id_field.add_theme_font_size_override("font_size", 32)
	id_field.add_theme_color_override("font_color", UITheme.ACCENT)
	id_field.custom_minimum_size = Vector2(ID_FIELD_WIDTH, 0)
	header_row.add_child(id_field)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	var del_btn := UITheme.action_button(Strings.get_string("settings.delete_agent"))
	del_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	del_btn.custom_minimum_size = Vector2(DELETE_BUTTON_WIDTH, DELETE_BUTTON_HEIGHT)
	UITheme.paint_danger(del_btn)
	del_btn.pressed.connect(_on_delete.bind(agent_id, panel))
	header_row.add_child(del_btn)
	vbox.add_child(header_row)

	# Fields
	var fields: Dictionary = {}
	fields["id_field"] = id_field
	fields["panel"] = panel
	fields["display_name"] = SettingsForm.text_row(vbox, "settings.display_name", cfg.get("display_name", agent_id))
	fields["backend"] = SettingsForm.option_row(vbox, "settings.backend", GameState.get_gateway_names(), cfg.get("backend", ""))
	fields["model"] = SettingsForm.text_row(vbox, "settings.gateway_model", cfg.get("model", ""))
	fields["model"].placeholder_text = Strings.get_string("settings.placeholder.agent_model")
	fields["session_id"] = SettingsForm.text_row(vbox, "settings.session_id", cfg.get("session_id", ""))
	fields["enabled"] = SettingsForm.check_row(vbox, "settings.agent_enabled", cfg.get("enabled", true))
	fields["interactions"] = SettingsForm.check_row(vbox, "settings.agent_interactions", cfg.get("interactions", true))
	fields["wandering"] = SettingsForm.check_row(vbox, "settings.agent_wandering", cfg.get("wandering", true))
	# Empty-safe: a missing "mcp" key (every agent predating this feature,
	# or a hand-edited config) reads as unchecked, matching
	# GameState.is_agent_mcp's own empty-safe default.
	fields["mcp"] = SettingsForm.check_row(vbox, "settings.agent_mcp", cfg.get("mcp", false))
	var mcp_hint := Label.new()
	mcp_hint.text = _mcp_hint_text(agent_id)
	mcp_hint.add_theme_font_size_override("font_size", 32)
	mcp_hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	mcp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(mcp_hint)
	# Endpoint URL is keyed on the agent ID, which lives in a sibling field
	# the user can rename — keep the hint in sync as they type instead of
	# freezing it to the ID the panel was built with.
	id_field.text_changed.connect(func(new_text: String) -> void:
		var shown_id: String = new_text.strip_edges()
		if shown_id == "":
			shown_id = agent_id
		mcp_hint.text = _mcp_hint_text(shown_id)
	)
	# Avatar at the bottom: big centered portrait with Change button below.
	_build_avatar_row(vbox, agent_id)

	panel.add_child(vbox)
	agents_config_container.add_child(panel)
	agent_fields[agent_id] = fields


func _on_add() -> void:
	var new_id := "agent_%d" % (agent_fields.size() + 1)
	var default_cfg := {
		"display_name": new_id,
		"backend": "",
		"session_id": "game:ai-avatars:%s" % new_id,
		"enabled": true,
		"interactions": true,
		"wandering": true,
		"mcp": false,
	}
	_add_agent_panel(new_id, default_cfg)


func _on_delete(agent_id: String, panel: PanelContainer) -> void:
	agent_fields.erase(agent_id)
	panel.queue_free()


# ── MCP hint ──

func _mcp_hint_text(agent_id: String) -> String:
	"""Dim hint shown under an agent's MCP checkbox — the URL the user
	must point their gateway's MCP client at for the flag to do anything.
	Not gated on the checkbox: the flag alone means nothing without the
	gateway-side wiring, so the hint stays useful whether checked or not."""
	var url := "http://127.0.0.1:%d/mcp/%s" % [_mcp_port(), agent_id]
	return Strings.get_string("settings.agent_mcp_hint", {"url": url})


func _mcp_port() -> int:
	"""Empty-safe read of defaults.mcp.port — mirrors mcp_server.gd's
	_configured_port()/_mcp_defaults() convention so this hint always
	agrees with the port the server actually listens on."""
	var raw: Variant = GameState.get_default("mcp", {})
	if raw is Dictionary:
		return int((raw as Dictionary).get("port", DEFAULT_MCP_PORT))
	return DEFAULT_MCP_PORT


# ── Avatar row ──

func _build_avatar_row(parent: VBoxContainer, agent_id: String) -> void:
	# Vertical stack: big centered portrait (only when one exists), Change/Select
	# button underneath, hidden picker grid below that (toggled by the button).
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Portrait slot lives in the tree so we can fill it later when the user
	# picks an avatar — but we only instantiate the TextureRect if there's
	# actually a sprite file backing this agent. Empty CenterContainer
	# collapses to zero height, so no blank 160×160 box shows up.
	var portrait_center := CenterContainer.new()
	portrait_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(portrait_center)
	_agent_portrait_centers[agent_id] = portrait_center

	var has_avatar: bool = _try_load_portrait(agent_id, portrait_center)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_key: String = "settings.change_sprite" if has_avatar else "settings.select_sprite"
	var change_btn := UITheme.action_button(Strings.get_string(btn_key))
	change_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	change_btn.custom_minimum_size = Vector2(CHANGE_BUTTON_WIDTH, CHANGE_BUTTON_HEIGHT)
	change_btn.pressed.connect(_toggle_picker.bind(agent_id))
	btn_row.add_child(change_btn)
	column.add_child(btn_row)
	_agent_change_buttons[agent_id] = change_btn

	# Hidden picker grid, toggled by the Change button.
	var picker_center := CenterContainer.new()
	picker_center.visible = false
	picker_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picker := GridContainer.new()
	picker.columns = GRID_COLUMNS
	picker.add_theme_constant_override("h_separation", 6)
	picker.add_theme_constant_override("v_separation", 6)
	for i in range(available_sprites.size()):
		var si: Dictionary = available_sprites[i]
		var cell_portrait: TextureRect = GameState.load_portrait_for_sprite(si, PICKER_CELL_SIZE)
		cell_portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell_portrait.gui_input.connect(_on_sprite_input.bind(agent_id, si))
		picker.add_child(cell_portrait)
	picker_center.add_child(picker)
	_agent_picker_grids[agent_id] = picker_center
	column.add_child(picker_center)

	parent.add_child(column)


func _try_load_portrait(agent_id: String, portrait_center: CenterContainer) -> bool:
	var tex: Texture2D = GameState.load_agent_portrait_texture(agent_id)
	if tex == null:
		return false
	var portrait := GameState.make_portrait_rect(tex, AGENT_PORTRAIT_SIZE)
	portrait_center.add_child(portrait)
	_agent_portrait_rects[agent_id] = portrait
	return true


func _toggle_picker(agent_id: String) -> void:
	for aid in _agent_picker_grids:
		var grid: Control = _agent_picker_grids[aid]
		if aid != agent_id:
			grid.visible = false
	var picker: Control = _agent_picker_grids[agent_id]
	picker.visible = not picker.visible


func _on_sprite_input(event: InputEvent, agent_id: String, sprite_info: Dictionary) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	GameState.agent_sprites[agent_id] = sprite_info["filename"]
	var new_portrait: TextureRect = GameState.load_portrait_for_sprite(sprite_info, AGENT_PORTRAIT_SIZE)
	# If the agent had no avatar before, the portrait center is empty —
	# just drop the new TextureRect in. Otherwise swap it with the old one.
	if _agent_portrait_rects.has(agent_id):
		var old_portrait: TextureRect = _agent_portrait_rects[agent_id]
		old_portrait.get_parent().add_child(new_portrait)
		new_portrait.get_parent().move_child(new_portrait, old_portrait.get_index())
		old_portrait.queue_free()
	else:
		var portrait_center: CenterContainer = _agent_portrait_centers[agent_id]
		portrait_center.add_child(new_portrait)
		# Swap the button label now that the agent has an avatar.
		var btn: Button = _agent_change_buttons[agent_id]
		btn.text = Strings.get_string("settings.change_sprite")
	_agent_portrait_rects[agent_id] = new_portrait
	var picker: Control = _agent_picker_grids[agent_id]
	picker.visible = false
