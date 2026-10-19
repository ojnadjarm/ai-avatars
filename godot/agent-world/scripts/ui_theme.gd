class_name UITheme
## Shared UI palette and helpers — single source of truth for all panels.
## Colors derived from the menu wallpaper: deep blue-purple forest, golden campfire, cyan magic.

# ── Palette ──
const BG := Color(0.04, 0.04, 0.10, 0.88)
const BORDER := Color(0.30, 0.25, 0.50, 0.5)
const ACCENT := Color(1.0, 0.82, 0.40)
const TEXT := Color(0.88, 0.86, 0.82)
const TEXT_DIM := Color(0.50, 0.48, 0.56)
const TEXT_PLAYER := Color(0.45, 0.75, 1.0)
const TEXT_AGENT := Color(1.0, 0.78, 0.35)
const INPUT_BG := Color(0.03, 0.03, 0.08, 0.95)
const INPUT_BORDER := Color(0.25, 0.22, 0.40, 0.5)
const INPUT_FOCUS := Color(0.45, 0.35, 0.65, 0.7)

# Section header cyan — used by the Edit sidebar and the Settings tabs.
const SECTION := Color(0.45, 0.90, 1.0)

# Framed panel — settings screen, room selector, modal. Slightly more opaque
# than BG and with a tighter purple border.
const FRAMED_BG := Color(0.04, 0.04, 0.10, 0.92)
const FRAMED_BORDER := Color(0.35, 0.30, 0.55, 0.6)

# Modal backdrop — full-screen dim behind LogModal and similar overlays.
const MODAL_BACKDROP := Color(0.0, 0.0, 0.0, 0.75)

# Tab container
const TAB_BG := Color(0.03, 0.03, 0.08, 0.85)
const TAB_SELECTED_BG := Color(0.08, 0.10, 0.18, 1.0)
const TAB_HOVERED_BG := Color(0.06, 0.06, 0.14, 0.6)
const TAB_TRANSPARENT := Color(0, 0, 0, 0)

# Avatar picker cell
const CELL_BG := Color(0.06, 0.06, 0.14, 0.7)

# Button variants
const BUTTON_BG := Color(0.05, 0.05, 0.12, 0.95)
const BUTTON_BG_DIM := Color(0.05, 0.05, 0.12, 0.85)
const BUTTON_HOVER_BG := Color(0.10, 0.10, 0.20, 0.95)
const BUTTON_HOVER_BORDER := Color(0.55, 0.45, 0.85, 0.9)
const BUTTON_HOVER_TEXT := Color(1.0, 1.0, 1.0)

# Danger (delete) button
const DANGER := Color(0.85, 0.40, 0.40)
const DANGER_HOVER := Color(1.0, 0.55, 0.55)

# Warning / action-critical chrome (end-meeting btn, destructive accents)
const WARN := Color(1.0, 0.65, 0.3)
const WARN_HOVER := Color(1.0, 0.35, 0.2)

# Dialogue close-button hover
const CLOSE_HOVER := Color(0.9, 0.5, 0.3)

# Input field placeholder text
const INPUT_PLACEHOLDER := Color(0.4, 0.36, 0.3)

# Wallpaper overlay — darkens the wallpaper so menu text stays readable.
const WALLPAPER_OVERLAY := Color(0.02, 0.02, 0.06, 0.45)
const WALLPAPER_DIM := Color(1, 1, 1, 0.15)

# Text shadow used on world-space labels.
const LABEL_SHADOW := Color(0, 0, 0, 0.8)
const LABEL_SHADOW_STRONG := Color(0, 0, 0, 0.85)
const LABEL_SHADOW_HEAVY := Color(0, 0, 0, 0.9)

# Panel / popup drop shadow colors — applied directly on StyleBoxFlat by
# callers that want a shadow (e.g. dialogue_cloud); panel_style() itself
# does not wire shadows.
const PANEL_SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const POPUP_SHADOW := Color(0.0, 0.0, 0.0, 0.75)

# Bevel — darker bottom/right border used by the controls-hint keycap.
const BEVEL_SHADOW := Color(0.02, 0.02, 0.05, 0.9)

