extends Node
## Autoload singleton — config hub for the game.
## Loads game_config.json, exposes content folder paths, persists user settings.
## Built-in content (res://assets/) always loads. External content folder adds more.

var room_config_path: String = ""

# Loaded from game_config.json
var config: Dictionary = {}
var defaults: Dictionary = {}
var agents: Dictionary = {}

# User settings (persisted to user://settings.json)
var content_folder: String = ""
var characters_folder: String = ""
var player_sprite: String = "player_default.png"
var agent_sprites: Dictionary = {}  # {agent_id: "filename.png"} overrides
var gateways: Dictionary = {}       # {id: {type, endpoint, api_key, model}}

const SETTINGS_PATH := "user://settings.json"
const CONFIG_FILE := "game_config.json"
const BUILTIN_CHARACTERS := "res://assets/characters/"


func _ready() -> void:
	_load_settings()
	_load_config()
	UITheme.apply_default_theme()


# ── Config Loading ──


func _load_config() -> void:
	var paths := ["user://" + CONFIG_FILE, "res://" + CONFIG_FILE]
	for p in paths:
		var path: String = p
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if not file:
			continue
		var data = JSON.parse_string(file.get_as_text())
		if data and data is Dictionary:
			config = data
			defaults = config.get("defaults", {})
			agents = config.get("agents", {})
			# Load gateway defaults from config (without API keys)
			var config_backends: Dictionary = config.get("backends", {})
			for gw_id in config_backends:
				var gw_cfg: Dictionary = config_backends[gw_id]
				if not gateways.has(gw_id):
					gateways[gw_id] = {
						"type": gw_cfg.get("type", "openai"),
						"endpoint": gw_cfg.get("endpoint", ""),
						"api_key": "",
						"model": gw_cfg.get("model", ""),
					}
			print("[config] Loaded from %s (%d agents, %d gateways)" % [path, agents.size(), gateways.size()])
			return
	push_warning("[config] No game_config.json found")


# ── Settings Persistence ──


func _load_settings() -> void:
	var data := load_json(SETTINGS_PATH)
	if data.is_empty():
		return
	content_folder = data.get("content_folder", "")
	characters_folder = data.get("characters_folder", "")
	player_sprite = data.get("player_sprite", "player_default.png")
	agent_sprites = data.get("agent_sprites", {})
	gateways = data.get("gateways", {})
	print("[config] Settings loaded")


func save_settings() -> void:
	var data := {
		"content_folder": content_folder,
		"characters_folder": characters_folder,
		"player_sprite": player_sprite,
		"agent_sprites": agent_sprites,
		"gateways": gateways,
	}
	save_json(SETTINGS_PATH, data, "config")


func save_config_override() -> void:
	"""Save modified config to user://game_config.json (overrides bundled)."""
	var override: Dictionary = config.duplicate(true)
	# Merge agent sprite overrides
	for aid in agent_sprites:
		if override.get("agents", {}).has(aid):
			override["agents"][aid]["sprite"] = agent_sprites[aid]
	if save_json("user://" + CONFIG_FILE, override, "config"):
		print("[config] Config override saved to user://%s" % CONFIG_FILE)
	# Reload live state
	agents = override.get("agents", {})


func get_default(key: String, fallback = null):
	return defaults.get(key, fallback)


func get_float(key: String, fallback: float) -> float:
	return float(defaults.get(key, fallback))


func get_ui_float(key: String, fallback: float) -> float:
	"""Read a float from the defaults.ui subdict. Centralizes UI tuning
	(tween durations, typewriter speed, etc.) under one config block so
	palette/animation polish doesn't require touching code."""
	var ui_cfg: Dictionary = defaults.get("ui", {})
	return float(ui_cfg.get(key, fallback))


func get_range(key: String, fallback: Vector2) -> Vector2:
	var raw: Variant = defaults.get(key, null)
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return fallback


func str_safe(dict: Dictionary, key: String, fallback: String = "") -> String:
	"""Null-safe dictionary string accessor — returns `fallback` when the key
	is missing or its value is null. Used at spawn time to coalesce optional
	agent-info fields without scattering `if val == null` guards."""
	var val: Variant = dict.get(key, fallback)
	if val == null:
		return fallback
	return str(val)


