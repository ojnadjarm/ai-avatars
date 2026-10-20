extends Node
## Gateway health monitor — periodically pings each unique configured gateway
## and exposes a coarse ok/fail/unknown state for UI indicators.
##
## - Pings the gateway's health endpoint (not an LLM call). Per-type defaults:
##   hermes   -> /health           (no auth, {"status":"ok"})
##   openclaw -> /v1/models        (OpenAI-compatible list, non-billable)
##   openai   -> /v1/models        (requires Authorization header)
##   anthropic -> none             (no public health endpoint → stays unknown)
##   Override per gateway by setting "health_path" in its config entry.
##   Set "health_path" to "" explicitly to disable pinging for that gateway.
##
## - Interval is `defaults.gateway_health_interval_seconds` (seconds). 0 disables.
## - HTTPRequest uses `use_threads=false` + short timeout to match the WSL2
##   rule in llm_client.gd (otherwise quitting can leave zombie processes).

signal health_changed(gateway_id: String, state: String)

const STATE_OK := "ok"
const STATE_FAIL := "fail"
const STATE_UNKNOWN := "unknown"

const DEFAULT_PATHS := {
	"hermes": "/health",
	"openclaw": "/v1/models",
	"openai": "/v1/models",
	"anthropic": "",
}

const PING_TIMEOUT := 5.0

var _status: Dictionary = {}       # gateway_id -> state string
var _in_flight: Dictionary = {}    # gateway_id -> HTTPRequest
var _accum: float = 0.0
var _interval: float = 60.0


func _ready() -> void:
	set_process(true)
	_refresh_interval()
	# Fire once on startup so the UI has something quickly.
	_tick_all.call_deferred()


func get_status(gateway_id: String) -> String:
	return _status.get(gateway_id, STATE_UNKNOWN)


func _refresh_interval() -> void:
	var v: float = float(GameState.get_default("gateway_health_interval_seconds", 60.0))
	_interval = maxf(0.0, v)


func _process(delta: float) -> void:
	if _interval <= 0.0:
		return
	_accum += delta
	if _accum >= _interval:
		_accum = 0.0
		_tick_all()


func _tick_all() -> void:
	_refresh_interval()
	if WorldBuilder.offline:
		return
	var gateways: Dictionary = GameState.gateways
	for gw_id in gateways.keys():
		_ping(String(gw_id), gateways[gw_id])


func _resolve_path(gw: Dictionary) -> String:
	if gw.has("health_path"):
		return String(gw["health_path"])
	var t: String = String(gw.get("type", "openai"))
	return String(DEFAULT_PATHS.get(t, ""))


func _set_state(gw_id: String, state: String) -> void:
	if _status.get(gw_id, "") == state:
		return
	_status[gw_id] = state
	health_changed.emit(gw_id, state)


func _ping(gw_id: String, gw: Dictionary) -> void:
	var endpoint: String = String(gw.get("endpoint", ""))
	var path: String = _resolve_path(gw)
	if endpoint == "" or path == "":
		_set_state(gw_id, STATE_UNKNOWN)
		return
	if _in_flight.has(gw_id):
		# Previous ping still outstanding — skip this tick.
		return

	var url: String = endpoint.rstrip("/") + path
	var headers: PackedStringArray = []
	var api_key: String = String(gw.get("api_key", ""))
	if api_key != "":
		# OpenAI-compatible gateways accept Bearer; harmless for hermes/openclaw.
		headers.append("Authorization: Bearer %s" % api_key)

	var http := HTTPRequest.new()
	http.use_threads = false
	http.timeout = PING_TIMEOUT
	add_child(http)
	_in_flight[gw_id] = http
	http.request_completed.connect(_on_ping_complete.bind(gw_id, http))
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_in_flight.erase(gw_id)
		http.queue_free()
		_set_state(gw_id, STATE_FAIL)


func _on_ping_complete(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, gw_id: String, http: HTTPRequest) -> void:
	_in_flight.erase(gw_id)
	if is_instance_valid(http):
		http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		_set_state(gw_id, STATE_FAIL)
		return
	# 2xx or 3xx → reachable. Anything else (404/5xx) → fail.
	if code >= 200 and code < 400:
		_set_state(gw_id, STATE_OK)
	else:
		_set_state(gw_id, STATE_FAIL)
