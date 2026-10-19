class_name TestPromptBuilderActions
extends RefCounted
## Unit tests for Story 007 — PromptBuilder action tag integration.
## Covers:
##   - extract_speech strips <action .../> tags from speech text
##   - build_observe appends ACTION_TAG_INSTRUCTIONS fragment to system prompt
##   - build_arrive does NOT append the fragment (R20/TR-puzzle-020)
##   - World-level action_tag_instructions override takes precedence over global default
##
## Uses hermetic puzzle defaults (install + restore pattern from test_action_resolver.gd)
## to ensure the user://game_config.json override cannot shadow puzzle block values.

## Puzzle defaults fixture — installed hermetically, restored after run().
## Must include action_tag_instructions so tests are not sensitive to the
## on-disk config state.
const FIXTURE_PUZZLE_DEFAULTS: Dictionary = {
	"action_tag_instructions": "FIXTURE_ACTION_INSTRUCTIONS",
	"nothing_happens": {
		"go_to": "Your feet carry you toward it, but the world does not shift.",
		"take": "Your hand closes on nothing that the world would yield.",
		"use_object": "You press it against the thing before you. Nothing stirs.",
		"use_skill": "You bring what you know to bear. The world does not respond.",
		"call_agent": "The name does not carry. No one turns.",
	},
	"nothing_happens_text": "The world holds its shape. Nothing yields.",
}

var failure_message: String = ""
var _saved_puzzle_defaults: Variant = null
var _had_puzzle_defaults: bool = false


func run() -> bool:
	_install_puzzle_defaults()

	# --- extract_speech: action tag stripping ---
	if not _test_extract_speech_strips_single_action_tag():
		_restore_puzzle_defaults()
		return false
	if not _test_extract_speech_strips_multiple_action_tags():
		_restore_puzzle_defaults()
		return false
	if not _test_extract_speech_preserves_text_when_no_action():
		_restore_puzzle_defaults()
		return false
	if not _test_extract_speech_handles_two_action_attrs_no_on():
		_restore_puzzle_defaults()
		return false
	if not _test_extract_speech_strips_whitespace_padded_action_tag():
		_restore_puzzle_defaults()
		return false
	if not _test_extract_speech_action_outside_block_dropped_with_outer_text():
		_restore_puzzle_defaults()
		return false

	# --- _action_tag_instructions / build_observe / build_arrive ---
	if not _test_action_tag_instructions_returns_default_when_no_override():
		_restore_puzzle_defaults()
		return false
	if not _test_action_tag_instructions_world_override_wins():
		_restore_puzzle_defaults()
		return false
	if not _test_action_tag_instructions_missing_puzzle_block_returns_empty():
		_restore_puzzle_defaults()
		return false
	if not _test_build_observe_appends_action_fragment():
		_restore_puzzle_defaults()
		return false
	if not _test_build_arrive_does_not_append_action_fragment():
		_restore_puzzle_defaults()
		return false

	_restore_puzzle_defaults()
	return true


# ── Fixture helpers ────────────────────────────────────────────────────────

func _install_puzzle_defaults() -> void:
	_had_puzzle_defaults = GameState.defaults.has("puzzle")
	if _had_puzzle_defaults:
		_saved_puzzle_defaults = GameState.defaults["puzzle"]
	GameState.defaults["puzzle"] = FIXTURE_PUZZLE_DEFAULTS.duplicate(true)


func _restore_puzzle_defaults() -> void:
	if _had_puzzle_defaults:
		GameState.defaults["puzzle"] = _saved_puzzle_defaults
	else:
		GameState.defaults.erase("puzzle")


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


# ── Minimal world config dict helpers ─────────────────────────────────────