# ── JSON I/O helpers ──
# Centralizes the FileAccess + JSON.parse_string + null-check boilerplate used
# in 6+ load sites and 5+ save sites. Pass a non-empty `log_label` to surface
# missing-file / bad-JSON warnings; pass "" for silent best-effort loads
# (settings, agent memory) where absence is expected on first run.

func load_json(path: String, log_label: String = "") -> Dictionary:
	if not FileAccess.file_exists(path):
		if log_label != "":
			push_warning("[%s] File not found: %s" % [log_label, path])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		if log_label != "":
			push_warning("[%s] Cannot open: %s" % [log_label, path])
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data == null or not (data is Dictionary):
		if log_label != "":
			push_warning("[%s] Invalid JSON in: %s" % [log_label, path])
		return {}
	return data


func save_json(path: String, data: Dictionary, log_label: String = "") -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		if log_label != "":
			push_error("[%s] Cannot write: %s" % [log_label, path])
		return false
	file.store_string(JSON.stringify(data, "  "))
	return true


# ── Character Directories ──


func get_all_character_dirs() -> Array:
	"""Built-in characters + every external source that's configured.
	characters_folder and content_folder/characters are additive."""
	var dirs: Array = [BUILTIN_CHARACTERS]
	if characters_folder != "" and DirAccess.dir_exists_absolute(characters_folder):
		dirs.append(_ensure_trailing_slash(characters_folder))
	if content_folder != "":
		var ext: String = _ensure_trailing_slash(content_folder + "/characters")
		if DirAccess.dir_exists_absolute(ext):
			dirs.append(ext)
	return dirs


func scan_available_sprites() -> Array:
	"""Scan all character directories for spritesheets.
	Returns [{name, filename, path, is_builtin}] sorted by name."""
	var sprites: Array = []
	var seen: Dictionary = {}
	for dp in get_all_character_dirs():
		var dir_path: String = dp
		var is_builtin: bool = dir_path.begins_with("res://")
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") and not file_name.ends_with("_portrait.png"):
				var display := file_name.get_basename()
				if not seen.has(display):
					seen[display] = true
					sprites.append({
						"name": display,
						"filename": file_name,
						"path": dir_path + file_name,
						"is_builtin": is_builtin,
					})
			file_name = dir.get_next()
	sprites.sort_custom(func(a, b): return a["name"] < b["name"])
	return sprites


# ── Agent Sprites ──


func get_agent_sprite(agent_id: String) -> String:
	"""Get sprite filename for an agent. Returns override or default."""
	if agent_sprites.has(agent_id):
		return agent_sprites[agent_id]
	# Check if agent config has a sprite field
	var agent_cfg: Dictionary = agents.get(agent_id, {})
	var cfg_sprite = agent_cfg.get("sprite", "")
	if cfg_sprite != "":
		return cfg_sprite
	return "%s.png" % agent_id


func get_player_sprite_path() -> String:
	"""Resolve the player sprite path from settings."""
	return resolve_character_asset(player_sprite)


# ── Gateways ──


func get_gateway(gateway_id: String) -> Dictionary:
	"""Get gateway config by ID. Returns empty dict if not found."""
	return gateways.get(gateway_id, {})


func get_agent_gateway(agent_id: String) -> String:
	"""Get the gateway ID assigned to an agent."""
	var agent_cfg: Dictionary = agents.get(agent_id, {})
	var backend: String = agent_cfg.get("backend", "")
	if backend != "" and gateways.has(backend):
		return backend
	# Fallback: return first gateway
	if not gateways.is_empty():
		return gateways.keys()[0]
	return ""


func get_agent_session(agent_id: String) -> String:
	var agent_cfg: Dictionary = agents.get(agent_id, {})
	return agent_cfg.get("session_id", "")


func get_agent_model(agent_id: String) -> String:
	var agent_cfg: Dictionary = agents.get(agent_id, {})
	return agent_cfg.get("model", "")


