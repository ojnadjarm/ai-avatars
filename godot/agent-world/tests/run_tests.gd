extends Node
## Test harness root. Instantiates every discovered test suite, calls
## run() on each, and exits with code 0 (all pass) or 1 (any failure).
##
## Each test script is a RefCounted with two conventions:
##   var failure_message: String        — set when a test fails
##   func run() -> bool                 — returns true iff all assertions pass
##
## Suites are every test_*.gd under TEST_ROOTS, sorted per root.

const TEST_ROOTS: Array[String] = ["res://tests/unit", "res://tests/integration"]


func _ready() -> void:
	print("=== TEST RUN ===")
	var passed: int = 0
	var failed: int = 0

	for script_path: String in _discover():
		var script: GDScript = load(script_path) as GDScript
		if script == null:
			print("FAIL: %s (could not load script)" % script_path)
			failed += 1
			continue
		var test: RefCounted = script.new() as RefCounted
		var test_name: String = script_path.get_file().get_basename()
		var ok: bool = test.call("run") as bool
		if ok:
			print("PASS: %s" % test_name)
			passed += 1
		else:
			var msg: String = str(test.get("failure_message"))
			print("FAIL: %s — %s" % [test_name, msg])
			failed += 1

	print("=== %d passed / %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


func _discover() -> Array[String]:
	var out: Array[String] = []
	for root: String in TEST_ROOTS:
		var found: Array[String] = []
		_scan(root, found)
		found.sort()
		out.append_array(found)
	return out


func _scan(dir_path: String, found: Array[String]) -> void:
	for sub: String in DirAccess.get_directories_at(dir_path):
		_scan(dir_path.path_join(sub), found)
	for file: String in DirAccess.get_files_at(dir_path):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