# Arcane ornament — rune cyan for corner glyphs on framed panels.
const ARCANE_GLYPH := Color(0.55, 0.85, 1.0, 0.85)
const ARCANE_GLYPH_DIM := Color(0.35, 0.55, 0.75, 0.55)

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
const TOAST_SUCCESS := Color(0.55, 1.0, 0.65)
const MODE_BUTTON_SELECTED_BG := Color(0.12, 0.15, 0.28, 1.0)
const MODE_BUTTON_UNSELECTED_BG := Color(0.05, 0.05, 0.12, 0.7)
const MODE_BUTTON_SELECTED_HOVER := Color(0.55, 0.95, 1.0)
const RESIZE_HANDLE_BG := Color(0.10, 0.14, 0.22, 0.95)
const RESIZE_HANDLE_BORDER := Color(0.45, 0.90, 1.0, 0.5)

# Agent mood — dot/aura/label colors for the emotion HUD.
const MOOD_COLORS := {
	"happy": Color(1.0, 0.84, 0.0),
	"curious": Color(0.4, 0.8, 1.0),
	"frustrated": Color(1.0, 0.45, 0.3),
	"tired": Color(0.55, 0.55, 0.6),
	"excited": Color(0.75, 0.4, 1.0),
	"neutral": Color(0.6, 0.55, 0.48),
}
const MOOD_NEUTRAL := "neutral"

# Unicode emoji per mood — shown next to mood label in emotion HUD and briefly
# popped over the vessel's head when mood transitions.
# Emoji-capable font — the project ships with a pixel font (m5x7) that has no
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
const HEALTH_OK := Color(0.4, 0.85, 0.4)
const HEALTH_FAIL := Color(0.9, 0.35, 0.35)
const HEALTH_UNKNOWN := Color(0.55, 0.55, 0.6)

# Emotion bar fills
const BAR_BG := Color(0.12, 0.1, 0.08)
const BAR_COLORS := {
	"energy": Color(0.35, 0.75, 0.35),
	"patience": Color(0.8, 0.6, 0.25),
	"social_battery": Color(0.7, 0.35, 0.65),
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
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BAR_BG
	bg_style.set_corner_radius_all(CORNER)
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = bar_color(bar_name)
	fill_style.set_corner_radius_all(CORNER)
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar

# Hex versions for BBCode
const ACCENT_HEX := "ffd166"
const TEXT_HEX := "e0dbd0"
const TEXT_DIM_HEX := "807a8f"
const TEXT_PLAYER_HEX := "73bfff"
const TEXT_AGENT_HEX := "ffc85a"
const TIMESTAMP_HEX := "5a5570"
const MOOD_HAPPY_HEX := "ffd600"

# Narration log entry types → BBCode hex
const NARRATION_TYPE_COLORS := {
	"event": "a89880",
	"thought": "6cb8d6",
	"dialogue": "e0dcd0",
	"emotion": "d4a840",
	"action": TEXT_DIM_HEX,
	"solve": MOOD_HAPPY_HEX,
}

# Narration log panel — darker than the default panel so the history
# sidebar visually recedes behind active UI like the dialogue cloud.
const LOG_BG := Color(BG.r * 0.6, BG.g * 0.6, BG.b * 0.6, BG.a)

# Menu
const MENU_BG := Color(0.03, 0.03, 0.08, 1.0)
const WALLPAPER_PATH := "res://assets/menu_wallpaper.png"

# Thought bubble — soft cream cloud with dark purple rim and dark dots.
const THOUGHT_BUBBLE_BG := Color(0.98, 0.98, 0.96, 0.98)
const THOUGHT_BUBBLE_BORDER := Color(0.08, 0.08, 0.14, 0.95)
const THOUGHT_BUBBLE_DOT := Color(0.25, 0.22, 0.35)

# Controls hint — bottom-left key-cap pill background + border.
const CONTROLS_HINT_KEY_BG := Color(0.08, 0.08, 0.16, 0.9)
const CONTROLS_HINT_KEY_BORDER := Color(0.55, 0.50, 0.75, 0.8)

# Accent-tinted hover border for the prominent_button pill — keeps the
# warm campfire hue but softened so the pill doesn't shout.
const ACCENT_BORDER_HOVER := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75)

# ── Sizes ──
const CORNER := 0
const BORDER_W := 1
const FRAMED_BORDER_W := 2
const FRAMED_CORNER := 0

# Panel content padding — `panel_style` (loose) vs `framed_panel_style` (chunky).
const PAD_PANEL_X := 14
const PAD_PANEL_Y := 10
const PAD_FRAMED_X := 28
const PAD_FRAMED_Y := 22