## True only when BOTH the per-agent config flag ("mcp": true on this
## agent's entry in agents{}) AND the master switch (defaults.mcp.enabled)
## are on — see migration step B4, cozy-plotting-dusk.md Part B
## "Coexistence" bullet. Callers (llm_client per-agent timeout,
## prompt_builder's observe-only action-tag gate, llm_coordinator's
## <action>-tag discard) use this as the single source of truth for which
## transport an agent's world-actions arrive on. Empty-safe: a missing
## agent, a missing/false "mcp" flag, or a missing/non-Dictionary
## defaults.mcp block (an older user://game_config.json override predating
## this feature) all resolve to false — fail toward the XML path, never
## silently switch transports.
func is_agent_mcp(agent_id: String) -> bool:
	var agent_cfg: Dictionary = agents.get(agent_id, {})
	if not bool(agent_cfg.get("mcp", false)):
		return false
	var mcp_raw: Variant = defaults.get("mcp", null)
	if not (mcp_raw is Dictionary):
		return false
	return bool((mcp_raw as Dictionary).get("enabled", false))


func get_gateway_names() -> Array:
	"""List all configured gateway names."""
	return gateways.keys()


# ── Texture Loading ──


## Process-lifetime texture cache. PNG decoding via Image.load() is
## synchronous main-thread I/O — 5-20ms per call on WSL2. Without caching,
## every agent spawn re-decodes its spritesheet on every world entry,
## producing felt stutter at scene transitions. Cache is keyed by path;
## same path always returns the same ImageTexture instance. Cleared only
## when the process exits.
static var _texture_cache: Dictionary = {}


func load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		var cached: Texture2D = _texture_cache[path]
		if is_instance_valid(cached):
			return cached
		_texture_cache.erase(path)
	var tex: Texture2D = null
	if path.begins_with("res://"):
		tex = load(path) as Texture2D
	else:
		var img := Image.new()
		if img.load(path) != OK:
			push_warning("[config] Cannot load texture: %s" % path)
			return null
		tex = ImageTexture.create_from_image(img)
	if tex:
		_texture_cache[path] = tex
	return tex


func load_audio(path: String) -> AudioStream:
	if path == "" or not path.begins_with("res://"):
		return null
	return load(path) as AudioStream


# ── Portrait Loading ──


func load_portrait_texture(sprite_path: String) -> Texture2D:
	"""Resolve a character sprite path to a portrait texture. Prefers a
	sibling _portrait.png if one exists, otherwise extracts the front-facing
	idle frame from the spritesheet. Returns null if neither is available."""
	if sprite_path == "":
		return null
	var portrait_path: String = sprite_path.replace(".png", "_portrait.png")
	if FileAccess.file_exists(portrait_path):
		var tex: Texture2D = load_texture(portrait_path)
		if tex:
			return tex
	if not FileAccess.file_exists(sprite_path):
		return null
	var full: Texture2D = load_texture(sprite_path)
	if not full:
		return null
	# Row 2 = facing down (front view), col 0 = idle pose
	var atlas := AtlasTexture.new()
	atlas.atlas = full
	var fw: int = full.get_width() / 3
	var fh: int = full.get_height() / 4
	atlas.region = Rect2(0, 2 * fh, fw, fh)
	return atlas


func load_agent_portrait_texture(agent_id: String) -> Texture2D:
	"""Convenience: agent_id → resolved sprite path → portrait texture."""
	if agent_id == "":
		return null
	var sprite_file: String = get_agent_sprite(agent_id)
	return load_portrait_texture(resolve_character_asset(sprite_file))


static func make_portrait_rect(tex: Texture2D, size: Vector2) -> TextureRect:
	"""Wrap a texture in a fixed-size TextureRect used by portrait cells."""
	var r := TextureRect.new()
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture = tex
	return r


func load_portrait_for_sprite(sprite_info: Dictionary, size: Vector2 = Vector2(64, 64)) -> TextureRect:
	"""Create a TextureRect showing the portrait for a sprite info dict."""
	return make_portrait_rect(load_portrait_texture(sprite_info.get("path", "")), size)


# ── Path Resolution ──


func resolve_character_asset(filename: String) -> String:
	"""Resolve a character asset. Check external folders first, fallback to built-in."""
	if characters_folder != "":
		var ext_path: String = characters_folder + "/" + filename
		if FileAccess.file_exists(ext_path):
			return ext_path
	if content_folder != "":
		var ext_path: String = content_folder + "/characters/" + filename
		if FileAccess.file_exists(ext_path):
			return ext_path
	return BUILTIN_CHARACTERS + filename


static func _ensure_trailing_slash(path: String) -> String:
	if path.ends_with("/"):
		return path
	return path + "/"
