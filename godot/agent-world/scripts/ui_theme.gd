class_name UITheme
## Shared UI palette, kit styles and helpers: the single style source for every panel.
## Colours come from the T704 title palette (night navy glass, gold hairlines, magenta gems);
## widget art is the code-drawn kit in res://assets/ui (tools/art/ui/build_ui.py).

# ── Palette (T704 title keys in brackets) ──
const BG := Color8(12, 16, 40, 224)              # n1 glass
const BORDER := Color8(184, 134, 46, 150)        # g1 hairline
const ACCENT := Color8(242, 196, 90)             # g2 gold
const TEXT := Color8(200, 219, 240)              # n10 pale
const TEXT_DIM := Color8(120, 148, 196)          # n8 dim
const TEXT_PLAYER := Color8(94, 194, 156)        # t6 teal
const TEXT_AGENT := Color8(242, 196, 90)         # g2 gold
const INPUT_BG := Color8(6, 7, 26, 242)          # n0
const INPUT_BORDER := Color8(27, 37, 80, 255)    # n3
const INPUT_FOCUS := Color8(184, 134, 46, 255)   # g1

# Section header — lavender, so gold stays reserved for titles and selection.
const SECTION := Color8(208, 168, 238)           # v6

# Framed panel — settings screen, room selector, modal (flat fallback when the kit is missing).
const FRAMED_BG := Color8(12, 16, 40, 235)
const FRAMED_BORDER := Color8(184, 134, 46, 255)

# Modal backdrop — full-screen dim behind LogModal and similar overlays.
const MODAL_BACKDROP := Color8(6, 7, 26, 191)

# Tab container
const TAB_BG := Color8(12, 16, 40, 217)
const TAB_SELECTED_BG := Color8(19, 26, 60, 255)
const TAB_HOVERED_BG := Color8(19, 26, 60, 153)
const TAB_TRANSPARENT := Color(0, 0, 0, 0)

# Avatar picker cell
const CELL_BG := Color8(19, 26, 60, 179)

# Button variants
const BUTTON_BG := Color8(19, 26, 60, 242)
const BUTTON_BG_DIM := Color8(19, 26, 60, 217)
const BUTTON_HOVER_BG := Color8(44, 27, 79, 242)
const BUTTON_HOVER_BORDER := Color8(242, 196, 90, 230)
const BUTTON_HOVER_TEXT := Color8(242, 246, 255)

# Danger (delete) button
const DANGER := Color8(255, 138, 58)              # f2
const DANGER_HOVER := Color8(255, 156, 204)       # m3

# Warning / action-critical chrome (end-meeting btn, destructive accents)
const WARN := Color8(255, 138, 58)                # f2
const WARN_HOVER := Color8(192, 80, 30)           # f1

# Dialogue close-button hover
const CLOSE_HOVER := Color8(255, 138, 58)

# Input field placeholder text
const INPUT_PLACEHOLDER := Color8(67, 90, 148)    # n6

# Menu backdrop glass — darkens the title art so menu text stays readable.
const BACKDROP_GLASS := Color8(6, 7, 26, 110)
const BACKDROP_GLASS_DIM := Color8(6, 7, 26, 170)

# Text shadow used on world-space labels.
const LABEL_SHADOW := Color8(6, 7, 26, 204)
const LABEL_SHADOW_STRONG := Color8(6, 7, 26, 217)
const LABEL_SHADOW_HEAVY := Color8(6, 7, 26, 230)

# Panel / popup drop shadow colors — applied directly on StyleBoxFlat by
# callers that want a shadow (e.g. dialogue_cloud); panel_style() itself
# does not wire shadows.
const PANEL_SHADOW := Color8(6, 7, 26, 140)
const POPUP_SHADOW := Color8(6, 7, 26, 191)

# Bevel — darker bottom/right border used by the controls-hint keycap.
const BEVEL_SHADOW := Color8(6, 7, 26, 230)

# Filigree — gold corner glyphs on framed panels (fallback when the kit is missing).
const ARCANE_GLYPH := Color8(242, 196, 90, 230)
const ARCANE_GLYPH_DIM := Color8(110, 74, 28, 200)

# Editor — prop markers on the map.
const MARKER_SELECTED := Color(0.45, 0.90, 1.0, 0.65)
const MARKER_COLLISION := Color(1.0, 0.4, 0.3, 0.6)
const MARKER_NORMAL := Color(0.4, 0.7, 1.0, 0.5)
const MARKER_BORDER_SELECTED := Color(0.45, 0.90, 1.0, 1.0)
const MARKER_BORDER := Color(1, 1, 1, 0.3)
const MARKER_LABEL := Color(1, 1, 1, 0.9)

# Editor — boundary rectangles.
const BOUND_FILL := Color(1.0, 0.3, 0.2, 0.25)
const BOUND_FILL_SEL := Color(1.0, 0.5, 0.2, 0.4)
const BOUND_BORDER_COL := Color(1.0, 0.3, 0.2, 0.6)
const BOUND_BORDER_SEL := Color(1.0, 0.7, 0.3, 0.9)
const BOUND_PREVIEW := Color(1.0, 1.0, 0.3, 0.35)
const BOUND_PREVIEW_PROP := Color(0.45, 0.75, 1.0, 0.35)

