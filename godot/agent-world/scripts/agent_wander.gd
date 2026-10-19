class_name AgentWander
extends RefCounted
## Ambient wander brain — decides WHEN the agent moves (dwell texture),
## WHERE it goes (utility-scored destinations), and HOW the walk feels
## (per-walk speed jitter, noise-driven sway, mid-walk change of mind).
##
## Owned by Agent (host-ref pattern, like the world_loader helpers). The
## host keeps everything below the decision layer: the Theta* planner,
## nav grid, RVO avoidance, and every stall/wedge recovery layer. This
## class only answers "what should the next walk be" and hands the goal
## to host.begin_wander_walk(); the host reports back through
## on_walk_finished() when the walk lands.
##
## Destination model (Sims-style smart-object scoring, Reynolds steering
## texture): every wander decision builds a candidate pool — interest-
## weighted prop rings, social rings around peers, correlated-heading
## exploration points, the home anchor — scores each by
##   weight × interest × novelty × distance-falloff × crowd factor
## then picks weighted-random among the top K. Top-k roulette, NOT
## argmax: argmax makes every agent deterministic and identical.
## Interest comes from AgentMemory.get_prop_interest — the "Formula 3
## wander-weight" hook that was built dormant in Story 008 and is wired
## in for real here.

## Fully random fallback for cul-de-sac escape: the last explore sample
## always ignores the correlated heading, mirroring the old
## _wander_random escape behavior.
const _RETRY_PAUSE_MIN: float = 0.3
const _RETRY_PAUSE_MAX: float = 0.8
## Change-of-mind fires somewhere in the middle of the estimated travel
## time — never right at the start (looks like a stutter) or the end
## (indistinguishable from arrival).
const _CHANGE_OF_MIND_WINDOW_MIN: float = 0.25
const _CHANGE_OF_MIND_WINDOW_MAX: float = 0.75
const _MIN_WALK_FOR_CHANGE_OF_MIND: float = 1.0
## Ring sampling attempts per POI candidate. 8 angles is enough to find
## a walkable spot around any prop that has walkable ground at all.
const _RING_SAMPLES: int = 8
## Channel spacing on the shared 1D noise line. Large enough that the
## sway and speed channels of every agent are uncorrelated slices.
const _SPEED_CHANNEL_SPACING: float = 5000.0

var host: Agent = null

# ── Config (script values are absolute fallbacks for missing keys) ────────
var _distances: Dictionary = {
	"short": [40.0, 120.0],
	"medium": [120.0, 320.0],
	"long": [320.0, 600.0],
}
var _dist_weights: Dictionary = {"short": 0.1, "medium": 0.6, "long": 0.3}
var _turn_max: float = PI / 3.0
var _speed_jitter: Vector2 = Vector2(0.85, 1.15)
var _speed_noise_amount: float = 0.12
var _speed_noise_frequency: float = 0.5
var _sway_max: float = deg_to_rad(7.0)
var _sway_frequency: float = 0.35
var _dwell_base: float = 1.6
var _dwell_sigma: float = 0.6
var _dwell_min: float = 0.6
var _dwell_max: float = 8.0
var _look_around_chance: float = 0.6
var _look_max_glances: int = 3
var _glance_interval: Vector2 = Vector2(0.5, 1.4)
var _change_of_mind_chance: float = 0.05
var _dest_cfg: Dictionary = {}
var _mood_bias: Dictionary = {}
var _personality: Dictionary = {}

# ── Runtime state ─────────────────────────────────────────────────────────
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Correlated explore heading. NAN = no prior heading, next explore roll
## is fully random. Reset by the host's wedge recovery — a heading that
## led into a pin demonstrably wasn't working.
var _heading: float = NAN
var _home: Vector2 = Vector2.INF
## Spatial anti-repeat: world positions of the last N wander landings.
var _recent_dests: Array[Vector2] = []
## POI anti-repeat: "prop:<id>" / "peer:<id>" → seconds at last landing.
var _poi_last_visit: Dictionary = {}

# Active-walk profile — rolled once per walk in start_wander.
var _walk_speed_scale: float = 1.0
var _walk_elapsed: float = 0.0
var _change_of_mind_at: float = -1.0
var _walk_poi_id: String = ""
var _face_target: Vector2 = Vector2.INF

