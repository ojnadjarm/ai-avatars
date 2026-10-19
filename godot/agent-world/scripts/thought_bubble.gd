class_name ThoughtBubble
extends Node2D
## Small status cloud above an agent's head. For now, blink() shows an animated
## three-dot "thinking" pulse. Kept intentionally generic — future agent status
## (happy, sleeping, confused, ...) can extend this with set_status(kind).

const BODY_WIDTH: float = 60.0
const BODY_HEIGHT: float = 28.0
const CORNER_RADIUS: float = 12.0
const DISPLAY_TIME: float = 6.0
const FADE_IN: float = 0.2
const FADE_OUT: float = 0.35

# Three bouncing dots, typing-indicator style.
const DOT_COUNT: int = 3
const DOT_RADIUS: float = 3.0
const DOT_SPACING: float = 10.5
const PULSE_CYCLE: float = 1.2     # seconds for one full bounce cycle
const PULSE_PHASE: float = 0.18    # offset between dots so they stagger
const DOT_Y_LIFT: float = 3.5      # pixels the dot lifts at peak

# Cloud tail trailing down toward the agent's head.
const TAIL_DOTS := [
	{"offset": Vector2(5.0, 5.5), "radius": 3.6},
	{"offset": Vector2(10.5, 13.5), "radius": 2.1},
]

var _remaining: float = 0.0
var _time: float = 0.0
var _tween: Tween


func _ready() -> void:
	z_as_relative = false
	z_index = 17
	modulate.a = 0.0
	visible = false
	set_process(false)


func blink() -> void:
	_remaining = DISPLAY_TIME
	_time = 0.0
	visible = true
	set_process(true)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN).set_trans(Tween.TRANS_LINEAR)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_fade_out()


func _fade_out() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT).set_trans(Tween.TRANS_LINEAR)
	_tween.chain().tween_callback(_hide)


func _hide() -> void:
	visible = false
	set_process(false)


func _draw() -> void:
	var body_rect := Rect2(Vector2(-BODY_WIDTH * 0.5, -BODY_HEIGHT), Vector2(BODY_WIDTH, BODY_HEIGHT))
	_fill_rounded_rect(body_rect.grow(1.0), CORNER_RADIUS + 1.0, UITheme.THOUGHT_BUBBLE_BORDER)
	_fill_rounded_rect(body_rect, CORNER_RADIUS, UITheme.THOUGHT_BUBBLE_BG)

	# Three bouncing dots, centered in the body.
	var dots_total_width: float = DOT_SPACING * float(DOT_COUNT - 1)
	var center_y: float = -BODY_HEIGHT * 0.5
	for i in DOT_COUNT:
		var dot_x: float = -dots_total_width * 0.5 + float(i) * DOT_SPACING
		var phase: float = fposmod(_time - float(i) * PULSE_PHASE, PULSE_CYCLE) / PULSE_CYCLE
		var lift: float = maxf(0.0, sin(phase * PI)) * DOT_Y_LIFT
		draw_circle(Vector2(dot_x, center_y - lift), DOT_RADIUS, UITheme.THOUGHT_BUBBLE_DOT)

	# Trailing cloud dots below the body.
	for tail in TAIL_DOTS:
		var o: Vector2 = tail["offset"]
		var r: float = tail["radius"]
		draw_circle(o, r + 1.0, UITheme.THOUGHT_BUBBLE_BORDER)
		draw_circle(o, r, UITheme.THOUGHT_BUBBLE_BG)


func _fill_rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(radius, 0), Vector2(rect.size.x - radius * 2.0, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(0, radius), Vector2(rect.size.x, rect.size.y - radius * 2.0)), color)
	draw_circle(rect.position + Vector2(radius, radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, radius), radius, color)
	draw_circle(rect.position + Vector2(radius, rect.size.y - radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), radius, color)
