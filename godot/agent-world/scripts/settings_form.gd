class_name SettingsForm
extends RefCounted
## Shared form-row primitives for settings tabs. Keeps the label/field/hint
## conventions consistent so tabs don't each reinvent the HBox+Label+LineEdit
## boilerplate. Every method is static — tabs just call them.

const LABEL_WIDTH := 130
const NUMBER_LABEL_WIDTH := 280
const NUMBER_FIELD_WIDTH := 100
const RANGE_FIELD_WIDTH := 80


static func section_header(key: String) -> Label:
	return UITheme.section_header(Strings.get_string(key))


static func form_label(key: String) -> Label:
	var lbl := UITheme.form_label(Strings.get_string(key))
	lbl.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	return lbl


static func _wide_label(key: String) -> Label:
	"""Dim 11pt label used by the numeric rows (wider column so the
	labels line up with the field side on the right)."""
	var lbl := Label.new()
	lbl.text = Strings.get_string(key).to_upper()
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	lbl.custom_minimum_size = Vector2(NUMBER_LABEL_WIDTH, 0)
	return lbl


static func text_row(parent: VBoxContainer, label_key: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(form_label(label_key))
	var field := LineEdit.new()
	field.text = value
	field.add_theme_font_size_override("font_size", 32)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	parent.add_child(row)
	return field


static func option_row(parent: VBoxContainer, label_key: String, options: Array, current: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(form_label(label_key))
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 32)
	for i in range(options.size()):
		opt.add_item(options[i])
		if options[i] == current:
			opt.selected = i
	row.add_child(opt)
	parent.add_child(row)
	return opt


static func check_row(parent: VBoxContainer, label_key: String, value: bool) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var check := CheckButton.new()
	check.text = Strings.get_string(label_key).to_upper()
	check.button_pressed = value
	check.add_theme_font_size_override("font_size", 32)
	row.add_child(check)
	parent.add_child(row)
	return check


static func number_row(parent: VBoxContainer, label_key: String, value: float) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_wide_label(label_key))
	var field := LineEdit.new()
	field.text = str(value)
	field.add_theme_font_size_override("font_size", 32)
	field.custom_minimum_size = Vector2(NUMBER_FIELD_WIDTH, 0)
	row.add_child(field)
	parent.add_child(row)
	return field


static func range_row(parent: VBoxContainer, label_key: String, min_val: float, max_val: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_wide_label(label_key))

	var min_field := LineEdit.new()
	min_field.text = str(min_val)
	min_field.add_theme_font_size_override("font_size", 32)
	min_field.custom_minimum_size = Vector2(RANGE_FIELD_WIDTH, 0)
	row.add_child(min_field)

	var dash := Label.new()
	dash.text = "—"
	dash.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(dash)

	var max_field := LineEdit.new()
	max_field.text = str(max_val)
	max_field.add_theme_font_size_override("font_size", 32)
	max_field.custom_minimum_size = Vector2(RANGE_FIELD_WIDTH, 0)
	row.add_child(max_field)

	parent.add_child(row)
	return [min_field, max_field]


static func parse_float(field: LineEdit, fallback: float) -> float:
	var txt := field.text.strip_edges()
	if txt == "":
		return fallback
	var v: float = float(txt)
	if v <= 0.0:
		return fallback
	return v