# Editor — toasts, mode buttons, resize handle.
const TOAST_SUCCESS := Color8(164, 240, 204)      # t7
const MODE_BUTTON_SELECTED_BG := Color8(44, 27, 79, 255)
const MODE_BUTTON_UNSELECTED_BG := Color8(19, 26, 60, 179)
const MODE_BUTTON_SELECTED_HOVER := Color8(255, 242, 176)
const RESIZE_HANDLE_BG := Color(0.10, 0.14, 0.22, 0.95)
const RESIZE_HANDLE_BORDER := Color(0.45, 0.90, 1.0, 0.5)

# Agent mood — dot/aura/label colors for the emotion HUD.
const MOOD_COLORS := {
	"happy": Color8(242, 196, 90),
	"curious": Color8(94, 194, 156),
	"frustrated": Color8(255, 138, 58),
	"tired": Color8(90, 118, 172),
	"excited": Color8(167, 122, 208),
	"neutral": Color8(120, 148, 196),
}
const MOOD_NEUTRAL := "neutral"

# Unicode emoji per mood — shown next to mood label in emotion HUD and briefly
# popped over the vessel's head when mood transitions.
# Emoji-capable font — the project's pixel fonts (PixelifySans etc.) have no
# emoji glyphs. Labels that display emoji must override with a SystemFont that
# resolves to the OS emoji font (Noto Color Emoji on Linux/WSL2, Segoe on
# Windows, Apple Color Emoji on macOS).
static var _emoji_font: SystemFont = null

static func emoji_font() -> SystemFont:
	if _emoji_font != null:
		return _emoji_font
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Noto Color Emoji",
		"Segoe UI Emoji",
		"Apple Color Emoji",
		"Twemoji",
		"JoyPixels",
	])
	_emoji_font = f
	return f


const MOOD_EMOJI := {
	"happy": "😊",
	"curious": "🤔",
	"frustrated": "😠",
	"tired": "😴",
	"excited": "🤩",
	"neutral": "😐",
}

# Gateway health indicator colors (ok / fail / unknown).
const HEALTH_OK := Color8(94, 194, 156)
const HEALTH_FAIL := Color8(255, 138, 58)
const HEALTH_UNKNOWN := Color8(90, 118, 172)

# Emotion bar fills
const BAR_BG := Color8(6, 7, 26)
const BAR_COLORS := {
	"energy": Color8(94, 194, 156),
	"patience": Color8(242, 196, 90),
	"social_battery": Color8(222, 79, 158),
}

# Agent mood aura — radial gradient texture for the soft halo behind agents.
# INNER is the center stop (visible); OUTER is the edge stop (invisible).
# HIDDEN is the modulate color used when the aura should not show.
const MOOD_AURA_GRADIENT_INNER := Color(1, 1, 1, 0.3)
const MOOD_AURA_GRADIENT_OUTER := Color(1, 1, 1, 0.0)
const MOOD_AURA_HIDDEN := Color(0, 0, 0, 0)


# ── Typed lookups ────────────────────────────────────────────────────────
# Callers go through these accessors instead of reaching into the const dicts
# directly — the dicts return Variant, the accessors return Color/String.

static func mood_color(mood: String) -> Color:
	"""Stable color for a mood key. Falls back to the neutral mood color."""
	var c: Color = MOOD_COLORS.get(mood, MOOD_COLORS[MOOD_NEUTRAL])
	return c


static func mood_emoji(mood: String) -> String:
	"""Unicode emoji glyph for a mood key. Falls back to the neutral emoji."""
	var s: String = MOOD_EMOJI.get(mood, MOOD_EMOJI[MOOD_NEUTRAL])
	return s


static func bar_color(bar_name: String) -> Color:
	"""Fill color for a stat bar. Unknown names fall back to white so the
	typo is visible in-game."""
	var c: Color = BAR_COLORS.get(bar_name, Color.WHITE)
	return c


static func narration_color(type_name: String) -> String:
	"""BBCode hex color for a narration log entry type. Unknown types fall
	back to the `event` color."""
	var s: String = NARRATION_TYPE_COLORS.get(type_name, NARRATION_TYPE_COLORS["event"])
	return s


# Stat bar (energy / patience / social_battery) — same look in the emotion HUD
# and the dialogue stats popup. min_size lets each caller size to its slot.
static func build_stat_bar(bar_name: String, min_size: Vector2 = Vector2(0, 8)) -> ProgressBar:
	"""Builds a 0–1 ProgressBar themed for one of the three emotion stats.
	Unknown `bar_name` falls back to a white fill (so the bar is still visible
	and the typo is obvious in-game)."""
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.5
	bar.show_percentage = false
	bar.custom_minimum_size = min_size
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg_style := kit_style("bar_track", 0, 0)
	if bg_style is StyleBoxFlat:
		(bg_style as StyleBoxFlat).bg_color = BAR_BG
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := kit_style("bar_fill", 0, 0)
	if fill_style is StyleBoxTexture:
		(fill_style as StyleBoxTexture).modulate_color = bar_color(bar_name)
	else:
		(fill_style as StyleBoxFlat).bg_color = bar_color(bar_name)
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar

