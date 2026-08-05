extends SceneTree
## Headless smoke test for the project skeleton.
##
## Verifies that the input map actually matches synthetic events, that the main
## scene instantiates, and that every shader in shaders/ compiles clean.
##
## Usage:
##   godot --headless --path . --script tools/verify_setup.gd

var _failures: int = 0


func _initialize() -> void:
	_check_input_map()
	_check_physics()
	_check_shaders()
	_check_materials()
	_check_prop_scenes()
	_check_main_scene()
	_check_addons()
	_check_quests()
	_check_graphics_tiers()

	print("")
	if _failures == 0:
		print("VERIFY: all checks passed.")
		quit(0)
	else:
		print("VERIFY: %d check(s) FAILED." % _failures)
		quit(1)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _ok(message: String) -> void:
	print("  ok    %s" % message)


func _check_input_map() -> void:
	print("[input map]")
	var expected := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
		"sprint": KEY_SHIFT,
		"interact": KEY_E,
	}
	for action: String in expected:
		if not InputMap.has_action(action):
			_fail("action '%s' is missing from the input map" % action)
			continue
		# Build the event the way the OS would deliver it and confirm it matches.
		var ev := InputEventKey.new()
		ev.physical_keycode = expected[action]
		ev.pressed = true
		if InputMap.event_is_action(ev, action):
			_ok("'%s' matches its key binding" % action)
		else:
			_fail("action '%s' exists but does not match its key event" % action)

	for action: String in ["attack_primary", "attack_secondary"]:
		if not InputMap.has_action(action):
			_fail("action '%s' is missing from the input map" % action)
			continue
		var mb := InputEventMouseButton.new()
		mb.button_index = (
			MOUSE_BUTTON_LEFT if action == "attack_primary" else MOUSE_BUTTON_RIGHT
		)
		mb.pressed = true
		if InputMap.event_is_action(mb, action):
			_ok("'%s' matches its mouse binding" % action)
		else:
			_fail("action '%s' exists but does not match its mouse event" % action)


## The physics engine settings are load-bearing for every test that follows:
## gravity feeds the controller, Jolt feeds the props, and the layer names are
## the contract every collision mask is written against.
func _check_physics() -> void:
	print("[physics]")

	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "")
	if engine == "Jolt Physics":
		_ok("physics engine is Jolt Physics")
	else:
		_fail("physics/3d/physics_engine is '%s', expected 'Jolt Physics'" % engine)

	var ticks: int = ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)
	if ticks == 60:
		_ok("physics runs at 60 Hz")
	else:
		_fail("physics/common/physics_ticks_per_second is %d, expected 60" % ticks)

	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 0.0)
	if is_equal_approx(gravity, 9.8):
		_ok("default gravity is 9.8")
	else:
		_fail("physics/3d/default_gravity is %.2f, expected 9.8" % gravity)

	for index in range(1, 11):
		var layer_name: String = ProjectSettings.get_setting(
			"layer_names/3d_physics/layer_%d" % index, ""
		)
		if layer_name.is_empty():
			_fail("3d physics layer %d has no name" % index)
		else:
			_ok("layer %d is named '%s'" % [index, layer_name])


func _check_materials() -> void:
	print("[materials]")
	var paths := _list_files("res://assets/materials", ".tres")
	if paths.is_empty():
		_fail("no materials found under res://assets/materials")
		return
	for path: String in paths:
		var resource := load(path)
		if resource == null:
			_fail("%s failed to load" % path)
			continue
		if resource is ShaderMaterial and resource.shader == null:
			_fail("%s is a ShaderMaterial with no shader" % path)
			continue
		_ok("%s loads (%s)" % [path.get_file(), resource.get_class()])


