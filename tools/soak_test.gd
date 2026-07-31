extends SceneTree
## Headless gameplay smoke test.
##
## Instantiates the real main scene, lets physics settle, then drives synthetic
## input through the actual input map to confirm the controller responds. Catches
## the failures a load-only check cannot: falling through the world, NaN in the
## transform, dead input bindings, a camera that never moves.
##
## Stages: settle, walk, tap jump vs held jump (variable height), rigid-prop
## drop-and-settle, and walking a crate across the street.
##
## Usage:
##   godot --headless --path . --script tools/soak_test.gd

const SETTLE_FRAMES := 150
const WALK_FRAMES := 90
const JUMP_HOLD_FRAMES := 4
const JUMP_FRAMES := 40
const HELD_JUMP_FRAMES := 45
const PROP_SETTLE_FRAMES := 150
const PUSH_FRAMES := 80
const TALK_AIM_FRAMES := 30
const DIALOGUE_LINES := 5
const DIALOGUE_ADVANCE_GAP := 8

var _scene: Node = null
var _player: CharacterBody3D = null
var _frame: int = 0
var _stage: int = 0
var _stage_frame: int = 0
var _failures: int = 0

var _walk_start := Vector3.ZERO
var _jump_start_y: float = 0.0
var _peak_y: float = -INF
var _tap_rise: float = 0.0

var _prop: RigidBody3D = null
var _prop_start := Vector3.ZERO
var _push_start := Vector3.ZERO
var _player_push_start := Vector3.ZERO
var _dialogue_advances: int = 0
var _quests: QuestSystem = null
var _dialogue: DialogueUI = null


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
	_quests = _scene.get_node_or_null("QuestSystem") as QuestSystem
	_dialogue = _scene.get_node_or_null("DialogueUI") as DialogueUI
	print("[soak] scene up, running stages...")


func _physics_process(_delta: float) -> bool:
	if _player == null:
		return true
	_frame += 1
	_stage_frame += 1

	match _stage:
		0:
			if _stage_frame >= SETTLE_FRAMES:
				_finish_settle()
		1:
			Input.action_press("move_forward")
			if _stage_frame >= WALK_FRAMES:
				_finish_walk()
		2:
			_peak_y = maxf(_peak_y, _player.global_position.y)
			if _stage_frame == JUMP_HOLD_FRAMES:
				Input.action_release("jump")
			if _stage_frame >= JUMP_FRAMES:
				_finish_tap_jump()
		3:
			# Wait for the tap arc to land before launching the held jump.
			if _player.is_on_floor():
				_begin_jump()
				_next_stage()
			elif _stage_frame > 90:
				_fail("player never landed after the tap jump")
				_begin_jump()
				_next_stage()
		4:
			_peak_y = maxf(_peak_y, _player.global_position.y)
			if _stage_frame >= HELD_JUMP_FRAMES:
				Input.action_release("jump")
				_finish_held_jump()
		5:
			if _stage_frame >= PROP_SETTLE_FRAMES:
				_finish_prop_drop()
		6:
			Input.action_press("move_forward")
			if _stage_frame >= PUSH_FRAMES:
				_finish_push()
		7:
			if _stage_frame >= TALK_AIM_FRAMES:
				_try_open_dialogue()
		8:
			if _stage_frame % DIALOGUE_ADVANCE_GAP == 0:
				Input.action_press("interact")
			elif _stage_frame % DIALOGUE_ADVANCE_GAP == 2:
				Input.action_release("interact")
				_dialogue_advances += 1
			if _dialogue_advances >= DIALOGUE_LINES + 1:
				_finish_talk()
		9:
			_finish_persona_checks()
			_report()
			return true
	return false


func _next_stage() -> void:
	_stage += 1
	_stage_frame = 0


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _ok(message: String) -> void:
	print("  ok    %s" % message)


func _finish_settle() -> void:
	var settled := _player.global_position
	print("[stage 1: settle]")
	print("        resting at %s" % str(settled))

	if not _is_finite(settled):
		_fail("player position is not finite (%s)" % str(settled))
	elif settled.y < -1.0:
		_fail("player fell through the ground (y=%.3f)" % settled.y)
	elif absf(settled.y) > 0.25:
		_fail("player did not settle on the ground plane (y=%.3f)" % settled.y)
	else:
		_ok("settled on the ground plane at y=%.3f" % settled.y)

	if _player.is_on_floor():
		_ok("is_on_floor() is true")
	else:
		_fail("is_on_floor() is false after %d frames" % SETTLE_FRAMES)

	_walk_start = _player.global_position
	_next_stage()


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

	_begin_jump()
	_next_stage()


