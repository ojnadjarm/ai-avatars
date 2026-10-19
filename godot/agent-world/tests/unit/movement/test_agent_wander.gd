class_name TestAgentWander
extends RefCounted
## Unit tests for AgentWander's pure scoring/sampling primitives (the
## ambient-movement refactor). All statics take an explicit
## RandomNumberGenerator, so every stochastic test runs on a fixed seed
## and is fully deterministic — no tree, no physics, no filesystem.

var failure_message: String = ""


func run() -> bool:
	var tests: Array[Callable] = [
		test_wander_score_destination_neutral_factors_returns_weight,
		test_wander_score_destination_distance_at_falloff_halves_score,
		test_wander_score_destination_crowd_saturation_zeroes_score,
		test_wander_novelty_factor_unvisited_poi_returns_one,
		test_wander_novelty_factor_fresh_visit_clamps_to_floor,
		test_wander_novelty_factor_full_refresh_recovers_to_one,
		test_wander_recency_multiplier_outside_radius_is_neutral,
		test_wander_recency_multiplier_compounds_per_nearby_landing,
		test_wander_pick_top_k_empty_pool_returns_negative,
		test_wander_pick_top_k_all_zero_scores_returns_negative,
		test_wander_pick_top_k_single_positive_returns_its_index,
		test_wander_pick_top_k_k1_always_returns_argmax,
		test_wander_pick_top_k_never_picks_outside_top_k,
		test_wander_sample_dwell_stays_within_bounds,
		test_wander_sample_dwell_zero_sigma_returns_base,
		test_wander_perturb_heading_stays_within_turn_max,
		test_wander_pick_band_distance_zero_weights_returns_zero,
		test_wander_pick_band_distance_stays_within_declared_bands,
		test_wander_pick_band_distance_never_picks_zero_weight_band,
	]
	for t: Callable in tests:
		if not t.call():
			if failure_message == "":
				failure_message = "unnamed failure in %s" % str(t.get_method())
			return false
	return true


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _seeded(seed_val: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


# ── score_destination ─────────────────────────────────────────────────────

func test_wander_score_destination_neutral_factors_returns_weight() -> bool:
	# Arrange: interest/novelty 1.0, zero distance, no crowd.
	# Act
	var score: float = AgentWander.score_destination(0.8, 1.0, 1.0, 0.0, 320.0, 0, 0.35)
	# Assert
	if not is_equal_approx(score, 0.8):
		return _fail("neutral factors should return bare weight, got %f" % score)
	return true


func test_wander_score_destination_distance_at_falloff_halves_score() -> bool:
	# Arrange: distance exactly equal to the falloff constant.
	# Act
	var score: float = AgentWander.score_destination(1.0, 1.0, 1.0, 320.0, 320.0, 0, 0.35)
	# Assert: hyperbolic falloff 1/(1 + d/falloff) = 0.5 at d == falloff.
	if not is_equal_approx(score, 0.5):
		return _fail("distance == falloff should halve score, got %f" % score)
	return true


func test_wander_score_destination_crowd_saturation_zeroes_score() -> bool:
	# Arrange: 3 agents near the POI at penalty 0.35 → factor would be
	# -0.05, which must floor at zero (a full POI stops advertising).
	# Act
	var score: float = AgentWander.score_destination(1.0, 1.0, 1.0, 0.0, 320.0, 3, 0.35)
	# Assert
	if score != 0.0:
		return _fail("saturated crowd should zero the score, got %f" % score)
	return true


# ── novelty_factor ────────────────────────────────────────────────────────

func test_wander_novelty_factor_unvisited_poi_returns_one() -> bool:
	# Arrange / Act
	var novelty: float = AgentWander.novelty_factor(-INF, 100.0, 90.0, 0.2)
	# Assert
	if not is_equal_approx(novelty, 1.0):
		return _fail("never-visited POI must be fully novel, got %f" % novelty)
	return true


func test_wander_novelty_factor_fresh_visit_clamps_to_floor() -> bool:
	# Arrange: visited this very second.
	# Act
	var novelty: float = AgentWander.novelty_factor(100.0, 100.0, 90.0, 0.2)
	# Assert
	if not is_equal_approx(novelty, 0.2):
		return _fail("just-visited POI must clamp to floor 0.2, got %f" % novelty)
	return true


func test_wander_novelty_factor_full_refresh_recovers_to_one() -> bool:
	# Arrange: a full refresh period (and more) has elapsed.
	# Act
	var novelty: float = AgentWander.novelty_factor(0.0, 200.0, 90.0, 0.2)
	# Assert
	if not is_equal_approx(novelty, 1.0):
		return _fail("elapsed >= refresh must recover to 1.0, got %f" % novelty)
	return true


# ── recency_multiplier ────────────────────────────────────────────────────

func test_wander_recency_multiplier_outside_radius_is_neutral() -> bool:
	# Arrange: one recent landing well outside the recency radius.
	var recents: Array[Vector2] = [Vector2(1000.0, 1000.0)]
	# Act
	var mult: float = AgentWander.recency_multiplier(Vector2.ZERO, recents, 160.0, 0.5)
	# Assert
	if not is_equal_approx(mult, 1.0):
		return _fail("far landing must not penalize, got %f" % mult)
	return true


func test_wander_recency_multiplier_compounds_per_nearby_landing() -> bool:
	# Arrange: two recent landings inside the radius at penalty 0.5.
	var recents: Array[Vector2] = [Vector2(10.0, 0.0), Vector2(0.0, 10.0)]
	# Act
	var mult: float = AgentWander.recency_multiplier(Vector2.ZERO, recents, 160.0, 0.5)
	# Assert: (1 - 0.5)^2 = 0.25.
	if not is_equal_approx(mult, 0.25):
		return _fail("two nearby landings must compound to 0.25, got %f" % mult)
	return true


# ── pick_top_k ────────────────────────────────────────────────────────────

func test_wander_pick_top_k_empty_pool_returns_negative() -> bool:
	# Arrange / Act
	var idx: int = AgentWander.pick_top_k(_seeded(1), [], 3)
	# Assert
	if idx != -1:
		return _fail("empty pool must return -1, got %d" % idx)
	return true


func test_wander_pick_top_k_all_zero_scores_returns_negative() -> bool:
	# Arrange
	var pool: Array[Dictionary] = [{"score": 0.0}, {"score": -2.0}]
	# Act
	var idx: int = AgentWander.pick_top_k(_seeded(1), pool, 3)
	# Assert
	if idx != -1:
		return _fail("non-positive scores must return -1, got %d" % idx)
	return true


func test_wander_pick_top_k_single_positive_returns_its_index() -> bool:
	# Arrange: only index 2 is viable.
	var pool: Array[Dictionary] = [{"score": 0.0}, {"score": 0.0}, {"score": 0.7}]
	# Act
	var idx: int = AgentWander.pick_top_k(_seeded(7), pool, 3)
	# Assert
	if idx != 2:
		return _fail("sole positive candidate must win, got %d" % idx)
	return true


func test_wander_pick_top_k_k1_always_returns_argmax() -> bool:
	# Arrange: index 1 has the strictly highest score.
	var pool: Array[Dictionary] = [{"score": 0.4}, {"score": 3.0}, {"score": 1.1}]
	# Act / Assert: with k=1 the roulette degenerates to argmax on
	# every seed.
	for seed_val: int in range(20):
		var idx: int = AgentWander.pick_top_k(_seeded(seed_val), pool, 1)
		if idx != 1:
			return _fail("k=1 must be argmax (index 1), got %d at seed %d" % [idx, seed_val])
	return true


func test_wander_pick_top_k_never_picks_outside_top_k() -> bool:
	# Arrange: indices 1 and 3 are the top-2; 0 and 2 must never win.
	var pool: Array[Dictionary] = [
		{"score": 0.1}, {"score": 5.0}, {"score": 0.2}, {"score": 4.0},
	]
	# Act / Assert
	for seed_val: int in range(50):
		var idx: int = AgentWander.pick_top_k(_seeded(seed_val), pool, 2)
		if idx != 1 and idx != 3:
			return _fail("k=2 pick escaped the top-2, got %d at seed %d" % [idx, seed_val])
	return true


# ── sample_dwell ──────────────────────────────────────────────────────────

func test_wander_sample_dwell_stays_within_bounds() -> bool:
	# Arrange
	var rng: RandomNumberGenerator = _seeded(42)
	# Act / Assert: the log-normal tail must always clamp into
	# [min, max] regardless of the gaussian draw.
	for i: int in range(200):
		var dwell: float = AgentWander.sample_dwell(rng, 1.6, 0.6, 0.6, 8.0)
		if dwell < 0.6 or dwell > 8.0:
			return _fail("dwell %f escaped [0.6, 8.0] at draw %d" % [dwell, i])
	return true


func test_wander_sample_dwell_zero_sigma_returns_base() -> bool:
	# Arrange / Act: sigma 0 collapses the log-normal to its base.
	var dwell: float = AgentWander.sample_dwell(_seeded(3), 1.6, 0.0, 0.6, 8.0)
	# Assert
	if not is_equal_approx(dwell, 1.6):
		return _fail("zero sigma must return base 1.6, got %f" % dwell)
	return true


# ── perturb_heading ───────────────────────────────────────────────────────

func test_wander_perturb_heading_stays_within_turn_max() -> bool:
	# Arrange
	var rng: RandomNumberGenerator = _seeded(11)
	var turn_max: float = PI / 3.0
	# Act / Assert
	for i: int in range(100):
		var heading: float = AgentWander.perturb_heading(rng, 1.0, turn_max)
		if absf(heading - 1.0) > turn_max + 0.0001:
			return _fail("perturbation %f exceeded ±%f at draw %d" % [heading - 1.0, turn_max, i])
	return true


# ── pick_band_distance ────────────────────────────────────────────────────

func test_wander_pick_band_distance_zero_weights_returns_zero() -> bool:
	# Arrange
	var distances: Dictionary = {"short": [40.0, 120.0]}
	var weights: Dictionary = {"short": 0.0}
	# Act
	var dist: float = AgentWander.pick_band_distance(_seeded(5), distances, weights)
	# Assert
	if dist != 0.0:
		return _fail("all-zero weights must return 0.0, got %f" % dist)
	return true


func test_wander_pick_band_distance_stays_within_declared_bands() -> bool:
	# Arrange
	var distances: Dictionary = {
		"short": [40.0, 120.0], "medium": [120.0, 320.0], "long": [320.0, 600.0],
	}
	var weights: Dictionary = {"short": 0.1, "medium": 0.6, "long": 0.3}
	var rng: RandomNumberGenerator = _seeded(99)
	# Act / Assert: every draw must land inside the union of the bands.
	for i: int in range(200):
		var dist: float = AgentWander.pick_band_distance(rng, distances, weights)
		if dist < 40.0 or dist > 600.0:
			return _fail("distance %f escaped all bands at draw %d" % [dist, i])
	return true


func test_wander_pick_band_distance_never_picks_zero_weight_band() -> bool:
	# Arrange: only "medium" carries weight; short/long must never win,
	# even on the randf() == 0.0 edge.
	var distances: Dictionary = {
		"short": [1.0, 2.0], "medium": [120.0, 320.0], "long": [900.0, 950.0],
	}
	var weights: Dictionary = {"short": 0.0, "medium": 1.0, "long": 0.0}
	var rng: RandomNumberGenerator = _seeded(17)
	# Act / Assert
	for i: int in range(200):
		var dist: float = AgentWander.pick_band_distance(rng, distances, weights)
		if dist < 120.0 or dist > 320.0:
			return _fail("zero-weight band was picked (%f) at draw %d" % [dist, i])
	return true