func _check_prop_scenes() -> void:
	print("[prop scenes]")
	for path: String in [
		"res://scenes/props/physics_crate.tscn",
		"res://scenes/props/physics_can.tscn",
		"res://scenes/props/dumpster.tscn",
		"res://scenes/props/jersey_barrier.tscn",
		"res://scenes/props/bollard.tscn",
		"res://scenes/props/traffic_cone.tscn",
		"res://scenes/props/manhole.tscn",
		"res://scenes/props/scaffold_frame.tscn",
		"res://scenes/props/spine_gate.tscn",
		"res://scenes/props/pass_forger.tscn",
	]:
		var packed := load(path) as PackedScene
		if packed == null:
			_fail("%s failed to load" % path)
			continue
		var instance := packed.instantiate()
		if instance == null:
			_fail("%s failed to instantiate" % path)
			continue
		var body := instance as RigidBody3D
		if body != null:
			if not instance.is_in_group("physics_props"):
				_fail("%s is not in group 'physics_props'" % path)
			elif instance.get_script() == null:
				_fail("%s has no script attached" % path)
			elif body.physics_material_override == null:
				_fail("%s has no physics_material_override" % path)
			else:
				_ok("%s: RigidBody3D, %.1f kg" % [path.get_file(), body.mass])
		else:
			_ok("%s: %s" % [path.get_file(), instance.get_class()])
		instance.free()


func _check_shaders() -> void:
	print("[shaders]")
	var paths := _list_files("res://shaders", ".gdshader")
	if paths.is_empty():
		_fail("no .gdshader files found under res://shaders")
		return
	for path: String in paths:
		var shader := load(path) as Shader
		if shader == null:
			_fail("%s failed to load" % path)
			continue

		# get_shader_uniform_list() runs the parser, but a shader that fails
		# partway still returns every uniform it read *before* the error — so
		# calling that "compiled" passes broken shaders. Compare the count the
		# API reports against the count actually declared in the source: a
		# parse that died early comes back short.
		var declared := _count_declared_uniforms(shader.code)
		var reported := shader.get_shader_uniform_list().size()
		if reported < declared:
			_fail("%s: parser reported %d of %d uniforms — it stopped early, so the shader did not compile" % [
				path, reported, declared,
			])
		else:
			_ok("%s compiled (%d uniforms)" % [path, reported])


## Top-level `uniform` declarations in shader source, ignoring commented-out
## lines and the built-in texture bindings.
##
## Samplers hinted as screen / depth / normal-roughness are wired by the
## renderer, not exposed as material parameters, so they never appear in
## get_shader_uniform_list() — counting them makes every post-process shader
## look like it stopped parsing one uniform early.
##
## Deliberately conservative: only lines that *begin* a declaration count, so
## this can undercount a multi-line declaration but never overcount.
const BUILTIN_TEXTURE_HINTS := [
	"hint_screen_texture", "hint_depth_texture", "hint_normal_roughness_texture",
]


func _count_declared_uniforms(code: String) -> int:
	var count := 0
	for raw_line: String in code.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("//") or not line.begins_with("uniform"):
			continue
		var builtin := false
		for hint: String in BUILTIN_TEXTURE_HINTS:
			if line.contains(hint):
				builtin = true
				break
		if builtin:
			continue
		count += 1
	return count


func _check_main_scene() -> void:
	print("[main scene]")
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_path.is_empty():
		_fail("application/run/main_scene is not set")
		return
	if not ResourceLoader.exists(main_path):
		_fail("main scene '%s' does not exist" % main_path)
		return

	var packed := load(main_path) as PackedScene
	if packed == null:
		_fail("main scene '%s' failed to load as a PackedScene" % main_path)
		return

	var instance := packed.instantiate()
	if instance == null:
		_fail("main scene '%s' failed to instantiate" % main_path)
		return

	_ok("%s instantiated as %s" % [main_path, instance.get_class()])

	# instantiate() still succeeds when a script fails to parse — it just silently
	# comes back scriptless. Assert the script actually attached.
	if instance.get_script() == null:
		_fail("main scene root has no script attached (check for parse errors above)")
	else:
		_ok("root script attached: %s" % instance.get_script().resource_path)

	for node_path: String in [
		"WorldEnvironment", "Moonlight", "World/Ground", "World/Blockout",
		"World/Rain",
		"Player", "Player/CameraPivot/SpringArm3D/Camera3D",
		"Player/CameraPivot/SpringArm3D/Camera3D/InteractRay",
		"PostFX/NoirRect", "DebugHUD/DebugLabel",
	]:
		if instance.has_node(node_path):
			_ok("node present: %s" % node_path)
		else:
			_fail("expected node missing: %s" % node_path)

	# Systems are spawned at runtime by GameRoot._ready — check the scripts load.
	for path: String in [
		"res://scripts/world/interactable.gd",
		"res://scripts/systems/world_flags.gd",
		"res://scripts/systems/quest_system.gd",
		"res://scripts/ui/dialogue_ui.gd",
		"res://scripts/characters/npc_vex.gd",
		"res://scenes/characters/npc_vex.tscn",
		"res://scenes/ui/dialogue_ui.tscn",
		"res://scripts/world/spine_gate.gd",
		"res://scripts/world/pass_forger.gd",
		"res://scenes/props/spine_gate.tscn",
		"res://scenes/props/pass_forger.tscn",
	]:
		if load(path) == null:
			_fail("failed to load %s" % path)
		else:
			_ok("loads: %s" % path.get_file())

	var player := instance.get_node_or_null("Player")
	if player != null and player.get_script() == null:
		_fail("Player has no script attached")

	_describe(instance, 0)
	instance.free()