# Button heights — large/medium/small buckets used by the primary/mode/action
# button factories. Heights drive vertical rhythm across forms; keep them in
# sync if anchors change.
const BUTTON_HEIGHT_LG := 38
const BUTTON_HEIGHT_MD := 36
const BUTTON_HEIGHT_SM := 32

# Button content padding — three buckets matching the three button heights,
# plus a tight pill bucket for the prominent_button keycap-style pill.
const PAD_BUTTON_LG_X := 14
const PAD_BUTTON_LG_Y := 8
const PAD_BUTTON_MD_X := 12
const PAD_BUTTON_MD_Y := 6
const PAD_BUTTON_SM_X := 10
const PAD_BUTTON_SM_Y := 6
const PAD_BUTTON_MENU_Y := 4   # small_menu_button — tighter than action_button
const PAD_BUTTON_PILL_X := 8
const PAD_BUTTON_PILL_Y := 4

# Modal sizing & layering.
const MODAL_LAYER := 50
const MODAL_MIN_WIDTH := 380
const MODAL_OUTER_SEP := 14
const MODAL_BODY_SEP := 8

# Toast sizing.
const TOAST_OFFSET_TOP := 24.0
const TOAST_SHADOW_OFFSET := 2
const TOAST_SHADOW_OUTLINE := 3

# In-world top-left menu stack — anchor offsets + VBox separation.
const MENU_STACK_OFFSET_LEFT := 12.0
const MENU_STACK_OFFSET_TOP := 12.0
const MENU_STACK_OFFSET_RIGHT := 260.0
const MENU_STACK_OFFSET_BOTTOM := 260.0
const MENU_STACK_SEPARATION := 8

# ── Fonts ──
# Arcane Grimoire typography — all three sourced from itch.io / Google Fonts
# under permissive licenses, dropped into res://assets/fonts/ manually.
#
#   m5x7       — cursive-leaning 5×7 pixel font, body text & dialogue
#   m3x6       — tiny 3×6 pixel font, HUD labels & timestamps
#   ThaleahFat — chunky display face, titles & section headers
#
# Pixel fonts only render crisp when antialiasing, hinting, and subpixel
# positioning are ALL disabled — otherwise Godot tries to smooth them and
# the glyphs turn to mush. ensure_fonts_loaded() enforces that once.
const FONT_BODY_PATH := "res://assets/fonts/m5x7.ttf"
const FONT_HUD_PATH := "res://assets/fonts/m3x6.ttf"
const FONT_TITLE_PATH := "res://assets/fonts/ThaleahFat.ttf"

# Canonical pixel-aligned sizes. m5x7's native glyph box is 16px tall, so
# body text pins to 16 and anything mixed with it (bold, italics in the
# dialogue RichTextLabel) stays at 16 — mismatched sizes would break the
# pixel grid. m3x6 doubles cleanly from 8 to 16. Thaleah is a display face
# with no single "native" size, so its sizes are tuned visually.
const FONT_SIZE_BODY := 32
const FONT_SIZE_HUD := 16
const FONT_SIZE_SECTION := 32
const FONT_SIZE_TITLE := 48

static var FONT_BODY: FontFile = null
static var FONT_HUD: FontFile = null
static var FONT_TITLE: FontFile = null
static var _fonts_loaded: bool = false

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


static func build_default_theme() -> Theme:
	"""Assembles the project-wide Theme resource: m5x7 as the default font,
	FONT_SIZE_BODY as the default font size. Specific Control types override
	their own font/size through add_theme_font_override at their call sites
	(e.g. titles switch to Thaleah, HUD labels switch to m3x6)."""
	ensure_fonts_loaded()
	var theme := Theme.new()
	if FONT_BODY != null:
		theme.default_font = FONT_BODY
	theme.default_font_size = FONT_SIZE_BODY
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
	root.theme = build_default_theme()


static func panel_style(bg: Color = BG, border: Color = BORDER) -> StyleBoxFlat:
	"""Standard panel chrome — flat bg, 1px border, panel padding, no shadow.
	Callers that want a drop shadow set `shadow_color` / `shadow_size` on the
	returned stylebox themselves (see dialogue_cloud)."""
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_corner_radius_all(CORNER)
	s.set_border_width_all(BORDER_W)
	s.content_margin_left = PAD_PANEL_X
	s.content_margin_right = PAD_PANEL_X
	s.content_margin_top = PAD_PANEL_Y
	s.content_margin_bottom = PAD_PANEL_Y
	return s


