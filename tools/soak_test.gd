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
## Long enough for a hold-then-move cycle to come round on the slowest gait —
## the vendor's hold tops out at 6.5 s, so anything under ~9 s can miss a step
## it did not actually fail to take.
const WANDER_FRAMES := 660
const GATE_REACH_FRAMES := 24
const GATE_RAY_DEADLINE := 90
const GATE_FRAMES := 220
## Index 1 of the gate's three outcomes: sell the pass. Chosen for the test
## because reaching it needs the menu to actually navigate, not just confirm.
const GATE_CHOICE_INDEX := 1
## Long enough that a press always straddles at least one idle frame, since the
## menu polls in _process while the test drives from _physics_process.
const TAP_HOLD_FRAMES := 4

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
		10:
			if _stage_frame == 2:
				_begin_ambience_check()
			if _stage_frame >= 130:
				_finish_ambience_check()
		11:
			if _stage_frame == 2:
				_begin_comic_fx_check()
			if _stage_frame >= 130:
				_finish_comic_fx_check()
		12:
			_finish_gossip_check()
		13:
			if _stage_frame == 2:
				_begin_rig_check()
			if _stage_frame >= 95:
				_finish_rig_check()
				_next_stage()
		14:
			if _stage_frame == 2:
				_begin_wander_check()
			if _stage_frame >= WANDER_FRAMES:
				_finish_wander_check()
				_next_stage()
		15:
			if _stage_frame == 2:
				_begin_gate()
			elif not _gate_opened and _stage_frame > GATE_REACH_FRAMES:
				_try_gate_ray()
			elif _gate_opened:
				_drive_gate_dialogue()
			if _stage_frame >= GATE_FRAMES:
				_finish_gate()
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
	_next_stage()


func _find_shell(persona_id: StringName) -> PersonaShell:
	for shell in get_nodes_in_group("persona_shells"):
		var persona := shell as PersonaShell
		if persona != null and persona.profile != null \
				and persona.profile.persona_id == persona_id:
			return persona
	return null


var _storm: StormDirector = null
var _ambience: AmbienceDirector = null
var _comic_fx: ComicFX = null
var _burst_label: Label3D = null
var _burst_spawned: bool = false


func _begin_ambience_check() -> void:
	print("[stage 10: ambience]")
	_ambience = _scene.get_node_or_null("AmbienceDirector") as AmbienceDirector
	_storm = _scene.get_node_or_null("StormDirector") as StormDirector
	if _ambience == null or _storm == null:
		_fail("AmbienceDirector or StormDirector missing")
		return
	var streams_ok := true
	for player_name in ["Rain", "Drone", "Thunder"]:
		var player := _ambience.get_node_or_null(player_name) as AudioStreamPlayer
		if player == null or player.stream == null:
			streams_ok = false
	if streams_ok:
		_ok("rain/drone/thunder streams generated")
	else:
		_fail("an ambience stream failed to generate")
	_storm.force_strike(1.2)


func _finish_ambience_check() -> void:
	if _ambience == null:
		return
	if _ambience.thunder_plays >= 1:
		_ok("thunder chased the forced lightning strike")
	else:
		_fail("thunder never followed the forced strike")
	_next_stage()


func _begin_comic_fx_check() -> void:
	print("[stage 11: comic fx]")
	_comic_fx = _scene.get_node_or_null("ComicFX") as ComicFX
	if _comic_fx == null:
		_fail("ComicFX missing from the scene")
		return
	_burst_label = _comic_fx.burst("THOK", Vector3(4.5, 1.6, -3.0), "impact")
	_burst_spawned = _burst_label != null
	_comic_fx.panel_flash(Color(1, 1, 1), 0.2, 0.1)


func _finish_comic_fx_check() -> void:
	if _comic_fx == null:
		return
	if not _burst_spawned:
		_fail("burst() returned no label")
	elif _burst_label != null and _burst_label.is_inside_tree():
		# 130 frames at 60 Hz outlives lifetime + fade, so it should be gone.
		_fail("onomatopoeia label outlived its panel")
	else:
		_ok("onomatopoeia bursts spawn, hold, and fade")
	_next_stage()


