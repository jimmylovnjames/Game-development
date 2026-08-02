class_name SpineGate
extends Interactable
## The spine-line gate: MQ01's destination, and the only place the courier can
## actually spend Vex's pass.
##
## Everything before this is setup. The quest data has carried three outcomes
## since it was authored, but there was nowhere to choose between them, so the
## first story beat had no ending. This is that ending: a reader console that
## states the price of each branch and makes the player pick one.
##
## Per CLAUDE.md's tone rules there is no clean option here. Boarding puts the
## courier in someone's debt, selling strands them, and burning it closes the
## line for good. The costs are shown before the choice, not after.

const OUTCOME_BOARD := &"boarded_with_the_pass"
const OUTCOME_SELL := &"sold_the_pass_to_the_syndicate"
const OUTCOME_BURN := &"burned_the_pass"
const QUEST_ID := &"mq01_the_transit_pass"
const TRIGGER_ID := &"trigger_spine_gate"

const ACID_YELLOW := Color(0.969, 1.0, 0.235)
const NEON_CYAN := Color(0.0, 0.898, 1.0)
const NEON_MAGENTA := Color(1.0, 0.176, 0.584)

const NEON_SHADER := preload("res://shaders/neon_sign.gdshader")
const METAL_DARK := preload("res://assets/materials/toon_metal_dark.tres")
const CONCRETE := preload("res://assets/materials/toon_concrete.tres")

var _dialogue: DialogueUI = null
var _quests: QuestSystem = null
var _flags: WorldFlags = null
var _comic: ComicFX = null

var _reached: bool = false
var _resolved: bool = false
var _sign_material: ShaderMaterial = null
var _lamp: OmniLight3D = null


func _ready() -> void:
	super._ready()
	interactable_id = TRIGGER_ID
	prompt = "Use the pass reader"
	collision_layer = 1 | 16  # world | interactable
	collision_mask = 0
	add_to_group("spine_gate")
	_build()

	var trigger := get_node_or_null("ReachTrigger") as Area3D
	if trigger != null:
		trigger.body_entered.connect(_on_body_entered)


func bind(
	dialogue: DialogueUI, quests: QuestSystem, flags: WorldFlags, comic: ComicFX
) -> void:
	_dialogue = dialogue
	_quests = quests
	_flags = flags
	_comic = comic


## --- Geometry -------------------------------------------------------------

func _build() -> void:
	var arch := Node3D.new()
	arch.name = "Arch"
	add_child(arch)

	# Two pylons and a lintel: the silhouette has to read as a threshold from
	# the far end of the street, long before the sign is legible.
	for side in [-1.0, 1.0]:
		var pylon := MeshInstance3D.new()
		var pylon_mesh := BoxMesh.new()
		pylon_mesh.size = Vector3(1.4, 8.5, 1.4)
		pylon.mesh = pylon_mesh
		pylon.position = Vector3(side * 5.0, 4.25, 0.0)
		pylon.material_override = CONCRETE
		arch.add_child(pylon)

		var collider := StaticBody3D.new()
		collider.collision_layer = 1
		collider.collision_mask = 0
		collider.position = pylon.position
		arch.add_child(collider)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = pylon_mesh.size
		shape.shape = box
		collider.add_child(shape)

	var lintel := MeshInstance3D.new()
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(11.4, 1.6, 1.6)
	lintel.mesh = lintel_mesh
	lintel.position = Vector3(0.0, 9.0, 0.0)
	lintel.material_override = CONCRETE
	arch.add_child(lintel)

	# Acid yellow: quest-critical only, per the style bible. This is the one
	# place in the district it is allowed to dominate.
	_sign_material = ShaderMaterial.new()
	_sign_material.shader = NEON_SHADER
	_sign_material.set_shader_parameter("neon_color", ACID_YELLOW)
	_sign_material.set_shader_parameter("energy", 2.6)
	_sign_material.set_shader_parameter("flicker_amount", 0.14)
	_sign_material.set_shader_parameter("flicker_speed", 9.0)
	_sign_material.set_shader_parameter("dropout_chance", 0.05)
	_sign_material.set_shader_parameter("tube_color", Color(0.08, 0.08, 0.04))

	var bezel := MeshInstance3D.new()
	var bezel_mesh := BoxMesh.new()
	bezel_mesh.size = Vector3(7.4, 1.5, 0.2)
	bezel.mesh = bezel_mesh
	bezel.position = Vector3(0.0, 7.6, 0.62)
	bezel.material_override = METAL_DARK
	arch.add_child(bezel)

	var sign_panel := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(7.0, 1.1, 0.16)
	sign_panel.mesh = sign_mesh
	sign_panel.position = Vector3(0.0, 7.6, 0.76)
	sign_panel.material_override = _sign_material
	sign_panel.name = "SignPanel"
	arch.add_child(sign_panel)

	var caption := Label3D.new()
	caption.name = "SignText"
	caption.text = "SPINE LINE — PASS ONLY"
	caption.font_size = 64
	caption.pixel_size = 0.0075
	caption.outline_size = 14
	caption.modulate = Color(0.05, 0.04, 0.02)
	caption.outline_modulate = ACID_YELLOW
	caption.position = Vector3(0.0, 7.6, 0.9)
	arch.add_child(caption)

	# The reader console the courier actually presses E on. Chest height, not
	# knee height: a waist-high box sits under the interact ray of a player
	# looking straight ahead, so it reads as scenery you cannot touch.
	var console := MeshInstance3D.new()
	var console_mesh := BoxMesh.new()
	console_mesh.size = Vector3(0.9, 2.0, 0.7)
	console.mesh = console_mesh
	console.position = Vector3(0.0, 1.0, 0.0)
	console.material_override = METAL_DARK
	add_child(console)

	var reader := MeshInstance3D.new()
	var reader_mesh := BoxMesh.new()
	reader_mesh.size = Vector3(0.55, 0.3, 0.1)
	reader.mesh = reader_mesh
	reader.position = Vector3(0.0, 1.62, 0.4)
	reader.rotation.x = -0.35
	reader.material_override = _sign_material
	add_child(reader)

	_lamp = OmniLight3D.new()
	_lamp.name = "GateLamp"
	_lamp.position = Vector3(0.0, 3.0, 1.6)
	_lamp.light_color = ACID_YELLOW
	_lamp.light_energy = 3.0
	_lamp.omni_range = 16.0
	_lamp.omni_attenuation = 1.3
	_lamp.shadow_enabled = false
	add_child(_lamp)


