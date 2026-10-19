class_name EmotionTags
extends RefCounted
## Lets the agent self-report emotion shifts in its own response using XML
## tags we parse out before showing the response to the player. Bridges to
## a proper MCP tool later — same semantics, different transport.
##
## Tag shape (all deltas optional, reason required when any delta present):
##
##     <emotion_update>
##       <energy>-0.1</energy>
##       <patience>+0.05</patience>
##       <social_battery>-0.08</social_battery>
##       <reason>short plain reason</reason>
##     </emotion_update>
##
## Agents can emit zero, one, or many blocks in a single response. The
## parser applies every block to the engine and returns the text with
## all blocks removed.

const INSTRUCTIONS := """You may include <emotion_update> tags in your response to self-report how this event shifted your internal state. Use them whenever you actually feel something change — not every turn. Shape:

<emotion_update>
  <energy>-0.1</energy>
  <patience>+0.05</patience>
  <social_battery>-0.08</social_battery>
  <reason>one short phrase</reason>
</emotion_update>

Deltas range [-1.0, 1.0]. All three variables are optional; <reason> is required when any delta is present. These tags are stripped from what you say out loud, so say them once and don't reference them in prose."""


static func parse_and_apply(text: String, engine: EmotionEngine) -> String:
	"""Extract every <emotion_update> block from text, apply each to the
	engine, return text with the blocks removed. Stripping also collapses
	the leading/trailing whitespace the removal leaves behind."""
	if engine == null or text == "" or not text.contains("<emotion_update>"):
		return text
	var block_re := RegEx.new()
	block_re.compile("(?s)<emotion_update>(.*?)</emotion_update>")
	for m in block_re.search_all(text):
		_apply_block(m.get_string(1), engine)
	var stripped: String = block_re.sub(text, "", true)
	return _tidy_whitespace(stripped)


static func _apply_block(body: String, engine: EmotionEngine) -> void:
	var energy_delta := _extract_float(body, "energy")
	var patience_delta := _extract_float(body, "patience")
	var social_delta := _extract_float(body, "social_battery")
	var reason := _extract_text(body, "reason")
	var any_delta := energy_delta != 0.0 or patience_delta != 0.0 or social_delta != 0.0
	if not any_delta:
		return
	if reason == "":
		reason = "unspecified"
	engine.energy = clampf(engine.energy + energy_delta, 0.0, 1.0)
	engine.patience = clampf(engine.patience + patience_delta, 0.0, 1.0)
	engine.social_battery = clampf(engine.social_battery + social_delta, 0.0, 1.0)
	engine.log_cause(reason)


static func _extract_float(body: String, tag: String) -> float:
	var re := RegEx.new()
	re.compile("<%s>\\s*([+-]?\\d*\\.?\\d+)\\s*</%s>" % [tag, tag])
	var m := re.search(body)
	if m == null:
		return 0.0
	return clampf(float(m.get_string(1)), -1.0, 1.0)


static func _extract_text(body: String, tag: String) -> String:
	var re := RegEx.new()
	re.compile("(?s)<%s>(.*?)</%s>" % [tag, tag])
	var m := re.search(body)
	if m == null:
		return ""
	return m.get_string(1).strip_edges()


static func _tidy_whitespace(text: String) -> String:
	var collapsed := RegEx.new()
	collapsed.compile("\\n{3,}")
	return collapsed.sub(text, "\n\n", true).strip_edges()
