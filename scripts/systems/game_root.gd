class_name GameRoot
extends Node3D
## Entry point for the playable scene.
##
## Owns nothing gameplay-critical on purpose: it wires the player to systems,
## handles quit, and prints a one-shot boot report that headless CI can assert
## against.

const VEX_SCENE := preload("res://scenes/characters/npc_vex.tscn")
const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue_ui.tscn")
const SPINE_GATE_SCENE := preload("res://scenes/props/spine_gate.tscn")
const PASS_FORGER_SCENE := preload("res://scenes/props/pass_forger.tscn")
## Matches the marker on mq01's reach_spine_gate objective: the far end of a
## street on the district's north-east edge, a real walk from the plaza.
const SPINE_GATE_POSITION := Vector3(96.0, 0.0, -42.0)
## Off the east kerb toward the gate — findable without being on the walking
## line. Optional objectives that sit on the critical path stop being optional.
const PASS_FORGER_POSITION := Vector3(52.0, 0.0, -8.0)

@export var print_boot_report: bool = true

@onready var _player: PlayerController = $Player
@onready var _blockout: DistrictBlockout = $World/Blockout
@onready var _debug_label: Label = $DebugHUD/DebugLabel

var _debug_visible: bool = true
var _flags: WorldFlags
var _quests: QuestSystem
var _dialogue: DialogueUI
var _backend: NpcLlmBackend
var _gossip: GossipNetwork
var _ambience: AmbienceDirector
var _comic_fx: ComicFX
var _graphics: GraphicsSettings
var _prompt_label: Label
var _prompt_panel: PanelContainer
var _journal_label: Label
var _journal_panel: PanelContainer
var _vex: NpcVex
var _spine_gate: SpineGate
var _pass_forger: PassForger


func _ready() -> void:
	_flags = WorldFlags.new()
	_flags.name = "WorldFlags"
	add_child(_flags)

	_quests = QuestSystem.new()
	_quests.name = "QuestSystem"
	_quests.flags = _flags
	add_child(_quests)
	_quests.objective_completed.connect(_on_objective_completed)

	_backend = NpcLlmBackend.new()
	_backend.name = "NpcLlmBackend"
	add_child(_backend)

	_gossip = GossipNetwork.new()
	_gossip.name = "GossipNetwork"
	add_child(_gossip)

	_ambience = AmbienceDirector.new()
	_ambience.name = "AmbienceDirector"
	add_child(_ambience)

	_comic_fx = ComicFX.new()
	_comic_fx.name = "ComicFX"
	add_child(_comic_fx)

	# Last, and deferred: the blockout's lights exist by now (children are ready
	# before their parent), but deferring lets any late spawner land first so
	# nothing escapes the distance-fade pass.
	_graphics = GraphicsSettings.new()
	_graphics.name = "GraphicsSettings"
	add_child(_graphics)
	_graphics.call_deferred("apply", -1, self)

	_dialogue = DIALOGUE_SCENE.instantiate() as DialogueUI
	add_child(_dialogue)

	_build_hud()

	_spawn_vex()
	_spawn_pass_forger()
	_spawn_spine_gate()
	_bind_persona_shells()

	_player.global_position = _blockout.get_spawn_point()
	_player.interactable_changed.connect(_on_interactable_changed)
	_player.landed.connect(_on_landed)
	_player.add_to_group("player")

	var storm := get_node_or_null("StormDirector") as StormDirector
	if storm != null:
		storm.struck.connect(_on_storm_struck)

	if print_boot_report:
		call_deferred("_print_boot_report")


## --- HUD ------------------------------------------------------------------
##
## Everything on screen is drawn as a comic panel: heavy ink border, near-black
## plum fill, neon only on the type. Flat coloured text floating over the scene
## was the one element not speaking the game's visual language.

