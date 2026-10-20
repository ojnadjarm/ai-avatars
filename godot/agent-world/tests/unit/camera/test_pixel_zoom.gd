class_name TestPixelZoom
extends RefCounted
## Unit tests for PixelZoom integer camera levels.

var failure_message: String = ""


func run() -> bool:
	return _test_stretch_factor() and _test_levels_1080_map() and _test_levels_1440_map() \
		and _test_small_map_clamps() and _test_step_ends() and _test_snap() and _test_integer_levels() \
		and _test_widest_view_cap()


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _same(a: Array[float], b: Array[float]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(a[i], b[i]):
			return false
	return true


func _test_stretch_factor() -> bool:
	var cases: Dictionary = {
		Vector2(1920, 1080): 3, Vector2(2560, 1440): 4, Vector2(1366, 768): 2,
		Vector2(640, 360): 1, Vector2(320, 200): 1, Vector2(1920, 1200): 3,
	}
	for size: Vector2 in cases:
		var got: int = PixelZoom.stretch_factor(size)
		if got != int(cases[size]):
			return _fail("stretch_factor(%s) = %d, want %d" % [size, got, cases[size]])
	return true


func _test_levels_1080_map() -> bool:
	var got: Array[float] = PixelZoom.levels(3, PixelZoom.BASE_VIEW, Vector2(1920, 1080), 2.0)
	var want: Array[float] = [1.0 / 3.0, 2.0 / 3.0, 1.0, 4.0 / 3.0, 5.0 / 3.0, 2.0]
	return _same(got, want) or _fail("1920x1080 map levels %s" % [got])


func _test_levels_1440_map() -> bool:
	var got: Array[float] = PixelZoom.levels(3, PixelZoom.BASE_VIEW, Vector2(2560, 1440), 2.0)
	var want: Array[float] = [1.0 / 3.0, 2.0 / 3.0, 1.0, 4.0 / 3.0, 5.0 / 3.0, 2.0]
	if not _same(got, want):
		return _fail("2560x1440 map at s=3 levels %s" % [got])
	got = PixelZoom.levels(4, PixelZoom.BASE_VIEW, Vector2(2560, 1440), 2.0)
	want = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
	return _same(got, want) or _fail("2560x1440 map at s=4 levels %s" % [got])


func _test_small_map_clamps() -> bool:
	var got: Array[float] = PixelZoom.levels(3, PixelZoom.BASE_VIEW, Vector2(400, 300), 2.0)
	if got.is_empty() or not is_equal_approx(got[0], 1.0):
		return _fail("small map should start at k=s, got %s" % [got])
	got = PixelZoom.levels(3, PixelZoom.BASE_VIEW, Vector2(1280, 720), 2.0)
	if not is_equal_approx(got[0], 2.0 / 3.0):
		return _fail("1280x720 map should start at k=2, got %s" % [got])
	return true


func _test_step_ends() -> bool:
	var lv: Array[float] = PixelZoom.levels(3, PixelZoom.BASE_VIEW, Vector2(1920, 1080), 2.0)
	if not is_equal_approx(PixelZoom.step(1.0, 1, lv), 4.0 / 3.0):
		return _fail("step in from 1.0")
	if not is_equal_approx(PixelZoom.step(1.0, -1, lv), 2.0 / 3.0):
		return _fail("step out from 1.0")
	if not is_equal_approx(PixelZoom.step(2.0, 1, lv), 2.0):
		return _fail("step in at max should stay at 2.0")
	if not is_equal_approx(PixelZoom.step(1.0 / 3.0, -1, lv), 1.0 / 3.0):
		return _fail("step out at min should stay at 1/3")
	var z: float = 1.0
	for i in 20:
		z = PixelZoom.step(z, 1 if i < 10 else -1, lv)
		if not is_equal_approx(z * 3.0, roundf(z * 3.0)):
			return _fail("step left an integer level: %f" % z)
	return true


func _test_snap() -> bool:
	var lv: Array[float] = PixelZoom.levels(3, PixelZoom.BASE_VIEW, Vector2(1920, 1080), 2.0)
	if not is_equal_approx(PixelZoom.snap(0.9, lv), 1.0):
		return _fail("snap(0.9) = %f" % PixelZoom.snap(0.9, lv))
	if not is_equal_approx(PixelZoom.snap(0.1, lv), 1.0 / 3.0):
		return _fail("snap(0.1) should clamp to 1/3")
	if not is_equal_approx(PixelZoom.snap(9.0, lv), 2.0):
		return _fail("snap(9.0) should clamp to 2.0")
	return true


func _test_integer_levels() -> bool:
	for s in [1, 2, 3, 4]:
		for map: Vector2 in [Vector2(1920, 1080), Vector2(2560, 1440), Vector2(2400, 1792), Vector2(500, 500)]:
			for level: float in PixelZoom.levels(s, PixelZoom.BASE_VIEW, map, 2.0):
				var k: float = level * s
				if not is_equal_approx(k, roundf(k)):
					return _fail("level %f at s=%d is not an integer k" % [level, s])
	return true


func _test_widest_view_cap() -> bool:
	var cases: Dictionary = {
		Vector2(1920, 1080): Vector2(1920, 1080), Vector2(2560, 1440): Vector2(1280, 720),
		Vector2(3840, 2160): Vector2(1920, 1080),
	}
	for window: Vector2 in cases:
		var s: int = PixelZoom.stretch_factor(window)
		var lv: Array[float] = PixelZoom.levels(s, PixelZoom.BASE_VIEW, Vector2(7680, 4320), 2.0)
		var widest: Vector2 = PixelZoom.BASE_VIEW / lv[0]
		if widest.x > PixelZoom.MAX_VIEW.x + 0.01 or widest.y > PixelZoom.MAX_VIEW.y + 0.01:
			return _fail("widest view at %s is %s > %s" % [window, widest, PixelZoom.MAX_VIEW])
		if not widest.is_equal_approx(cases[window]):
			return _fail("widest view at %s is %s, want %s" % [window, widest, cases[window]])
	return true
