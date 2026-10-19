class_name ActivityGate
extends RefCounted
## Single global cooldown timer shared across every agent. The only valid
## actions (Observation and Encounter) may trigger when remaining == 0.
## Each trigger resets remaining to cooldown_time. Tick from
## world_loader._process.

var cooldown_time: float = 30.0
var remaining: float = 0.0


func tick(delta: float) -> void:
	if remaining > 0.0:
		remaining -= delta


func can_trigger() -> bool:
	return remaining <= 0.0


func trigger() -> void:
	remaining = cooldown_time


## Seed the cooldown to an explicit value without going through trigger().
## Used by world_loader at startup to enforce a grace period before any
## autonomous activity fires. Values <= 0 leave the gate immediately open.
func set_initial_delay(seconds: float) -> void:
	remaining = maxf(seconds, 0.0)