# Dwell look-around state.
var _glances_left: int = 0
var _next_glance_in: float = 0.0

## One noise resource for every agent; per-agent decorrelation comes from
## a large hash-derived offset along the 1D line. frequency = 1.0 so the
## per-channel frequencies below are the only time scaling.
static var _noise: FastNoiseLite = null
var _noise_offset: float = 0.0


func setup(p_host: Agent) -> void:
	host = p_host
	_rng.randomize()
	_noise_offset = float(absi(p_host.agent_id.hash()) % 100000)
	_home = p_host.global_position
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
	_load_config()


func _load_config() -> void:
	var cfg: Variant = GameState.get_default("wander", null)
	if not (cfg is Dictionary):
		return
	var wander: Dictionary = cfg
	var distances: Variant = wander.get("distances", null)
	if distances is Dictionary and not (distances as Dictionary).is_empty():
		_distances = distances
	var weights: Variant = wander.get("weights", null)
	if weights is Dictionary and not (weights as Dictionary).is_empty():
		_dist_weights = weights
	var turn_deg: Variant = wander.get("turn_max_degrees", null)
	if turn_deg is float or turn_deg is int:
		_turn_max = deg_to_rad(float(turn_deg))
	_speed_jitter = _as_range(wander.get("speed_jitter", null), _speed_jitter)
	_speed_noise_amount = _as_float(wander.get("speed_noise_amount", null), _speed_noise_amount)
	_speed_noise_frequency = _as_float(wander.get("speed_noise_frequency", null), _speed_noise_frequency)
	var sway_deg: Variant = wander.get("sway_degrees", null)
	if sway_deg is float or sway_deg is int:
		_sway_max = deg_to_rad(float(sway_deg))
	_sway_frequency = _as_float(wander.get("sway_frequency", null), _sway_frequency)
	_dwell_base = _as_float(wander.get("dwell_base_seconds", null), _dwell_base)
	_dwell_sigma = _as_float(wander.get("dwell_sigma", null), _dwell_sigma)
	_dwell_min = _as_float(wander.get("dwell_min_seconds", null), _dwell_min)
	_dwell_max = _as_float(wander.get("dwell_max_seconds", null), _dwell_max)
	_look_around_chance = _as_float(wander.get("look_around_chance", null), _look_around_chance)
	var glances: Variant = wander.get("look_max_glances", null)
	if glances is float or glances is int:
		_look_max_glances = int(glances)
	_glance_interval = _as_range(wander.get("glance_interval", null), _glance_interval)
	_change_of_mind_chance = _as_float(wander.get("change_of_mind_chance", null), _change_of_mind_chance)
	var dest: Variant = wander.get("destination", null)
	if dest is Dictionary:
		_dest_cfg = dest
	var bias: Variant = wander.get("mood_bias", null)
	if bias is Dictionary:
		_mood_bias = bias
	# Optional per-agent multipliers on the destination-kind weights —
	# lets individual agents lean social / curious / homebound without
	# code. Absent key = neutral personality.
	var agent_cfg: Variant = GameState.agents.get(host.agent_id, null)
	if agent_cfg is Dictionary:
		var pers: Variant = (agent_cfg as Dictionary).get("wander_personality", null)
		if pers is Dictionary:
			_personality = pers


