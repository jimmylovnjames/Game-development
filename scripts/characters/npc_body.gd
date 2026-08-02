class_name NpcBody
extends CharacterBody3D
## Lightweight locomotion for NPCs and enemies.
##
## Shares the same CharacterBody3D contract as the player so ComicVisual can
## read velocity for walk poses. Optional idle wander keeps the street alive.

@export var walk_speed: float = 1.8
@export var wander: bool = false
@export var wander_radius: float = 5.0
@export var wander_pause: float = 2.5

var _gravity: float = 9.8
var _home: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3.ZERO
var _pause_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_home = global_position
	_rng.randomize()
	_pick_target()
	_pause_left = _rng.randf_range(0.5, wander_pause)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if wander:
		_wander(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)

	move_and_slide()


func _wander(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		return

	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.6:
		_pause_left = _rng.randf_range(wander_pause * 0.5, wander_pause * 1.5)
		_pick_target()
		return

	var dir := to_target.normalized()
	velocity.x = dir.x * walk_speed
	velocity.z = dir.z * walk_speed
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 6.0 * delta)


func _pick_target() -> void:
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(wander_radius * 0.3, wander_radius)
	_target = _home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