# Hex versions for BBCode
const ACCENT_HEX := "f2c45a"
const TEXT_HEX := "c8dbf0"
const TEXT_DIM_HEX := "7894c4"
const TEXT_PLAYER_HEX := "5ec29c"
const TEXT_AGENT_HEX := "f2c45a"
const TIMESTAMP_HEX := "435a94"
const MOOD_HAPPY_HEX := "fff2b0"

# Narration log entry types → BBCode hex
const NARRATION_TYPE_COLORS := {
	"event": "a77ad0",
	"thought": "a4f0cc",
	"dialogue": "c8dbf0",
	"emotion": "ff9ccc",
	"action": TEXT_DIM_HEX,
	"solve": MOOD_HAPPY_HEX,
}

# Narration log panel — darker than the default panel so the history
# sidebar visually recedes behind active UI like the dialogue cloud.
const LOG_BG := Color8(6, 7, 26, 200)

# Menu
const MENU_BG := Color8(6, 7, 26)

# Thought bubble — moonlit cloud with a night rim and violet dots.
const THOUGHT_BUBBLE_BG := Color8(242, 246, 255, 250)
const THOUGHT_BUBBLE_BORDER := Color8(6, 7, 26, 242)
const THOUGHT_BUBBLE_DOT := Color8(65, 40, 107)

# Controls hint — bottom-left key-cap pill background + border.
const CONTROLS_HINT_KEY_BG := Color8(27, 37, 80, 230)
const CONTROLS_HINT_KEY_BORDER := Color8(67, 90, 148, 230)

# Accent-tinted hover border for the prominent_button pill — keeps the
# warm campfire hue but softened so the pill doesn't shout.
const ACCENT_BORDER_HOVER := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75)

# ── Sizes (640x360 base; canvas_items draws them x3 at 1080p) ──
const CORNER := 0
const BORDER_W := 1
const FRAMED_BORDER_W := 1
const FRAMED_CORNER := 0

# Panel content padding — `panel_style` (loose) vs `framed_panel_style` (chunky).
const PAD_PANEL_X := 8
const PAD_PANEL_Y := 6
const PAD_FRAMED_X := 14
const PAD_FRAMED_Y := 12

# Button heights — large/medium/small buckets used by the primary/mode/action
# button factories. Heights drive vertical rhythm across forms; keep them in
# sync if anchors change.
const BUTTON_HEIGHT_LG := 22
const BUTTON_HEIGHT_MD := 20
const BUTTON_HEIGHT_SM := 18

# Button content padding — three buckets matching the three button heights,
# plus a tight pill bucket for the prominent_button keycap-style pill.
const PAD_BUTTON_LG_X := 10
const PAD_BUTTON_LG_Y := 3
const PAD_BUTTON_MD_X := 8
const PAD_BUTTON_MD_Y := 3
const PAD_BUTTON_SM_X := 6
const PAD_BUTTON_SM_Y := 2
const PAD_BUTTON_MENU_Y := 2   # small_menu_button — tighter than action_button
const PAD_BUTTON_PILL_X := 4
const PAD_BUTTON_PILL_Y := 2

# Modal sizing & layering.
const MODAL_LAYER := 50
const MODAL_MIN_WIDTH := 200
const MODAL_OUTER_SEP := 8
const MODAL_BODY_SEP := 4

# Toast sizing.
const TOAST_OFFSET_TOP := 12.0
const TOAST_SHADOW_OFFSET := 1
const TOAST_SHADOW_OUTLINE := 2

# In-world top-left menu stack — anchor offsets + VBox separation.
const MENU_STACK_OFFSET_LEFT := 6.0
const MENU_STACK_OFFSET_TOP := 6.0
const MENU_STACK_OFFSET_RIGHT := 120.0
const MENU_STACK_OFFSET_BOTTOM := 120.0
const MENU_STACK_SEPARATION := 4

# ── Fonts ──
# OFL pixel fonts (credits in res://assets/fonts/OFL.txt): PixelifySans body,
# Silkscreen HUD, Jersey 10 titles. Sizes are native on the 640x360 grid.
#
# Pixel fonts only render crisp when antialiasing, hinting, and subpixel
# positioning are ALL disabled — otherwise Godot tries to smooth them and
# the glyphs turn to mush. ensure_fonts_loaded() enforces that once.
const FONT_BODY_PATH := "res://assets/fonts/PixelifySans.ttf"
const FONT_HUD_PATH := "res://assets/fonts/Silkscreen-Regular.ttf"
const FONT_TITLE_PATH := "res://assets/fonts/Jersey10-Regular.ttf"

const FONT_SIZE_BODY := 16
const FONT_SIZE_HUD := 8
const FONT_SIZE_SECTION := 16
const FONT_SIZE_TITLE := 20

static var FONT_BODY: FontFile = null
static var FONT_HUD: FontFile = null
static var FONT_TITLE: FontFile = null
static var _fonts_loaded: bool = false

# ── UI kit (code-drawn PNGs + ui.json from tools/art/ui/build_ui.py) ──
const UI_DIR := "res://assets/ui/"
const FONT_DISABLED := Color8(67, 90, 148)        # n6
const SELECTION := Color8(156, 44, 124, 160)      # m1 text selection
const CURSOR_SCALE_BASE := 360