func _finish_tap_jump() -> void:
	_tap_rise = _peak_y - _jump_start_y
	print("[stage 3: tap jump]")
	print("        rose %.2f m on a %d-frame press" % [_tap_rise, JUMP_HOLD_FRAMES])
	if _tap_rise < 0.15:
		_fail("tap 'jump' did not lift the player (rise=%.3f m)" % _tap_rise)
	else:
		_ok("responds to 'jump' (rise=%.2f m)" % _tap_rise)
	_next_stage()


func _finish_held_jump() -> void:
	var held_rise := _peak_y - _jump_start_y
	print("[stage 4: held jump]")
	print("        rose %.2f m holding jump (tap gave %.2f m)" % [held_rise, _tap_rise])

	if held_rise < 0.85:
		_fail("held jump only rose %.2f m, expected close to full height" % held_rise)
	elif held_rise < _tap_rise + 0.15:
		_fail(
			"held jump (%.2f m) barely beat the tap (%.2f m); " % [held_rise, _tap_rise]
			+ "variable jump height is not working"
		)
	else:
		_ok("variable jump height works (%.2f m vs %.2f m)" % [held_rise, _tap_rise])

	_begin_prop_drop()
	_next_stage()


func _finish_prop_drop() -> void:
	print("[stage 5: prop drop]")
	if _prop == null:
		_fail("no rigid prop available for the drop test")
		_begin_push()
		_next_stage()
		return

	var pos := _prop.global_position
	var speed := _prop.linear_velocity.length()
	print("        prop resting at %s, speed %.3f m/s" % [str(pos), speed])

	if not _is_finite(pos):
		_fail("prop position is not finite (%s)" % str(pos))
	elif pos.y < 0.05 or pos.y > 1.5:
		_fail("prop did not settle on the street (y=%.3f)" % pos.y)
	elif speed > 0.4:
		_fail("prop never came to rest (%.2f m/s after %d frames)" % [
			speed, PROP_SETTLE_FRAMES,
		])
	else:
		_ok("prop fell and settled (y=%.3f, %.3f m/s)" % [pos.y, speed])

	_begin_push()
	_next_stage()


func _finish_push() -> void:
	Input.action_release("move_forward")
	print("[stage 6: push]")
	if _prop == null:
		_fail("no rigid prop available for the push test")
		return

	var moved := _prop.global_position - _push_start
	moved.y = 0.0
	var walked := _player.global_position - _player_push_start
	walked.y = 0.0
	print("        crate displaced %.2f m, player advanced %.2f m" % [
		moved.length(), walked.length(),
	])

	if moved.length() < 0.4:
		_fail("walking into the crate barely moved it (%.3f m)" % moved.length())
	elif walked.length() < 0.8:
		_fail("player failed to advance through the crate (%.3f m)" % walked.length())
	else:
		_ok("player shoves rigid bodies (crate moved %.2f m)" % moved.length())

	_begin_talk()
	_next_stage()


func _begin_talk() -> void:
	Input.action_release("move_forward")
	# Close enough that a short spring still puts Vex inside the interact ray.
	if _player is PlayerController:
		(_player as PlayerController).set_look_angles(0.0, -0.12)
		(_player as PlayerController).camera_distance = 1.6
	_player.global_position = Vector3(4.5, 0.1, -2.7)
	_player.velocity = Vector3.ZERO
	_dialogue_advances = 0


func _try_open_dialogue() -> void:
	print("[stage 7: talk to Vex]")
	var target: Node3D = null
	if _player.has_method("get_current_interactable"):
		target = _player.get_current_interactable() as Node3D
	if target == null:
		_fail("InteractRay did not find NpcVex")
		_next_stage()
		_dialogue_advances = DIALOGUE_LINES + 1  # skip stage 8 waits
		return
	_ok("InteractRay locked onto %s" % target.name)
	Input.action_press("interact")
	_next_stage()
	# Release on the next physics frame via stage 8's gap logic.


