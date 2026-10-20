extends PanelContainer
## Avatar portrait in the kit's portrait frame at an integer scale: timed 2-frame blink, open mouth while talking.

const FRAME_TALK := 0
const FRAME_BLINK := 1
const FRAME_OPEN := 2
const BORDER := 4
const BLINK_GAP_MIN := 2.4
const BLINK_GAP_MAX := 4.8
const BLINK_TIME := 0.14
const MOUTH_STEP := 0.12

var talking: bool = false
var _frames: Array[Texture2D] = []
var _rect: TextureRect
var _t: float = 0.0
var _blink_left: float = 0.0
var _next_blink: float = BLINK_GAP_MIN
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.kit_style("portrait_frame", BORDER, BORDER))
	_rect = TextureRect.new()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var backing := Panel.new()
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.add_theme_stylebox_override("panel", UITheme.kit_style("panel", 0, 0))
	add_child(backing)
	add_child(_rect)


## Portrait strip frames (talk, blink, open mouth, signature) shown at integer scale k; the seed key fixes the blink rhythm.
func set_frames(frames: Array[Texture2D], k: int = 1, seed_key: String = "") -> void:
	_frames = frames
	visible = not frames.is_empty()
	talking = false
	_t = 0.0
	_blink_left = 0.0
	_rng.seed = hash(seed_key)
	_next_blink = _rng.randf_range(BLINK_GAP_MIN, BLINK_GAP_MAX)
	if frames.is_empty():
		_rect.texture = null
		return
	_rect.custom_minimum_size = frames[0].get_size() * maxi(1, k)
	_show(FRAME_TALK)


## Loads an agent's portrait strip (GameState) and shows it; false when the agent has none.
func show_agent(agent_id: String, k: int = 1) -> bool:
	var frames: Array[Texture2D] = []
	if agent_id != "":
		frames = GameState.load_portrait_frames(GameState.resolve_character_asset(GameState.get_agent_sprite(agent_id)))
	set_frames(frames, k, agent_id)
	return not frames.is_empty()


func _process(delta: float) -> void:
	if _frames.size() <= FRAME_OPEN:
		return
	_t += delta
	if talking:
		_show(FRAME_OPEN if int(_t / MOUTH_STEP) % 2 == 0 else FRAME_TALK)
		return
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_show(FRAME_TALK)
		return
	_next_blink -= delta
	if _next_blink <= 0.0:
		_next_blink = _rng.randf_range(BLINK_GAP_MIN, BLINK_GAP_MAX)
		_blink_left = BLINK_TIME
		_show(FRAME_BLINK)
	elif _rect.texture != _frames[FRAME_TALK]:
		_show(FRAME_TALK)


func _show(i: int) -> void:
	_rect.texture = _frames[clampi(i, 0, _frames.size() - 1)]


## Name plate on the kit's nametag 9-slice.
static func name_tag(text: String, color: Color = UITheme.ACCENT) -> Label:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_stylebox_override("normal", UITheme.kit_style("nametag", 7, 1))
	tag.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	tag.add_theme_color_override("font_color", color)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tag
