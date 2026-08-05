class_name PassForger
extends Interactable
## MQ01's optional setpiece: someone who can crack a sealed transit pass
## without filing a report.
##
## The quest data has carried `read_the_pass` → `setpiece_pass_forger` since it
## was authored. Without this node the objective was a journal line with no
## destination. Reading the pass is optional on purpose — it does not unlock a
## fourth ending — but it changes the *price list* at the spine gate: once you
## know whose name is on the seal, every branch costs something more specific.

const QUEST_ID := &"mq01_the_transit_pass"
const OBJECTIVE_ID := &"read_the_pass"
const SETPIECE_ID := &"setpiece_pass_forger"
## The name under the seal. Gate dialogue and plaza knowledge both hang on it.
const BUYER_NAME := "Halcyon Collection"

const SODIUM_AMBER := Color(1.0, 0.68, 0.36)
const NEON_MAGENTA := Color(1.0, 0.176, 0.584)
const NEON_CYAN := Color(0.0, 0.898, 1.0)

const METAL_DARK := preload("res://assets/materials/toon_metal_dark.tres")
const CONCRETE := preload("res://assets/materials/toon_concrete.tres")
const NEON_SHADER := preload("res://shaders/neon_sign.gdshader")

var _dialogue: DialogueUI = null
var _quests: QuestSystem = null
var _flags: WorldFlags = null
var _comic: ComicFX = null

var _read: bool = false
var _sign_material: ShaderMaterial = null


func _ready() -> void:
	super._ready()
	interactable_id = SETPIECE_ID
	prompt = "Ask about the seal"
	collision_layer = 1 | 16  # world | interactable
	collision_mask = 0
	add_to_group("pass_forger")
	_build()


func bind(
	dialogue: DialogueUI, quests: QuestSystem, flags: WorldFlags, comic: ComicFX
) -> void:
	_dialogue = dialogue
	_quests = quests
	_flags = flags
	_comic = comic


## --- Geometry -------------------------------------------------------------

func _build() -> void:
	# A lean-to stall tucked off the street — silhouette has to read as a
	# destination from the kerb, not as more street furniture.
	var stall := Node3D.new()
	stall.name = "Stall"
	add_child(stall)

	var counter := MeshInstance3D.new()
	var counter_mesh := BoxMesh.new()
	counter_mesh.size = Vector3(2.4, 1.05, 0.9)
	counter.mesh = counter_mesh
	counter.position = Vector3(0.0, 0.525, 0.15)
	counter.material_override = METAL_DARK
	stall.add_child(counter)

	var backboard := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(2.6, 2.2, 0.18)
	backboard.mesh = board_mesh
	backboard.position = Vector3(0.0, 1.7, -0.45)
	backboard.material_override = CONCRETE
	stall.add_child(backboard)

	var awning := MeshInstance3D.new()
	var awning_mesh := BoxMesh.new()
	awning_mesh.size = Vector3(2.8, 0.08, 1.6)
	awning.mesh = awning_mesh
	awning.position = Vector3(0.0, 2.85, 0.2)
	awning.rotation.x = -0.18
	awning.material_override = METAL_DARK
	stall.add_child(awning)

	_sign_material = ShaderMaterial.new()
	_sign_material.shader = NEON_SHADER
	_sign_material.set_shader_parameter("neon_color", SODIUM_AMBER)
	_sign_material.set_shader_parameter("energy", 2.2)
	_sign_material.set_shader_parameter("flicker_amount", 0.18)
	_sign_material.set_shader_parameter("flicker_speed", 7.0)
	_sign_material.set_shader_parameter("dropout_chance", 0.08)
	_sign_material.set_shader_parameter("tube_color", Color(0.08, 0.05, 0.02))

	var fascia := MeshInstance3D.new()
	var fascia_mesh := BoxMesh.new()
	fascia_mesh.size = Vector3(2.2, 0.45, 0.12)
	fascia.mesh = fascia_mesh
	fascia.position = Vector3(0.0, 2.55, 0.35)
	fascia.material_override = _sign_material
	fascia.name = "Fascia"
	stall.add_child(fascia)

	var caption := Label3D.new()
	caption.name = "SignText"
	caption.text = "SEALS · NAMES · NO RECEIPTS"
	caption.font_size = 48
	caption.pixel_size = 0.0065
	caption.outline_size = 12
	caption.modulate = Color(0.05, 0.03, 0.01)
	caption.outline_modulate = SODIUM_AMBER
	caption.position = Vector3(0.0, 2.55, 0.48)
	stall.add_child(caption)

	var lamp := OmniLight3D.new()
	lamp.name = "StallLamp"
	lamp.position = Vector3(0.0, 2.4, 0.9)
	lamp.light_color = SODIUM_AMBER
	lamp.light_energy = 2.4
	lamp.omni_range = 9.0
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	add_child(lamp)

	# The forger herself — vendor silhouette, magenta trim so she reads as
	# Ferrum-adjacent rather than another scrap stall.
	var palette := PackedColorArray([
		Color(0.12, 0.11, 0.16),
		NEON_MAGENTA,
		Color(0.7, 0.62, 0.72),
		NEON_MAGENTA,
	])
	var rig: Node3D = CharacterBuilder.build(&"vendor", 1.68, 1.05, palette)
	rig.position = Vector3(0.0, 0.0, -0.85)
	rig.name = "ForgerRig"
	add_child(rig)

	var nameplate := Label3D.new()
	nameplate.name = "Nameplate"
	nameplate.text = "Nix"
	nameplate.font_size = 40
	nameplate.pixel_size = 0.007
	nameplate.outline_size = 10
	nameplate.modulate = NEON_MAGENTA
	nameplate.outline_modulate = Color(0.031, 0.02, 0.059)
	nameplate.position = Vector3(0.0, 2.05, -0.85)
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(nameplate)


