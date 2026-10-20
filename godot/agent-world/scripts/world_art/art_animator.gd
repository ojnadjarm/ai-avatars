extends RefCounted
## One loop phase drives light/halo flicker, firefly drift and foliage atlas frames; nodes outside the camera view are hidden (culled).

const CULL_EVERY := 4
const MARGIN := 96.0

var period := 9.0
var flick: Array = []
var flies: Array = []
var culled: Array = []
var foliage: Array = []
## Foliage entries per y-sort chunk node (culled as a whole); entries without a chunk are culled by their own rect.
var _fol_groups: Dictionary = {}
var _fol_on: Array = []
var _flick_on: Array = []
var _flies_on: Array = []
var _tick := 0


func _init(loop_seconds: float) -> void:
	period = loop_seconds


## mode "energy" drives Light2D.energy, "alpha" drives modulate.a.
func add_flicker(node: CanvasItem, base: float, amount: float, phase: float, mode: String) -> void:
	flick.append([node, base, amount, phase, mode])


func add_fly(node: Node2D, base: Vector2, phase: float) -> void:
	flies.append([node, base, phase])


func add_cull(node: CanvasItem, rect: Rect2) -> void:
	culled.append([node, rect])


## T715 pixel-foliage: frame = seq[(t - x / speed) * fps], the gust reaching the plant x / speed seconds later.
func add_foliage(node: Sprite2D, seq: PackedInt32Array, fps: float, speed: float, rect: Rect2, chunk: CanvasItem = null) -> void:
	var f := [node, seq, fps, rect.get_center().x / speed, rect]
	foliage.append(f)
	if not _fol_groups.has(chunk):
		_fol_groups[chunk] = []
	_fol_groups[chunk].append(f)


func update(t: float, view: Rect2) -> void:
	if _tick % CULL_EVERY == 0:
		cull(view)
	_tick += 1
	var w := TAU / period
	for f in _flick_on:
		var node: CanvasItem = f[0]
		var v: float = 1.0 + (sin(t * w * 5.0 + f[3]) * 0.6 + sin(t * w * 11.0 + f[3] * 2.3) * 0.4) * f[2]
		if f[4] == "energy":
			node.energy = f[1] * v
		else:
			node.modulate.a = f[1] * v
	for f in _fol_on:
		var seq: PackedInt32Array = f[1]
		var fr: int = seq[posmod(int(floor((t - f[3]) * f[2])), seq.size())]
		var s: Sprite2D = f[0]
		if s.frame != fr:
			s.frame = fr
			for c in s.get_children():
				c.frame = fr
	for fl in _flies_on:
		(fl[0] as Node2D).position = fl[1] + Vector2(sin(t * w + fl[2]) * 26.0, sin(t * w * 2.0 + fl[2] * 1.3) * 10.0)


func cull(view: Rect2) -> int:
	var grown := view.grow(MARGIN)
	var shown := 0
	for c in culled:
		var on: bool = grown.intersects(c[1])
		c[0].visible = on
		shown += int(on)
	_fol_on = []
	for chunk in _fol_groups:
		if chunk == null:
			_fol_on.append_array(_fol_groups[chunk].filter(func(f): return grown.intersects(f[4])))
		elif (chunk as CanvasItem).visible:
			_fol_on.append_array(_fol_groups[chunk])
	_flick_on = flick.filter(func(f): return (f[0] as CanvasItem).is_visible_in_tree())
	_flies_on = flies.filter(func(f): return (f[0] as CanvasItem).visible)
	return shown