static var _kit_items: Dictionary = {}
static var _kit_loaded: bool = false
static var _kit_textures: Dictionary = {}

# ── Helpers ──

# ── Pixel fonts ──────────────────────────────────────────────────────────
# Loaded once at startup via apply_default_theme(), then reused everywhere.
# The three FontFile resources are cached on UITheme as static vars so any
# script can reach for them directly (e.g. for add_theme_font_override on
# a specific Label). The project-wide default font is set on the root
# Window's theme in apply_default_theme(), so 99% of controls inherit the
# body font automatically without any per-node setup.

static func _load_pixel_font(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		push_warning("[ui_theme] Pixel font missing: %s" % path)
		return null
	var font: FontFile = load(path)
	if font == null:
		push_warning("[ui_theme] Failed to load font: %s" % path)
		return null
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.force_autohinter = false
	font.generate_mipmaps = false
	return font


static func ensure_fonts_loaded() -> void:
	# The project-wide default font is wired through project.godot
	# (gui/theme/custom_font + gui/theme/default_font_*). This cache just
	# holds references so specific controls can opt into FONT_HUD /
	# FONT_TITLE via add_theme_font_override().
	if _fonts_loaded:
		return
	FONT_BODY = _load_pixel_font(FONT_BODY_PATH)
	FONT_HUD = _load_pixel_font(FONT_HUD_PATH)
	FONT_TITLE = _load_pixel_font(FONT_TITLE_PATH)
	_fonts_loaded = true


## Manifest entry (file, size, margin, frames, kind) of one kit item; empty when the kit is not built.
static func kit_meta(item: String) -> Dictionary:
	if not _kit_loaded:
		_kit_loaded = true
		var path := ProjectSettings.globalize_path(UI_DIR + "ui.json")
		if FileAccess.file_exists(path):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				_kit_items = (data as Dictionary).get("items", {})
		if _kit_items.is_empty():
			push_warning("[ui_theme] UI kit missing: run tools/art/ui/build_ui.py")
	var meta: Dictionary = _kit_items.get(item, {})
	return meta


## Kit texture loaded with Image.load_from_file (no import step); null when missing.
static func kit_texture(item: String) -> Texture2D:
	if _kit_textures.has(item):
		return _kit_textures[item]
	var tex: Texture2D = null
	var meta := kit_meta(item)
	if not meta.is_empty():
		var img := Image.load_from_file(ProjectSettings.globalize_path(UI_DIR + String(meta["file"])))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_kit_textures[item] = tex
	return tex


## 9-slice StyleBoxTexture of a kit item (frame picks a cell of a strip); flat panel fallback without the kit.
static func kit_style(item: String, pad_x: int = -1, pad_y: int = -1, frame: int = 0) -> StyleBox:
	var tex := kit_texture(item)
	if tex == null:
		var flat := _flat_panel_style()
		if pad_x >= 0:
			flat.content_margin_left = pad_x
			flat.content_margin_right = pad_x
		if pad_y >= 0:
			flat.content_margin_top = pad_y
			flat.content_margin_bottom = pad_y
		return flat
	var meta := kit_meta(item)
	var m: Array = meta.get("margin", [0, 0, 0, 0])
	var cell: Array = meta.get("size", [tex.get_width(), tex.get_height()])
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.region_rect = Rect2(float(cell[0]) * frame, 0, float(cell[0]), float(cell[1]))
	s.texture_margin_left = m[0]
	s.texture_margin_top = m[1]
	s.texture_margin_right = m[2]
	s.texture_margin_bottom = m[3]
	var mode := StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH if meta.get("stretch", false) else StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_horizontal = mode
	s.axis_stretch_vertical = mode
	s.content_margin_left = pad_x if pad_x >= 0 else m[0]
	s.content_margin_right = pad_x if pad_x >= 0 else m[2]
	s.content_margin_top = pad_y if pad_y >= 0 else m[1]
	s.content_margin_bottom = pad_y if pad_y >= 0 else m[3]
	return s


## Frame count of an animated kit strip (focus_shimmer has 4); 1 for still items.
static func kit_frames(item: String) -> int:
	return int(kit_meta(item).get("frames", 1))


## Labelled keycap texture: "e", "esc", "ctrl_l", "enter", "up", "down", "left", "right", "wheel".
static func keycap_texture(key: String) -> Texture2D:
	return kit_texture("key_" + key)


static func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func _theme_buttons(theme: Theme) -> void:
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, kit_style("btn_normal", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y))
		theme.set_stylebox("hover", type, kit_style("btn_hover", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y))
		theme.set_stylebox("pressed", type, _pressed_inset(kit_style("btn_pressed", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y), kit_style("btn_normal", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y)))
		theme.set_stylebox("hover_pressed", type, kit_style("btn_hover", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y))
		theme.set_stylebox("disabled", type, kit_style("btn_disabled", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y))
		theme.set_stylebox("focus", type, kit_style("focus", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, ACCENT)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_hover_pressed_color", type, ACCENT)
		theme.set_color("font_focus_color", type, TEXT)
		theme.set_color("font_disabled_color", type, FONT_DISABLED)
	for type: String in ["CheckBox", "CheckButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, _empty_style())
		theme.set_icon("checked", type, kit_texture("check_on"))
		theme.set_icon("unchecked", type, kit_texture("check_off"))
		theme.set_icon("checked_disabled", type, kit_texture("check_on"))
		theme.set_icon("unchecked_disabled", type, kit_texture("check_off"))
		theme.set_icon("radio_checked", type, kit_texture("radio_on"))
		theme.set_icon("radio_unchecked", type, kit_texture("radio_off"))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, ACCENT)
		theme.set_color("font_pressed_color", type, TEXT)
		theme.set_color("font_hover_pressed_color", type, ACCENT)
		theme.set_constant("h_separation", type, 4)


static func _theme_fields(theme: Theme) -> void:
	for type: String in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, kit_style("field", 5, 3))
		theme.set_stylebox("focus", type, kit_style("field_focus", 5, 3))
		theme.set_stylebox("read_only", type, kit_style("field_readonly", 5, 3))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_placeholder_color", type, INPUT_PLACEHOLDER)
		theme.set_color("caret_color", type, ACCENT)
		theme.set_color("selection_color", type, SELECTION)
		theme.set_color("font_selected_color", type, BUTTON_HOVER_TEXT)
	theme.set_stylebox("panel", "TooltipPanel", kit_style("tooltip", 5, 3))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "PopupMenu", kit_style("panel_dim", 6, 5))
	theme.set_stylebox("hover", "PopupMenu", kit_style("select9", 6, 1))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", ACCENT)
	theme.set_color("font_disabled_color", "PopupMenu", FONT_DISABLED)
	theme.set_icon("radio_checked", "PopupMenu", kit_texture("gem"))
	theme.set_icon("submenu", "PopupMenu", kit_texture("arrow_right"))
	theme.set_icon("arrow", "OptionButton", kit_texture("arrow_down"))
	theme.set_icon("up", "SpinBox", kit_texture("arrow_up"))
	theme.set_icon("up_hover", "SpinBox", kit_texture("arrow_up_hover"))
	theme.set_icon("down", "SpinBox", kit_texture("arrow_down"))
	theme.set_icon("down_hover", "SpinBox", kit_texture("arrow_down_hover"))
	theme.set_icon("checked", "PopupMenu", kit_texture("gem"))