func _describe(node: Node, depth: int) -> void:
	# Keep the dump shallow; this is a sanity check, not a scene inspector.
	if depth > 2:
		return
	for child in node.get_children():
		print("        %s- %s (%s)" % ["  ".repeat(depth), child.name, child.get_class()])
		_describe(child, depth + 1)


## The tier table is what lets this run on a laptop at all, so a typo in it
## should fail the build rather than surface as a black screen on someone
## else's machine.
func _check_graphics_tiers() -> void:
	print("[graphics tiers]")
	var required := [
		"name", "render_scale", "scaling_mode", "msaa", "fxaa", "volumetric_fog",
		"ssil", "ssao", "glow", "shadow_atlas", "directional_shadows",
		"shadow_distance", "light_fade_begin", "light_fade_length", "rain_intensity",
	]
	for tier: int in GraphicsSettings.TIERS:
		var config: Dictionary = GraphicsSettings.TIERS[tier]
		var missing: Array[String] = []
		for key: String in required:
			if not config.has(key):
				missing.append(key)
		if not missing.is_empty():
			_fail("tier '%s' is missing %s" % [config.get("name", tier), ", ".join(missing)])
			continue
		var scale := float(config["render_scale"])
		if scale <= 0.0 or scale > 1.0:
			_fail("tier '%s' has render_scale %.2f outside (0, 1]" % [config["name"], scale])
		else:
			_ok("tier '%s': scale %.2f, fade %.0f m, vol_fog=%s" % [
				config["name"], scale, config["light_fade_begin"],
				str(config["volumetric_fog"]),
			])

	var resolved: int = GraphicsSettings.resolve_tier()
	if GraphicsSettings.TIERS.has(resolved):
		_ok("resolves to '%s' on this machine" % GraphicsSettings.TIERS[resolved]["name"])
	else:
		_fail("resolve_tier() returned %s, which is not a tier" % str(resolved))


func _check_addons() -> void:
	print("[addons]")
	var enabled: PackedStringArray = ProjectSettings.get_setting(
		"editor_plugins/enabled", PackedStringArray()
	)
	for cfg: String in ["res://addons/godot_ai/plugin.cfg", "res://addons/godot_mcp/plugin.cfg"]:
		if not FileAccess.file_exists(cfg):
			_fail("addon missing from disk: %s" % cfg)
		elif cfg not in enabled:
			_fail("addon present but not enabled in project settings: %s" % cfg)
		else:
			_ok("installed and enabled: %s" % cfg.get_base_dir().get_file())


func _check_quests() -> void:
	print("[quests]")
	var paths := _list_files("res://quests", ".tres")
	if paths.is_empty():
		_ok("no quest resources yet")
		return
	for path: String in paths:
		var quest := load(path) as Quest
		if quest == null:
			_fail("%s did not load as a Quest" % path)
			continue
		# design_warnings() enforces the tone contract from CLAUDE.md: a quest
		# with a single outcome has no choice in it.
		var warnings := quest.design_warnings()
		if warnings.is_empty():
			_ok("%s (%d objectives, %d outcomes)" % [
				path.get_file(), quest.objectives.size(), quest.outcomes.size(),
			])
		else:
			for warning: String in warnings:
				_fail("%s: %s" % [path.get_file(), warning])


func _list_files(dir_path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_list_files(full, suffix))
		elif entry.ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