const INK := Color(0.031, 0.02, 0.059)
const PANEL_FILL := Color(0.043, 0.031, 0.075, 0.88)
const NEON_CYAN := Color(0.0, 0.898, 1.0)
const NEON_MAGENTA := Color(1.0, 0.176, 0.584)
const ACID_YELLOW := Color(0.969, 1.0, 0.235)


func _build_hud() -> void:
	# Interact prompt: a caption box centred low, where the eye already is.
	var prompt_panel := PanelContainer.new()
	prompt_panel.name = "InteractPrompt"
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_top = 0.78
	prompt_panel.anchor_bottom = 0.78
	prompt_panel.offset_left = -190.0
	prompt_panel.offset_right = 190.0
	prompt_panel.offset_top = -26.0
	prompt_panel.offset_bottom = 26.0
	prompt_panel.add_theme_stylebox_override("panel", _panel_box(NEON_CYAN))
	prompt_panel.visible = false
	$DebugHUD.add_child(prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ink_type(_prompt_label, NEON_CYAN, 20)
	prompt_panel.add_child(_prompt_label)
	_prompt_panel = prompt_panel

	# Journal: its own caption box, top right, away from the debug readout.
	var journal_panel := PanelContainer.new()
	journal_panel.name = "JournalPanel"
	journal_panel.anchor_left = 1.0
	journal_panel.anchor_right = 1.0
	journal_panel.anchor_top = 0.0
	journal_panel.anchor_bottom = 0.0
	journal_panel.offset_left = -430.0
	journal_panel.offset_right = -22.0
	journal_panel.offset_top = 22.0
	journal_panel.offset_bottom = 200.0
	journal_panel.add_theme_stylebox_override("panel", _panel_box(ACID_YELLOW))
	$DebugHUD.add_child(journal_panel)

	_journal_label = Label.new()
	_journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ink_type(_journal_label, ACID_YELLOW, 16)
	journal_panel.add_child(_journal_label)
	_journal_panel = journal_panel

	# The debug readout stays a debug readout, but stops floating unstyled.
	if _debug_label != null:
		_ink_type(_debug_label, NEON_MAGENTA, 14)


## Ink border + near-black plum fill: the panel edge of the style bible, not a
## translucent grey rectangle.
func _panel_box(edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_FILL
	box.border_color = INK
	box.set_border_width_all(4)
	box.set_corner_radius_all(2)
	box.set_content_margin_all(12)
	# A thin neon keyline inside the ink, the way a panel gutter reads.
	box.shadow_color = Color(edge.r, edge.g, edge.b, 0.32)
	box.shadow_size = 5
	return box


func _ink_type(label: Label, color: Color, size: int) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", size)


func _spawn_vex() -> void:
	_vex = VEX_SCENE.instantiate() as NpcVex
	_vex.name = "NpcVex"
	# Plaza edge — close enough to find on boot, clear of the spawn pad.
	_vex.position = Vector3(4.5, 0.0, -3.5)
	$World.add_child(_vex)
	_vex.bind(_dialogue, _quests)


## Optional MQ01 setpiece: crack the sealed pass before the gate. Completing it
## does not add a fourth ending — it rewrites the price list on the three that
## already exist.
func _spawn_pass_forger() -> void:
	_pass_forger = PASS_FORGER_SCENE.instantiate() as PassForger
	_pass_forger.name = "PassForger"
	_pass_forger.position = PASS_FORGER_POSITION
	# Face the street so the fascia reads from the walking line.
	_pass_forger.rotation.y = PI * 0.5
	$World.add_child(_pass_forger)
	_pass_forger.bind(_dialogue, _quests, _flags, _comic_fx)


## MQ01's destination. Without it the quest has three outcomes and no way to
## reach any of them — the first story beat literally cannot end.
func _spawn_spine_gate() -> void:
	_spine_gate = SPINE_GATE_SCENE.instantiate() as SpineGate
	_spine_gate.name = "SpineGate"
	_spine_gate.position = SPINE_GATE_POSITION
	# Face back down the street toward the plaza the courier walks in from.
	_spine_gate.rotation.y = PI * 0.5
	$World.add_child(_spine_gate)
	_spine_gate.bind(_dialogue, _quests, _flags, _comic_fx)


## Persona shells spawn with the blockout (before systems exist), so binding
## happens here, once the backend and flags are live.
func _bind_persona_shells() -> void:
	for shell in get_tree().get_nodes_in_group("persona_shells"):
		if shell is PersonaShell:
			shell.bind(_dialogue, _flags, _backend)
			_gossip.register_shell(shell)


func _print_boot_report() -> void:
	var viewport := get_viewport()
	print("=== NeonWastesRPG boot report ===")
	print("  engine        : %s" % Engine.get_version_info().get("string", "unknown"))
	print("  renderer      : %s" % ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "?"
	))
	print("  headless      : %s" % str(DisplayServer.get_name() == "headless"))
	print("  gpu           : %s" % RenderingServer.get_video_adapter_name())
	print("  quality tier  : %s" % (
		_graphics.get_tier_name() if _graphics != null else "?"
	))
	print("  main scene    : %s" % scene_file_path)
	print("  player at     : %s" % str(_player.global_position))
	print("  vex at        : %s" % str(_vex.global_position if _vex else Vector3.ZERO))
	print("  pass forger at: %s" % str(
		_pass_forger.global_position if _pass_forger else Vector3.ZERO
	))
	print("  spine gate at : %s" % str(
		_spine_gate.global_position if _spine_gate else Vector3.ZERO
	))
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
	# The journal is a caption box now, not part of the debug readout, so F3
	# must not freeze it — but a conversation still owns the whole screen.
	var talking := _dialogue != null and _dialogue.is_active()
	if _journal_panel != null:
		_update_journal(talking)
	if talking or not _debug_visible or not _debug_label.visible:
		return

	var interactable := _player.get_current_interactable()
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
		"WASD move · Shift sprint · Ctrl crouch · Space jump",
		"E interact · F flashlight · Esc release mouse · F3 hide",
	])