static func _theme_containers(theme: Theme) -> void:
	for type: String in ["PanelContainer", "Panel"]:
		theme.set_stylebox("panel", type, panel_style())
	for type: String in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, kit_style("tab_selected", 8, 3))
		theme.set_stylebox("tab_unselected", type, kit_style("tab_unselected", 8, 3))
		theme.set_stylebox("tab_hovered", type, kit_style("tab_hovered", 8, 3))
		theme.set_stylebox("tab_disabled", type, kit_style("tab_unselected", 8, 3))
		theme.set_stylebox("tab_focus", type, kit_style("focus", 8, 3))
		theme.set_color("font_selected_color", type, ACCENT)
		theme.set_color("font_unselected_color", type, TEXT_DIM)
		theme.set_color("font_hovered_color", type, TEXT)
		theme.set_icon("increment", type, kit_texture("arrow_right"))
		theme.set_icon("increment_highlight", type, kit_texture("arrow_right_hover"))
		theme.set_icon("decrement", type, kit_texture("arrow_left"))
		theme.set_icon("decrement_highlight", type, kit_texture("arrow_left_hover"))
	theme.set_stylebox("panel", "TabContainer", kit_style("panel", 6, 6))
	theme.set_stylebox("tabbar_background", "TabContainer", _empty_style())
	theme.set_stylebox("separator", "HSeparator", line_style())
	theme.set_constant("separation", "HSeparator", 6)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)


static func _theme_ranges(theme: Theme) -> void:
	for type: String in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", type, kit_style("slider_track", 0, 2))
		theme.set_stylebox("grabber_area", type, kit_style("slider_fill", 0, 2))
		theme.set_stylebox("grabber_area_highlight", type, kit_style("slider_fill_hover", 0, 2))
		theme.set_icon("grabber", type, kit_texture("slider_grabber"))
		theme.set_icon("grabber_highlight", type, kit_texture("slider_grabber_hover"))
		theme.set_icon("grabber_disabled", type, kit_texture("slider_grabber"))
	for type: String in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", type, kit_style("scroll_track", 2, 2))
		theme.set_stylebox("scroll_focus", type, kit_style("scroll_track", 2, 2))
		theme.set_stylebox("grabber", type, kit_style("scroll_grabber", 2, 2))
		theme.set_stylebox("grabber_highlight", type, kit_style("scroll_grabber_hover", 2, 2))
		theme.set_stylebox("grabber_pressed", type, kit_style("scroll_grabber_pressed", 2, 2))
	theme.set_stylebox("background", "ProgressBar", kit_style("bar_track", 0, 0))
	theme.set_stylebox("fill", "ProgressBar", kit_style("slider_fill", 0, 0))
	theme.set_color("font_color", "ProgressBar", TEXT)


