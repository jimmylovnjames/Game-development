extends SceneTree
## One-shot project configuration script.
##
## Writes the input map, physics layer names and renderer/quality settings into
## project.godot using the engine's own serializer, so the output always matches
## the exact Godot version in use. Re-running it is safe and idempotent.
##
## Usage:
##   godot --headless --path . --script tools/setup_project_settings.gd


func _initialize() -> void:
	_setup_input_map()
	_setup_physics_layers()
	_setup_rendering()
	_setup_application()

	var err := ProjectSettings.save()
	if err != OK:
		push_error("Failed to save project settings: %d" % err)
		quit(1)
		return

	print("Project settings written successfully.")
	quit(0)


## Action name -> array of physical key scancodes / mouse buttons.
const KEY_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"interact": [KEY_E],
	"reload": [KEY_R],
	"inventory": [KEY_TAB],
	"journal": [KEY_J],
	"map": [KEY_M],
	"pause": [KEY_ESCAPE],
	"toggle_flashlight": [KEY_F],
	"time_toggle": [KEY_T],
	"debug_toggle": [KEY_F3],
}

const MOUSE_BINDINGS := {
	"attack_primary": [MOUSE_BUTTON_LEFT],
	"attack_secondary": [MOUSE_BUTTON_RIGHT],
}


func _setup_input_map() -> void:
	for action_name: String in KEY_BINDINGS:
		var events: Array[InputEvent] = []
		for scancode: int in KEY_BINDINGS[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = scancode
			events.append(ev)
		_write_action(action_name, events)

	for action_name: String in MOUSE_BINDINGS:
		var events: Array[InputEvent] = []
		for button: int in MOUSE_BINDINGS[action_name]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			events.append(ev)
		_write_action(action_name, events)

	print("Configured %d input actions." % (KEY_BINDINGS.size() + MOUSE_BINDINGS.size()))


func _write_action(action_name: String, events: Array[InputEvent]) -> void:
	ProjectSettings.set_setting("input/" + action_name, {
		"deadzone": 0.2,
		"events": events,
	})


## Layer index (1-based, as shown in the editor) -> name.
const PHYSICS_LAYERS := {
	1: "world",
	2: "player",
	3: "enemy",
	4: "npc",
	5: "interactable",
	6: "projectile",
	7: "trigger",
	8: "vehicle",
	9: "cover",
	10: "water",
}


func _setup_physics_layers() -> void:
	for index: int in PHYSICS_LAYERS:
		ProjectSettings.set_setting(
			"layer_names/3d_physics/layer_%d" % index, PHYSICS_LAYERS[index]
		)
	print("Named %d 3D physics layers." % PHYSICS_LAYERS.size())


func _setup_rendering() -> void:
	# Forward+ is required for the volumetric fog and SDFGI the neon-noir look leans on.
	ProjectSettings.set_setting("rendering/renderer/rendering_method", "forward_plus")
	ProjectSettings.set_setting("rendering/renderer/rendering_method.mobile", "gl_compatibility")

	# Cel shading wants crisp edges, so keep MSAA rather than relying on TAA smearing.
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 2)  # 4x
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)  # Disabled
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/use_taa", false)

	# Neon signage in fog is the signature of the art direction.
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/volume_size", 96)
	ProjectSettings.set_setting("rendering/environment/volumetric_fog/volume_depth", 96)

	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)
	print("Configured rendering settings.")


func _setup_application() -> void:
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/main.tscn")
	ProjectSettings.set_setting("application/config/name", "NeonWastesRPG")
	ProjectSettings.set_setting(
		"application/config/description",
		"Dark, violent neo-noir cyberpunk wasteland RPG. Cel-shaded 3D open world."
	)
	ProjectSettings.set_setting("debug/settings/stdout/verbose_stdout", false)
	print("Configured application settings.")
