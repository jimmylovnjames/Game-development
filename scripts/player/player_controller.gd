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
## Gravity multiplier on the way down. Falling slightly faster than rising is
## the single cheapest way to stop a jump feeling floaty.
@export var fall_gravity_multiplier: float = 1.55
## Releasing jump early scales velocity by this — a tap hops, a hold soars.
@export var jump_cut_multiplier: float = 0.45
@export var max_fall_speed: float = 26.0
## Grace period after walking off a ledge during which a jump still registers.
@export var coyote_time: float = 0.12
## A jump pressed this long before landing is queued rather than dropped.
@export var jump_buffer_time: float = 0.15

@export_group("Slopes")
## Snap distance that keeps the body glued over kerbs and rubble lips.
@export var snap_length: float = 0.35
## Steepest walkable slope in degrees.
@export var max_slope_deg: float = 50.0
## Above this angle the ground starts sliding the body downhill.
@export var slide_start_deg: float = 38.0
@export var slide_acceleration: float = 14.0

@export_group("Props")
## The body tries to drag shoved props toward this fraction of its own speed.
@export var push_speed_cap: float = 3.0
## Force ceiling (N) on the shove: cans reach the target in a frame or two and
## skitter off, crates grind against friction and never get there.
@export var push_max_force: float = 400.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_deg: float = -70.0
@export var max_pitch_deg: float = 45.0
@export var camera_distance: float = 4.5
@export var camera_distance_aim: float = 2.0

@export_group("Interaction")
@export var interact_range: float = 3.0

@onready var _pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _mesh: Node3D = $Mesh
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
	floor_snap_length = snap_length
	floor_max_angle = deg_to_rad(max_slope_deg)
	_yaw = rotation.y
	_mesh.add_child(CharacterBuilder.build(&"courier", 1.78, 1.0))
	_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _is_mouse_captured():
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(
			_pitch - motion.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg),
		)

	if event.is_action_pressed("pause"):
		_capture_mouse(not _is_mouse_captured())

	if event.is_action_pressed("toggle_flashlight"):
		_flashlight.visible = not _flashlight.visible


func _physics_process(delta: float) -> void:
	# Jump and interact are polled rather than read from _unhandled_input so that
	# anything driving the character through Input.action_press() — automated
	# tests, replays, scripted cutscenes, AI-controlled bodies — moves it
	# identically to a human at the keyboard.
	if Input.is_action_just_pressed("jump"):
		_time_since_jump_pressed = 0.0
	_time_since_jump_pressed += delta
	_update_camera()
	_update_crouch()
	_apply_gravity(delta)
	_apply_jump()
	_apply_jump_cut()
	_apply_movement(delta)
	_apply_slope_slide(delta)

	# Intent speed must be sampled before move_and_slide(): once the body is
	# blocked the slide projection zeroes velocity, and a push measured after
	# that would never fire.
	var intent_speed := Vector2(velocity.x, velocity.z).length()
	move_and_slide()

	_push_rigid_bodies(delta, intent_speed)
	_detect_landing()
	_update_interactable()
	_poll_interact()


func _poll_interact() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	if _current_interactable == null:
		return
	interacted.emit(_current_interactable)
	if _current_interactable.has_method("interact"):
		_current_interactable.interact(self)


func _update_camera() -> void:
	# The pivot is a child of the body, and _apply_movement turns the body to
	# face the direction of travel. Writing the pivot's *local* yaw therefore
	# adds the body's rotation on top of the camera's, so walking drags the view
	# around and the camera-relative movement basis stops agreeing with what is
	# actually on screen. Counter-rotate so the pivot's world yaw stays _yaw.
	_pivot.rotation.y = wrapf(_yaw - rotation.y, -PI, PI)
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
	_mesh.scale.y = 0.55 if _crouching else 1.0
	_pivot.position.y = 1.1 if _crouching else 1.6


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
		var gravity := _gravity
		if velocity.y < 0.0:
			gravity *= fall_gravity_multiplier
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)


func _apply_jump() -> void:
	var can_jump := _time_since_grounded <= coyote_time
	var wants_jump := _time_since_jump_pressed <= jump_buffer_time
	if can_jump and wants_jump:
		velocity.y = jump_velocity
		_time_since_jump_pressed = INF
		_time_since_grounded = INF


## Early release shortens the arc. Polled like the jump itself so replays and
## AI drivers get the same trajectory a human would.
func _apply_jump_cut() -> void:
	if Input.is_action_just_released("jump") and velocity.y > jump_velocity * jump_cut_multiplier:
		velocity.y *= jump_cut_multiplier


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


## Steep ground shoves the body downhill along the slope tangent. The effect
## ramps in gently so ordinary rooftops and kerbs stay walkable.
func _apply_slope_slide(delta: float) -> void:
	if not is_on_floor():
		return
	var normal := get_floor_normal()
	if normal.y <= 0.0:
		return
	var angle := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
	if angle <= slide_start_deg:
		return
	var steepness := inverse_lerp(slide_start_deg, max_slope_deg, angle)
	# Downhill is the floor normal with its up-component removed.
	var downhill := (Vector3(normal.x, 0.0, normal.z)).normalized()
	velocity += downhill * slide_acceleration * steepness * delta


## Walk into a rigid body and it goes. Each frame the shove closes part of the
## gap between the prop's speed and a fraction of the player's intent speed,
## capped by push_max_force — so a can jumps away in one contact while a crate
## accelerates slowly against ground friction.
func _push_rigid_bodies(delta: float, intent_speed: float) -> void:
	if intent_speed < 0.3:
		return
	var desired := minf(intent_speed * 0.8, push_speed_cap)
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null:
			continue
		var normal := collision.get_normal()
		if absf(normal.y) > 0.6:
			continue  # standing on it or hanging under it; leave it alone
		var deficit := desired + body.linear_velocity.dot(normal)
		if deficit <= 0.0:
			continue  # already outrunning the shove
		# Push level with the centre of mass: the crate slides instead of
		# somersaulting over the contact point. Cans still roll via the ground.
		var at := collision.get_position()
		at.y = body.global_position.y
		var impulse := -normal * minf(deficit * body.mass, push_max_force * delta)
		body.apply_impulse(impulse, at - body.global_position)


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


func _capture_mouse(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Exposed for the debug overlay and for future save/load.
func get_camera() -> Camera3D:
	return _camera


func get_current_interactable() -> Node3D:
	return _current_interactable


## Aim the camera. Used by soak tests and scripted look-ats.
func set_look_angles(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_update_camera()
