class_name ArcaneCorners
extends Control
## Overlay that paints four arcane corner glyphs on a panel.
## Procedurally drawn — no sprite assets. Each corner is an L-bracket of
## three pixel runes plus an inner 4-pointed star dot, mirrored per corner.
##
## Attach via UITheme.attach_arcane_corners(panel).

@export var inset: int = 3
@export var glyph_size: int = 6


func _ready() -> void:
	z_index = 1
	resized.connect(queue_redraw)


func _draw() -> void:
	var rect_size: Vector2 = size
	if rect_size.x < 16 or rect_size.y < 16:
		return
	_draw_corner(Vector2(inset, inset), Vector2(1, 1))
	_draw_corner(Vector2(rect_size.x - inset - 1, inset), Vector2(-1, 1))
	_draw_corner(Vector2(inset, rect_size.y - inset - 1), Vector2(1, -1))
	_draw_corner(Vector2(rect_size.x - inset - 1, rect_size.y - inset - 1), Vector2(-1, -1))


func _draw_corner(origin: Vector2, dir: Vector2) -> void:
	# L-bracket arm: three pixel runes forming the rune arm.
	var arm: int = glyph_size
	var bright: Color = UITheme.ARCANE_GLYPH
	var dim: Color = UITheme.ARCANE_GLYPH_DIM

	# Horizontal arm pixels
	for i in range(arm):
		var p := origin + Vector2(i, 0) * dir
		var c: Color = bright if i == 0 else (dim if i >= arm - 3 else bright)
		draw_rect(Rect2(p, Vector2(1, 1)), c)

	# Vertical arm pixels
	for i in range(arm):
		var p := origin + Vector2(0, i) * dir
		if i == 0:
			continue  # already drawn by horizontal arm
		var c: Color = dim if i >= arm - 3 else bright
		draw_rect(Rect2(p, Vector2(1, 1)), c)

	# Single dim pixel one step inward — hints at the inner rune without
	# encroaching on panel content.
	var inner := origin + Vector2(2, 2) * dir
	draw_rect(Rect2(inner, Vector2(1, 1)), dim)
