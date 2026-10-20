class_name PixelZoom
extends RefCounted
## Integer pixel zoom: camera zoom = k / s, k screen px per art px, s the stretch factor.

const BASE_VIEW := Vector2(640, 360)
const MAX_VIEW := Vector2(1920, 1080)


## Integer canvas_items stretch factor for a window size.
static func stretch_factor(window_size: Vector2) -> int:
	return maxi(1, floori(minf(window_size.x / BASE_VIEW.x, window_size.y / BASE_VIEW.y)))


## Camera zooms from the smallest k whose view fits inside the map and MAX_VIEW up to s * max_mult.
static func levels(s: int, base_view: Vector2, map_size: Vector2, max_mult: float) -> Array[float]:
	var k_min: int = s
	if map_size.x > 0.0 and map_size.y > 0.0:
		var need: float = maxf(s * base_view.x / map_size.x, s * base_view.y / map_size.y)
		k_min = clampi(ceili(need - 0.0001), 1, s)
	var cap: float = maxf(s * base_view.x / MAX_VIEW.x, s * base_view.y / MAX_VIEW.y)
	k_min = clampi(maxi(k_min, ceili(cap - 0.0001)), 1, s)
	var k_max: int = maxi(k_min, floori(s * max_mult + 0.0001))
	var out: Array[float] = []
	for k in range(k_min, k_max + 1):
		out.append(float(k) / float(s))
	return out


## The level one notch from zoom: dir > 0 zooms in, dir < 0 out, clamped at the ends.
static func step(zoom: float, dir: int, zoom_levels: Array[float]) -> float:
	var i: int = _nearest(zoom, zoom_levels)
	return zoom_levels[clampi(i + signi(dir), 0, zoom_levels.size() - 1)]


## The level closest to zoom.
static func snap(zoom: float, zoom_levels: Array[float]) -> float:
	return zoom_levels[_nearest(zoom, zoom_levels)]


static func _nearest(zoom: float, zoom_levels: Array[float]) -> int:
	var best: int = 0
	for i in zoom_levels.size():
		if absf(zoom_levels[i] - zoom) < absf(zoom_levels[best] - zoom):
			best = i
	return best
