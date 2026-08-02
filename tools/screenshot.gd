extends SceneTree
## Renders the main scene to a PNG. Used to review the art direction without a
## desktop — works over software Vulkan (lavapipe) inside Xvfb, just slowly.
##
## Usage:
##   xvfb-run -a godot --path . --resolution 1280x720 \
##       --script tools/screenshot.gd -- --out=/tmp/shot.png
##
## Optional user args (after the bare `--`):
##   --out=PATH        where to write the PNG            (default user://screenshot.png)
##   --frames=N        warm-up frames before grabbing    (default 90)
##   --cam=x,y,z       detached camera position; omit to follow the player
##   --look=x,y,z      point the detached camera at this (default 0,2,0)
##   --fov=DEG         detached camera FOV               (default 70)
##   --yaw=DEG         player-cam yaw   (ignored when --cam is set)
##   --pitch=DEG       player-cam pitch (ignored when --cam is set)
##   --dist=M          player-cam spring length          (default 7)
##   --hud=0           hide the debug overlay
##   --fog=0           disable both fog passes (isolate the shading)
##   --glow=0          disable the glow pass
##   --rain=0          hide the rain volume
##   --postfx=0        hide the post-process layer
##   --burst=WORD      letter a comic word over the plaza (held for the shot)
##   --exposure=F      multiply tonemap exposure

var _out_path := "user://screenshot.png"
var _warmup := 90
var _cam_pos := Vector3.INF
var _look_at := Vector3(0.0, 2.0, 0.0)
var _fov := 70.0
var _yaw_deg := 35.0
var _pitch_deg := -6.0
var _distance := 7.0
var _show_hud := true
var _fog := true
var _glow := true
var _rain := true
var _postfx := true
var _burst_word := ""
var _exposure := -1.0

var _frames := 0
var _scene: Node = null


func _initialize() -> void:
	_parse_args()

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("could not load res://scenes/main.tscn")
		quit(1)
		return

	_scene = packed.instantiate()
	root.add_child(_scene)
	call_deferred("_setup_shot")
	print("[screenshot] warming up %d frames -> %s" % [_warmup, _out_path])


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		var key := parts[0].lstrip("-")
		var value := parts[1]
		match key:
			"out": _out_path = value
			"frames": _warmup = int(value)
			"cam": _cam_pos = _parse_vec3(value)
			"look": _look_at = _parse_vec3(value)
			"fov": _fov = float(value)
			"yaw": _yaw_deg = float(value)
			"pitch": _pitch_deg = float(value)
			"dist": _distance = float(value)
			"hud": _show_hud = value != "0"
			"fog": _fog = value != "0"
			"glow": _glow = value != "0"
			"rain": _rain = value != "0"
			"postfx": _postfx = value != "0"
			"burst": _burst_word = value
			"exposure": _exposure = float(value)


func _parse_vec3(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() != 3:
		push_error("expected x,y,z but got '%s'" % text)
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _setup_shot() -> void:
	var hud := _scene.get_node_or_null("DebugHUD") as CanvasLayer
	if hud != null:
		hud.visible = _show_hud

	var rain := _scene.get_node_or_null("World/Rain")
	if rain != null:
		rain.visible = _rain

	var postfx := _scene.get_node_or_null("PostFX") as CanvasLayer
	if postfx != null:
		postfx.visible = _postfx

	_apply_environment_overrides()

	# The controller drives the pivot every physics frame, so freeze it and keep
	# whatever framing we asked for.
	var player := _scene.get_node_or_null("Player")
	if player != null:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.set_process(false)

	if _cam_pos.is_finite():
		_use_detached_camera()
	else:
		_use_player_camera()


func _apply_environment_overrides() -> void:
	var world_env := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment
	if not _fog:
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	if not _glow:
		env.glow_enabled = false
	if _exposure > 0.0:
		env.tonemap_exposure = _exposure


func _use_detached_camera() -> void:
	var camera := Camera3D.new()
	camera.fov = _fov
	camera.near = 0.1
	camera.far = 800.0
	_scene.add_child(camera)
	camera.global_position = _cam_pos
	# look_at fails when the camera sits exactly on its target.
	if _cam_pos.distance_to(_look_at) > 0.01:
		camera.look_at(_look_at, Vector3.UP)
	camera.make_current()
	print("[screenshot] detached camera at %s looking at %s" % [
		str(_cam_pos), str(_look_at),
	])


func _use_player_camera() -> void:
	var pivot := _scene.get_node_or_null("Player/CameraPivot") as Node3D
	var arm := _scene.get_node_or_null("Player/CameraPivot/SpringArm3D") as SpringArm3D
	if pivot != null:
		pivot.rotation = Vector3(deg_to_rad(_pitch_deg), deg_to_rad(_yaw_deg), 0.0)
	if arm != null:
		arm.spring_length = _distance


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == _warmup - 2 and not _burst_word.is_empty():
		var fx := _scene.get_node_or_null("ComicFX") as ComicFX
		if fx != null:
			fx.burst(_burst_word, Vector3(0.0, 4.5, -6.0), "storm", 120.0)
	if _frames < _warmup:
		return false

	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport texture was empty - is a rendering driver available?")
		quit(1)
		return true

	var err := image.save_png(_out_path)
	if err != OK:
		push_error("failed to write %s (error %d)" % [_out_path, err])
		quit(1)
		return true

	print("[screenshot] wrote %s (%dx%d)" % [
		_out_path, image.get_width(), image.get_height(),
	])
	quit(0)
	return true