func _finish_gossip_check() -> void:
	print("[stage 12: gossip]")
	var gossip := _scene.get_node_or_null("GossipNetwork") as GossipNetwork
	var marrow := _find_shell(&"marrow_scrap")
	var amp := _find_shell(&"sister_amp")
	var kip := _find_shell(&"kip_dockrat")
	if gossip == null or marrow == null:
		_fail("GossipNetwork or shells missing")
		return

	marrow.answer_about(&"syndicate")
	var spread := gossip.force_spread_all()
	if spread < 1:
		_fail("nothing entered circulation after marrow talked")
		return
	var heard := ""
	for shell: PersonaShell in [amp, kip, marrow]:
		if shell == null or shell._hearsay.is_empty():
			continue
		heard = shell._hearsay[0]
		break
	if heard.is_empty():
		_fail("hearsay never reached another persona")
	else:
		_ok("rumor traveled: \"%s\"" % heard.left(56))
	_next_stage()


var _rig_marrow: PersonaShell = null
var _rig_marrow_start_yaw: float = 0.0


func _begin_rig_check() -> void:
	print("[stage 13: character rigs]")
	var rig_failures := 0
	for entry: Dictionary in [
		{"name": "player", "rig": _player.get_node_or_null("Mesh/Rig")},
		{"name": "vex", "rig": (_scene.get_node_or_null("World/NpcVex") as NpcVex).get_rig()},
		{"name": "marrow", "rig": _find_shell(&"marrow_scrap").get_rig()},
		{"name": "amp", "rig": _find_shell(&"sister_amp").get_rig()},
		{"name": "kip", "rig": _find_shell(&"kip_dockrat").get_rig()},
		{"name": "bram", "rig": _find_shell(&"warden_bram").get_rig()},
	]:
		var rig: Node3D = entry["rig"]
		if rig == null:
			_fail("%s has no character rig" % entry["name"])
			rig_failures += 1
			continue
		var head := rig.get_node_or_null("Head")
		if head == null:
			_fail("%s rig has no head" % entry["name"])
			rig_failures += 1
		elif rig.get_child_count() < 12:
			_fail("%s rig is too simple (%d parts)" % [entry["name"], rig.get_child_count()])
			rig_failures += 1
	if rig_failures == 0:
		_ok("six rigs assembled with heads, eyes, and costume parts")

	# Put the courier in front of Marrow and give the shell time to turn.
	_rig_marrow = _find_shell(&"marrow_scrap")
	if _rig_marrow != null:
		_rig_marrow_start_yaw = _rig_marrow.rotation.y
		_player.global_position = Vector3(7.5, 0.1, 6.5)
		_player.velocity = Vector3.ZERO


func _finish_rig_check() -> void:
	if _rig_marrow == null:
		return
	var target_yaw := CharacterBuilder.yaw_toward(
		_rig_marrow.global_position, _player.global_position
	)
	var diff := absf(wrapf(_rig_marrow.rotation.y - target_yaw, -PI, PI))
	if diff > 0.5:
		_fail("marrow never turned to face the courier (off by %.2f rad)" % diff)
	else:
		_ok("shells turn to face the courier (%.2f rad off target)" % diff)


var _wander_start: Dictionary = {}  # persona_id -> Vector3
var _wander_yaw_start: Dictionary = {}  # persona_id -> float


## Wander is only observable when the courier is out of the face-player radius,
## so park the player far away and let the plaza get on with itself.
func _begin_wander_check() -> void:
	print("[stage 14: wander + MQ01 consequence]")
	_player.global_position = Vector3(0.0, 0.1, 26.0)
	_player.velocity = Vector3.ZERO
	for persona_id: StringName in [&"marrow_scrap", &"sister_amp", &"kip_dockrat", &"warden_bram"]:
		var shell := _find_shell(persona_id)
		if shell != null:
			_wander_start[persona_id] = shell.global_position
			_wander_yaw_start[persona_id] = shell.rotation.y