## --- Quest ----------------------------------------------------------------

func _on_interact(_who: Node3D) -> void:
	if _dialogue == null or _dialogue.is_active():
		return

	if _read:
		_dialogue.open(interactable_id, "Nix", PackedStringArray([
			"You already know the name. Knowing twice does not make it cheaper.",
		]))
		_dialogue.set_speaker_color(SODIUM_AMBER)
		return

	# Gate the reveal on having the pass at all — talk_to_vex is the moment
	# Vex hands it over. Without that flag this is just a forger's stall.
	if _flags == null or not _flags.has_flag(&"talk_to_vex"):
		_dialogue.open(interactable_id, "Nix", PackedStringArray([
			"Seals, names, no receipts. Come back when you have something sealed.",
			"I do not do curiosity. Curiosity leaves a trail.",
		]))
		_dialogue.set_speaker_color(SODIUM_AMBER)
		return

	if not _dialogue.finished.is_connected(_on_dialogue_finished):
		_dialogue.finished.connect(_on_dialogue_finished)

	_dialogue.open(
		interactable_id,
		"Nix",
		PackedStringArray([
			"Hand it over. Flat on the glass. I do not touch what I have not been paid to.",
			"Chip is clean. Seal is clean. The name underneath is not yours.",
			"%s bought your morning. Collections arm of Ferrum Halo — they buy debts the towers want forgotten, then they collect in person." % BUYER_NAME,
			"You can board and owe them a face. You can sell and hope the Syndicate already knows. Or you can burn it and make an enemy that keeps ledgers.",
			"I was never here. The seal looks unread. That is what you paid for.",
		])
	)
	_dialogue.set_speaker_color(SODIUM_AMBER)


func _on_dialogue_finished(speaker_id: StringName) -> void:
	if speaker_id != interactable_id or _read:
		return
	_read = true
	prompt = "The seal has been read"

	if _quests != null:
		_quests.notify_custom(SETPIECE_ID)
	# Explicit flag as well as the objective-id convention — plaza knowledge
	# and the gate both look for this by name.
	if _flags != null:
		_flags.set_flag(OBJECTIVE_ID, true)
		_flags.set_flag(&"knows_pass_buyer", true)

	if _sign_material != null:
		_sign_material.set_shader_parameter("neon_color", NEON_CYAN)
		_sign_material.set_shader_parameter("energy", 1.6)
		_sign_material.set_shader_parameter("flicker_amount", 0.05)
	var caption := get_node_or_null("Stall/SignText") as Label3D
	if caption != null:
		caption.text = "CLOSED — ASK ELSEWHERE"
		caption.outline_modulate = NEON_CYAN

	if _comic != null:
		_comic.burst("READ", global_position + Vector3(0.0, 2.8, 0.6), "cool", 2.0)
	print("[PassForger] seal cracked — buyer is %s" % BUYER_NAME)


## Exposed for the soak test and for SpineGate's informed price list.
func has_read_the_pass() -> bool:
	return _read


static func buyer_name() -> String:
	return BUYER_NAME
