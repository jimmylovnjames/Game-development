class_name NpcVex
extends Interactable
## Vex — lowspine fixer who clears debts she did not owe. First beat of MQ01.
##
## She is a CharacterBody3D so she stands on the street like anything that
## walks; interaction lives on this same node (layer 5). Dialogue content stays
## here as data until a real dialogue resource format lands.

const DISPLAY_NAME := "Vex"

var _lines := PackedStringArray([
	"You look like someone who just found out debts can be bought.",
	"Relax. Yours is cleared. Don't thank me — thank whoever paid.",
	"They left you this. Spine-line transit pass, sealed. Expires at dawn.",
	"I don't know whose name is on it. The people who do will want it back.",
	"Take it. Or don't. Either way, somebody owns a piece of your morning.",
])

@onready var _mesh: MeshInstance3D = $Mesh

var _dialogue: DialogueUI
var _quests: QuestSystem
var _talked: bool = false
var _cooldown: float = 0.0


func _ready() -> void:
	super._ready()
	interactable_id = &"npc_vex"
	prompt = "Talk to Vex"
	collision_layer = 8 | 16  # npc | interactable
	collision_mask = 1  # world


func bind(dialogue: DialogueUI, quests: QuestSystem) -> void:
	_dialogue = dialogue
	_quests = quests


func _on_interact(_who: Node3D) -> void:
	if _dialogue == null:
		print("[Vex] no dialogue UI bound")
		return
	if _dialogue.is_active():
		return
	if _cooldown > 0.0:
		return
	if not _dialogue.finished.is_connected(_on_dialogue_finished):
		_dialogue.finished.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
	if not _dialogue.cancelled.is_connected(_on_dialogue_cancelled):
		_dialogue.cancelled.connect(_on_dialogue_cancelled, CONNECT_ONE_SHOT)
	_dialogue.open(interactable_id, DISPLAY_NAME, _lines)


func _on_dialogue_finished(speaker_id: StringName) -> void:
	if speaker_id != interactable_id:
		return
	_talked = true
	_cooldown = 0.5
	prompt = "Talk to Vex again"
	if _quests != null:
		_quests.notify_talked(interactable_id)
	print("[Vex] she finishes. the pass is yours to refuse.")


func _on_dialogue_cancelled(speaker_id: StringName) -> void:
	if speaker_id != interactable_id:
		return
	_cooldown = 0.35
	print("[Vex] you walk away mid-sentence. she does not follow.")


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
