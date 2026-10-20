extends RefCounted
## Minimap world-to-map mapping at both world sizes and the camera view frame at every zoom level.

const SIZES := [Vector2(1920, 1080), Vector2(2560, 1440)]

const Minimap := preload("res://scripts/hud/minimap.gd")

var failure_message: String = ""


func run() -> bool:
	for s: Vector2 in SIZES:
		if not (_test_mapping(s) and _test_view_frames(s)):
			return false
	return _test_offset_world()


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _test_mapping(size: Vector2) -> bool:
	var f := Minimap.factor_for(size)
	if f != ceili(size.x / Minimap.MAP_W) or size.x / f > Minimap.MAP_W:
		return _fail("%s: factor %d" % [size, f])
	var rect := Rect2(Vector2.ZERO, size)
	var map := size / f
	if map != map.floor():
		return _fail("%s: map %s not whole pixels" % [size, map])
	var cases := {Vector2.ZERO: Vector2.ZERO, size: map, size * 0.5: map * 0.5, Vector2(f * 7, f * 3): Vector2(7, 3)}
	for p: Vector2 in cases:
		var got := Minimap.world_to_map(p, rect, f)
		if not got.is_equal_approx(cases[p]):
			return _fail("%s: world_to_map(%s) = %s, want %s" % [size, p, got, cases[p]])
	return true


func _test_view_frames(size: Vector2) -> bool:
	var f := Minimap.factor_for(size)
	var rect := Rect2(Vector2.ZERO, size)
	var map_rect := Rect2(Vector2.ZERO, size / f)
	var levels: Array[float] = PixelZoom.levels(3, PixelZoom.BASE_VIEW, size, 2.0)
	if levels.size() < 3:
		return _fail("%s: only %d zoom levels" % [size, levels.size()])
	for z: float in levels:
		var center := size * 0.5
		var fr := Minimap.view_frame(center, z, PixelZoom.BASE_VIEW, rect, f)
		var want := PixelZoom.BASE_VIEW / z / f
		if not fr.size.is_equal_approx(want):
			return _fail("%s zoom %.3f: frame %s, want size %s" % [size, z, fr.size, want])
		if not fr.get_center().is_equal_approx(center / f):
			return _fail("%s zoom %.3f: frame not centred on the camera" % [size, z])
		var corner := Minimap.view_frame(Vector2(-500, size.y + 500), z, PixelZoom.BASE_VIEW, rect, f)
		if not map_rect.encloses(corner) or not corner.size.is_equal_approx(want) or corner.position.x != 0.0 \
				or not is_equal_approx(corner.end.y, map_rect.end.y):
			return _fail("%s zoom %.3f: corner frame %s not clamped into %s" % [size, z, corner, map_rect])
	return true


func _test_offset_world() -> bool:
	var rect := Rect2(Vector2(-320, 40), Vector2(1920, 1080))
	var f := Minimap.factor_for(rect.size)
	var got := Minimap.world_to_map(Vector2(-320 + f * 10, 40 + f * 5), rect, f)
	if not got.is_equal_approx(Vector2(10, 5)):
		return _fail("offset world: %s" % got)
	return true
