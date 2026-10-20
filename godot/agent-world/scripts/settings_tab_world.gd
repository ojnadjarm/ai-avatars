class_name SettingsTabWorld
extends RefCounted
## World behavior settings tab — single global activity cooldown (one timer
## throttles both observations and encounters for every agent) plus the
## gateway health check interval.

var world_behavior_fields: Dictionary = {}


func build(parent: VBoxContainer) -> void:
	parent.add_child(SettingsForm.section_header("settings.world_behavior"))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", SettingsForm.ROW_SEP)

	var global_val: float = GameState.get_float("activity_global_cooldown", 30.0)
	world_behavior_fields["global_cooldown"] = SettingsForm.number_row(vbox, "settings.activity_global_cooldown", global_val)

	var health_val: float = GameState.get_float("gateway_health_interval_seconds", 60.0)
	world_behavior_fields["gateway_health_interval"] = SettingsForm.number_row(vbox, "settings.gateway_health_interval", health_val)

	vbox.add_child(SettingsForm.hint(Strings.get_string("settings.world_behavior_hint")))

	parent.add_child(vbox)


func commit(defaults: Dictionary) -> void:
	"""Mutates the passed defaults dict with the world-behavior values."""
	defaults["activity_global_cooldown"] = SettingsForm.parse_float(world_behavior_fields["global_cooldown"], 30.0)
	defaults["gateway_health_interval_seconds"] = SettingsForm.parse_float(world_behavior_fields["gateway_health_interval"], 60.0)
