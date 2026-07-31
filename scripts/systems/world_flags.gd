class_name WorldFlags
extends Node
## StringName -> bool bag for quest prerequisites and world state.
##
## Explicit node under GameRoot rather than an autoload — see scripts/systems/
## README. Anything that needs flags takes a reference instead of reaching
## globally.

signal flag_changed(flag: StringName, value: bool)

var _flags: Dictionary = {}  # StringName -> bool


func set_flag(flag: StringName, value: bool = true) -> void:
	if _flags.get(flag, false) == value:
		return
	_flags[flag] = value
	flag_changed.emit(flag, value)


func has_flag(flag: StringName) -> bool:
	return bool(_flags.get(flag, false))


func get_all() -> Dictionary:
	return _flags.duplicate()
