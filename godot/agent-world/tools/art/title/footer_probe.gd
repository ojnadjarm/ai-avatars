extends Node
## Title footer readability: WCAG ratio of each key-hint/footer label colour vs the p90 luminance of the art behind it (labels hidden); `-- --json OUT`.

const MIN_RATIO := 4.5


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[args.find("--json") + 1] if "--json" in args else "user://footer_probe.json"
	var sel: Node = load("res://scenes/room_selector.tscn").instantiate()
	add_child(sel)
	await get_tree().create_timer(6.0).timeout
	var labels: Array = (sel.title.menu.footer as Control).get_children().filter(func(n: Node) -> bool: return n is Label)
	for l: Label in labels:
		l.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	for l: Label in labels:
		l.visible = true
	var k := img.get_width() / 640.0
	var rows: Array = []
	var worst := 99.0
	for l: Label in labels:
		var font := l.get_theme_font("font")
		var size := l.get_theme_font_size("font_size")
		var r := Rect2(l.get_global_rect().position, font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size))
		var bg: Array[float] = []
		for y in range(int(r.position.y * k), int(r.end.y * k)):
			for x in range(int(r.position.x * k), int(r.end.x * k)):
				bg.append(_luma(img.get_pixel(x, y)))
		bg.sort()
		var b: float = bg[int(bg.size() * 0.9)]
		var t := _luma(l.get_theme_color("font_color"))
		var ratio := (maxf(t, b) + 0.05) / (minf(t, b) + 0.05)
		worst = minf(worst, ratio)
		rows.append({"text": l.text, "ratio": snappedf(ratio, 0.01), "text_luma": snappedf(t, 0.001), "bg_p90_luma": snappedf(b, 0.001)})
		print("[preview] %-22s %.2f:1" % [l.text, ratio])
	print("[preview] FOOTER %s worst %.2f:1" % ["pass" if worst >= MIN_RATIO else "fail", worst])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"worst": worst, "pass": worst >= MIN_RATIO, "labels": rows}, "  "))


static func _luma(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)