static func build_default_theme() -> Theme:
	"""Assembles the project-wide Theme resource: PixelifySans body font at
	FONT_SIZE_BODY plus the kit styles for every stock widget. Specific
	controls still override font and size at their call sites (titles use
	FONT_TITLE, HUD labels FONT_HUD)."""
	ensure_fonts_loaded()
	var theme := Theme.new()
	if FONT_BODY != null:
		theme.default_font = FONT_BODY
	theme.default_font_size = FONT_SIZE_BODY
	if kit_texture("panel") != null:
		_theme_buttons(theme)
		_theme_fields(theme)
		_theme_containers(theme)
		_theme_ranges(theme)
	return theme


static func apply_default_theme() -> void:
	"""Installs the default theme on the scene tree root. Every Control in
	every scene inherits it automatically — no per-scene wiring needed.
	Called from GameState._ready() after config load. Idempotent: calling
	twice reuses the same cached font resources."""
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root: Window = tree.root
	if root == null:
		return
	var theme := build_default_theme()
	root.theme = theme
	# Controls under a CanvasLayer do not inherit the root Window theme; the engine default theme reaches them.
	ThemeDB.get_default_theme().merge_with(theme)
	_apply_cursor()


static func _apply_cursor() -> void:
	var tex := kit_texture("cursor")
	if tex == null or DisplayServer.get_name() == "headless":
		return
	var k := maxi(1, DisplayServer.window_get_size().y / CURSOR_SCALE_BASE)
	var img := tex.get_image()
	img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	Input.set_custom_mouse_cursor(img, Input.CURSOR_ARROW, Vector2.ZERO)


static func panel_style() -> StyleBox:
	"""Standard panel chrome: the kit's 9-slice glass panel with gold hairlines, panel padding."""
	return kit_style("panel", PAD_PANEL_X, PAD_PANEL_Y)


static func _flat_panel_style() -> StyleBoxFlat:
	"""Flat stand-in for kit styles when the UI kit is not built."""
	var s := StyleBoxFlat.new()
	s.bg_color = BG
	s.border_color = BORDER
	s.set_corner_radius_all(CORNER)
	s.set_border_width_all(BORDER_W)
	s.content_margin_left = PAD_PANEL_X
	s.content_margin_right = PAD_PANEL_X
	s.content_margin_top = PAD_PANEL_Y
	s.content_margin_bottom = PAD_PANEL_Y
	return s


static func framed_panel_style() -> StyleBox:
	"""Big chrome panel used by the room selector, settings, and modals —
	the kit's glass frame with gold hairlines and gem filigree corners."""
	var s := kit_style("frame", PAD_FRAMED_X, PAD_FRAMED_Y)
	if s is StyleBoxFlat:
		var flat := s as StyleBoxFlat
		flat.bg_color = FRAMED_BG
		flat.border_color = FRAMED_BORDER
		flat.set_border_width_all(FRAMED_BORDER_W)
	return s


static func attach_arcane_corners(panel: Control, inset: int = 4, glyph_size: int = 10) -> Control:
	"""Attaches an ArcaneCorners overlay to `panel` — four filigree corners
	(a no-op when the panel's kit 9-slice already draws them). The overlay
	anchors to the full panel rect and ignores mouse so it never blocks
	input. Returns the overlay node."""
	if panel == null:
		return null
	var corners := ArcaneCorners.new()
	corners.inset = inset
	corners.glyph_size = glyph_size
	corners.anchor_right = 1.0
	corners.anchor_bottom = 1.0
	corners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(corners)
	return corners


static func wallpaper_background(parent: CanvasLayer, dim_for_readability: bool = false) -> void:
	"""Solid night bg + the live title scene (menu_backdrop.gd) + a dark glass layer —
	the layered backdrop used by every menu screen. Adds three children."""
	var bg := ColorRect.new()
	bg.color = MENU_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	parent.add_child(bg)

	parent.add_child(preload("res://scripts/menu_backdrop.gd").new())

	var glass := ColorRect.new()
	glass.color = BACKDROP_GLASS_DIM if dim_for_readability else BACKDROP_GLASS
	glass.anchor_right = 1.0
	glass.anchor_bottom = 1.0
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(glass)


static func paint_danger(btn: Button) -> void:
	"""Re-tints an existing button red — used to mark destructive actions
	(delete, remove) without changing the button's shape or padding."""
	btn.add_theme_color_override("font_color", DANGER)
	btn.add_theme_color_override("font_hover_color", DANGER_HOVER)


static func section_spacer(height: int = 8) -> Control:
	"""Fixed-height empty Control for vertical breathing room inside a VBox."""
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


static func apply_mode_button_style(btn: Button, selected: bool) -> void:
	"""Toggle-button look used by the editor mode switch. Each Button state
	gets its own stylebox instance so the overrides cannot alias and mutate
	together if a caller later edits one of them."""
	if selected:
		btn.add_theme_color_override("font_color", ACCENT)
		btn.add_theme_color_override("font_hover_color", MODE_BUTTON_SELECTED_HOVER)
	else:
		btn.add_theme_color_override("font_color", TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", TEXT)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, _mode_button_stylebox(selected, state))


static func _mode_button_stylebox(selected: bool, state: String = "normal") -> StyleBox:
	if selected:
		return kit_style("btn_hover", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y)
	if state == "hover" or state == "pressed":
		return kit_style("btn_quiet_hover", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y)
	return kit_style("btn_quiet", PAD_BUTTON_MD_X, PAD_BUTTON_MD_Y)


static func mode_button(text: String) -> Button:
	"""Builds an unselected mode-toggle button — caller flips it to selected
	via apply_mode_button_style(btn, true) when activated."""
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_MD)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	apply_mode_button_style(btn, false)
	return btn


