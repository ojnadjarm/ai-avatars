class_name SettingsTabGateways
extends RefCounted
## Gateways settings tab — add/edit/delete LLM gateway endpoints.

const GATEWAY_TYPES := ["hermes", "openai", "openclaw", "anthropic"]
const NAME_FIELD_WIDTH := 180
const MODEL_FIELD_WIDTH := 160
const DELETE_BUTTON_WIDTH := 64
const DELETE_BUTTON_HEIGHT := 0

var gateways_container: VBoxContainer
var gateway_fields: Dictionary = {}


func build(parent: VBoxContainer) -> void:
	parent.add_child(SettingsForm.section_header("settings.gateways"))
	gateways_container = VBoxContainer.new()
	gateways_container.add_theme_constant_override("separation", 6)
	for gw_id in GameState.gateways:
		var gw_id_str: String = gw_id
		var gw: Dictionary = GameState.gateways[gw_id_str]
		_add_gateway_panel(gw_id_str, gw)
	parent.add_child(gateways_container)

	var add_btn := UITheme.action_button(Strings.get_string("settings.add_gateway"))
	add_btn.pressed.connect(_on_add)
	parent.add_child(add_btn)


func commit() -> void:
	var new_gateways: Dictionary = {}
	for old_id in gateway_fields:
		var fields: Dictionary = gateway_fields[old_id]
		var gw_name: String = fields["name"].text.strip_edges()
		if gw_name == "":
			gw_name = old_id
		var type_opt: OptionButton = fields["type"]
		new_gateways[gw_name] = {
			"type": GATEWAY_TYPES[type_opt.selected] if type_opt.selected >= 0 else "openai",
			"endpoint": fields["endpoint"].text.strip_edges(),
			"api_key": fields["api_key"].text.strip_edges(),
			"model": fields["model"].text.strip_edges(),
		}
	GameState.gateways = new_gateways


func _add_gateway_panel(gw_id: String, gw: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.kit_style("panel", 10, 8))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var fields: Dictionary = {}

	# Name row with delete button
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", SettingsForm.ROW_SEP)
	name_row.add_child(SettingsForm.form_label("settings.gateway_name"))
	var name_field := LineEdit.new()
	name_field.text = gw_id
	name_field.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	name_field.custom_minimum_size = Vector2(NAME_FIELD_WIDTH, 0)
	name_row.add_child(name_field)
	fields["name"] = name_field
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(spacer)
	var del_btn := UITheme.action_button(Strings.get_string("settings.delete_gateway"))
	del_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	del_btn.custom_minimum_size = Vector2(DELETE_BUTTON_WIDTH, DELETE_BUTTON_HEIGHT)
	UITheme.paint_danger(del_btn)
	del_btn.pressed.connect(_on_delete.bind(gw_id, panel))
	name_row.add_child(del_btn)
	vbox.add_child(name_row)

	# Type
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", SettingsForm.ROW_SEP)
	type_row.add_child(SettingsForm.form_label("settings.gateway_type"))
	var type_opt := OptionButton.new()
	type_opt.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	for i in range(GATEWAY_TYPES.size()):
		type_opt.add_item(GATEWAY_TYPES[i])
		if GATEWAY_TYPES[i] == gw.get("type", "openai"):
			type_opt.selected = i
	type_row.add_child(type_opt)
	fields["type"] = type_opt
	vbox.add_child(type_row)

	# Endpoint
	var ep_row := HBoxContainer.new()
	ep_row.name = "EndpointRow"
	ep_row.add_theme_constant_override("separation", SettingsForm.ROW_SEP)
	ep_row.add_child(SettingsForm.form_label("settings.gateway_endpoint"))
	var ep_field := LineEdit.new()
	ep_field.text = gw.get("endpoint", "")
	ep_field.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	ep_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ep_field.placeholder_text = Strings.get_string("settings.placeholder.hermes_endpoint")
	ep_row.add_child(ep_field)
	fields["endpoint"] = ep_field
	vbox.add_child(ep_row)

	# API key
	var key_row := HBoxContainer.new()
	key_row.name = "ApiKeyRow"
	key_row.add_theme_constant_override("separation", SettingsForm.ROW_SEP)
	key_row.add_child(SettingsForm.form_label("settings.gateway_api_key"))
	var key_field := LineEdit.new()
	key_field.text = gw.get("api_key", "")
	key_field.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	key_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_field.secret = true
	key_field.placeholder_text = Strings.get_string("settings.placeholder.openai_key")
	key_row.add_child(key_field)
	fields["api_key"] = key_field
	vbox.add_child(key_row)

	# Initial placeholder hints + update on type change
	var current_type: String = GATEWAY_TYPES[type_opt.selected] if type_opt.selected >= 0 else "openai"
	_update_hints(current_type, ep_field, key_field)
	type_opt.item_selected.connect(func(idx: int) -> void:
		_update_hints(GATEWAY_TYPES[idx], ep_field, key_field)
	)

	# Model
	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", SettingsForm.ROW_SEP)
	model_row.add_child(SettingsForm.form_label("settings.gateway_model"))
	var model_field := LineEdit.new()
	model_field.text = gw.get("model", "")
	model_field.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	model_field.custom_minimum_size = Vector2(MODEL_FIELD_WIDTH, 0)
	model_field.placeholder_text = Strings.get_string("settings.placeholder.hermes_model")
	model_row.add_child(model_field)
	fields["model"] = model_field
	vbox.add_child(model_row)

	panel.add_child(vbox)
	gateways_container.add_child(panel)
	gateway_fields[gw_id] = fields


func _on_add() -> void:
	var new_id := "gateway-%d" % (gateway_fields.size() + 1)
	_add_gateway_panel(new_id, {"type": "openai", "endpoint": "", "api_key": "", "model": ""})


func _on_delete(gw_id: String, panel: PanelContainer) -> void:
	gateway_fields.erase(gw_id)
	panel.queue_free()


func _update_hints(gw_type: String, ep_field: LineEdit, key_field: LineEdit) -> void:
	match gw_type:
		"hermes":
			ep_field.placeholder_text = Strings.get_string("settings.placeholder.hermes_endpoint")
			key_field.placeholder_text = Strings.get_string("settings.placeholder.hermes_key")
		"openclaw":
			ep_field.placeholder_text = Strings.get_string("settings.placeholder.openclaw_endpoint")
			key_field.placeholder_text = Strings.get_string("settings.placeholder.openclaw_key")
		_:
			ep_field.placeholder_text = Strings.get_string("settings.placeholder.openai_endpoint")
			key_field.placeholder_text = Strings.get_string("settings.placeholder.openai_key")