static func _as_float(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	return fallback


static func _as_range(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and (v as Array).size() == 2:
		var arr: Array = v
		return Vector2(float(arr[0]), float(arr[1]))
	return fallback


func _dest_float(key: String, fallback: float) -> float:
	return _as_float(_dest_cfg.get(key, null), fallback)


# ── Destination decision ──────────────────────────────────────────────────

func start_wander() -> void:
	## Called by the host when the idle dwell expires. Builds and scores
	## the candidate pool, picks by top-k roulette, rolls the walk
	## profile, and starts the walk. On any failure the host just idles
	## briefly and retries — same contract as the old _wander_random.
	var candidates: Array[Dictionary] = _build_candidates()
	var idx: int = pick_top_k(_rng, candidates, int(_dest_float("top_k", 3.0)))
	if idx < 0:
		host.idle_timer = _rng.randf_range(_RETRY_PAUSE_MIN, _RETRY_PAUSE_MAX)
		return
	var chosen: Dictionary = candidates[idx]
	var goal: Vector2 = chosen["pos"]
	_walk_speed_scale = _rng.randf_range(_speed_jitter.x, _speed_jitter.y)
	_walk_elapsed = 0.0
	_walk_poi_id = str(chosen.get("id", ""))
	var face_v: Variant = chosen.get("face", null)
	_face_target = face_v if face_v is Vector2 else Vector2.INF
	_change_of_mind_at = -1.0
	var travel_est: float = host.global_position.distance_to(goal) / maxf(host.move_speed, 1.0)
	if travel_est > _MIN_WALK_FOR_CHANGE_OF_MIND and _rng.randf() < _change_of_mind_chance:
		_change_of_mind_at = travel_est * _rng.randf_range(
			_CHANGE_OF_MIND_WINDOW_MIN, _CHANGE_OF_MIND_WINDOW_MAX
		)
	if not host.begin_wander_walk(goal):
		host.idle_timer = _rng.randf_range(_RETRY_PAUSE_MIN, _RETRY_PAUSE_MAX)
		return
	_heading = (goal - host.global_position).angle()


func _build_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now: float = Time.get_ticks_msec() / 1000.0
	var wts: Dictionary = _kind_weights()
	# Content-directed candidates (props, peers) are autonomous
	# interaction behavior and stay behind the `interactions` flag —
	# same rule as observation and encounter rolls. Pure locomotion
	# (explore, home) only needs `wandering`.
	if host.interactions:
		_add_prop_candidates(out, now, float(wts.get("prop", 1.0)))
		_add_peer_candidates(out, now, float(wts.get("peer", 0.6)))
	_add_explore_candidates(out, float(wts.get("explore", 1.0)))
	_add_home_candidate(out, float(wts.get("home", 0.25)))
	return out


func _kind_weights() -> Dictionary:
	## Base kind weights × mood bias × per-agent personality. Mood makes
	## movement legible: curious agents drift toward props, tired ones
	## drift home, excited ones range wider.
	var wts: Dictionary = {
		"prop": _dest_float("prop_weight", 1.0),
		"peer": _dest_float("peer_weight", 0.6),
		"explore": _dest_float("explore_weight", 1.0),
		"home": _dest_float("home_weight", 0.25),
	}
	var bias: Variant = _mood_bias.get(host.current_mood, null)
	for source: Variant in [bias, _personality]:
		if not (source is Dictionary):
			continue
		for kind: String in wts:
			var mult: Variant = (source as Dictionary).get(kind, null)
			if mult is float or mult is int:
				wts[kind] = float(wts[kind]) * float(mult)
	return wts


func _add_prop_candidates(out: Array[Dictionary], now: float, weight: float) -> void:
	var interest_min: float = _dest_float("interest_min", 0.1)
	var ring: float = host.observe_radius * _dest_float("prop_ring_mult", 0.8)
	for prop: Variant in host._cached_props:
		if not is_instance_valid(prop):
			continue
		var pid: String = prop.prop_id
		var interest: float = 1.0
		if host.memory != null:
			interest = host.memory.get_prop_interest(pid)
		if interest < interest_min:
			continue
		var prop_pos: Vector2 = (prop as Node2D).global_position
		var pos: Vector2 = _sample_ring(prop_pos, ring)
		if pos == Vector2.INF:
			continue
		var score: float = score_destination(
			weight,
			interest,
			novelty_factor(_poi_last_visit.get("prop:" + pid, -INF), now,
				_dest_float("novelty_refresh_seconds", 90.0), _dest_float("novelty_floor", 0.2)),
			host.global_position.distance_to(pos),
			_dest_float("distance_falloff", 900.0),
			_count_agents_near(prop_pos),
			_dest_float("crowd_penalty", 0.35),
		)
		score *= recency_multiplier(pos, _recent_dests,
			_dest_float("recency_radius", 160.0), _dest_float("recency_penalty", 0.5))
		out.append({"pos": pos, "score": score, "id": "prop:" + pid, "face": prop_pos})


func _add_peer_candidates(out: Array[Dictionary], now: float, weight: float) -> void:
	## Social pull: the goal is a ring point at conversational distance
	## from a peer, not the peer itself (Reynolds offset-arrival). Landing
	## inside encounter range lets the existing proximity roll fire — the
	## wander layer creates the opportunity, the encounter system decides.
	if host.world_loader == null or host.world_loader.agents_container == null:
		return
	var social_dist: float = host.display_height * _dest_float("social_distance_mult", 1.6)
	for other: Node in host.world_loader.agents_container.get_children():
		if other == host or not is_instance_valid(other) or not (other is Agent):
			continue
		var peer: Agent = other
		if not peer.interactions or peer.is_socially_busy() or peer._meeting_anchor != null:
			continue
		var pos: Vector2 = _sample_ring(peer.global_position, social_dist)
		if pos == Vector2.INF:
			continue
		var score: float = score_destination(
			weight,
			1.0,
			novelty_factor(_poi_last_visit.get("peer:" + peer.agent_id, -INF), now,
				_dest_float("novelty_refresh_seconds", 90.0), _dest_float("novelty_floor", 0.2)),
			host.global_position.distance_to(pos),
			_dest_float("distance_falloff", 900.0),
			_count_agents_near(peer.global_position),
			_dest_float("crowd_penalty", 0.35),
		)
		score *= recency_multiplier(pos, _recent_dests,
			_dest_float("recency_radius", 160.0), _dest_float("recency_penalty", 0.5))
		out.append({
			"pos": pos, "score": score,
			"id": "peer:" + peer.agent_id, "face": peer.global_position,
		})


func _add_explore_candidates(out: Array[Dictionary], weight: float) -> void:
	## Correlated random walk, kept from the previous implementation —
	## each sample perturbs the last heading by ±turn_max so exploration
	## drifts instead of snapping. The final sample is always fully
	## random so a cul-de-sac can't trap the heading. Explore candidates
	## pay the same distance falloff as POI candidates — without it they
	## score a flat weight while props get multiplied down by distance,
	## and the roulette never sends anyone to a prop (observed live:
	## explore 1.0 vs props 0.03-0.09).
	var samples: int = int(_dest_float("explore_samples", 3.0))
	for i: int in range(samples):
		var dist: float = pick_band_distance(_rng, _distances, _dist_weights)
		if dist <= 0.0:
			continue
		var angle: float
		if not is_nan(_heading) and i < samples - 1:
			angle = perturb_heading(_rng, _heading, _turn_max)
		else:
			angle = _rng.randf() * TAU
		var pos: Vector2 = host.global_position + Vector2(cos(angle), sin(angle)) * dist
		pos = host.clamp_to_room(pos)
		if not host.is_wanderable_point(pos):
			continue
		var score: float = score_destination(
			weight, 1.0, 1.0,
			host.global_position.distance_to(pos),
			_dest_float("distance_falloff", 900.0),
			0, 0.0,
		)
		score *= recency_multiplier(pos, _recent_dests,
			_dest_float("recency_radius", 160.0), _dest_float("recency_penalty", 0.5))
		out.append({"pos": pos, "score": score, "id": "", "face": null})


func _add_home_candidate(out: Array[Dictionary], weight: float) -> void:
	## The anchor beat: an occasional walk back toward the spawn spot
	## keeps each agent loosely territorial, which is what makes a room
	## of wanderers read as inhabited instead of diffusing into uniform
	## soup. Flat weight — home is a mood, not an errand.
	if _home == Vector2.INF:
		return
	if host.global_position.distance_to(_home) < _dest_float("recency_radius", 160.0):
		return
	if not host.is_wanderable_point(_home):
		return
	out.append({"pos": _home, "score": weight, "id": "", "face": null})


func _sample_ring(center: Vector2, radius: float) -> Vector2:
	## First walkable in-room point on a ring around a POI. Random start
	## angle so repeated visits approach from different sides.
	var start: float = _rng.randf() * TAU
	for k: int in range(_RING_SAMPLES):
		var angle: float = start + TAU * float(k) / float(_RING_SAMPLES)
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		if host.is_wanderable_point(pos):
			return pos
	return Vector2.INF


func _count_agents_near(pos: Vector2) -> int:
	var radius: float = _dest_float("crowd_radius", 180.0)
	var count: int = 0
	if host.world_loader == null or host.world_loader.agents_container == null:
		return 0
	for other: Node in host.world_loader.agents_container.get_children():
		if other == host or not is_instance_valid(other) or not (other is Agent):
			continue
		if (other as Agent).global_position.distance_to(pos) < radius:
			count += 1
	return count


# ── Walk texture (host calls these while WALKING a wander goal) ──────────

func tick_walk(delta: float) -> void:
	_walk_elapsed += delta
	if _change_of_mind_at > 0.0 and _walk_elapsed >= _change_of_mind_at:
		# Mid-walk "actually, no" — abandon the goal, pause, re-roll on
		# the next idle expiry. Disproportionately humanizing for one
		# conditional (kills the metronomic walk-stop-walk rhythm).
		_change_of_mind_at = -1.0
		host.cancel_wander_walk()


func speed_scale() -> float:
	## Per-walk cruise jitter × slow noise surge. The surge reads as
	## attention drifting; ±speed_noise_amount around the rolled cruise.
	var n: float = _noise.get_noise_1d(
		_walk_elapsed * _speed_noise_frequency + _noise_offset + _SPEED_CHANNEL_SPACING
	)
	return _walk_speed_scale * (1.0 + _speed_noise_amount * n)


func sway_angle() -> float:
	## Smooth heading wobble from the shared simplex line — organic arcs
	## instead of laser-straight segments. C1-continuous by construction,
	## frame-rate independent (time accumulates from physics delta).
	return _noise.get_noise_1d(_walk_elapsed * _sway_frequency + _noise_offset) * _sway_max


func reset_heading() -> void:
	## Host wedge recovery hook — the current heading led into a pin, so
	## the next explore roll starts fresh.
	_heading = NAN


# ── Arrival + dwell texture ───────────────────────────────────────────────

func on_walk_finished() -> void:
	## The wander walk landed. Stamp anti-repeat memory, face the POI,
	## seed the heavy-tailed dwell, maybe schedule look-around glances.
	var now: float = Time.get_ticks_msec() / 1000.0
	_recent_dests.append(host.global_position)
	var keep: int = int(_dest_float("recency_memory", 4.0))
	while _recent_dests.size() > keep:
		_recent_dests.remove_at(0)
	if _walk_poi_id != "":
		_poi_last_visit[_walk_poi_id] = now
		_walk_poi_id = ""
	if _face_target != Vector2.INF:
		host.face_toward(_face_target)
	host.idle_timer = sample_dwell(_rng, _dwell_base, _dwell_sigma, _dwell_min, _dwell_max)
	_glances_left = 0
	if _rng.randf() < _look_around_chance:
		_glances_left = _rng.randi_range(1, maxi(_look_max_glances, 1))
		_next_glance_in = _rng.randf_range(_glance_interval.x, _glance_interval.y)


func tick_dwell(delta: float) -> void:
	## Idle body language: during a dwell the agent occasionally turns
	## its head — toward a peer, back toward the POI it walked to, or
	## nowhere in particular. Pure facing changes, no movement.
	if _glances_left <= 0:
		return
	_next_glance_in -= delta
	if _next_glance_in > 0.0:
		return
	_glances_left -= 1
	_next_glance_in = _rng.randf_range(_glance_interval.x, _glance_interval.y)
	host.face_toward(_pick_glance_target())


func _pick_glance_target() -> Vector2:
	var roll: float = _rng.randf()
	if roll < 0.35:
		var peer_pos: Vector2 = _nearest_peer_position()
		if peer_pos != Vector2.INF:
			return peer_pos
	if roll < 0.55 and _face_target != Vector2.INF:
		return _face_target
	return host.global_position + Vector2(
		cos(_rng.randf() * TAU), sin(_rng.randf() * TAU)
	) * 50.0


func _nearest_peer_position() -> Vector2:
	if host.world_loader == null or host.world_loader.agents_container == null:
		return Vector2.INF
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for other: Node in host.world_loader.agents_container.get_children():
		if other == host or not is_instance_valid(other) or not (other is Agent):
			continue
		var d: float = host.global_position.distance_to((other as Agent).global_position)
		if d < best_d:
			best_d = d
			best = (other as Agent).global_position
	return best


# ── Pure scoring/sampling primitives (static — headless-testable) ────────

static func score_destination(
	weight: float,
	interest: float,
	novelty: float,
	dist: float,
	falloff: float,
	crowd_count: int,
	crowd_penalty: float,
) -> float:
	## weight × interest × novelty × distance-falloff × crowd factor.
	## Falloff is hyperbolic (1 / (1 + d/falloff)): near things tempt
	## more, but far ones never hit zero. Crowd factor floors at zero —
	## a fully crowded POI stops advertising entirely.
	var crowd: float = maxf(0.0, 1.0 - crowd_penalty * float(crowd_count))
	return weight * interest * novelty * (1.0 / (1.0 + dist / maxf(falloff, 1.0))) * crowd


static func novelty_factor(last_visit: float, now: float, refresh: float, floor_val: float) -> float:
	## 1.0 for never-visited, linear recovery from floor_val back to 1.0
	## over `refresh` seconds since the last landing at this POI.
	if last_visit == -INF:
		return 1.0
	return clampf((now - last_visit) / maxf(refresh, 0.001), floor_val, 1.0)


static func recency_multiplier(
	pos: Vector2, recents: Array[Vector2], radius: float, penalty: float
) -> float:
	## Compounding spatial anti-repeat: each recent landing within
	## `radius` of the candidate multiplies its score by (1 - penalty).
	var mult: float = 1.0
	for r: Vector2 in recents:
		if pos.distance_to(r) < radius:
			mult *= 1.0 - penalty
	return mult


static func pick_top_k(rng: RandomNumberGenerator, candidates: Array[Dictionary], k: int) -> int:
	## Weighted-random pick among the K highest-scoring candidates.
	## Returns an index into `candidates`, or -1 when nothing has a
	## positive score. Roulette over the top slice keeps agents varied
	## while still favoring the best option.
	var order: Array[int] = []
	for i: int in range(candidates.size()):
		if float(candidates[i].get("score", 0.0)) > 0.0:
			order.append(i)
	if order.is_empty():
		return -1
	order.sort_custom(func(a: int, b: int) -> bool:
		return float(candidates[a]["score"]) > float(candidates[b]["score"]))
	var top: Array[int] = order.slice(0, maxi(k, 1))
	var total: float = 0.0
	for i: int in top:
		total += float(candidates[i]["score"])
	var roll: float = rng.randf() * total
	for i: int in top:
		roll -= float(candidates[i]["score"])
		if roll <= 0.0:
			return i
	return top[top.size() - 1]


static func sample_dwell(
	rng: RandomNumberGenerator, base: float, sigma: float, min_s: float, max_s: float
) -> float:
	## Heavy-tailed (log-normal) dwell: most pauses land near `base`,
	## rare ones linger several times longer. Fixed uniform ranges read
	## as a metronome; the long tail is what reads as "he's thinking."
	return clampf(base * exp(rng.randfn(0.0, sigma)), min_s, max_s)


static func perturb_heading(rng: RandomNumberGenerator, heading: float, turn_max: float) -> float:
	return heading + rng.randf_range(-turn_max, turn_max)


static func pick_band_distance(
	rng: RandomNumberGenerator, distances: Dictionary, weights: Dictionary
) -> float:
	## Weighted band roll (short/medium/long), then uniform inside the
	## band's [min, max]. Zero-weight bands can never be picked; float
	## residue falls to the last positive band. Returns 0.0 on
	## empty/invalid config.
	var total: float = 0.0
	for band: String in weights:
		total += maxf(float(weights[band]), 0.0)
	if total <= 0.0:
		return 0.0
	var roll: float = rng.randf() * total
	var chosen: String = ""
	for band: String in weights:
		var w: float = maxf(float(weights[band]), 0.0)
		if w <= 0.0:
			continue
		chosen = band
		roll -= w
		if roll <= 0.0:
			break
	var range_arr: Variant = distances.get(chosen, null)
	if range_arr is Array and (range_arr as Array).size() == 2:
		var arr: Array = range_arr
		return rng.randf_range(float(arr[0]), float(arr[1]))
	return 0.0
