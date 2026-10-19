class_name EmotionEngine
extends RefCounted

signal mood_changed(new_mood: String)
## Emotion state for an agent — four persistent variables + a derived mood
## label + a short causal ring buffer that remembers WHY the agent feels
## what it feels. The causal log is what makes the state legible: it drives
## the prose rendered into every LLM prompt, so the agent can reference
## recent events in its own voice instead of staring at bare numbers.
##
## Design: events move the needle fast; decay is a slow background drift.
## (Previous version inverted this ratio and the decay drowned out every
## event, which is why emotion felt invisible in-game.)

# ── Persistent state ──────────────────────────────────────────────────────

var energy: float = 0.8
var patience: float = 0.7
var social_battery: float = 0.7
var trust: Dictionary = {}  # target_id → float, per-target relationships

# Transient: how many "curiosity ticks" since the last novel observation.
# Used to keep the derived mood on 'curious' briefly after a new sighting.
var _fresh_curiosity_ticks: int = 0

# Causal ring buffer — last N things that shifted how the agent feels.
# Each entry is {"reason": String, "t": unix_seconds}. Drives the prose prompt
# injection (which reads the tail via recent_causes). Sized generously so the
# UI modal has something to show; prompts pass their own much smaller limit.
const CAUSAL_LOG_MAX := 50
var _causal_log: Array[Dictionary] = []


# ── Tunable thresholds (loaded from game_config.defaults.emotion each call) ──
# Direct lookup each call so live config edits take effect without restart.

static func _th(key: String, fallback: float) -> float:
	var cfg: Variant = GameState.get_default("emotion", {})
	if cfg is Dictionary:
		return float(cfg.get(key, fallback))
	return fallback


## Return the defaults.emotion.events.<event_name> dict, or {} if missing/malformed.
## Single lookup point for event-specific deltas and log-cause strings so per-event
## handlers can't accidentally diverge on config-key conventions.
static func _event_config(event_name: String) -> Dictionary:
	var emo: Variant = GameState.get_default("emotion", {})
	if not (emo is Dictionary):
		return {}
	var events: Variant = (emo as Dictionary).get("events", {})
	if not (events is Dictionary):
		return {}
	var cfg: Variant = (events as Dictionary).get(event_name, {})
	if cfg is Dictionary:
		return cfg as Dictionary
	return {}


# ── Serialization (HUD) ───────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"mood": mood,
		"energy": snappedf(energy, 0.01),
		"patience": snappedf(patience, 0.01),
		"social_battery": snappedf(social_battery, 0.01),
	}


# ── Derived mood ──────────────────────────────────────────────────────────

var mood: String:
	get:
		return _derive_mood()

func _derive_mood() -> String:
	if energy < _th("tired_below", 0.3):
		return "tired"
	if patience < _th("frustrated_below", 0.3):
		return "frustrated"
	if _fresh_curiosity_ticks > 0:
		return "curious"
	if energy > _th("excited_energy", 0.85) and social_battery > _th("excited_social", 0.6):
		return "excited"
	if social_battery > _th("happy_social", 0.8) and patience > _th("happy_patience", 0.6):
		return "happy"
	return "neutral"


# ── Events ────────────────────────────────────────────────────────────────

func process_event(event: String, context: Dictionary = {}) -> void:
	var prev_mood: String = _derive_mood()
	_apply_event(event, context)
	var next_mood: String = _derive_mood()
	if next_mood != prev_mood:
		mood_changed.emit(next_mood)


