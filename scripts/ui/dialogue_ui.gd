class_name DialogueUI
extends CanvasLayer
## Minimal noir dialogue panel. Lines advance on interact/attack_primary;
## Esc / pause dismisses without completing. Completing the last line emits
## `finished` so quests can mark a TALK objective done.

signal finished(speaker_id: StringName)
signal cancelled(speaker_id: StringName)

@onready var _panel: PanelContainer = $Panel
@onready var _speaker: Label = $Panel/Margin/VBox/Speaker
@onready var _body: Label = $Panel/Margin/VBox/Body
@onready var _hint: Label = $Panel/Margin/VBox/Hint

var _speaker_id: StringName = &""
var _lines: PackedStringArray = PackedStringArray()
var _index: int = 0
var _active: bool = false
var _ignore_advance_frames: int = 0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_active() -> bool:
	return _active


func open(speaker_id: StringName, speaker_name: String, lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	_speaker_id = speaker_id
	_lines = lines
	_index = 0
	_active = true
	# The same interact press that opened us must not also advance the first line.
	_ignore_advance_frames = 2
	_speaker.text = speaker_name
	_show_line()
	visible = true
	get_tree().paused = true


func _show_line() -> void:
	_body.text = _lines[_index]
	var last := _index >= _lines.size() - 1
	_hint.text = "E / click — done" if last else "E / click — continue · Esc — walk away"


func _process(_delta: float) -> void:
	# Polled so Input.action_press() from soak tests / cutscenes advances the
	# same way a key event would. _unhandled_input alone cannot see action_press.
	if not _active:
		return
	if _ignore_advance_frames > 0:
		_ignore_advance_frames -= 1
		return
	if Input.is_action_just_pressed("pause"):
		_close(false)
		return
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack_primary"):
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# Swallow interact/pause so the player controller does not also see them.
	if event.is_action_pressed("pause") or event.is_action_pressed("interact") \
			or event.is_action_pressed("attack_primary"):
		get_viewport().set_input_as_handled()


func _advance() -> void:
	if _index >= _lines.size() - 1:
		_close(true)
		return
	_index += 1
	_show_line()


func _close(completed: bool) -> void:
	_active = false
	visible = false
	get_tree().paused = false
	var id := _speaker_id
	_speaker_id = &""
	_lines = PackedStringArray()
	if completed:
		finished.emit(id)
	else:
		cancelled.emit(id)