static func small_menu_button(text: String) -> Button:
	"""Compact quiet button used for the in-world Main Menu return link."""
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	btn.add_theme_color_override("font_color", TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	var s := kit_style("btn_quiet", PAD_BUTTON_SM_X, PAD_BUTTON_MENU_Y)
	btn.add_theme_stylebox_override("normal", s)
	var hover := kit_style("btn_quiet_hover", PAD_BUTTON_SM_X, PAD_BUTTON_MENU_Y)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	return btn


static func line_style(color: Color = BORDER) -> StyleBox:
	"""Separator stylebox: the kit's fading gold hairline, or a thin flat
	line at 50% of `color`'s alpha when the kit is missing."""
	var rule := kit_texture("rule")
	if rule != null and color == BORDER:
		var s := kit_style("rule", 0, 1)
		s.content_margin_bottom = 2
		return s
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(color.r, color.g, color.b, color.a * 0.5)
	flat.content_margin_top = 1
	flat.content_margin_bottom = 1
	return flat


# ── Agent name colors ──
# Stable per-agent color derived from the agent_id hash. Hue spans the full
# wheel; saturation and value are kept in a high-contrast band so every color
# reads against the dark panel background. All three channels derive from the
# same hash int, so they are not independently distributed — fine in practice
# for the small agent counts this game ships with.
static func agent_color(agent_id: String) -> Color:
	"""Deterministic per-agent color. Empty id falls back to ACCENT."""
	if agent_id == "":
		return ACCENT
	var h: int = absi(agent_id.hash())
	var hue: float = float(h % 360) / 360.0
	var sat: float = 0.55 + float((h / 360) % 25) / 100.0  # 0.55–0.79
	var val: float = 0.90 + float((h / 9000) % 10) / 100.0  # 0.90–0.99
	return Color.from_hsv(hue, sat, val)


static func agent_color_hex(agent_id: String) -> String:
	"""Same as agent_color() but as a `#rrggbb` string for BBCode."""
	return "#" + agent_color(agent_id).to_html(false)


# ── Buttons ──
# Shared button builders used by the editor and settings screens so both
# surfaces keep the same top-bar style.

static func _kit_button(text: String, height: int, pad_x: int, pad_y: int, normal: String) -> Button:
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(0, height)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	btn.add_theme_color_override("font_pressed_color", ACCENT)
	var s := kit_style(normal, pad_x, pad_y)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", kit_style("btn_hover", pad_x, pad_y))
	btn.add_theme_stylebox_override("pressed", _pressed_inset(kit_style("btn_pressed", pad_x, pad_y), s))
	btn.add_theme_stylebox_override("disabled", kit_style("btn_disabled", pad_x, pad_y))
	return btn


static func primary_button(text: String) -> Button:
	"""Big button for top-row actions (Save, Back): navy glass with dark gold
	hairlines; hover turns violet with a magenta gem notch, like the title."""
	return _kit_button(text, BUTTON_HEIGHT_LG, PAD_BUTTON_LG_X, PAD_BUTTON_LG_Y, "btn_normal")


static func section_header(text: String) -> Label:
	"""Lavender section header — same style as Edit sidebar headings."""
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_SECTION)
	lbl.add_theme_color_override("font_color", SECTION)
	return lbl


static func form_label(text: String) -> Label:
	"""Small dim label used to annotate form rows."""
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	return lbl


static func action_button(text: String) -> Button:
	"""Medium button for Add / Delete / secondary actions."""
	return _kit_button(text, BUTTON_HEIGHT_SM, PAD_BUTTON_SM_X, PAD_BUTTON_SM_Y, "btn_normal")


static func _pressed_inset(base: StyleBox, ref: StyleBox) -> StyleBox:
	# Press-in: shift content 1px down/right by adjusting content margins.
	# `ref` carries the original padding so the inset is symmetric regardless
	# of which hover/normal style was duplicated.
	# Precondition: `ref` bottom/right margins must be >= 1 — otherwise the
	# subtraction yields a negative content margin and Godot will silently
	# accept it. All current callers use PAD_BUTTON_*_Y >= 2.
	var pressed := base.duplicate() as StyleBox
	pressed.content_margin_top = ref.content_margin_top + 1
	pressed.content_margin_bottom = ref.content_margin_bottom - 1
	pressed.content_margin_left = ref.content_margin_left + 1
	pressed.content_margin_right = ref.content_margin_right - 1
	return pressed


static func prominent_button(text: String) -> Button:
	"""Subtle pill button for the in-world menu stack. Matches the
	bottom-left controls-hint keycaps: dim HUD text on a quiet navy cap
	that reveals itself on hover (gold text, gold hairline). Deliberately
	quiet so the world stays the focus."""
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(0, 0)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_HUD)
	ensure_fonts_loaded()
	if FONT_HUD != null:
		btn.add_theme_font_override("font", FONT_HUD)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	var s := kit_style("btn_quiet", PAD_BUTTON_PILL_X, PAD_BUTTON_PILL_Y)
	btn.add_theme_stylebox_override("normal", s)
	var hover := kit_style("btn_quiet_hover", PAD_BUTTON_PILL_X, PAD_BUTTON_PILL_Y)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	return btn