static func framed_panel_style() -> StyleBoxFlat:
	"""Big chrome panel used by the room selector, settings, and modals —
	2px purple border, hard drop shadow, generous padding."""
	var s := panel_style(FRAMED_BG, FRAMED_BORDER)
	s.content_margin_left = PAD_FRAMED_X
	s.content_margin_right = PAD_FRAMED_X
	s.content_margin_top = PAD_FRAMED_Y
	s.content_margin_bottom = PAD_FRAMED_Y
	s.set_border_width_all(FRAMED_BORDER_W)
	s.set_corner_radius_all(FRAMED_CORNER)
	return s


static func attach_arcane_corners(panel: Control, inset: int = 4, glyph_size: int = 10) -> Control:
	"""Attaches an ArcaneCorners overlay to `panel` — four procedurally drawn
	rune glyphs in the corners. The overlay anchors to the full panel rect
	and ignores mouse so it never blocks input. Returns the overlay node."""
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
	"""Solid dark bg + menu wallpaper + optional overlay — the layered
	background used by every menu screen. Adds three children to `parent`."""
	var bg := ColorRect.new()
	bg.color = MENU_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	parent.add_child(bg)

	var tex: Texture2D = GameState.load_texture(WALLPAPER_PATH)
	if tex:
		var wallpaper := TextureRect.new()
		wallpaper.texture = tex
		wallpaper.anchor_right = 1.0
		wallpaper.anchor_bottom = 1.0
		wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if dim_for_readability:
			wallpaper.modulate = WALLPAPER_DIM
		parent.add_child(wallpaper)

		if not dim_for_readability:
			var overlay := ColorRect.new()
			overlay.color = WALLPAPER_OVERLAY
			overlay.anchor_right = 1.0
			overlay.anchor_bottom = 1.0
			parent.add_child(overlay)


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
	"""Flat toggle-button look used by the editor mode switch. Each Button state
	gets its own StyleBoxFlat instance so the four overrides cannot alias and
	mutate together if a caller later edits one of them."""
	if selected:
		btn.add_theme_color_override("font_color", SECTION)
		btn.add_theme_color_override("font_hover_color", MODE_BUTTON_SELECTED_HOVER)
	else:
		btn.add_theme_color_override("font_color", TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", TEXT)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, _mode_button_stylebox(selected))


static func _mode_button_stylebox(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(CORNER)
	s.content_margin_left = PAD_BUTTON_MD_X
	s.content_margin_right = PAD_BUTTON_MD_X
	s.content_margin_top = PAD_BUTTON_MD_Y
	s.content_margin_bottom = PAD_BUTTON_MD_Y
	if selected:
		s.bg_color = MODE_BUTTON_SELECTED_BG
		s.border_color = SECTION
		s.set_border_width_all(FRAMED_BORDER_W)
	else:
		s.bg_color = MODE_BUTTON_UNSELECTED_BG
		s.border_color = BORDER
		s.set_border_width_all(BORDER_W)
	return s


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
	"""Compact outlined button used for the in-world Main Menu return link."""
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	btn.add_theme_color_override("font_color", TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	var s := StyleBoxFlat.new()
	s.bg_color = BG
	s.border_color = BORDER
	s.set_border_width_all(BORDER_W)
	s.set_corner_radius_all(CORNER)
	s.content_margin_left = PAD_BUTTON_SM_X
	s.content_margin_right = PAD_BUTTON_SM_X
	s.content_margin_top = PAD_BUTTON_MENU_Y
	s.content_margin_bottom = PAD_BUTTON_MENU_Y
	btn.add_theme_stylebox_override("normal", s)
	var hover := s.duplicate()
	hover.border_color = ACCENT
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	return btn


static func line_style(color: Color = BORDER) -> StyleBoxFlat:
	"""Thin horizontal separator stylebox at 50% of the source color's alpha —
	used by HSeparator/VSeparator overrides to match panel chrome."""
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color.r, color.g, color.b, color.a * 0.5)
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


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

static func primary_button(text: String) -> Button:
	"""Big outlined button for top-row actions (Save, Back).
	Palette-neutral dark panel, no yellow accent — matches the Edit page."""
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_LG)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", BUTTON_HOVER_TEXT)
	var s := StyleBoxFlat.new()
	s.bg_color = BUTTON_BG
	s.border_color = BORDER
	s.set_border_width_all(FRAMED_BORDER_W)
	s.set_corner_radius_all(CORNER)
	s.content_margin_left = PAD_BUTTON_LG_X
	s.content_margin_right = PAD_BUTTON_LG_X
	s.content_margin_top = PAD_BUTTON_LG_Y
	s.content_margin_bottom = PAD_BUTTON_LG_Y
	btn.add_theme_stylebox_override("normal", s)
	var hover := s.duplicate()
	hover.bg_color = BUTTON_HOVER_BG
	hover.border_color = BUTTON_HOVER_BORDER
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", _pressed_inset(hover, s))
	return btn


static func section_header(text: String) -> Label:
	"""Cyan section header — same style as Edit sidebar headings."""
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
	"""Medium outlined button for Add / Delete / secondary actions."""
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_SM)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", BUTTON_HOVER_TEXT)
	var s := StyleBoxFlat.new()
	s.bg_color = BUTTON_BG_DIM
	s.border_color = BORDER
	s.set_border_width_all(BORDER_W)
	s.set_corner_radius_all(CORNER)
	s.content_margin_left = PAD_BUTTON_SM_X
	s.content_margin_right = PAD_BUTTON_SM_X
	s.content_margin_top = PAD_BUTTON_SM_Y
	s.content_margin_bottom = PAD_BUTTON_SM_Y
	btn.add_theme_stylebox_override("normal", s)
	var hover := s.duplicate()
	hover.bg_color = BUTTON_HOVER_BG
	hover.border_color = BUTTON_HOVER_BORDER
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", _pressed_inset(hover, s))
	return btn