func _finish_talk() -> void:
	Input.action_release("interact")
	print("[stage 8: dialogue]")
	_quests = _scene.get_node_or_null("QuestSystem") as QuestSystem
	_dialogue = _scene.get_node_or_null("DialogueUI") as DialogueUI
	if _dialogue != null and _dialogue.is_active():
		_fail("dialogue UI still open after advancing all lines")
	elif _quests == null:
		_fail("QuestSystem missing from the scene")
	elif not _quests.is_objective_done(&"mq01_the_transit_pass", &"talk_to_vex"):
		_fail("talk_to_vex objective was not completed")
	else:
		_ok("MQ01 talk_to_vex completed via dialogue")
	_next_stage()


## Kernel-level persona assertions: knowledge boundaries, forbidden-scope
## deflection, flag-gated reveals unlocked by the quest beat in stage 8, and
## the LLM backend's offline-by-default behaviour (no key in CI).
func _finish_persona_checks() -> void:
	print("[stage 9: persona shells]")
	var marrow := _find_shell(&"marrow_scrap")
	var amp := _find_shell(&"sister_amp")
	var bram := _find_shell(&"warden_bram")

	if marrow == null or amp == null or bram == null:
		_fail("expected persona shells missing from the district")
		return
	_ok("three persona shells present")

	if marrow.compose_lines().is_empty():
		_fail("marrow produced no kernel lines")
	else:
		_ok("marrow kernel composes lines")

	var forbidden := marrow.answer_about(&"pass_buyer")
	if not bool(forbidden.get("deflected", false)):
		_fail("marrow answered a forbidden scope instead of deflecting")
	else:
		_ok("marrow deflects pass_buyer: \"%s\"" % str(forbidden["text"]).left(42))

	var allowed := marrow.answer_about(&"scrap")
	if bool(allowed.get("deflected", true)):
		_fail("marrow deflected his own trade")
	else:
		_ok("marrow answers scrap within his knowledge")

	var bram_pass := bram.answer_about(&"pass")
	if not bool(bram_pass.get("deflected", false)):
		_fail("bram talked about passes; his forbidden scope failed")
	else:
		_ok("bram refuses the pass topic")

	var amp_pass := amp.answer_about(&"pass")
	if bool(amp_pass.get("deflected", true)):
		_fail("amp's flag-gated warning did not unlock after talk_to_vex")
	else:
		_ok("amp's gated knowledge unlocked via quest flag")

	var backend := _scene.get_node_or_null("NpcLlmBackend") as NpcLlmBackend
	if backend == null:
		_fail("NpcLlmBackend missing from the scene")
	elif backend.is_active():
		_fail("LLM backend active without a configured key in CI")
	else:
		_ok("LLM backend offline by default (kernel is the voice)")


func _find_shell(persona_id: StringName) -> PersonaShell:
	for shell in get_nodes_in_group("persona_shells"):
		var persona := shell as PersonaShell
		if persona != null and persona.profile != null \
				and persona.profile.persona_id == persona_id:
			return persona
	return null


func _begin_jump() -> void:
	_jump_start_y = _player.global_position.y
	_peak_y = _jump_start_y
	Input.action_press("jump")


## Take the first crate the blockout seeded and lift it over the plaza, which
## is guaranteed clear of buildings and lamps.
func _begin_prop_drop() -> void:
	for node in get_nodes_in_group("physics_props"):
		var body := node as RigidBody3D
		if body != null and body.mass > 5.0:
			_prop = body
			break
	if _prop == null:
		for node in get_nodes_in_group("physics_props"):
			_prop = node as RigidBody3D
			if _prop != null:
				break
	if _prop == null:
		return

	_prop.global_position = Vector3(6.0, 6.5, 4.0)
	_prop.linear_velocity = Vector3.ZERO
	_prop.angular_velocity = Vector3.ZERO
	_prop.sleeping = false
	_prop_start = _prop.global_position


## Line the player up behind the settled crate and walk into it.
func _begin_push() -> void:
	if _prop == null:
		return
	_push_start = _prop.global_position
	_player_push_start = _prop.global_position + Vector3(0.0, 0.1, 2.2)
	_player.global_position = _player_push_start
	_player.velocity = Vector3.ZERO


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