## Own panel, own visibility: hidden during dialogue so a conversation gets the
## frame to itself, and hidden entirely when there is no active quest — an empty
## caption box is worse than no caption box.
func _update_journal(talking: bool) -> void:
	if _journal_label == null:
		return
	if talking:
		_journal_panel.visible = false
		return
	var journal := "\n".join(_quests.get_journal_lines()) if _quests != null else ""
	_journal_label.text = journal
	_journal_panel.visible = not journal.strip_edges().is_empty()


func _on_interactable_changed(interactable: Node3D) -> void:
	if interactable != null:
		print("[GameRoot] interactable in range: %s" % interactable.name)
		if _prompt_label != null:
			var prompt := "Interact"
			if interactable.has_method("get_prompt"):
				prompt = interactable.get_prompt()
			_prompt_label.text = "[ E ]  %s" % prompt.to_upper()
			if _prompt_panel != null:
				_prompt_panel.visible = true
	elif _prompt_panel != null:
		_prompt_panel.visible = false


func _on_landed(fall_speed: float) -> void:
	if fall_speed > 12.0:
		print("[GameRoot] hard landing at %.1f m/s" % fall_speed)
		_comic_fx.burst("WHUMP", _player.global_position, "heavy")
		_comic_fx.panel_flash(Color(1, 1, 1), 0.12, 0.12)


func _on_storm_struck(strength: float) -> void:
	var sky_position := _player.global_position + Vector3(0.0, 16.0, -14.0)
	_comic_fx.burst(_comic_fx.pick_storm(), sky_position, "storm")
	_comic_fx.panel_flash(Color(0.9, 0.95, 1.0), 0.1 + strength * 0.08, 0.2)


func _on_objective_completed(_quest: Quest, _objective: QuestObjective) -> void:
	_comic_fx.panel_flash(Color(1.0, 0.176, 0.584), 0.16, 0.22)