func _finish_wander_check() -> void:
	# Every shell except the watching warden should have shifted its feet.
	var moved := 0
	var expected := 0
	var strayed := false
	for persona_id: StringName in [&"marrow_scrap", &"sister_amp", &"kip_dockrat"]:
		var shell := _find_shell(persona_id)
		if shell == null or not _wander_start.has(persona_id):
			continue
		var start: Vector3 = _wander_start[persona_id]
		var travelled := shell.global_position - start
		travelled.y = 0.0
		expected += 1
		if travelled.length() > 0.15:
			moved += 1
		else:
			# Named, not counted: a silent 2/3 hides a whole archetype whose
			# gait never drives the body at all.
			_fail("%s (%s) never moved in %d frames" % [
				persona_id, shell.profile.rig_archetype, WANDER_FRAMES,
			])
		# A wander that drifts is a wander that empties the plaza overnight.
		var gait := CharacterBuilder.gait_for(shell.profile.rig_archetype)
		if shell.global_position.distance_to(start) > float(gait["radius"]) * 2.5 + 1.0:
			strayed = true
			_fail("%s wandered %.1f m from where it started" % [
				persona_id, shell.global_position.distance_to(start),
			])

	if moved == expected and expected > 0:
		_ok("all %d wandering archetypes ran a cycle" % expected)
	if not strayed:
		_ok("shells stayed tethered to their pitch")

	# Breathe must survive the gait: apply_idle writes scale.y every frame.
	var amp := _find_shell(&"sister_amp")
	if amp != null and amp.get_rig() != null:
		var scale_y := amp.get_rig().scale.y
		if absf(scale_y - 1.0) > 0.0001 and absf(scale_y - 1.0) < 0.05:
			_ok("breathe still driving rig scale (%.4f)" % scale_y)
		else:
			_fail("breathe not applied to rig scale (scale.y=%.4f)" % scale_y)

	# The consequence: taking Vex's pass in stage 8 put the warden on watch.
	var bram := _find_shell(&"warden_bram")
	if bram == null:
		_fail("warden bram missing")
		return
	if not bram.is_watching():
		_fail("bram did not react to talk_to_vex")
		return
	_ok("bram broke patrol after talk_to_vex")

	var bram_drift := bram.global_position - Vector3(_wander_start.get(&"warden_bram", bram.global_position))
	bram_drift.y = 0.0
	if bram_drift.length() > 0.2:
		_fail("watching warden kept moving (%.2f m)" % bram_drift.length())
	else:
		_ok("watching warden holds station")

	var want_yaw := CharacterBuilder.yaw_toward(bram.global_position, _player.global_position)
	var off := absf(wrapf(bram.rotation.y - want_yaw, -PI, PI))
	# The player is ~35 m away — far outside the 6.5 m face radius, so this only
	# passes if watching genuinely ignores the radius.
	if off > 0.4:
		_fail("watching warden is not tracking the courier (off by %.2f rad)" % off)
	else:
		_ok("watching warden tracks the courier across the plaza (%.2f rad off)" % off)


var _gate: SpineGate = null
var _gate_ray_ok: bool = false
var _gate_opened: bool = false
var _gate_moves_done: int = 0
var _gate_committed: bool = false
var _held_action: String = ""
var _held_frames: int = 0
var _gate_outcome: StringName = &""


## MQ01 end to end: walk into the gate volume, read the reader, and take one of
## the three branches. Before the gate existed the quest could not be finished
## at all, so this stage is the one that proves the first beat has an ending.
func _begin_gate() -> void:
	print("[stage 15: spine gate + MQ01 outcome]")
	_gate = _scene.get_node_or_null("World/SpineGate") as SpineGate
	if _gate == null:
		_fail("SpineGate missing from the world")
		return
	# Stand inside the reach volume, facing the console.
	# Close enough that the ray, which starts at the camera behind the player,
	# still reaches the console face 0.55 m inside the gate origin.
	_player.global_position = _gate.global_position + Vector3(0.0, 0.2, 1.5)
	_player.velocity = Vector3.ZERO
	if _player is PlayerController:
		(_player as PlayerController).set_look_angles(0.0, -0.1)
		(_player as PlayerController).camera_distance = 1.0