## Returns a minimal world config dict — only the fields PromptBuilder reads
## from config in build_context and build_observe/build_arrive (name, biome).
func _world_config(extra: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = {"name": "Test World", "biome": "test"}
	for key: String in extra:
		cfg[key] = extra[key]
	return cfg


# ── Tests: extract_speech strips <action .../> ────────────────────────────

func _test_extract_speech_strips_single_action_tag() -> bool:
	## extract_speech removes a single <action .../> inside a <speech> block.
	# Arrange
	var input := "<speech>I press the medallion.<action verb=\"use_object\" target=\"medallion\" on=\"pillar\"/></speech>"

	# Act
	var result: String = PromptBuilder.extract_speech(input)

	# Assert
	if result.contains("<action"):
		return _fail("single action strip: <action tag still present in output: '%s'" % result)
	if result != "I press the medallion.":
		return _fail("single action strip: expected 'I press the medallion.', got '%s'" % result)
	return true


func _test_extract_speech_strips_whitespace_padded_action_tag() -> bool:
	## TD-012: action tag padded by whitespace on both sides inside the speech
	## block — the strip_edges pass after the regex sub must trim the padding
	## so no stray spaces survive around the spoken text.
	# Arrange
	var input := "<speech>The runes glow.   <action verb=\"take\" target=\"medallion\"/>   </speech>"

	# Act
	var result: String = PromptBuilder.extract_speech(input)

	# Assert
	if result != "The runes glow.":
		return _fail("whitespace-padded strip: expected 'The runes glow.', got '%s'" % result)
	return true


func _test_extract_speech_strips_multiple_action_tags() -> bool:
	## extract_speech removes all <action .../> elements from a single <speech> block.
	# Arrange
	var input := "<speech>I look around.<action verb=\"go_to\" target=\"altar\"/> Then I reach out.<action verb=\"take\" target=\"coin\"/></speech>"

	# Act
	var result: String = PromptBuilder.extract_speech(input)

	# Assert
	if result.contains("<action"):
		return _fail("multiple action strip: <action tag still present in output: '%s'" % result)
	if result.is_empty():
		return _fail("multiple action strip: result should not be empty after stripping")
	if not result.contains("I look around."):
		return _fail("multiple action strip: speech text lost, got: '%s'" % result)
	if not result.contains("Then I reach out."):
		return _fail("multiple action strip: second speech fragment lost, got: '%s'" % result)
	return true


func _test_extract_speech_preserves_text_when_no_action() -> bool:
	## extract_speech returns speech contents unchanged when no <action .../> is present.
	# Arrange
	var input := "<speech>Plain spoken line.</speech>"

	# Act
	var result: String = PromptBuilder.extract_speech(input)

	# Assert
	if result != "Plain spoken line.":
		return _fail("no action tag: expected 'Plain spoken line.', got '%s'" % result)
	return true


func _test_extract_speech_handles_two_action_attrs_no_on() -> bool:
	## extract_speech strips <action verb="..." target="..."/> (two-attribute form, no `on`).
	# Arrange
	var input := "<speech>I walk toward it.<action verb=\"go_to\" target=\"pillar\"/></speech>"

	# Act
	var result: String = PromptBuilder.extract_speech(input)

	# Assert
	if result.contains("<action"):
		return _fail("two-attr strip: <action tag still present in output: '%s'" % result)
	if result != "I walk toward it.":
		return _fail("two-attr strip: expected 'I walk toward it.', got '%s'" % result)
	return true


func _test_extract_speech_action_outside_block_dropped_with_outer_text() -> bool:
	## When <action .../> is outside the <speech> block, extract_speech only
	## returns the speech contents — the outer text (including the action tag)
	## is dropped because nothing outside a <speech> block is ever rendered.
	## Output equals the speech content only; no action tag survives in any
	## form.
	# Arrange
	# Action is OUTSIDE the <speech> block — in the surrounding "inner monologue".
	var input := "Some inner monologue.<action verb=\"take\" target=\"coin\"/> <speech>I say nothing worth repeating.</speech>"

	# Act
	var result: String = PromptBuilder.extract_speech(input)

	# Assert — outer text (including the action tag) is dropped; only speech contents returned.
	if result.contains("<action"):
		return _fail("outside block: <action tag appeared in output: '%s'" % result)
	if result != "I say nothing worth repeating.":
		return _fail("outside block: expected speech-only text, got '%s'" % result)
	return true


# ── Tests: _action_tag_instructions / build_observe / build_arrive ─────────

func _test_action_tag_instructions_returns_default_when_no_override() -> bool:
	## When world config has no action_tag_instructions key, build_observe uses
	## the global default from GameState.defaults.puzzle.action_tag_instructions.
	## Verified indirectly via build_observe (option b — public API test).
	# Arrange — FIXTURE_PUZZLE_DEFAULTS is already installed with "FIXTURE_ACTION_INSTRUCTIONS".
	var config: Dictionary = _world_config()  # no action_tag_instructions key

	# Act
	var result: Dictionary = PromptBuilder.build_observe(config, null, "old stone", "It has stood here long.")

	# Assert
	var system: String = result.get("system", "")
	if not system.contains("FIXTURE_ACTION_INSTRUCTIONS"):
		return _fail("default fragment: system prompt missing global default fragment, got: '%s'" % system)
	return true


func _test_action_tag_instructions_world_override_wins() -> bool:
	## When world config declares action_tag_instructions, it takes precedence
	## over the global default.
	# Arrange — FIXTURE_PUZZLE_DEFAULTS installed with "FIXTURE_ACTION_INSTRUCTIONS" as global.
	var config: Dictionary = _world_config({"action_tag_instructions": "WORLD_OVERRIDE_TEXT"})

	# Act
	var result: Dictionary = PromptBuilder.build_observe(config, null, "old stone", "It has stood here long.")

	# Assert
	var system: String = result.get("system", "")
	if not system.contains("WORLD_OVERRIDE_TEXT"):
		return _fail("world override: system prompt missing world override text, got: '%s'" % system)
	if system.contains("FIXTURE_ACTION_INSTRUCTIONS"):
		return _fail("world override: global default leaked into system prompt despite world override")
	return true


func _test_action_tag_instructions_missing_puzzle_block_returns_empty() -> bool:
	## When GameState.defaults has no "puzzle" key at all, _action_tag_instructions
	## must return "" (via build_observe) — no crash, no leaked variant, and the
	## emitted system prompt simply lacks the fragment. Covers the
	## `if puzzle_defaults is Dictionary` fallback branch in prompt_builder.gd.
	# Arrange — temporarily erase the suite-installed puzzle block.
	var saved_puzzle: Variant = GameState.defaults.get("puzzle", null)
	GameState.defaults.erase("puzzle")
	var config: Dictionary = _world_config()  # no world override either

	# Act
	var result: Dictionary = PromptBuilder.build_observe(config, null, "old stone", "It has stood here long.")

	# Restore before asserting.
	if saved_puzzle != null:
		GameState.defaults["puzzle"] = saved_puzzle

	# Assert — no fixture marker can appear, and the call must have succeeded.
	var system: String = result.get("system", "")
	if system.contains("FIXTURE_ACTION_INSTRUCTIONS"):
		return _fail("missing puzzle block: stale fragment leaked into system prompt, got: '%s'" % system)
	if not result.has("user"):
		return _fail("missing puzzle block: build_observe returned malformed result (no 'user' key)")
	return true


func _test_build_observe_appends_action_fragment() -> bool:
	## build_observe appends the ACTION_TAG_INSTRUCTIONS fragment to the system prompt.
	# Arrange — fixture installs "FIXTURE_ACTION_INSTRUCTIONS" as global default.
	var config: Dictionary = _world_config()

	# Act
	var result: Dictionary = PromptBuilder.build_observe(config, null, "stone pillar", "Carved from a single block.")

	# Assert
	var system: String = result.get("system", "")
	if not system.contains("FIXTURE_ACTION_INSTRUCTIONS"):
		return _fail("build_observe fragment: system prompt missing action fragment, got: '%s'" % system)
	return true


func _test_build_arrive_does_not_append_action_fragment() -> bool:
	## build_arrive must NOT append the action instructions fragment (R20).
	## The suite-level fixture installs "FIXTURE_ACTION_INSTRUCTIONS" as the
	## global default, so any leak would surface here.
	# Arrange
	var config: Dictionary = _world_config()
	var opts: Dictionary = {"previous_world_name": "", "is_new": true, "transition_override": ""}

	# Act
	var result: Dictionary = PromptBuilder.build_arrive(config, null, opts)

	# Assert
	var system: String = result.get("system", "")
	if system.contains("FIXTURE_ACTION_INSTRUCTIONS"):
		return _fail("build_arrive R20: action fragment found in arrival system prompt (must be excluded), system: '%s'" % system)
	return true
