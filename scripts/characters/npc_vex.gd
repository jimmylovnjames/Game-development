class_name NpcVex
extends Interactable
## Vex — lowspine fixer who clears debts she did not owe. First beat of MQ01.
##
## Quest dialogue stays fully authored here; the noir cost structure is not
## something to improvise. Her body is a CharacterBuilder "fixer" rig like
## every other person in the district.

const DISPLAY_NAME := "Vex"

var _lines := PackedStringArray([
	"You look like someone who just found out debts can be bought.",
	"Relax. Yours is cleared. Don't thank me — thank whoever paid.",
	"They left you this. Spine-line transit pass, sealed. Expires at dawn.",
	"I don't know whose name is on it. The people who do will want it back.",
	"Take it. Or don't. Either way, somebody owns a piece of your morning.",
])

var _dialogue: DialogueUI
var _quests: QuestSystem
var _talked: bool = false
var _cooldown: float = 0.0
var _rig: Node3D = null
var _idle_time: float = 0.0
var _look_target: Node3D = null


func _ready() -> void:
	super._ready()
	interactable_id = &"npc_vex"
	prompt = "Talk to Vex"
	collision_layer = 8 | 16  # npc | interactable
	collision_mask = 1  # world
	_rig = CharacterBuilder.build(&"fixer", 1.82, 1.0)
	add_child(_rig)
	_idle_time = 4.2


func bind(dialogue: DialogueUI, quests: QuestSystem) -> void:
	_dialogue = dialogue
	_quests = quests


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	_idle_time += delta
	CharacterBuilder.apply_idle(_rig, _idle_time, 0.6)

	if _look_target == null or not is_instance_valid(_look_target):
		_look_target = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _dialogue != null and _dialogue.is_active():
		return
	var dist := global_position.distance_to(_look_target.global_position)
	if dist > 7.0:
		return
	var want := CharacterBuilder.yaw_toward(global_position, _look_target.global_position)
	rotation.y = lerp_angle(rotation.y, want, minf(2.8 * delta, 1.0))


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
	_dialogue.set_speaker_color(Color(1.0, 0.176, 0.584))


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


## Exposed for soak tests: the built rig root.
func get_rig() -> Node3D:
	return _rig
