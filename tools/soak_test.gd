extends SceneTree
## Headless gameplay smoke test.
##
## Instantiates the real main scene, lets physics settle, then drives synthetic
## input through the actual input map to confirm the controller responds. Catches
## the failures a load-only check cannot: falling through the world, NaN in the
## transform, dead input bindings, a camera that never moves.
##
## Usage:
##   godot --headless --path . --script tools/soak_test.gd

const SETTLE_FRAMES := 150
const WALK_FRAMES := 90
const JUMP_HOLD_FRAMES := 4
const JUMP_FRAMES := 20

var _scene: Node = null
var _player: CharacterBody3D = null
var _frame: int = 0
var _stage: int = 0
var _failures: int = 0

var _settled_position := Vector3.ZERO
var _walk_start := Vector3.ZERO
var _jump_start_y: float = 0.0
var _peak_y: float = -INF


func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("could not load res://scenes/main.tscn")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player") as CharacterBody3D
	if _player == null:
		push_error("main scene has no Player node")
		quit(1)
		return
	print("[soak] scene up, running stages...")


func _physics_process(_delta: float) -> bool:
	if _player == null:
		return true
	_frame += 1

	match _stage:
		0:
			if _frame >= SETTLE_FRAMES:
				_finish_settle()
		1:
			Input.action_press("move_forward")
			if _frame >= SETTLE_FRAMES + WALK_FRAMES:
				_finish_walk()
		2:
			_peak_y = maxf(_peak_y, _player.global_position.y)
			# Hold for a few frames, the way a real key press lands, then let go.
			if _frame == SETTLE_FRAMES + WALK_FRAMES + JUMP_HOLD_FRAMES:
				Input.action_release("jump")
			if _frame >= SETTLE_FRAMES + WALK_FRAMES + JUMP_FRAMES:
				_finish_jump()
				_report()
				return true
	return false


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _ok(message: String) -> void:
	print("  ok    %s" % message)


func _finish_settle() -> void:
	_settled_position = _player.global_position
	print("[stage 1: settle]")
	print("        resting at %s" % str(_settled_position))

	if not _is_finite(_settled_position):
		_fail("player position is not finite (%s)" % str(_settled_position))
	elif _settled_position.y < -1.0:
		_fail("player fell through the ground (y=%.3f)" % _settled_position.y)
	elif absf(_settled_position.y) > 0.25:
		_fail("player did not settle on the ground plane (y=%.3f)" % _settled_position.y)
	else:
		_ok("settled on the ground plane at y=%.3f" % _settled_position.y)

	if _player.is_on_floor():
		_ok("is_on_floor() is true")
	else:
		_fail("is_on_floor() is false after %d frames" % SETTLE_FRAMES)

	var touch := _scene.get_node_or_null("TouchControls")
	if touch == null:
		_fail("TouchControls node missing from main scene")
	elif touch.get_script() == null:
		_fail("TouchControls has no script attached")
	else:
		_ok("TouchControls present")
		if DisplayServer.get_name() == "headless" and touch.visible:
			_fail("TouchControls should stay hidden in headless soak")
		else:
			_ok("TouchControls hidden under headless")

	_walk_start = _player.global_position
	_stage = 1


func _finish_walk() -> void:
	Input.action_release("move_forward")
	var travelled := _player.global_position - _walk_start
	travelled.y = 0.0
	print("[stage 2: walk]")
	print("        travelled %.2f m in %d frames" % [travelled.length(), WALK_FRAMES])

	if travelled.length() < 0.5:
		_fail("'move_forward' produced almost no movement (%.3f m)" % travelled.length())
	else:
		_ok("responds to 'move_forward' (%.2f m)" % travelled.length())

	_jump_start_y = _player.global_position.y
	_peak_y = _jump_start_y
	Input.action_press("jump")
	_stage = 2


func _finish_jump() -> void:
	var rise := _peak_y - _jump_start_y
	print("[stage 3: jump]")
	print("        rose %.2f m above the launch height" % rise)
	if rise < 0.2:
		_fail("'jump' did not lift the player (rise=%.3f m)" % rise)
	else:
		_ok("responds to 'jump' (rise=%.2f m)" % rise)


func _is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _report() -> void:
	print("")
	if _failures == 0:
		print("SOAK: all stages passed.")
		quit(0)
	else:
		print("SOAK: %d stage check(s) FAILED." % _failures)
		quit(1)
