extends CanvasLayer
## Settings screen orchestrator — backdrop, frame, tab container, Save/Back.
## Every tab lives in its own file (settings_tab_*.gd); this screen just
## composes them and coordinates the save flow.

const SELECTOR_SCENE := "res://scenes/room_selector.tscn"
const BUTTON_W := 72

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

const FRAME_MARGIN := 10

var tabs: TabContainer


func _build_ui() -> void:
	UITheme.wallpaper_background(self)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, FRAME_MARGIN)
	add_child(margin)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.add_theme_stylebox_override("panel", UITheme.framed_panel_style())
	margin.add_child(frame)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	frame.add_child(outer)

	# Title row: title, save status, Save + Back.
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = Strings.get_string("settings.title").to_upper()
	UITheme.ensure_fonts_loaded()
	if UITheme.FONT_TITLE != null:
		title.add_theme_font_override("font", UITheme.FONT_TITLE)
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.add_theme_color_override("font_shadow_color", UITheme.LABEL_SHADOW_HEAVY)
	top_row.add_child(title)

	status_label = Label.new()
	status_label.add_theme_font_override("font", UITheme.FONT_HUD)
	status_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HUD)
	status_label.add_theme_color_override("font_color", UITheme.TOAST_SUCCESS)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(status_label)

	var save_btn := UITheme.primary_button(Strings.get_string("settings.save"))
	save_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	save_btn.custom_minimum_size.x = BUTTON_W
	save_btn.pressed.connect(_on_save)
	top_row.add_child(save_btn)
	var back_btn := UITheme.primary_button(Strings.get_string("settings.back"))
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	back_btn.custom_minimum_size.x = BUTTON_W
	back_btn.pressed.connect(_on_back)
	top_row.add_child(back_btn)
	outer.add_child(top_row)
	outer.add_child(HSeparator.new())

	# Tabbed content — one ScrollContainer per tab; styles come from the kit theme.
	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_add_tab(tabs, "settings.tab_player", _tab_player.build)
	_add_tab(tabs, "settings.tab_gateways", _tab_gateways.build)
	_add_tab(tabs, "settings.tab_agents", _tab_agents.build)
	_add_tab(tabs, "settings.tab_world", _tab_world.build)
	outer.add_child(tabs)


## Opens a tab by index (the UI demo shows each one).
func select_tab(index: int) -> void:
	if tabs:
		tabs.current_tab = clampi(index, 0, tabs.get_tab_count() - 1)


func _add_tab(tab_host: TabContainer, title_key: String, builder: Callable) -> void:
	# Each tab is a ScrollContainer wrapping a padded VBox; the builder only adds its own rows.
	var scroll := ScrollContainer.new()
	scroll.name = Strings.get_string(title_key).to_upper()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builder.call(vbox)
	margin.add_child(vbox)
	scroll.add_child(margin)
	tab_host.add_child(scroll)


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
