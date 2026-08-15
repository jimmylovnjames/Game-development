class_name TouchControls
extends CanvasLayer
## On-screen stick + look pad + action buttons for phones and tablets.
##
## Feeds the existing input map through Input.action_press / action_release so
## the player controller, soak tests and any future replay stay on one path.
## Hidden on headless runs and on mouse-only desktops unless `--touch=1`.

signal look_delta(relative: Vector2)

const MAGENTA := Color(1.0, 0.176, 0.584, 1.0)
const CYAN := Color(0.0, 0.898, 1.0, 1.0)
const INK := Color(0.031, 0.02, 0.059, 0.72)
const PLUM := Color(0.239, 0.18, 0.42, 0.55)

@export var deadzone: float = 0.18
@export var stick_radius: float = 96.0

var _move_index: int = -1
var _look_index: int = -1
var _move_vector := Vector2.ZERO
var _enabled: bool = false
var _has_interactable: bool = false

var _root: Control
var _stick_base: Control
var _stick_knob: Control
var _look_pad: Control
var _btn_jump: Button
var _btn_sprint: Button
var _btn_interact: Button
var _btn_light: Button
var _btn_crouch: Button
var _prompt: Label


func _ready() -> void:
	layer = 20
	_enabled = _should_show()
	visible = _enabled
	set_process(_enabled)
	set_process_unhandled_input(false)
	_build_hud()
	if not _enabled:
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return


func _should_show() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var args := OS.get_cmdline_user_args()
	for arg: String in args:
		if arg == "--touch=0":
			return false
		if arg == "--touch=1" or arg == "--touch":
			return true
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func set_interactable(interactable: Node3D) -> void:
	_has_interactable = interactable != null
	if _btn_interact == null:
		return
	_btn_interact.modulate = MAGENTA if _has_interactable else Color.WHITE
	if _prompt != null:
		_prompt.visible = _has_interactable and _enabled


func _process(_delta: float) -> void:
	if not _enabled:
		return
	_apply_move_actions(_move_vector)


func _build_hud() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_stick_base = _make_circle_panel("MoveStick", Vector2(210, 210))
	_stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.position = Vector2(36, -246)
	_stick_base.gui_input.connect(_on_stick_gui_input)
	_root.add_child(_stick_base)
	_stick_base.offset_left = 36.0
	_stick_base.offset_top = -246.0
	_stick_base.offset_right = 246.0
	_stick_base.offset_bottom = -36.0

	_stick_knob = _make_circle_panel("Knob", Vector2(84, 84))
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.modulate = CYAN
	_center_knob()
	_stick_base.add_child(_stick_knob)

	_look_pad = Control.new()
	_look_pad.name = "LookPad"
	_look_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_look_pad.anchor_left = 0.42
	_look_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_look_pad.gui_input.connect(_on_look_gui_input)
	_root.add_child(_look_pad)

	var buttons := Control.new()
	buttons.name = "Buttons"
	buttons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	buttons.position = Vector2(-300, -280)
	buttons.size = Vector2(280, 260)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(buttons)

	_btn_jump = _make_action_button("Jump", "JUMP", "jump", Vector2(148, 148), Vector2(110, 90))
	_btn_sprint = _make_action_button("Sprint", "SPRINT", "sprint", Vector2(108, 56), Vector2(0, 148))
	_btn_interact = _make_action_button("Interact", "USE", "interact", Vector2(108, 56), Vector2(148, 0))
	_btn_light = _make_action_button("Light", "LIGHT", "toggle_flashlight", Vector2(108, 56), Vector2(0, 70))
	_btn_crouch = _make_action_button("Crouch", "DUCK", "crouch", Vector2(108, 56), Vector2(0, 210))
	for btn: Button in [_btn_jump, _btn_sprint, _btn_interact, _btn_light, _btn_crouch]:
		buttons.add_child(btn)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = "USE"
	_prompt.visible = false
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", MAGENTA)
	_prompt.add_theme_color_override("font_outline_color", Color(0.031, 0.02, 0.059, 1.0))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-80, -52)
	_prompt.size = Vector2(160, 32)
	_root.add_child(_prompt)


