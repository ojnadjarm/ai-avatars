extends Node2D
## Deterministic HUD showcase: `-- --state dialogue|hud|settings|log|group|quit|call|meeting [--tab N] [--world ID] [--banner SECONDS]`.

const WORLD_SCENE := preload("res://scenes/world.tscn")
const SETTINGS_SCENE := preload("res://scenes/settings_screen.tscn")
const MinimapScript := preload("res://scripts/hud/minimap.gd")
const WORLD_JSON := "res://assets/worlds/%s/world.json"
const SETTLE_FRAMES := 8
const PLAYER_LINE := "Luna, the old lanterns by the bridge went dark again. Did you see who passed?"
const LUNA_REPLY := "I saw a fox with a moth-light tied to its tail slip under the bridge at dusk. The lanterns dimmed one by one as it passed, as if they bowed to it. Follow the glow and you may find where the light went."
const GROUP_LINES := [
	["player", "You", "We need the moonstone before the river rises.", "user"],
	["luna", "Luna", "The stone hums under the old oak. I can hear it from here.", "agent"],
	["grok", "Grok", "Then we dig. I will carry the lantern, you two watch the water.", "agent"],
]
const LOG_LINES := [
	["Luna arrived in Magic Forest.", "event"],
	["DarkSaddler studies the mossy shrine.", "thought"],
	["Grok: \"The bridge planks are loose here.\"", "dialogue"],
	["Luna feels curious.", "emotion"],
	["DarkSaddler lifts the silver key.", "action"],
	["The glowing ring wakes with a low chime.", "solve"],
]

var state := "hud"
var world: Node


func _ready() -> void:
	state = _arg("--state", "hud")
	if state == "settings":
		var screen := SETTINGS_SCENE.instantiate()
		add_child(screen)
		screen.select_tab(int(_arg("--tab", "0")))
		return
	WorldBuilder.offline = true
	world = WORLD_SCENE.instantiate()
	world.room_config_path = WORLD_JSON % _arg("--world", "magic_forest")
	add_child(world)
	for i in SETTLE_FRAMES:
		await get_tree().physics_frame
	_stage()


func _stage() -> void:
	var player: Node2D = world.player
	_place_agents(player.global_position)
	match state:
		"dialogue":
			world.dialogue.show_input("luna", "Luna")
			world.dialogue.conversation_history.append({"speaker": "You", "text": PLAYER_LINE, "is_player": true})
			world.dialogue.show_response("Luna", LUNA_REPLY)
			world.dialogue.set_mood("curious")
		"group":
			world.dialogue.show_meeting([{"id": "luna", "name": "Luna"}, {"id": "grok", "name": "Grok"}, {"id": "darksaddler", "name": "DarkSaddler"}])
			for l: Array in GROUP_LINES:
				world.dialogue.append_meeting_line(l[0], l[1], l[2], l[3])
		"hud":
			_fill_log()
			world.narration_log.set_open(true)
			var grok: Node = world.find_agent("grok")
			if grok:
				grok.show_thought("The bridge looks weaker than yesterday.")
			_freeze_banner(player.global_position)
		"log":
			_fill_log()
			world.narration_log.set_open(true)
			var lines: Array[String] = []
			for i in 3:
				lines.append_array(world.narration_log.entries)
			LogModal.show_entries(world, Strings.get_string("log_modal.title_world"), lines)
		"quit":
			world.menu_builder.show_quit_confirm()
		"call":
			world.menu_builder.show_call_picker()
		"meeting":
			world.menu_builder.show_meeting_picker()


## Freezes every agent near the player so each run frames the same scene.
func _place_agents(p: Vector2) -> void:
	var spots := {"luna": Vector2(22, -4), "grok": Vector2(-70, -30), "darksaddler": Vector2(-40, 40)}
	for agent: Node in world.agents_container.get_children():
		agent.set_physics_process(false)
		if agent is CharacterBody2D:
			(agent as CharacterBody2D).velocity = Vector2.ZERO
		var id := String(agent.get("agent_id"))
		agent.global_position = p + spots.get(id, Vector2(60, 20))


func _fill_log() -> void:
	for l: Array in LOG_LINES:
		world.narration_log.add_entry(l[0], l[1])


## Holds the zone banner mid-slide on the zone under the player.
func _freeze_banner(p: Vector2) -> void:
	var zname := ""
	for z: Dictionary in MinimapScript.read_zones(world._world_scene):
		if (z["rect"] as Rect2).has_point(p):
			zname = z["name"]
	if zname == "":
		return
	world.zone_banner.set_process(false)
	world.zone_banner.present(zname, float(_arg("--banner", str(world.zone_banner.SLIDE * 0.5))))


func _arg(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with(key + "="):
			return args[i].trim_prefix(key + "=")
	return fallback
