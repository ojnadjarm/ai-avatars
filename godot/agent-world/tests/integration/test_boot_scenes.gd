extends RefCounted
## Boots title, settings and both worlds in a child Godot for 300 frames each: exit 0, no ERROR lines, no leaks at exit.

const FRAMES := 300
## [label, scene, extra user args, line the log must contain]
const BOOTS := [
	["title", "res://scenes/room_selector.tscn", [], ""],
	["settings", "res://scenes/settings_screen.tscn", [], ""],
	["magic_forest", "res://scenes/world.tscn", ["--world=magic_forest"], "[world] Loaded:"],
	["darkwood", "res://scenes/world.tscn", ["--world=darkwood"], "[world] Loaded:"],
]

var failure_message: String = ""


func run() -> bool:
	for boot: Array in BOOTS:
		var err := _boot(boot[0], boot[1], boot[2], boot[3])
		if err != "":
			failure_message = "%s: %s" % [boot[0], err]
			return false
	return true


func _boot(label: String, scene: String, extra: Array, marker: String) -> String:
	var args := PackedStringArray(["--headless", "--audio-driver", "Dummy", "--path",
		ProjectSettings.globalize_path("res://"), "--quit-after", str(FRAMES), scene, "--", "--offline"])
	args.append_array(PackedStringArray(extra))
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var log := "\n".join(out)
	var bad: Array[String] = []
	for line: String in log.split("\n"):
		if "ERROR" in line or "leak" in line.to_lower() or "still in use at exit" in line:
			bad.append(line.strip_edges())
	print("[boot] %s exit=%d bad=%d" % [label, code, bad.size()])
	if code != 0:
		return "exit %d" % code
	if not bad.is_empty():
		return "%d ERROR/leak lines, first: %s" % [bad.size(), bad[0]]
	if marker != "" and not marker in log:
		return "no '%s' line" % marker
	return ""
