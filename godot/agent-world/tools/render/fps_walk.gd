extends Node
## Real-time frame times over a scripted walk: `-- --world <id> [--secs 20]`; prints `[fps] s=<k> fps=<n>` per second and `[fps] p99=..ms`.

const WORLD_SCENE := preload("res://scenes/world.tscn")
const WORLDS := "res://assets/worlds/%s/world.json"
## Walk polylines along each world's paths (road, then a side leg), covered at constant speed in `--secs`.
const ROUTES := {
	"darkwood": [
		Vector2(1330, 600), Vector2(1466, 577), Vector2(1760, 592), Vector2(2080, 600), Vector2(2298, 597),
		Vector2(2470, 612), Vector2(2484, 760), Vector2(2444, 950), Vector2(2340, 1110), Vector2(2200, 1192),
		Vector2(2000, 1180), Vector2(1760, 1164), Vector2(1520, 1150),
	],
	"magic_forest": [
		Vector2(1300, 840), Vector2(1230, 700), Vector2(1260, 560), Vector2(1420, 450), Vector2(1600, 400),
		Vector2(1850, 310), Vector2(2100, 310), Vector2(2330, 440), Vector2(2470, 600), Vector2(2470, 820),
	],
}
const WARMUP := 3.0
const BUDGET_MS := 16.7

var world: Node
var route: PackedVector2Array
var secs := 20.0
var speed := 0.0
var walked := 0.0
var t := -1.0
var frames: Array[float] = []
var gaps := PackedFloat32Array()
var last_us := 0
var proc_peak: Array[float] = []
var draws := 0.0
var gpu := PackedFloat32Array()
var spikes := false


func _ready() -> void:
	var id := _arg("--world", "darkwood")
	secs = float(_arg("--secs", "20"))
	spikes = _arg("--spikes", "") != ""
	route = PackedVector2Array(ROUTES[id])
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	speed = length / secs
	WorldBuilder.offline = true
	world = WORLD_SCENE.instantiate()
	world.room_config_path = WORLDS % id
	add_child(world)
	await get_tree().create_timer(WARMUP).timeout
	world.player.set_physics_process(false)
	for what in _arg("--off", "").split(",", false):
		_switch_off(what)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	t = 0.0
	print("[fps] world=%s route=%.0f px speed=%.1f px/s window=%s" % [id, length, speed, get_window().size])


func _process(delta: float) -> void:
	if t < 0.0:
		return
	var now := Time.get_ticks_usec()
	if last_us > 0:
		gaps.append((now - last_us) / 1000.0)
		if spikes and gaps[-1] > BUDGET_MS:
			print("[fps] spike t=%.2f %.1fms at %s" % [t, gaps[-1], world.player.global_position])
	last_us = now
	t += delta
	walked += speed * delta
	world.player.global_position = _at(walked)
	frames.append(t)
	if int(t) >= proc_peak.size():
		proc_peak.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	if t >= secs:
		t = -1.0
		_report()


