extends Node
## Autoload singleton — string externalization.
## Loads all UI text from strings.json so nothing is hardcoded in scripts.

var _strings: Dictionary = {}

const STRINGS_PATH := "res://strings.json"


func _ready() -> void:
	var data := GameState.load_json(STRINGS_PATH, "strings")
	if not data.is_empty():
		_strings = data
		print("[strings] Loaded %d strings" % _strings.size())


func get_string(key: String, replacements: Dictionary = {}) -> String:
	var text: String = _strings.get(key, key)
	for placeholder in replacements:
		text = text.replace("{%s}" % placeholder, str(replacements[placeholder]))
	return text