func _make_circle_panel(node_name: String, size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.custom_minimum_size = size
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = CYAN
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(minf(size.x, size.y) * 0.5))
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_action_button(
		node_name: String,
		caption: String,
		action: String,
		size: Vector2,
		pos: Vector2
	) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = caption
	btn.position = pos
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = INK
	normal.border_color = CYAN
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(int(minf(size.x, size.y) * 0.5) if size.x == size.y else 10)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = PLUM
	pressed.border_color = MAGENTA
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", CYAN)
	btn.add_theme_color_override("font_pressed_color", MAGENTA)
	btn.add_theme_color_override("font_hover_color", CYAN)
	btn.button_down.connect(func() -> void: Input.action_press(action))
	btn.button_up.connect(func() -> void: Input.action_release(action))
	return btn


func _center_knob() -> void:
	if _stick_base == null or _stick_knob == null:
		return
	_stick_knob.position = (_stick_base.size - _stick_knob.size) * 0.5


func _on_stick_gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	# Touchscreens emit both Screen* and emulated mouse events. Ignore the
	# mouse copies so left-stick and look-pad can be used at the same time.
	if _has_touchscreen() and event is InputEventMouse:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _move_index < 0:
			_move_index = touch.index
			_update_stick(touch.position)
			_stick_base.accept_event()
		elif not touch.pressed and touch.index == _move_index:
			_reset_stick()
			_stick_base.accept_event()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _move_index:
		_update_stick((event as InputEventScreenDrag).position)
		_stick_base.accept_event()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed and _move_index < 0:
			_move_index = 0
			_update_stick(mouse.position)
			_stick_base.accept_event()
		elif not mouse.pressed and _move_index == 0:
			_reset_stick()
			_stick_base.accept_event()
	elif event is InputEventMouseMotion and _move_index == 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_update_stick((event as InputEventMouseMotion).position)
		_stick_base.accept_event()


func _on_look_gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if _has_touchscreen() and event is InputEventMouse:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _look_index < 0:
			_look_index = touch.index
			_look_pad.accept_event()
		elif not touch.pressed and touch.index == _look_index:
			_look_index = -1
			_look_pad.accept_event()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _look_index:
		look_delta.emit((event as InputEventScreenDrag).relative)
		_look_pad.accept_event()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed and _look_index < 0:
			_look_index = 0
			_look_pad.accept_event()
		elif not mouse.pressed and _look_index == 0:
			_look_index = -1
			_look_pad.accept_event()
	elif event is InputEventMouseMotion and _look_index == 0:
		look_delta.emit((event as InputEventMouseMotion).relative)
		_look_pad.accept_event()


func _has_touchscreen() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _update_stick(local_pos: Vector2) -> void:
	var center := _stick_base.size * 0.5
	var offset := local_pos - center
	var max_len := minf(_stick_base.size.x, _stick_base.size.y) * 0.5 - _stick_knob.size.x * 0.5
	if offset.length() > max_len:
		offset = offset.normalized() * max_len
	_stick_knob.position = center + offset - _stick_knob.size * 0.5
	var vec := offset / maxf(max_len, 0.001)
	if vec.length() < deadzone:
		vec = Vector2.ZERO
	else:
		vec = vec.limit_length(1.0)
	# Stick Y is screen-space (down positive); movement forward is negative Y.
	_move_vector = Vector2(vec.x, vec.y)


func _reset_stick() -> void:
	_move_index = -1
	_move_vector = Vector2.ZERO
	_center_knob()
	_apply_move_actions(Vector2.ZERO)


func _apply_move_actions(vec: Vector2) -> void:
	_set_axis("move_right", maxf(vec.x, 0.0))
	_set_axis("move_left", maxf(-vec.x, 0.0))
	_set_axis("move_back", maxf(vec.y, 0.0))
	_set_axis("move_forward", maxf(-vec.y, 0.0))


func _set_axis(action: String, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


func _exit_tree() -> void:
	_apply_move_actions(Vector2.ZERO)
	for action: String in ["jump", "sprint", "interact", "toggle_flashlight", "crouch"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
