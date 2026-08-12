extends SceneTree
## Headless gameplay smoke test.
##
## Instantiates the real main scene, lets physics settle, then drives synthetic
## input through the actual input map to confirm the controller responds. Catches
## the failures a load-only check cannot: falling through the world, NaN in the
## transform, dead input bindings, a camera that never moves.
##
## The last stage teleports the player across the map to confirm the chunk
## streamer both builds ground ahead of them and lets go of what they left.
##
## Usage:
##   godot --headless --path . --script tools/soak_test.gd

const SETTLE_FRAMES := 150
const WALK_FRAMES := 90
const JUMP_HOLD_FRAMES := 4
const JUMP_FRAMES := 20
const STREAM_FRAMES := 60

## Far enough out that not one chunk of the spawn ring survives the move, and on
## an exact lot corner so the teleport lands in a junction rather than inside a
## tower. Odd parity, so the junction carries no street lamp either.
const FAR_LOT := Vector2i(18, -15)

var _scene: Node = null
var _player: CharacterBody3D = null
var _streamer: ChunkStreamer = null
var _frame: int = 0
var _stage: int = 0
var _failures: int = 0

var _settled_position := Vector3.ZERO
var _walk_start := Vector3.ZERO
var _jump_start_y: float = 0.0
var _peak_y: float = -INF

var _stream_start_frame: int = 0
var _home_coords: Array = []
var _far_position := Vector3.ZERO


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
				_begin_stream()
		3:
			if _frame >= _stream_start_frame + STREAM_FRAMES:
				_finish_stream()
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


func _begin_stream() -> void:
	_stage = 3
	_stream_start_frame = _frame

	_streamer = _scene.get_node_or_null("World/Streamer") as ChunkStreamer
	if _streamer == null:
		# get_node_or_null returning a node that fails the cast means the class
		# cache is stale — run `godot --headless --path . --import`.
		_fail("main scene has no ChunkStreamer at World/Streamer")
		return

	_home_coords = _streamer.loaded_coords().duplicate()
	_far_position = WorldGrid.lot_corner(FAR_LOT) + Vector3(0.0, 1.2, 0.0)

	# Warm up first, then teleport. The other order drops the player through a
	# world that has not been built yet, which is exactly the bug this catches.
	_streamer.warm_up_at(_far_position)
	_player.velocity = Vector3.ZERO
	_player.global_position = _far_position


func _finish_stream() -> void:
	print("[stage 4: streaming]")
	if _streamer == null:
		return

	var expected_centre := WorldGrid.world_to_chunk(_far_position)
	print("        home ring %d chunks, now centred on %s with %d loaded" % [
		_home_coords.size(), str(_streamer.current_centre()), _streamer.loaded_count(),
	])

	if _streamer.current_centre() == expected_centre:
		_ok("streamer followed the player to %s" % str(expected_centre))
	else:
		_fail("streamer centre is %s, expected %s" % [
			str(_streamer.current_centre()), str(expected_centre),
		])

	# Exact, because the teleport went through warm_up(): a full recentre drops
	# everything the hysteresis margin would otherwise still be holding.
	var ring := _streamer.load_ring_count()
	if _streamer.loaded_count() == ring:
		_ok("holds exactly the %d chunks of the load ring" % ring)
	else:
		_fail("holds %d chunks, expected the %d of the load ring" % [
			_streamer.loaded_count(), ring,
		])

	# The spawn ring was captured mid-walk, after the player crossed a seam, so
	# it carries the hysteresis margin. That margin is the whole reason walking
	# back and forth over a border does not rebuild a chunk every step — but it
	# has to stay bounded, or "streaming" is just a slow memory leak.
	var ceiling := _streamer.max_resident_count()
	if _home_coords.size() <= ceiling:
		_ok("spawn ring held %d chunks, inside the %d hysteresis ceiling" % [
			_home_coords.size(), ceiling,
		])
	else:
		_fail("spawn ring held %d chunks, over the %d hysteresis ceiling" % [
			_home_coords.size(), ceiling,
		])

	# The point of streaming is what is *not* resident.
	var stale := 0
	for coord: Vector2i in _home_coords:
		if _streamer.is_loaded(coord):
			stale += 1
	if stale == 0:
		_ok("released all %d chunks from the spawn ring" % _home_coords.size())
	else:
		_fail("%d chunk(s) from the spawn ring are still resident" % stale)

	# And that there is ground under the player when they get there.
	var y := _player.global_position.y
	if not _is_finite(_player.global_position):
		_fail("player position is not finite after the teleport")
	elif absf(y) > 0.25:
		_fail("no streamed ground under the player at %s (y=%.3f)" % [
			str(_streamer.current_centre()), y,
		])
	elif not _player.is_on_floor():
		_fail("player is not standing on the streamed ground")
	else:
		_ok("stands on streamed ground at y=%.3f" % y)


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