func _apply_event(event: String, context: Dictionary) -> void:
	match event:
		"new_topic":
			var entity: String = context.get("entity_name", "something new")
			energy = _clamp01(energy + 0.05)
			_fresh_curiosity_ticks = 3
			log_cause("noticed " + entity)

		"conversation_turn":
			energy = _clamp01(energy - 0.03)
			social_battery = _clamp01(social_battery - 0.08)
			if social_battery < 0.35:
				patience = _clamp01(patience - 0.05)
			var speaker: String = context.get("with", "your user")
			log_cause("talked with " + speaker)

		"repeated_question":
			patience = _clamp01(patience - 0.2)
			log_cause("the same question came up again")

		"idle":
			var turns: int = context.get("turns", 1)
			_decay(turns)
			if _fresh_curiosity_ticks > 0:
				_fresh_curiosity_ticks -= 1

		## Story 004 / AC-FE-01 — fires from ActionResolver.resolve() when
		## state_changed == true (a rule matched and effects applied). Deltas
		## and curiosity tick count from game_config.defaults.emotion.events.action_resolved.
		"action_resolved":
			var ar_cfg: Dictionary = _event_config("action_resolved")
			energy = _clamp01(energy + float(ar_cfg.get("energy_delta", 0.04)))
			_fresh_curiosity_ticks = int(ar_cfg.get("curiosity_ticks", 2))
			var target_id: String = context.get("target_id", "")
			if target_id.is_empty():
				log_cause(str(ar_cfg.get("log_cause_no_target", "something in the world shifted because of you")))
			else:
				log_cause(str(ar_cfg.get("log_cause_with_target", "acted on {target}")).format({"target": target_id}))

		## Story 004 / AC-FE-02 — fires from ActionResolver._apply_puzzle_solved_emotion
		## for contributor + collaborators only (bystanders are skipped at the call site).
		## All deltas from game_config.defaults.emotion.events.puzzle_solved.
		"puzzle_solved":
			var ps_cfg: Dictionary = _event_config("puzzle_solved")
			energy = _clamp01(energy + float(ps_cfg.get("energy_delta", 0.08)))
			social_battery = _clamp01(social_battery + float(ps_cfg.get("social_battery_delta", 0.06)))
			patience = _clamp01(patience + float(ps_cfg.get("patience_delta", 0.04)))
			var is_contributor: bool = context.get("is_contributor", false)
			var cause_key: String = "log_cause_contributor" if is_contributor else "log_cause_witness"
			var cause: String = str(ps_cfg.get(cause_key, ""))
			# Guard: a missing config key would otherwise append a blank entry,
			# which leaks as "Recently: ." in the agent's prompt injection.
			if not cause.is_empty():
				log_cause(cause)


func _decay(turns: int) -> void:
	# Slow background drift toward rest. Events are supposed to dominate;
	# decay is just the "nothing happened for a while" baseline.
	var rate := 0.015 * float(turns)
	energy = _clamp01(energy + rate * 0.6)
	patience = _clamp01(patience + rate * 0.4)
	social_battery = _clamp01(social_battery + rate * 0.5)


# ── Causal log ────────────────────────────────────────────────────────────

func log_cause(reason: String) -> void:
	_causal_log.append({"reason": reason, "t": int(Time.get_unix_time_from_system())})
	while _causal_log.size() > CAUSAL_LOG_MAX:
		_causal_log.pop_front()


func full_log() -> Array[Dictionary]:
	return _causal_log.duplicate()


func recent_causes(limit: int = 3) -> Array[String]:
	if _causal_log.is_empty():
		return []
	var out: Array[String] = []
	var start: int = maxi(0, _causal_log.size() - limit)
	for i in range(start, _causal_log.size()):
		out.append(str(_causal_log[i].get("reason", "")))
	return out


# ── Prompt injection ──────────────────────────────────────────────────────

func to_prompt_injection() -> String:
	"""Natural-language prose wrapped in <emotional_state>. LLMs narrativize
	prose but ignore bare numbers — so the numbers stay in the game logic
	and only the prose leaves the engine for the prompt."""
	var lines: PackedStringArray = []
	lines.append(_state_sentence())
	var causes := recent_causes(3)
	if not causes.is_empty():
		lines.append("Recently: %s." % _join_prose(causes))
	return "<emotional_state>\n%s\n</emotional_state>" % "\n".join(lines)


func _state_sentence() -> String:
	var phrases: PackedStringArray = []
	# Energy
	if energy < 0.25:
		phrases.append("exhausted")
	elif energy < 0.5:
		phrases.append("a little tired")
	elif energy > 0.85:
		phrases.append("full of energy")
	# Patience
	if patience < 0.25:
		phrases.append("at the end of your patience")
	elif patience < 0.5:
		phrases.append("running thin on patience")
	elif patience > 0.85:
		phrases.append("calm and patient")
	# Social battery
	if social_battery < 0.25:
		phrases.append("worn out from conversation")
	elif social_battery < 0.5:
		phrases.append("starting to want some quiet")
	elif social_battery > 0.85:
		phrases.append("feeling sociable")

	if phrases.is_empty():
		return "You feel steady and present."
	return "You feel " + _join_prose(phrases) + "."


static func _join_prose(items: Array) -> String:
	var n := items.size()
	if n == 0:
		return ""
	if n == 1:
		return items[0]
	if n == 2:
		return "%s and %s" % [items[0], items[1]]
	var head: Array = items.slice(0, n - 1)
	return "%s, and %s" % [", ".join(head), items[n - 1]]


static func _clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)