## Poll for the ray rather than sampling one exact frame: the spring arm is
## still easing to its new length for the first frames after the teleport, so a
## single-frame check races the camera and reports a miss that is not real.
func _try_gate_ray() -> void:
	if _gate == null:
		return

	var target: Node3D = null
	if _player.has_method("get_current_interactable"):
		target = _player.get_current_interactable() as Node3D

	if target == _gate:
		_gate_ray_ok = true
	elif _stage_frame < GATE_RAY_DEADLINE:
		return

	if _gate.has_been_reached():
		_ok("walking into the gate volume fired reach_spine_gate")
	else:
		_fail("gate reach trigger never fired")

	if _quests != null and _quests.is_objective_done(
		&"mq01_the_transit_pass", &"reach_spine_gate"
	):
		_ok("reach_spine_gate objective completed")
	else:
		_fail("reach_spine_gate objective did not complete")

	if _gate_ray_ok:
		_ok("InteractRay locked onto the gate console after %d frames" % _stage_frame)
	else:
		_fail("InteractRay never found the gate console within %d frames" % GATE_RAY_DEADLINE)

	_gate.interact(_player)
	_gate_opened = true


## Read through the lines, then walk the menu down to the chosen branch and
## commit — all through the same actions a player presses.
##
## Uses an explicit press/release state rather than a global frame phase. Phase
## arithmetic silently assumes every sub-state is entered on the press half of
## the cycle; enter one on the release half and it "releases" a key it never
## pressed, then marks the step done.
func _drive_gate_dialogue() -> void:
	if _dialogue == null or _gate == null or _gate_committed:
		return

	if not _dialogue.is_choosing():
		_tap("interact")
		return

	if _dialogue.get_selected_index() != GATE_CHOICE_INDEX:
		_tap("move_back")
		return

	if _held_action == "move_back":
		Input.action_release("move_back")
		_held_action = ""
		_held_frames = 0
		return

	if _tap("interact"):
		_gate_committed = true


## Hold an action for a few frames, then let go. Returns true on the frame the
## key is released, which is the frame the menu has actually seen the press.
func _tap(action: String) -> bool:
	if _held_action != action:
		if not _held_action.is_empty():
			Input.action_release(_held_action)
		_held_action = action
		_held_frames = 0
		Input.action_press(action)
		return false

	_held_frames += 1
	if _held_frames < TAP_HOLD_FRAMES:
		return false

	Input.action_release(action)
	_held_action = ""
	_held_frames = 0
	return true


func _finish_gate() -> void:
	if not _held_action.is_empty():
		Input.action_release(_held_action)
		_held_action = ""
	Input.action_release("interact")
	Input.action_release("move_back")
	if _gate == null:
		return

	if not _gate_opened:
		_fail("gate dialogue never opened")
		return

	if not _gate.is_resolved():
		# Report the menu state instead of just "did not commit" — the useful
		# question is always whether it never opened, never moved, or never
		# confirmed.
		print("        dialogue active=%s choosing=%s pending=%s selected=%d/%d moves=%d" % [
			str(_dialogue.is_active()), str(_dialogue.is_choosing()),
			str(_dialogue.has_pending_choices()),
			_dialogue.get_selected_index(), _dialogue.get_choice_count(),
			_gate_moves_done,
		])

	if _gate.is_resolved():
		_ok("gate resolved MQ01 through the choice menu")
	else:
		_fail("gate dialogue never reached a committed choice")
		return

	if _quests == null:
		_fail("QuestSystem missing")
		return
	if not _quests.is_quest_completed(&"mq01_the_transit_pass"):
		_fail("MQ01 is still active after the gate resolved")
		return
	_gate_outcome = _quests.get_outcome(&"mq01_the_transit_pass")
	_ok("MQ01 completed on outcome \'%s\'" % _gate_outcome)

	# The chosen branch, not just any branch: a menu that ignores navigation
	# and always commits the first entry would pass a weaker check.
	if _gate_outcome != SpineGate.OUTCOME_SELL:
		_fail("expected outcome \'%s\' at menu index %d, got \'%s\'" % [
			SpineGate.OUTCOME_SELL, GATE_CHOICE_INDEX, _gate_outcome,
		])

	var flags := _scene.get_node_or_null("WorldFlags") as WorldFlags
	if flags != null and flags.has_flag(_gate_outcome):
		_ok("outcome flag \'%s\' set on the world" % _gate_outcome)
	else:
		_fail("outcome flag was not set")

	# The quest resolving has to leave a mark in the world, not only the log.
	var caption := _gate.get_node_or_null("Arch/SignText") as Label3D
	if caption != null and caption.text != "SPINE LINE — PASS ONLY":
		_ok("gate signage changed to \'%s\'" % caption.text)
	else:
		_fail("gate signage did not change after the outcome")


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