## --- Quest ----------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if _reached or not body.is_in_group("player"):
		return
	_reached = true
	if _quests != null:
		_quests.notify_reached(TRIGGER_ID)
	if _comic != null:
		_comic.burst("THE GATE", global_position + Vector3(0.0, 6.0, 2.0), "storm", 2.2)
	print("[SpineGate] the courier reaches the spine line.")


func _on_interact(_who: Node3D) -> void:
	if _dialogue == null or _dialogue.is_active():
		return

	if _resolved:
		_dialogue.open(interactable_id, "Spine Gate", PackedStringArray([
			_epilogue_line(),
		]))
		_dialogue.set_speaker_color(ACID_YELLOW)
		return

	if not _dialogue.choice_made.is_connected(_on_choice_made):
		_dialogue.choice_made.connect(_on_choice_made)

	_dialogue.open_with_choices(
		interactable_id,
		"Spine Gate",
		PackedStringArray([
			"The reader wants the pass. Above it, a camera that has not been cleaned in a decade wants your face.",
			"There is a man at the barrier who has been watching you walk the whole length of the street. He has the patient look of somebody paid by the hour to wait.",
			"\"Sealed pass,\" he says. \"I can read the name on that. So can the people who bought it. Question is who gets to.\"",
		]),
		[
			{
				"id": OUTCOME_BOARD,
				"text": "Feed the pass to the reader and board.",
				"cost": "You go through. Whoever paid your debt now knows where you are, and they will come to collect in their own time.",
			},
			{
				"id": OUTCOME_SELL,
				"text": "Sell the pass to the man at the barrier.",
				"cost": "You eat tonight and for a month. You stay in the Lowspine, and the Lowspine watches you take the money.",
			},
			{
				"id": OUTCOME_BURN,
				"text": "Burn it in front of him.",
				"cost": "Nobody owns a piece of your morning. Nobody helps you either, and the spine line closes to you for good.",
			},
		]
	)
	_dialogue.set_speaker_color(ACID_YELLOW)


func _on_choice_made(speaker_id: StringName, choice_id: StringName) -> void:
	if speaker_id != interactable_id or _resolved:
		return
	_resolved = true
	prompt = "The gate has nothing left to say"

	if _quests != null:
		_quests.complete_quest(QUEST_ID, choice_id)
	if _flags != null:
		_flags.set_flag(choice_id, true)

	_apply_outcome(choice_id)
	print("[SpineGate] MQ01 resolved: %s" % choice_id)


## Every branch leaves the gate visibly different, so the choice is legible in
## the world afterwards and not only in the journal.
func _apply_outcome(choice_id: StringName) -> void:
	var caption := get_node_or_null("Arch/SignText") as Label3D
	match choice_id:
		OUTCOME_BOARD:
			_set_sign(NEON_CYAN, 3.0, 0.03)
			if caption != null:
				caption.text = "SPINE LINE — CLEARED"
				caption.outline_modulate = NEON_CYAN
			_burst("CLEARED", "cool")
		OUTCOME_SELL:
			_set_sign(NEON_MAGENTA, 2.2, 0.2)
			if caption != null:
				caption.text = "SPINE LINE — PASS VOID"
				caption.outline_modulate = NEON_MAGENTA
			_burst("SOLD", "impact")
		OUTCOME_BURN:
			# The gate goes dark. Nothing is coming back on.
			_set_sign(Color(0.35, 0.3, 0.22), 0.35, 0.0)
			if caption != null:
				caption.text = "SPINE LINE — NO ENTRY"
				caption.outline_modulate = Color(0.4, 0.35, 0.3)
			if _lamp != null:
				_lamp.light_energy = 0.5
				_lamp.light_color = Color(0.6, 0.45, 0.3)
			_burst("ASH", "storm")


func _set_sign(color: Color, energy: float, flicker: float) -> void:
	if _sign_material == null:
		return
	_sign_material.set_shader_parameter("neon_color", color)
	_sign_material.set_shader_parameter("energy", energy)
	_sign_material.set_shader_parameter("flicker_amount", flicker)
	_sign_material.set_shader_parameter("dropout_chance", 0.0)
	if _lamp != null and energy > 1.0:
		_lamp.light_color = color


func _burst(word: String, style: String) -> void:
	if _comic == null:
		return
	_comic.burst(word, global_position + Vector3(0.0, 5.0, 2.0), style, 2.6)


func _epilogue_line() -> String:
	if _flags == null:
		return "The reader is dark."
	if _flags.has_flag(OUTCOME_BOARD):
		return "The barrier is open. Somewhere down the line, somebody is expecting you."
	if _flags.has_flag(OUTCOME_SELL):
		return "The man is gone and so is the pass. Your pockets are heavier and the street knows it."
	if _flags.has_flag(OUTCOME_BURN):
		return "Ash on the reader plate. The gate does not open for you again."
	return "The reader is dark."


## Exposed for the soak test.
func is_resolved() -> bool:
	return _resolved


func has_been_reached() -> bool:
	return _reached
