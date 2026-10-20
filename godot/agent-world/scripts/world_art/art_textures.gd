extends RefCounted
## Texture source for the world art: PNGs from the world's art/ dir (no import step) plus procedural sprites.

var dir: String
var _cache := {}
var _masks := {}
var _radials := {}
var dot: Texture2D
var px: Texture2D
var leaf: Texture2D


func _init(art_dir: String) -> void:
	dir = art_dir
	dot = _dot(15, 1.6)
	px = _solid(3, 3)
	leaf = _solid(2, 1)


## `cell` > 0 also keeps the alpha of the image's top-left cell as a BitMap (see mask()).
func img(name: String, cell := Vector2i.ZERO) -> Texture2D:
	if not _cache.has(name):
		var im := Image.load_from_file(dir.path_join(name))
		_cache[name] = ImageTexture.create_from_image(im) if im else null
		if im and cell.x > 0 and cell.y > 0:
			var bm := BitMap.new()
			bm.create_from_image_alpha(im.get_region(Rect2i(Vector2i.ZERO, cell.min(im.get_size()))))
			_masks[name] = bm
	return _cache[name]


## Frame-0 alpha of an albedo loaded with a cell: occlusion tests read it instead of is_pixel_opaque (a GPU readback per atlas).
func mask(name: String) -> BitMap:
	return _masks.get(name)


## Albedo + normal map pair for lit sprites; `cell` as in img().
func canvas(files: Dictionary, cell := Vector2i.ZERO) -> CanvasTexture:
	var ct := CanvasTexture.new()
	ct.diffuse_texture = img(files["albedo"], cell)
	if files.has("normal"):
		ct.normal_texture = nrm(files["normal"])
	return ct


## Normal map as RG8: Godot's canvas shader reads only .xy and rebuilds z, so B and A are wasted GPU bytes.
func nrm(name: String) -> Texture2D:
	var key := "rg8:" + name
	if not _cache.has(key):
		var im := Image.load_from_file(dir.path_join(name))
		if im:
			im.convert(Image.FORMAT_RG8)
		_cache[key] = ImageTexture.create_from_image(im) if im else null
	return _cache[key]


func radial(r: int, falloff: float = 2.0) -> Texture2D:
	var key := Vector2(r, falloff)
	if not _radials.has(key):
		var im := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
		for y in r * 2:
			for x in r * 2:
				var d := clampf(1.0 - Vector2(x - r + 0.5, y - r + 0.5).length() / r, 0.0, 1.0)
				im.set_pixel(x, y, Color(1, 1, 1, pow(d, falloff)))
		_radials[key] = ImageTexture.create_from_image(im)
	return _radials[key]


static func grad(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	return g


static func color8(a: Array) -> Color:
	return Color8(int(a[0]), int(a[1]), int(a[2]))


func _dot(size: int, falloff: float) -> Texture2D:
	var im := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var v := 1.0 if (absi(x - c) <= 1 and absi(y - c) <= 1) else pow(clampf(1.0 - d / c, 0.0, 1.0), falloff) * 0.6
			im.set_pixel(x, y, Color(1, 1, 1, v))
	return ImageTexture.create_from_image(im)


func _solid(w: int, h: int) -> Texture2D:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color.WHITE)
	return ImageTexture.create_from_image(im)