static func _pressed_inset(base: StyleBoxFlat, ref: StyleBoxFlat) -> StyleBoxFlat:
	# Press-in: shift content 1px down/right by adjusting content margins.
	# `ref` carries the original padding so the inset is symmetric regardless
	# of which hover/normal style was duplicated.
	# Precondition: `ref` bottom/right margins must be >= 1 — otherwise the
	# subtraction yields a negative content margin and Godot will silently
	# accept it. All current callers use PAD_BUTTON_*_Y >= 6.
	var pressed := base.duplicate()
	pressed.content_margin_top = ref.content_margin_top + 1
	pressed.content_margin_bottom = ref.content_margin_bottom - 1
	pressed.content_margin_left = ref.content_margin_left + 1
	pressed.content_margin_right = ref.content_margin_right - 1
	return pressed


static func prominent_button(text: String) -> Button:
	"""Subtle pill button for the in-world menu stack. Matches the
	bottom-left controls-hint aesthetic: dim text, 1px soft purple
	border, tight corner radius — a passive-looking label that
	reveals itself as a button on hover (accent text, brighter
	border). Deliberately quiet so the world stays the focus."""
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(0, 0)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_HUD)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", ACCENT)
	var s := StyleBoxFlat.new()
	s.bg_color = CONTROLS_HINT_KEY_BG
	s.border_color = CONTROLS_HINT_KEY_BORDER
	s.set_border_width_all(BORDER_W)
	s.set_corner_radius_all(CORNER)
	s.content_margin_left = PAD_BUTTON_PILL_X
	s.content_margin_right = PAD_BUTTON_PILL_X
	s.content_margin_top = PAD_BUTTON_PILL_Y
	s.content_margin_bottom = PAD_BUTTON_PILL_Y
	btn.add_theme_stylebox_override("normal", s)
	var hover := s.duplicate()
	hover.border_color = ACCENT_BORDER_HOVER
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
	panel.add_theme_stylebox_override("panel", framed_panel_style())
	panel.custom_minimum_size = Vector2(MODAL_MIN_WIDTH, 0)
	center.add_child(panel)
	return panel


static func _modal_title(text: String) -> Label:
	var title := Label.new()
	title.text = text.to_upper()
	title.add_theme_font_size_override("font_size", FONT_SIZE_SECTION)
	title.add_theme_color_override("font_color", ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


static func _modal_button_row(ok_btn: Button, cancel_btn: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MODAL_BODY_SEP)
	row.add_child(ok_btn)
	row.add_child(cancel_btn)
	return row
