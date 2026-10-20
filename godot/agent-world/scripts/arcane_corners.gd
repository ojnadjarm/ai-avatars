class_name ArcaneCorners
extends Control
## Overlay that paints the UI kit's gold filigree into a panel's four corners.
## A no-op when the panel's own style is a kit 9-slice (its corners already carry the filigree).
##
## Attach via UITheme.attach_arcane_corners(panel).

@export var inset: int = 3
@export var glyph_size: int = 6


func _ready() -> void:
	z_index = 1
	resized.connect(queue_redraw)


func _draw() -> void:
	var rect_size: Vector2 = size
	if rect_size.x < 16 or rect_size.y < 16 or _host_has_kit_frame():
		return
	var tex := UITheme.kit_texture("corner")
	for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var origin := Vector2(inset if dir.x > 0 else rect_size.x - inset, inset if dir.y > 0 else rect_size.y - inset)
		if tex != null:
			draw_set_transform(origin, 0.0, dir)
			draw_texture(tex, Vector2.ZERO)
		else:
			draw_set_transform(origin - Vector2(0 if dir.x > 0 else 1, 0 if dir.y > 0 else 1), 0.0, Vector2.ONE)
			_draw_corner(dir)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _host_has_kit_frame() -> bool:
	var host := get_parent() as Control
	return host != null and host.has_theme_stylebox("panel") and host.get_theme_stylebox("panel") is StyleBoxTexture


func _draw_corner(dir: Vector2) -> void:
	# Fallback without the kit: a gold L-bracket that dims toward its ends.
	for i in range(glyph_size):
		var c: Color = UITheme.ARCANE_GLYPH_DIM if i >= glyph_size - 3 else UITheme.ARCANE_GLYPH
		draw_rect(Rect2(Vector2(i, 0) * dir, Vector2(1, 1)), c)
		if i > 0:
			draw_rect(Rect2(Vector2(0, i) * dir, Vector2(1, 1)), c)
	draw_rect(Rect2(Vector2(2, 2) * dir, Vector2(1, 1)), UITheme.ARCANE_GLYPH_DIM)
