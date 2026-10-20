class_name ThoughtBubble
extends Node2D
## Pixel thought cloud above an agent's head: blink() shows a three-dot "thinking" pulse.
## Kept generic — future agent status (happy, sleeping, ...) can extend this with set_status(kind).

const BODY := Vector2i(24, 13)
## World px from the node (placed by agent.gd) up to the cloud's lowest tail blob, clearing the head.
const LIFT := 22
const DISPLAY_TIME: float = 6.0
const FADE_IN: float = 0.2
const FADE_OUT: float = 0.35

const DOT_COUNT: int = 3
const DOT_SPACING: int = 6
const PULSE_CYCLE: float = 1.2     # seconds for one full bounce cycle
const PULSE_PHASE: float = 0.18    # offset between dots so they stagger

# Tail blobs trailing down toward the head: [x, y from the cloud's bottom, size].
const TAIL := [[-3, 2, 3], [-6, 6, 2]]

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
	var bottom := -LIFT - 8
	var body := Rect2i(Vector2i(-BODY.x / 2, bottom - BODY.y), BODY)
	_blob(body, 3)
	for t: Array in TAIL:
		_blob(Rect2i(t[0], bottom + t[1], t[2], t[2]), 0)
	var cy: int = body.position.y + BODY.y / 2 - 1
	var x0: int = -DOT_SPACING * (DOT_COUNT - 1) / 2 - 1
	for i in DOT_COUNT:
		var phase: float = fposmod(_time - float(i) * PULSE_PHASE, PULSE_CYCLE) / PULSE_CYCLE
		var lift: int = 1 if phase < 0.5 else 0
		draw_rect(Rect2(x0 + i * DOT_SPACING, cy - lift, 2, 2), UITheme.THOUGHT_BUBBLE_DOT)


## Pixel-rounded box: 1 px outline, corners cut by `cut` px stair steps.
func _blob(r: Rect2i, cut: int) -> void:
	for pass_i in 2:
		var grow: int = 1 - pass_i
		var color: Color = UITheme.THOUGHT_BUBBLE_BORDER if pass_i == 0 else UITheme.THOUGHT_BUBBLE_BG
		var rr := r.grow(grow)
		for y in rr.size.y:
			var edge: int = mini(y, rr.size.y - 1 - y)
			var inset: int = maxi(0, cut - edge) if cut > 0 else (1 if edge == 0 and rr.size.x > 2 else 0)
			draw_rect(Rect2(rr.position.x + inset, rr.position.y + y, rr.size.x - inset * 2, 1), color)