## Diagnosis only: hides one art system to attribute frame cost (fog, rays, haze, post, glow, glow_lite, glow_linear, particles, lights, occlusion, agents, ysort, shade, water).
func _switch_off(what: String) -> void:
	var art: Node = world.find_child("Art", true, false)
	var root: Node = art.get_parent()
	var nodes: Array[Node] = []
	match what:
		"fog", "rays", "haze":
			var glow := root.get_node("Glow")
			var idx: int = {"fog": 0, "haze": 1, "rays": 2}[what]
			var rects: Array = glow.get_children().filter(func(c): return c is ColorRect or c is TextureRect)
			if idx < rects.size():
				nodes.append(rects[idx])
		"anim":
			root.set_process(false)
		"occlusion":
			world.player.set_process(false)
		"agents":
			world.agents_container.process_mode = Node.PROCESS_MODE_DISABLED
		"anim_fol", "anim_flick", "anim_flies":
			root.anim.set({"anim_fol": "foliage", "anim_flick": "flick", "anim_flies": "flies"}[what], [])
		"post":
			nodes.append(root.get_node("PostGrade"))
		"env":
			for c in root.get_children():
				if c is WorldEnvironment:
					c.queue_free()
		"glow_linear":
			RenderingServer.environment_glow_set_use_bicubic_upscale(false)
		"glow", "glow_lite":
			for c in root.get_children():
				if c is WorldEnvironment and what == "glow":
					c.environment.glow_enabled = false
				elif c is WorldEnvironment:
					c.environment.set_glow_level(1, 0.0)
		"particles":
			nodes.append_array(root.find_children("*", "GPUParticles2D", true, false))
		"lights":
			nodes.append_array(root.find_children("*", "PointLight2D", true, false))
		"moon_noground", "biglights_noground":
			for l: Light2D in root.find_children("*", "Light2D", true, false):
				l.range_item_cull_mask = 3
			for tl: CanvasItem in root.get_node("GroundTiles").get_children():
				tl.light_mask = 2
			if what == "moon_noground":
				nodes.append_array([])
				for m: Light2D in root.find_children("*", "DirectionalLight2D", true, false):
					m.range_item_cull_mask = 1
			else:
				for l: PointLight2D in root.find_children("*", "PointLight2D", true, false):
					if l.texture and l.texture.get_width() * l.texture_scale > 120.0:
						l.range_item_cull_mask = 1
		"moon":
			nodes.append_array(root.find_children("*", "DirectionalLight2D", true, false))
		"ground":
			nodes.append(root.get_node("GroundTiles"))
		"big_lights":
			for l: PointLight2D in root.find_children("*", "PointLight2D", true, false):
				if l.texture and l.texture.get_width() * l.texture_scale > 120.0:
					nodes.append(l)
		"small_lights":
			for l: PointLight2D in root.find_children("*", "PointLight2D", true, false):
				if l.texture and l.texture.get_width() * l.texture_scale <= 120.0:
					nodes.append(l)
		_:
			nodes.append(art.get_node(what.capitalize() if what != "ysort" else "YSort"))
	for n in nodes:
		n.set("visible", false)
		n.set("emitting", false)
		n.set("enabled", false)
		n.process_mode = Node.PROCESS_MODE_DISABLED
	print("[fps] off %s (%d nodes)" % [what, nodes.size()])


func _at(d: float) -> Vector2:
	for i in route.size() - 1:
		var seg := route[i].distance_to(route[i + 1])
		if d <= seg:
			return route[i].lerp(route[i + 1], d / seg)
		d -= seg
	return route[route.size() - 1]


func _report() -> void:
	var per := PackedInt32Array()
	per.resize(int(ceil(secs)))
	for f in frames:
		per[mini(int(f), per.size() - 1)] += 1
	var lo := 1 << 30
	for k in per.size():
		print("[fps] s=%d fps=%d" % [k, per[k]])
		lo = mini(lo, per[k])
	var art_root: Node = world.find_child("Art", true, false).get_parent()
	var t0 := Time.get_ticks_usec()
	for i in 40:
		art_root.anim.update(secs + i * 0.016, art_root.view_rect())
	print("[fps] anim.update=%.2fms" % ((Time.get_ticks_usec() - t0) / 40000.0))
	var sorted := gaps.duplicate()
	sorted.sort()
	var over := 0
	for g in gaps:
		over += int(g > BUDGET_MS)
	# Godot sets TIME_PROCESS once a second to the slowest process step of that second, not a per-frame mean.
	print("[fps] process_peak_per_s=%.1fms draw_calls=%.0f frames_over_%.1fms=%d" % [
		proc_peak.max() if not proc_peak.is_empty() else 0.0, draws / frames.size(), BUDGET_MS, over])
	gpu.sort()
	print("[fps] gpu_p50=%.2fms gpu_p99=%.2fms" % [_pct(gpu, 0.5), _pct(gpu, 0.99)])
	print("[fps] p50=%.2fms p95=%.2fms p99=%.2fms worst=%.1fms" % [_pct(sorted, 0.5), _pct(sorted, 0.95),
		_pct(sorted, 0.99), sorted[sorted.size() - 1]])
	print("[fps] min=%d avg=%.1f frames=%d" % [lo, frames.size() / secs, frames.size()])
	get_tree().quit()


## Nearest-rank percentile of an ascending array.
func _pct(sorted: PackedFloat32Array, q: float) -> float:
	return sorted[clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)]


func _arg(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i + 1 < args.size():
			return args[i + 1]
	return fallback