# ── Toast ─────────────────────────────────────────────────────────────────
# Top-center transient confirmation label. Fades in, holds, fades out.
# Matches the look of the editor's save toast. Callers build the label
# once (add to a CanvasLayer), then call show_toast(label, text) from
# any action that deserves a "here's what I just did" confirmation.

static func build_toast_label() -> Label:
	"""Constructs the transparent top-center toast Label. Caller adds it to a
	CanvasLayer once, then drives it via show_toast(label, text)."""
	var label := Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.offset_top = TOAST_OFFSET_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	label.add_theme_color_override("font_color", TOAST_SUCCESS)
	label.add_theme_color_override("font_shadow_color", LABEL_SHADOW_HEAVY)
	label.add_theme_constant_override("shadow_offset_x", TOAST_SHADOW_OFFSET)
	label.add_theme_constant_override("shadow_offset_y", TOAST_SHADOW_OFFSET)
	label.add_theme_constant_override("shadow_outline_size", TOAST_SHADOW_OUTLINE)
	label.modulate.a = 0.0
	return label


static func show_toast(label: Label, text: String) -> void:
	"""Fades the toast label in, holds, and fades it out. Re-invoking before
	the previous toast finishes kills the old tween and restarts cleanly."""
	if label == null:
		return
	label.text = text
	var existing: Tween = label.get_meta("_toast_tween", null)
	if existing != null and existing.is_valid():
		existing.kill()
	label.modulate.a = 0.0
	var tw := label.create_tween()
	var fade_in: float = GameState.get_ui_float("toast_fade_in", 0.2)
	var hold: float = GameState.get_ui_float("toast_hold", 1.4)
	var fade_out: float = GameState.get_ui_float("toast_fade_out", 0.4)
	tw.tween_property(label, "modulate:a", 1.0, fade_in).set_trans(Tween.TRANS_LINEAR)
	tw.tween_interval(hold)
	tw.tween_property(label, "modulate:a", 0.0, fade_out).set_trans(Tween.TRANS_LINEAR)
	label.set_meta("_toast_tween", tw)


# ── Modal popup ───────────────────────────────────────────────────────────
# Custom modal built on a CanvasLayer so dialogs match the rest of the UI
# instead of falling back to Godot's native ConfirmationDialog chrome.
# Caller adds rows to `result.body`, connects `result.ok_button.pressed` /
# `result.cancel_button.pressed`, adds `result.layer` to the scene, and frees
# the layer when done. The backdrop swallows clicks outside the panel so
# nothing underneath is interactable while the modal is up.

class ModalResult extends RefCounted:
	## Typed bundle of nodes returned by `UITheme.modal()`. Callers wire
	## button signals and add `layer` to the scene; freeing `layer` tears
	## down the entire popup.
	var layer: CanvasLayer
	var body: VBoxContainer
	var ok_button: Button
	var cancel_button: Button


static func modal(title_text: String, ok_text: String = "OK", cancel_text: String = "Cancel") -> ModalResult:
	"""Builds an arcane-cornered modal with a title bar, a body VBox for the
	caller to populate, and an OK/Cancel button row. Returns a typed
	ModalResult — no casting required at the call site."""
	var layer := CanvasLayer.new()
	layer.layer = MODAL_LAYER
	_modal_backdrop(layer)

	var panel := _modal_panel(layer)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", MODAL_OUTER_SEP)
	panel.add_child(outer)

	if title_text != "":
		outer.add_child(_modal_title(title_text))

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", MODAL_BODY_SEP)
	outer.add_child(body)

	var ok_btn := primary_button(ok_text)
	var cancel_btn := primary_button(cancel_text)
	outer.add_child(_modal_button_row(ok_btn, cancel_btn))

	attach_arcane_corners(panel)

	var result := ModalResult.new()
	result.layer = layer
	result.body = body
	result.ok_button = ok_btn
	result.cancel_button = cancel_btn
	return result


static func _modal_backdrop(layer: CanvasLayer) -> void:
	var backdrop := ColorRect.new()
	backdrop.color = MODAL_BACKDROP
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(backdrop)


static func _modal_panel(layer: CanvasLayer) -> PanelContainer:
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	layer.add_child(center)
	var panel := PanelContainer.new()
	var style := kit_style("modal", PAD_FRAMED_X, PAD_FRAMED_Y)
	panel.add_theme_stylebox_override("panel", style if style is StyleBoxTexture else framed_panel_style())
	panel.custom_minimum_size = Vector2(MODAL_MIN_WIDTH, 0)
	center.add_child(panel)
	return panel


static func _modal_title(text: String) -> Label:
	var title := Label.new()
	title.text = text.to_upper()
	ensure_fonts_loaded()
	if FONT_TITLE != null:
		title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_color_override("font_shadow_color", LABEL_SHADOW_HEAVY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


static func _modal_button_row(ok_btn: Button, cancel_btn: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MODAL_BODY_SEP)
	row.add_child(ok_btn)
	row.add_child(cancel_btn)
	return row
