class_name GameRoot
extends Node3D
## Entry point for the playable scene.
##
## Owns nothing gameplay-critical on purpose: it wires the player to the debug
## overlay, handles quit, and prints a one-shot boot report that headless CI can
## assert against.

@export var print_boot_report: bool = true

@onready var _player: PlayerController = $Player
@onready var _blockout: DistrictBlockout = $World/Blockout
@onready var _debug_label: Label = $DebugHUD/DebugLabel
@onready var _touch: TouchControls = $TouchControls

var _debug_visible: bool = true


func _ready() -> void:
	_player.global_position = _blockout.get_spawn_point()
	_player.interactable_changed.connect(_on_interactable_changed)
	_player.landed.connect(_on_landed)
	_touch.look_delta.connect(_on_touch_look)
	_apply_mobile_visuals()

	if print_boot_report:
		# Deferred so the blockout has finished spawning before we count nodes.
		call_deferred("_print_boot_report")


func _print_boot_report() -> void:
	var viewport := get_viewport()
	print("=== NeonWastesRPG boot report ===")
	print("  engine        : %s" % Engine.get_version_info().get("string", "unknown"))
	print("  renderer      : %s" % ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "?"
	))
	print("  headless      : %s" % str(DisplayServer.get_name() == "headless"))
	print("  main scene    : %s" % scene_file_path)
	print("  player at     : %s" % str(_player.global_position))
	print("  spawned nodes : %d under World" % _count_descendants($World))
	print("  viewport size : %s" % str(viewport.get_visible_rect().size))
	print("  feature mobile: %s" % str(OS.has_feature("mobile")))
	print("  touch HUD     : %s" % str(_touch.visible))
	print("================================")


func _count_descendants(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		total += 1 + _count_descendants(child)
	return total


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible


func _process(_delta: float) -> void:
	if not _debug_visible or not _debug_label.visible:
		return
	var interactable := _player.get_current_interactable()
	_debug_label.text = "\n".join([
		"NeonWastesRPG — blockout",
		"fps      %d" % Engine.get_frames_per_second(),
		"pos      %.1f, %.1f, %.1f" % [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z,
		],
		"speed    %.1f m/s" % Vector2(_player.velocity.x, _player.velocity.z).length(),
		"grounded %s" % str(_player.is_on_floor()),
		"target   %s" % ("—" if interactable == null else interactable.name),
		"",
		_control_hint(),
	])


func _control_hint() -> String:
	if _touch.visible:
		return "stick move · drag look · JUMP / SPRINT / USE / LIGHT / DUCK"
	return "WASD move · Shift sprint · Ctrl crouch · Space jump\nE interact · F flashlight · Esc release mouse · F3 hide"


func _on_interactable_changed(interactable: Node3D) -> void:
	_touch.set_interactable(interactable)
	if interactable != null:
		print("[GameRoot] interactable in range: %s" % interactable.name)


func _on_touch_look(relative: Vector2) -> void:
	_player.apply_look(relative, _player.touch_look_sensitivity)


func _apply_mobile_visuals() -> void:
	# Compatibility / mobile renderers skip volumetric fog and SSAO; leaving
	# them enabled just burns CPU on a phone for no on-screen result.
	if not OS.has_feature("mobile"):
		return
	var world_env := $WorldEnvironment as WorldEnvironment
	var env := world_env.environment
	if env != null:
		env.volumetric_fog_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.glow_intensity = 0.6
	var moon := $Moonlight as DirectionalLight3D
	if moon != null:
		moon.directional_shadow_max_distance = 70.0


func _on_landed(fall_speed: float) -> void:
	if fall_speed > 12.0:
		print("[GameRoot] hard landing at %.1f m/s" % fall_speed)
