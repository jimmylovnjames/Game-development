class_name PlayerController
extends CharacterBody3D
## Third-person courier/merc controller for NeonWastesRPG.
##
## Deliberately kept to locomotion, camera and interaction probing. Combat,
## inventory and dialogue live in their own systems and talk to this node through
## signals rather than reaching into it — see CLAUDE.md, "Architecture".

signal interactable_changed(interactable: Node3D)
signal interacted(interactable: Node3D)
signal landed(fall_speed: float)

@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.0
## How fast horizontal velocity converges on the target. Higher is snappier.
@export var ground_acceleration: float = 12.0
@export var air_acceleration: float = 3.0
@export var jump_velocity: float = 5.0
## Grace period after walking off a ledge during which a jump still registers.
@export var coyote_time: float = 0.12
## A jump pressed this long before landing is queued rather than dropped.
@export var jump_buffer_time: float = 0.15

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var touch_look_sensitivity: float = 0.0032
## Radians per second at full right-stick deflection.
@export var joy_look_speed: float = 2.6
@export var min_pitch_deg: float = -70.0
@export var max_pitch_deg: float = 45.0
@export var camera_distance: float = 4.5
@export var camera_distance_aim: float = 2.0

@export_group("Interaction")
@export var interact_range: float = 3.0

@onready var _pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $Collision
@onready var _interact_ray: RayCast3D = $CameraPivot/SpringArm3D/Camera3D/InteractRay
@onready var _flashlight: SpotLight3D = $CameraPivot/Flashlight

var _gravity: float = 9.8
var _yaw: float = 0.0
var _pitch: float = -0.15
var _time_since_grounded: float = 0.0
var _time_since_jump_pressed: float = INF
var _was_on_floor: bool = true
var _current_interactable: Node3D = null
var _crouching: bool = false


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_interact_ray.target_position = Vector3(0.0, 0.0, -interact_range)
	_spring_arm.spring_length = camera_distance
	_yaw = rotation.y
	if _wants_mouse_capture():
		_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _is_mouse_captured():
		var motion := event as InputEventMouseMotion
		apply_look(motion.relative, mouse_sensitivity)

	if event.is_action_pressed("pause") and _wants_mouse_capture():
		_capture_mouse(not _is_mouse_captured())


func _physics_process(delta: float) -> void:
	# Jump / interact / flashlight are polled rather than read from
	# _unhandled_input so that anything driving the character through
	# Input.action_press() — automated tests, on-screen Android buttons,
	# replays, scripted cutscenes — moves it identically to a human at the
	# keyboard.
	if Input.is_action_just_pressed("jump"):
		_time_since_jump_pressed = 0.0
	_time_since_jump_pressed += delta
	_poll_interact()
	_poll_flashlight()
	_apply_look_stick(delta)
	_update_camera()
	_update_crouch()
	_apply_gravity(delta)
	_apply_jump()
	_apply_movement(delta)

	move_and_slide()

	_detect_landing()
	_update_interactable()


func _update_camera() -> void:
	_pivot.rotation.y = _yaw
	_pivot.rotation.x = _pitch
	var target_length := camera_distance_aim if Input.is_action_pressed("attack_secondary") else camera_distance
	_spring_arm.spring_length = lerpf(_spring_arm.spring_length, target_length, 0.2)


func _update_crouch() -> void:
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch == _crouching:
		return
	# Refuse to stand up under low cover rather than clipping through it.
	if not want_crouch and _is_blocked_overhead():
		return
	_crouching = want_crouch
	var capsule := _collision.shape as CapsuleShape3D
	if capsule != null:
		capsule.height = 1.0 if _crouching else 1.8
		_collision.position.y = capsule.height * 0.5
	_visual.scale.y = 0.55 if _crouching else 1.0
	_visual.position.y = -0.45 if _crouching else 0.0
	_pivot.position.y = 1.15 if _crouching else 1.65


func _is_blocked_overhead() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.9,
		global_position + Vector3.UP * 1.95,
	)
	query.exclude = [get_rid()]
	query.collision_mask = 1  # world
	return not space.intersect_ray(query).is_empty()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_time_since_grounded = 0.0
	else:
		_time_since_grounded += delta
		velocity.y -= _gravity * delta


func _apply_jump() -> void:
	var can_jump := _time_since_grounded <= coyote_time
	var wants_jump := _time_since_jump_pressed <= jump_buffer_time
	if can_jump and wants_jump:
		velocity.y = jump_velocity
		_time_since_jump_pressed = INF
		_time_since_grounded = INF


func _apply_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Movement is relative to where the camera is looking, not to the body.
	var basis_yaw := Basis(Vector3.UP, _yaw)
	var direction := (basis_yaw * Vector3(input.x, 0.0, input.y)).normalized()

	var speed := walk_speed
	if _crouching:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed

	var target := direction * speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, target.x, accel * delta * speed)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * speed)

	# Face the direction of travel; the camera yaw stays independent.
	if direction.length_squared() > 0.01:
		var desired_yaw := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, 12.0 * delta)


func _detect_landing() -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		landed.emit(absf(velocity.y))
	_was_on_floor = grounded


func _update_interactable() -> void:
	var found: Node3D = null
	if _interact_ray.is_colliding():
		var collider := _interact_ray.get_collider()
		if collider is Node3D and collider.has_method("interact"):
			found = collider

	if found != _current_interactable:
		_current_interactable = found
		interactable_changed.emit(found)


func apply_look(relative: Vector2, sensitivity: float = -1.0) -> void:
	var sens := mouse_sensitivity if sensitivity < 0.0 else sensitivity
	_yaw -= relative.x * sens
	_pitch = clampf(
		_pitch - relative.y * sens,
		deg_to_rad(min_pitch_deg),
		deg_to_rad(max_pitch_deg),
	)


func _apply_look_stick(delta: float) -> void:
	if not InputMap.has_action("look_left"):
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() < 0.0025:
		return
	_yaw -= look.x * joy_look_speed * delta
	_pitch = clampf(
		_pitch - look.y * joy_look_speed * delta,
		deg_to_rad(min_pitch_deg),
		deg_to_rad(max_pitch_deg),
	)


func _poll_interact() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	if _current_interactable == null:
		return
	interacted.emit(_current_interactable)
	if _current_interactable.has_method("interact"):
		_current_interactable.interact(self)


func _poll_flashlight() -> void:
	if Input.is_action_just_pressed("toggle_flashlight"):
		_flashlight.visible = not _flashlight.visible


func _wants_mouse_capture() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if OS.has_feature("mobile"):
		return false
	return true


func _capture_mouse(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Exposed for the debug overlay and for future save/load.
func get_camera() -> Camera3D:
	return _camera


func get_current_interactable() -> Node3D:
	return _current_interactable
