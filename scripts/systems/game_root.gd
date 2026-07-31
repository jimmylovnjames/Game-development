class_name GameRoot
extends Node3D
## Entry point for the playable scene.
##
## Owns nothing gameplay-critical on purpose: it wires the player to systems,
## handles quit, and prints a one-shot boot report that headless CI can assert
## against.

const VEX_SCENE := preload("res://scenes/characters/npc_vex.tscn")
const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue_ui.tscn")

@export var print_boot_report: bool = true

@onready var _player: PlayerController = $Player
@onready var _blockout: DistrictBlockout = $World/Blockout
@onready var _debug_label: Label = $DebugHUD/DebugLabel

var _debug_visible: bool = true
var _flags: WorldFlags
var _quests: QuestSystem
var _dialogue: DialogueUI
var _prompt_label: Label
var _vex: NpcVex


func _ready() -> void:
	_flags = WorldFlags.new()
	_flags.name = "WorldFlags"
	add_child(_flags)

	_quests = QuestSystem.new()
	_quests.name = "QuestSystem"
	_quests.flags = _flags
	add_child(_quests)

	_dialogue = DIALOGUE_SCENE.instantiate() as DialogueUI
	add_child(_dialogue)

	_prompt_label = Label.new()
	_prompt_label.name = "InteractPrompt"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 0.72
	_prompt_label.anchor_bottom = 0.72
	_prompt_label.offset_left = -220.0
	_prompt_label.offset_right = 220.0
	_prompt_label.offset_top = -18.0
	_prompt_label.offset_bottom = 18.0
	_prompt_label.add_theme_color_override("font_color", Color(0.0, 0.898, 1.0))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.04))
	_prompt_label.add_theme_constant_override("outline_size", 5)
	_prompt_label.visible = false
	$DebugHUD.add_child(_prompt_label)

	_spawn_vex()

	_player.global_position = _blockout.get_spawn_point()
	_player.interactable_changed.connect(_on_interactable_changed)
	_player.landed.connect(_on_landed)

	if print_boot_report:
		call_deferred("_print_boot_report")


func _spawn_vex() -> void:
	_vex = VEX_SCENE.instantiate() as NpcVex
	_vex.name = "NpcVex"
	# Plaza edge — close enough to find on boot, clear of the spawn pad.
	_vex.position = Vector3(4.5, 0.0, -3.5)
	$World.add_child(_vex)
	_vex.bind(_dialogue, _quests)


func _print_boot_report() -> void:
	var viewport := get_viewport()
	print("=== NeonWastesRPG boot report ===")
	print("  engine        : %s" % Engine.get_version_info().get("string", "unknown"))
	print("  renderer      : %s" % ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "?"
	))
	print("  headless      : %s" % str(DisplayServer.get_name() == "headless"))
	print("  main scene    : %s" % scene_file_path)
	print("  player at     : %s" % str(_player.global_position))
	print("  vex at        : %s" % str(_vex.global_position if _vex else Vector3.ZERO))
	print("  spawned nodes : %d under World" % _count_descendants($World))
	print("  viewport size : %s" % str(viewport.get_visible_rect().size))
	print("================================")


func _count_descendants(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		total += 1 + _count_descendants(child)
	return total


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue != null and _dialogue.is_active():
		return
	if event.is_action_pressed("debug_toggle"):
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible


func _process(_delta: float) -> void:
	if not _debug_visible or not _debug_label.visible:
		return
	if _dialogue != null and _dialogue.is_active():
		return
	var interactable := _player.get_current_interactable()
	var journal := "\n".join(_quests.get_journal_lines()) if _quests != null else ""
	_debug_label.text = "\n".join([
		"NeonWastesRPG — blockout",
		"fps      %d" % Engine.get_frames_per_second(),
		"pos      %.1f, %.1f, %.1f" % [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z,
		],
		"speed    %.1f m/s" % Vector2(_player.velocity.x, _player.velocity.z).length(),
		"grounded %s" % str(_player.is_on_floor()),
		"target   %s" % ("—" if interactable == null else interactable.name),
		"",
		journal,
		"",
		"WASD move · Shift sprint · Ctrl crouch · Space jump",
		"E interact · F flashlight · Esc release mouse · F3 hide",
	])


func _on_interactable_changed(interactable: Node3D) -> void:
	if interactable != null:
		print("[GameRoot] interactable in range: %s" % interactable.name)
		if _prompt_label != null:
			var prompt := "E — Interact"
			if interactable.has_method("get_prompt"):
				prompt = "E — %s" % interactable.get_prompt()
			_prompt_label.text = prompt
			_prompt_label.visible = true
	elif _prompt_label != null:
		_prompt_label.visible = false


func _on_landed(fall_speed: float) -> void:
	if fall_speed > 12.0:
		print("[GameRoot] hard landing at %.1f m/s" % fall_speed)
