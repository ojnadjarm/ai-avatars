extends Node
## Test harness root. Instantiates every registered test suite, calls
## run() on each, and exits with code 0 (all pass) or 1 (any failure).
##
## Each test script is a RefCounted with two conventions:
##   var failure_message: String        — set when a test fails
##   func run() -> bool                 — returns true iff all assertions pass
##
## New Logic stories add their test script path to TEST_SCRIPTS below.

const TEST_SCRIPTS: Array[String] = [
	"res://tests/unit/world/test_world_builder_merge.gd",
	"res://tests/unit/movement/test_agent_wander.gd",
	"res://tests/unit/mcp/test_mcp_protocol.gd",
	"res://tests/unit/puzzle/test_world_state.gd",
	"res://tests/unit/puzzle/test_action_resolver.gd",
	"res://tests/unit/puzzle/test_solve_state.gd",
	"res://tests/unit/puzzle/test_prop_layers.gd",
	"res://tests/unit/puzzle/test_prompt_builder_actions.gd",
	"res://tests/integration/puzzle/test_collaboration.gd",
	"res://tests/integration/puzzle/test_coordinator_integration.gd",
	"res://tests/integration/puzzle/test_agent_dispatcher_extensions.gd",
]


func _ready() -> void:
	print("=== TEST RUN ===")
	var passed: int = 0
	var failed: int = 0

	for script_path: String in TEST_SCRIPTS:
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
