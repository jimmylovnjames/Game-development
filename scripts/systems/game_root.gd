class_name GameRoot
extends Node3D
## Entry point for the playable scene.
##
## Owns nothing gameplay-critical on purpose: it wires the player to the debug
## overlay, handles quit, and prints a one-shot boot report that headless CI can
## assert against.

@export var print_boot_report: bool = true
## The world is streamed, so there is no floor outside the load ring. If the
## player ends up under it — a streaming stall, a physics tunnel, a bad teleport
## — put them back rather than letting them fall forever.
@export var fall_respawn_y: float = -25.0

@onready var _player: PlayerController = $Player
@onready var _streamer: ChunkStreamer = $World/Streamer
@onready var _debug_label: Label = $DebugHUD/DebugLabel

var _debug_visible: bool = true


func _ready() -> void:
	# Warm up before moving the player: a frame-budgeted stream would drop them
	# through a world that has not been built yet.
	_streamer.warm_up_at(_streamer.get_spawn_point())
	_player.global_position = _streamer.get_spawn_point()

	_player.interactable_changed.connect(_on_interactable_changed)
	_player.landed.connect(_on_landed)

	if print_boot_report:
		# Deferred so the streamer has finished its warm-up before we count nodes.
		call_deferred("_print_boot_report")


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
	print("  world seed    : %d" % _streamer.world_seed)
	print("  chunks loaded : %d (load ring %d)" % [
		_streamer.loaded_count(), _streamer.load_ring_count(),
	])
	print("  spawned nodes : %d under World" % _count_descendants($World))
	print("  viewport size : %s" % str(viewport.get_visible_rect().size))
	print("================================")


func _count_descendants(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		total += 1 + _count_descendants(child)
	return total


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible


func _process(_delta: float) -> void:
	if _player.global_position.y < fall_respawn_y:
		_respawn()

	if not _debug_visible or not _debug_label.visible:
		return
	var interactable := _player.get_current_interactable()
	var biome := _streamer.biome_at(_player.global_position)
	_debug_label.text = "\n".join([
		"NeonWastesRPG — seed %d" % _streamer.world_seed,
		"fps      %d" % Engine.get_frames_per_second(),
		"pos      %.1f, %.1f, %.1f" % [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z,
		],
		"speed    %.1f m/s" % Vector2(_player.velocity.x, _player.velocity.z).length(),
		"grounded %s" % str(_player.is_on_floor()),
		"target   %s" % ("—" if interactable == null else interactable.name),
		"chunk    %s · %s (%.2f)" % [
			str(_streamer.current_centre()),
			"—" if biome == null else biome.display_name,
			_streamer.urbanisation(_player.global_position),
		],
		"streamed %d loaded · %d queued" % [
			_streamer.loaded_count(), _streamer.pending_count(),
		],
		"",
		"WASD move · Shift sprint · Ctrl crouch · Space jump",
		"E interact · F flashlight · Esc release mouse · F3 hide",
	])


func _respawn() -> void:
	var spawn := _streamer.get_spawn_point()
	_streamer.warm_up_at(spawn)
	_player.velocity = Vector3.ZERO
	_player.global_position = spawn
	print("[GameRoot] player fell out of the world; respawned at %s" % str(spawn))


func _on_interactable_changed(interactable: Node3D) -> void:
	if interactable != null:
		print("[GameRoot] interactable in range: %s" % interactable.name)


func _on_landed(fall_speed: float) -> void:
	if fall_speed > 12.0:
		print("[GameRoot] hard landing at %.1f m/s" % fall_speed)
