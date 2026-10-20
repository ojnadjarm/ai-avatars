extends CanvasLayer
## Zone name on the kit banner plate: unfurls from its centre when the player's feet enter a zone, holds, furls back in.

enum Phase { HIDDEN, IN, HOLD, OUT }

const SLIDE := 0.4
const HOLD := 2.5
const REENTRY := 3.0
const TOP := 10

var zone: String = ""
var _clock: float = 0.0
var _start: float = -INF
var _last_seen: Dictionary = {}
var _clip: Control
var _plate: PanelContainer
var _label: Label


func _ready() -> void:
	_plate = PanelContainer.new()
	_plate.name = "Plate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", UITheme.kit_style("zone_banner", 30, 3))
	_label = Label.new()
	UITheme.ensure_fonts_loaded()
	if UITheme.FONT_TITLE != null:
		_label.add_theme_font_override("font", UITheme.FONT_TITLE)
	_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_label.add_theme_color_override("font_color", UITheme.ACCENT)
	_label.add_theme_color_override("font_shadow_color", UITheme.LABEL_SHADOW_HEAVY)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.add_child(_label)
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_plate)
	add_child(_clip)
	_apply()


func _process(delta: float) -> void:
	tick(delta)


## Advances the banner clock (tests drive it directly).
func tick(delta: float) -> void:
	_clock += delta
	_apply()


## The player's feet entered a zone; false when ignored as a re-entry within REENTRY seconds.
func enter_zone(zone_name: String) -> bool:
	var last: float = _last_seen.get(zone_name, -INF)
	_last_seen[zone_name] = _clock
	if _clock - last < REENTRY:
		return false
	present(zone_name)
	return true


## The player's feet left a zone (starts its re-entry window).
func exit_zone(zone_name: String) -> void:
	_last_seen[zone_name] = _clock


## Shows a zone name now, `elapsed` seconds into its animation (demo stills freeze it mid-slide).
func present(zone_name: String, elapsed: float = 0.0) -> void:
	if phase() in [Phase.IN, Phase.HOLD] and elapsed == 0.0:
		elapsed = SLIDE
	zone = zone_name
	_start = _clock - elapsed
	if _label != null:
		_label.text = zone_name
	_apply()


func phase() -> Phase:
	var e: float = _clock - _start
	if e < 0.0 or e >= SLIDE * 2.0 + HOLD:
		return Phase.HIDDEN
	if e < SLIDE:
		return Phase.IN
	if e < SLIDE + HOLD:
		return Phase.HOLD
	return Phase.OUT


## How far the plate is unfurled: 0 hidden, 1 fully shown.
func shown() -> float:
	var e: float = _clock - _start
	match phase():
		Phase.IN:
			return _ease(e / SLIDE)
		Phase.HOLD:
			return 1.0
		Phase.OUT:
			return 1.0 - _ease((e - SLIDE - HOLD) / SLIDE)
	return 0.0


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


## Connects every Zones/<Area2D> (metadata zone_name) of a world scene to this banner for `body`.
func watch_zones(world_scene: Node, body: Node2D) -> int:
	var zones := world_scene.get_node_or_null("Zones") if world_scene else null
	if zones == null:
		return 0
	var n := 0
	for area: Node in zones.get_children():
		if not (area is Area2D) or not area.has_meta("zone_name"):
			continue
		var zone_name := String(area.get_meta("zone_name"))
		(area as Area2D).body_entered.connect(func(b: Node2D) -> void:
			if b == body:
				enter_zone(zone_name))
		(area as Area2D).body_exited.connect(func(b: Node2D) -> void:
			if b == body:
				exit_zone(zone_name))
		n += 1
	return n


## Screen rect of the visible part of the plate (empty when hidden).
func plate_rect() -> Rect2:
	return Rect2(_clip.position, _clip.size) if _clip and _clip.visible else Rect2()


func _apply() -> void:
	if _clip == null:
		return
	var s := shown()
	_clip.visible = s > 0.0
	if not _clip.visible:
		return
	_plate.reset_size()
	var vw: float = _clip.get_viewport_rect().size.x if _clip.is_inside_tree() else PixelZoom.BASE_VIEW.x
	var w: float = minf(_plate.size.x, vw)
	var open_w: float = roundf(w * s * 0.5) * 2.0
	_clip.visible = open_w > 0.0
	_clip.position = Vector2(roundf((vw - open_w) * 0.5), TOP)
	_clip.size = Vector2(open_w, _plate.size.y)
	_plate.position = Vector2(roundf((open_w - _plate.size.x) * 0.5), 0.0)
