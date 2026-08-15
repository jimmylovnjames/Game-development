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
	_check_shaders()
	_check_main_scene()
	_check_addons()
	_check_quests()

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

	for action: String in ["look_left", "look_right", "look_up", "look_down"]:
		if InputMap.has_action(action):
			_ok("action '%s' is in the input map" % action)
		else:
			_fail("action '%s' is missing (needed for gamepad look)" % action)

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
		# get_shader_uniform_list() forces the parser to run over the source.
		shader.get_shader_uniform_list()
		_ok("%s compiled" % path)


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
		"Player", "Player/CameraPivot/SpringArm3D/Camera3D",
		"Player/CameraPivot/SpringArm3D/Camera3D/InteractRay",
		"DebugHUD/DebugLabel",
		"TouchControls",
	]:
		if instance.has_node(node_path):
			_ok("node present: %s" % node_path)
		else:
			_fail("expected node missing: %s" % node_path)

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
