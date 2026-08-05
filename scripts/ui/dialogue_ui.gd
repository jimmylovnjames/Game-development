class_name DialogueUI
extends CanvasLayer
## Minimal noir dialogue panel. Lines advance on interact/attack_primary;
## Esc / pause dismisses without completing. Completing the last line emits
## `finished` so quests can mark a TALK objective done.

signal finished(speaker_id: StringName)
signal cancelled(speaker_id: StringName)
## Emitted when the player commits to a branch. `choice_id` is whatever the
## caller put in the choice dictionary — for MQ01 those are quest outcome ids.
signal choice_made(speaker_id: StringName, choice_id: StringName)

@onready var _panel: PanelContainer = $Panel
@onready var _speaker: Label = $Panel/Margin/VBox/Speaker
@onready var _body: Label = $Panel/Margin/VBox/Body
@onready var _hint: Label = $Panel/Margin/VBox/Hint
@onready var _choices_box: VBoxContainer = $Panel/Margin/VBox/Choices
@onready var _cost_label: Label = $Panel/Margin/VBox/Cost

var _speaker_id: StringName = &""
var _lines: PackedStringArray = PackedStringArray()
var _index: int = 0
var _active: bool = false
var _ignore_advance_frames: int = 0

## Choice mode. `_choices` entries are {"id": StringName, "text": String,
## "cost": String}. The cost line is the tone contract made visible: the player
## is handed a price list, not a right answer, so every branch states what it
## costs before it is taken.
var _choices: Array[Dictionary] = []
var _selected: int = 0
var _choice_labels: Array[Label] = []

const CHOICE_IDLE := Color(0.72, 0.7, 0.78)
const CHOICE_ACTIVE := Color(0.0, 0.898, 1.0)


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_active() -> bool:
	return _active


## True only while the menu is actually on screen. Reporting "has choices"
## instead would be true from the moment the conversation opened, before the
## player has read a word of it.
func is_choosing() -> bool:
	return _active and _choices_box != null and _choices_box.visible


## True when a decision is pending but the player is still reading.
func has_pending_choices() -> bool:
	return _active and not _choices.is_empty()


## Which branch the cursor is on. Exposed so automation can confirm a keypress
## actually moved the cursor instead of assuming one press equals one move.
func get_selected_index() -> int:
	return _selected


func get_choice_count() -> int:
	return _choices.size()


## Cost line for the currently selected branch. Soak uses this to prove the
## optional forger beat rewrote the price list, not just set a flag.
func get_cost_text() -> String:
	if _cost_label == null or not _cost_label.visible:
		return ""
	return _cost_label.text


func set_speaker_color(color: Color) -> void:
	_speaker.add_theme_color_override("font_color", color)


## Swap the body mid-conversation (LLM reply arriving after the "…" placeholder
## or a kernel fallback taking over). Restarts at the first new line.
func replace_lines(lines: PackedStringArray) -> void:
	if lines.is_empty() or not _active:
		return
	_lines = lines
	_index = 0
	_show_line()


func open(speaker_id: StringName, speaker_name: String, lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	_speaker_id = speaker_id
	_lines = lines
	_index = 0
	_active = true
	_clear_choices()
	# The same interact press that opened us must not also advance the first line.
	_ignore_advance_frames = 2
	_speaker.text = speaker_name
	_show_line()
	visible = true
	get_tree().paused = true


## Open with a decision at the end of the lines. The player reads through, then
## picks; there is no way to leave without choosing except walking away.
func open_with_choices(
	speaker_id: StringName,
	speaker_name: String,
	lines: PackedStringArray,
	choices: Array[Dictionary]
) -> void:
	if choices.is_empty():
		open(speaker_id, speaker_name, lines)
		return
	open(speaker_id, speaker_name, lines)
	_choices = choices
	_selected = 0
	if _lines.size() <= 1:
		_enter_choice_mode()


func _show_line() -> void:
	_body.text = _lines[_index]
	var last := _index >= _lines.size() - 1
	if last and not _choices.is_empty():
		_hint.text = "E / click — decide"
	elif last:
		_hint.text = "E / click — done"
	else:
		_hint.text = "E / click — continue · Esc — walk away"


func _enter_choice_mode() -> void:
	_choices_box.visible = true
	_cost_label.visible = true
	for label in _choice_labels:
		label.queue_free()
	_choice_labels.clear()

	for i in _choices.size():
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 17)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_choices_box.add_child(label)
		_choice_labels.append(label)

	_refresh_choices()
	_hint.text = "W/S — weigh it · E — commit · Esc — walk away"


func _refresh_choices() -> void:
	for i in _choice_labels.size():
		var chosen := i == _selected
		var entry: Dictionary = _choices[i]
		_choice_labels[i].text = "%s %s" % ["▸" if chosen else " ", entry.get("text", "?")]
		_choice_labels[i].add_theme_color_override(
			"font_color", CHOICE_ACTIVE if chosen else CHOICE_IDLE
		)
	var current: Dictionary = _choices[_selected]
	_cost_label.text = str(current.get("cost", ""))


func _clear_choices() -> void:
	_choices.clear()
	_selected = 0
	for label in _choice_labels:
		label.queue_free()
	_choice_labels.clear()
	if _choices_box != null:
		_choices_box.visible = false
	if _cost_label != null:
		_cost_label.visible = false


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

	if _choices_box.visible:
		# Reuse the movement actions rather than inventing bindings: they are
		# already mapped to W/S and the arrows, and Input.action_press() can
		# drive them, so the soak test walks this menu exactly like a player.
		if Input.is_action_just_pressed("move_forward"):
			_selected = wrapi(_selected - 1, 0, _choices.size())
			_refresh_choices()
		elif Input.is_action_just_pressed("move_back"):
			_selected = wrapi(_selected + 1, 0, _choices.size())
			_refresh_choices()
		elif Input.is_action_just_pressed("interact") \
				or Input.is_action_just_pressed("attack_primary"):
			_commit_choice()
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
		if not _choices.is_empty():
			_enter_choice_mode()
			return
		_close(true)
		return
	_index += 1
	_show_line()


func _commit_choice() -> void:
	if _choices.is_empty():
		return
	var chosen: StringName = _choices[_selected].get("id", &"")
	var speaker := _speaker_id
	_close(true)
	choice_made.emit(speaker, chosen)


func _close(completed: bool) -> void:
	_active = false
	visible = false
	get_tree().paused = false
	var id := _speaker_id
	_speaker_id = &""
	_lines = PackedStringArray()
	_clear_choices()
	if completed:
		finished.emit(id)
	else:
		cancelled.emit(id)


## Hard reset for automation. Does not emit finished/cancelled — soak stages
## use this between setpieces so a leftover panel cannot pause the tree or
## block the next interact().
func force_close() -> void:
	_active = false
	visible = false
	_speaker_id = &""
	_lines = PackedStringArray()
	_clear_choices()
	get_tree().paused = false
