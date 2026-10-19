extends CanvasLayer
## Settings screen orchestrator — wallpaper, frame, tab container, Save/Back.
## Every tab lives in its own file (settings_tab_*.gd); this screen just
## composes them and coordinates the save flow.

const SELECTOR_SCENE := "res://scenes/room_selector.tscn"

var available_sprites: Array = []
var status_label: Label

var _tab_player: SettingsTabPlayer
var _tab_gateways: SettingsTabGateways
var _tab_agents: SettingsTabAgents
var _tab_world: SettingsTabWorld


func _ready() -> void:
	layer = 1
	available_sprites = GameState.scan_available_sprites()
	_tab_player = SettingsTabPlayer.new(self, available_sprites)
	_tab_gateways = SettingsTabGateways.new()
	_tab_agents = SettingsTabAgents.new(available_sprites)
	_tab_world = SettingsTabWorld.new()
	_build_ui()


# ── Main UI ──

func _build_ui() -> void:
	UITheme.wallpaper_background(self, true)

	# Outer margin — leaves room around the framed settings panel.
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	# Framed panel — dark bg, 2px purple border (same chrome as the Edit sidebar).
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.framed_panel_style())
	margin.add_child(frame)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	frame.add_child(outer)

	# Title
	var title := Label.new()
	title.text = Strings.get_string("settings.title").to_upper()
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	# Save + Back row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	var save_btn := UITheme.primary_button(Strings.get_string("settings.save"))
	save_btn.pressed.connect(_on_save)
	top_row.add_child(save_btn)
	var back_btn := UITheme.primary_button(Strings.get_string("settings.back"))
	back_btn.pressed.connect(_on_back)
	top_row.add_child(back_btn)
	outer.add_child(top_row)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", UITheme.line_style())
	outer.add_child(sep)

	# Tabbed content — one ScrollContainer per tab.
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tab_container(tabs)
	_add_tab(tabs, "settings.tab_player", _tab_player.build)
	_add_tab(tabs, "settings.tab_gateways", _tab_gateways.build)
	_add_tab(tabs, "settings.tab_agents", _tab_agents.build)
	_add_tab(tabs, "settings.tab_world", _tab_world.build)
	outer.add_child(tabs)

	# Status label below tabs.
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 32)
	status_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(status_label)

	UITheme.attach_arcane_corners(frame)


func _style_tab_container(tabs: TabContainer) -> void:
	# Flat tab bar — no shadows, no borders, just bg-color distinction.
	# Selected tab reads as active through the cyan font color alone.
	tabs.add_theme_font_size_override("font_size", 32)
	tabs.add_theme_color_override("font_selected_color", UITheme.SECTION)
	tabs.add_theme_color_override("font_unselected_color", UITheme.TEXT_DIM)
	tabs.add_theme_color_override("font_hovered_color", UITheme.TEXT)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UITheme.TAB_BG
	panel_style.set_corner_radius_all(UITheme.CORNER)
	panel_style.content_margin_left = 4
	panel_style.content_margin_right = 4
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	tabs.add_theme_stylebox_override("panel", panel_style)

	var selected := StyleBoxFlat.new()
	selected.bg_color = UITheme.TAB_SELECTED_BG
	selected.set_corner_radius_all(UITheme.CORNER)
	selected.content_margin_left = 14
	selected.content_margin_right = 14
	selected.content_margin_top = 6
	selected.content_margin_bottom = 6
	tabs.add_theme_stylebox_override("tab_selected", selected)

	var unselected := selected.duplicate()
	unselected.bg_color = UITheme.TAB_TRANSPARENT
	tabs.add_theme_stylebox_override("tab_unselected", unselected)

	var hovered := selected.duplicate()
	hovered.bg_color = UITheme.TAB_HOVERED_BG
	tabs.add_theme_stylebox_override("tab_hovered", hovered)

	var tabbar_bg := StyleBoxFlat.new()
	tabbar_bg.bg_color = UITheme.TAB_TRANSPARENT
	tabs.add_theme_stylebox_override("tabbar_background", tabbar_bg)


func _add_tab(tabs: TabContainer, title_key: String, builder: Callable) -> void:
	# Each tab is a ScrollContainer wrapping a padded VBox. Builder is
	# called with the inner VBox so it only adds its own rows.
	var scroll := ScrollContainer.new()
	scroll.name = Strings.get_string(title_key).to_upper()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builder.call(vbox)
	margin.add_child(vbox)
	scroll.add_child(margin)
	tabs.add_child(scroll)


# ── Save / Back ──

func _on_save() -> void:
	_tab_player.commit()
	_tab_gateways.commit()
	GameState.save_settings()

	# Build config override, then let tabs that care fold their state in.
	var override: Dictionary = GameState.config.duplicate(true)
	override["agents"] = _tab_agents.commit()

	var defaults: Dictionary = override.get("defaults", {}).duplicate(true)
	_tab_world.commit(defaults)
	override["defaults"] = defaults
	# GameState.defaults is the live copy world_loader reads from on reload.
	GameState.defaults = defaults

	GameState.config = override
	GameState.save_config_override()

	status_label.text = Strings.get_string("settings.saved")
	print("[settings] Saved")


func _on_back() -> void:
	get_tree().change_scene_to_file(SELECTOR_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()
